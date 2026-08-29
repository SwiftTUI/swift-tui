// The per-node capture of one resolve pass's runtime registrations: one
// `RuntimeNodeRecord` field per registration family, written by the typed
// `record*` intake methods below and read back by each registry's
// `RuntimeRegistry.restore(from:context:)`. Family capture semantics
// (last-write-wins vs append, descriptor dedup, owner stamping) live on the
// record types; the whole-bag operations fold over `allRecordFields`, so a
// family participates in emptiness checks and absorb adoption by
// construction once its field joins that list —
// `RuntimeRegistrationKindTotalityTests` pins the coverage.
// `ResolvedNode.handlerInventory` is a derived identity-only projection, not
// another registration record family: it is deliberately excluded from
// `allRecordFields` and rebuilt from the selected records at commit seams.

/// The single merge direction every family's `absorbAdopted` uses (F121):
/// on a key collision the ADOPTING record keeps its own entry — the
/// departing record only fills gaps. One named function instead of 14
/// re-encoded closures, so an inverted copy-paste cannot slip past the
/// totality suites (which pin coverage, not direction).
package func mergeKeepingCurrent<Value>(_ current: Value, _ departing: Value) -> Value {
  current
}

/// Re-points every entry of an identity-keyed owner map that still names the
/// `departing` node at the `adopter` (F04).
///
/// Adoption transfers ownership of a departing node's records to the node
/// that absorbed its committed value, so the owner keys must follow. An owner
/// key is not decoration: the publication path's owner-liveness sweep proves
/// departure from `viewNodeID` alone, so an adopted registration still keyed
/// to the absorbed node reads as stale and is torn down even though a live
/// node now carries its record.
package func rehomeAdoptedOwnerKeys<Key>(
  _ owners: inout [Key: RuntimeRegistrationOwnerKey],
  from departing: ViewNodeID,
  to adopter: ViewNodeID
) {
  for (key, owner) in owners where owner.viewNodeID == departing {
    owners[key] = RuntimeRegistrationOwnerKey(
      viewNodeID: adopter,
      identity: owner.identity
    )
  }
}

package struct ActionNodeRecord: RuntimeNodeRecord {
  package var registrations: [Identity: LocalActionRegistry.Registration] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: ActionNodeRecord) {
    registrations.merge(departing.registrations, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    owner: RuntimeRegistrationOwnerKey
  ) {
    owners[identity] = owner
    registrations[identity] = .init(
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }
}

/// A stacked handler family (key press / paste) whose per-identity handler
/// lists carry a persisted contribution ordinal for cross-owner dispatch
/// priority.
package struct ContributedHandlerNodeRecord<Handler>: RuntimeNodeRecord {
  package var handlers: [Identity: [Handler]] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]
  package var ordinals: [Identity: UInt64] = [:]

  package init() {}

  package var isEmpty: Bool {
    handlers.isEmpty
  }

  package mutating func absorbAdopted(_ departing: Self) {
    handlers.merge(departing.handlers, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
    ordinals.merge(departing.ordinals, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    ordinal: UInt64,
    handler: Handler
  ) {
    owners[identity] = .current(identity: identity)
    ordinals[identity] = ordinal
    handlers[identity, default: []].append(handler)
  }
}

package struct KeyHandlerNodeRecord: RuntimeNodeRecord {
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]
  package var keyPress = ContributedHandlerNodeRecord<LocalKeyHandlerRegistry.KeyPressHandler>()
  package var paste = ContributedHandlerNodeRecord<LocalKeyHandlerRegistry.PasteHandler>()

  package init() {}

  package var isEmpty: Bool {
    keyPress.isEmpty && paste.isEmpty
  }

  package mutating func absorbAdopted(_ departing: KeyHandlerNodeRecord) {
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
    keyPress.absorbAdopted(departing.keyPress)
    paste.absorbAdopted(departing.paste)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
    keyPress.rehomeAdoptedOwners(from: departing, to: adopter)
    paste.rehomeAdoptedOwners(from: departing, to: adopter)
  }
}

package struct TerminationNodeRecord: RuntimeNodeRecord {
  package var handlers: [Identity: [LocalTerminationRegistry.Handler]] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  package var isEmpty: Bool {
    handlers.isEmpty
  }

  package mutating func absorbAdopted(_ departing: TerminationNodeRecord) {
    handlers.merge(departing.handlers, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    owners[identity] = .current(identity: identity)
    handlers[identity, default: []].append(handler)
  }
}

package struct PointerNodeRecord: RuntimeNodeRecord {
  package var handlers: [RouteID: LocalPointerHandlerRegistry.Handler] = [:]
  package var handlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  // Ordered stack per route: stacked `.onPointerHover` levels on one chain
  // node share the exact route key, and every level must keep receiving
  // phases — a single-slot map would silently drop all but the last-recorded
  // level. The capture-session reset keeps the append idempotent per pass.
  package var hoverHandlers: [RouteID: [LocalPointerHandlerRegistry.HoverHandler]] = [:]
  package var hoverOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  /// Latest route recorded per authored site (the registering modifier's
  /// structural identity). A derived (entity-keyed) gesture route changes
  /// value when the entity below the site re-mints; out-of-session record
  /// refreshes then land under a NEW dictionary key while the old entry
  /// stays — this map lets a site's re-registration replace its previous
  /// route instead of accumulating one per generation.
  package var structuralRoutes: [Identity: RouteID] = [:]
  /// Hover twin of ``structuralRoutes`` — hover routes derive from the same
  /// entity descent, so a churned entity below a surviving hover site needs
  /// the same per-site replacement.
  package var hoverStructuralRoutes: [Identity: RouteID] = [:]

  package init() {}

  package var isEmpty: Bool {
    handlers.isEmpty && hoverHandlers.isEmpty
  }

  package mutating func absorbAdopted(_ departing: PointerNodeRecord) {
    handlers.merge(departing.handlers, uniquingKeysWith: mergeKeepingCurrent)
    handlerOwners.merge(departing.handlerOwners, uniquingKeysWith: mergeKeepingCurrent)
    hoverHandlers.merge(departing.hoverHandlers, uniquingKeysWith: mergeKeepingCurrent)
    hoverOwners.merge(departing.hoverOwners, uniquingKeysWith: mergeKeepingCurrent)
    // A departing route superseded by this record's same-site registration
    // must not re-enter through the merge above.
    for (site, departingRoute) in departing.structuralRoutes {
      if let currentRoute = structuralRoutes[site], currentRoute != departingRoute {
        handlers.removeValue(forKey: departingRoute)
        handlerOwners.removeValue(forKey: departingRoute)
      }
    }
    structuralRoutes.merge(departing.structuralRoutes, uniquingKeysWith: mergeKeepingCurrent)
    for (site, departingRoute) in departing.hoverStructuralRoutes {
      if let currentRoute = hoverStructuralRoutes[site], currentRoute != departingRoute {
        hoverHandlers.removeValue(forKey: departingRoute)
        hoverOwners.removeValue(forKey: departingRoute)
      }
    }
    hoverStructuralRoutes.merge(
      departing.hoverStructuralRoutes,
      uniquingKeysWith: mergeKeepingCurrent
    )
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&handlerOwners, from: departing, to: adopter)
    rehomeAdoptedOwnerKeys(&hoverOwners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    routeID: RouteID,
    structuralKey: Identity? = nil,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    if let structuralKey {
      if let previousRoute = structuralRoutes[structuralKey], previousRoute != routeID {
        handlers.removeValue(forKey: previousRoute)
        handlerOwners.removeValue(forKey: previousRoute)
      }
      structuralRoutes[structuralKey] = routeID
    }
    handlerOwners[routeID] = .current(identity: routeID.identity)
    handlers[routeID] = handler
  }

  @MainActor
  package mutating func recordHover(
    routeID: RouteID,
    structuralKey: Identity? = nil,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    if let structuralKey {
      if let previousRoute = hoverStructuralRoutes[structuralKey], previousRoute != routeID {
        hoverHandlers.removeValue(forKey: previousRoute)
        hoverOwners.removeValue(forKey: previousRoute)
      }
      hoverStructuralRoutes[structuralKey] = routeID
    }
    // Owner the record under the authored (structural) identity: a derived
    // entity route lives in a re-rooted identity space that subtree-removal
    // prefixes never reach, while the authored site's identity is inside the
    // removable subtree.
    hoverOwners[routeID] = .current(identity: structuralKey ?? routeID.identity)
    hoverHandlers[routeID, default: []].append(handler)
  }
}

package struct GestureNodeRecord: RuntimeNodeRecord {
  package var recognizers: [Identity: AnyGestureRecognizer] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]
  /// Latest registry key recorded per authored site — same replacement
  /// contract as ``PointerNodeRecord/structuralRoutes``.
  package var structuralKeys: [Identity: Identity] = [:]

  package init() {}

  package var isEmpty: Bool {
    recognizers.isEmpty
  }

  /// Re-points owner keys naming `departing` at the adopting node.
  ///
  /// ``absorbAdopted(_:)`` merges the departing node's `owners` forward
  /// verbatim, so an adopted recognizer keeps an owner key naming a node that
  /// is no longer live. `LocalGestureRegistry.prune(keeping:)` proves
  /// departure from that key's `viewNodeID` alone, so the adopted recognizer
  /// is torn down on the next liveness pass even though a live node now
  /// carries its record. Adoption IS the ownership transfer: the key has to
  /// follow the record.
  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  package mutating func absorbAdopted(_ departing: GestureNodeRecord) {
    recognizers.merge(departing.recognizers, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
    for (site, departingKey) in departing.structuralKeys {
      if let currentKey = structuralKeys[site], currentKey != departingKey {
        recognizers.removeValue(forKey: departingKey)
        owners.removeValue(forKey: departingKey)
      }
    }
    structuralKeys.merge(departing.structuralKeys, uniquingKeysWith: mergeKeepingCurrent)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    structuralKey: Identity? = nil,
    recognizer: AnyGestureRecognizer
  ) {
    if let structuralKey {
      if let previousIdentity = structuralKeys[structuralKey], previousIdentity != identity {
        recognizers.removeValue(forKey: previousIdentity)
        owners.removeValue(forKey: previousIdentity)
      }
      structuralKeys[structuralKey] = identity
    }
    owners[identity] = .current(identity: identity)
    recognizers[identity] = recognizer
  }
}

package struct GestureStateNodeRecord: RuntimeNodeRecord {
  package var bindings: [Identity: [AnyGestureStateBinding]] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  package var isEmpty: Bool {
    bindings.isEmpty
  }

  package mutating func absorbAdopted(_ departing: GestureStateNodeRecord) {
    bindings.merge(departing.bindings, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    owners[identity] = .current(identity: identity)
    bindings[identity, default: []].append(binding)
  }
}

package struct FocusBindingNodeRecord: RuntimeNodeRecord {
  package var registrations: [FocusBindingRegistrationSnapshot] = []

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: FocusBindingNodeRecord) {
    registrations.append(contentsOf: departing.registrations)
  }

  @MainActor
  package mutating func record(_ registration: FocusBindingRegistrationSnapshot) {
    registrations.append(registration)
  }
}

package struct FocusedValuesNodeRecord: RuntimeNodeRecord {
  package var registrations: [FocusedValuesRegistrationSnapshot] = []

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: FocusedValuesNodeRecord) {
    registrations.append(contentsOf: departing.registrations)
  }

  @MainActor
  package mutating func record(_ registration: FocusedValuesRegistrationSnapshot) {
    if let existingIndex = registrations.firstIndex(where: {
      $0.identity == registration.identity
    }) {
      registrations[existingIndex].descendantIdentities.formUnion(
        registration.descendantIdentities
      )
      registrations[existingIndex].values.merge(registration.values)
    } else {
      registrations.append(registration)
    }
  }
}

package struct ScrollPositionNodeRecord: RuntimeNodeRecord {
  package var registrations: [ScrollPositionRegistrationSnapshot] = []

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: ScrollPositionNodeRecord) {
    registrations.append(contentsOf: departing.registrations)
  }

  @MainActor
  package mutating func record(_ registration: ScrollPositionRegistrationSnapshot) {
    if let existingIndex = registrations.firstIndex(where: {
      $0.identity == registration.identity
    }) {
      registrations[existingIndex] = registration
    } else {
      registrations.append(registration)
    }
  }
}

package struct TaskNodeRecord: RuntimeNodeRecord {
  package var registrations: [Identity: [TaskRegistration]] = [:]
  package var owners: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: TaskNodeRecord) {
    registrations.merge(departing.registrations, uniquingKeysWith: mergeKeepingCurrent)
    owners.merge(departing.owners, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&owners, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(
    identity: Identity,
    registration: TaskRegistration
  ) {
    owners[identity] = .current(identity: identity)
    var identityRegistrations = registrations[identity] ?? []
    if let index = identityRegistrations.firstIndex(where: {
      $0.descriptor.id == registration.descriptor.id
    }) {
      identityRegistrations[index] = registration
    } else {
      identityRegistrations.append(registration)
    }
    registrations[identity] = identityRegistrations
  }
}

package struct PreferenceObservationNodeRecord: RuntimeNodeRecord {
  package var registrations: [PreferenceObservationRegistrationSnapshot] = []

  package init() {}

  package var isEmpty: Bool {
    registrations.isEmpty
  }

  package mutating func absorbAdopted(_ departing: PreferenceObservationNodeRecord) {
    registrations.append(contentsOf: departing.registrations)
  }

  @MainActor
  package mutating func record(_ registration: PreferenceObservationRegistrationSnapshot) {
    registrations.append(registration)
  }
}

extension DefaultFocusRegistrationSnapshot: RuntimeNodeRecord {
  package init() {
    self.init(scopes: [], candidates: [])
  }

  package var isEmpty: Bool {
    scopes.isEmpty && candidates.isEmpty
  }

  package mutating func absorbAdopted(_ departing: DefaultFocusRegistrationSnapshot) {
    scopes.append(contentsOf: departing.scopes)
    candidates.append(contentsOf: departing.candidates)
  }

  @MainActor
  package mutating func record(_ registration: DefaultFocusScopeRegistrationSnapshot) {
    if !scopes.contains(where: {
      $0.namespace == registration.namespace && $0.identity == registration.identity
    }) {
      scopes.append(registration)
    }
  }

  @MainActor
  package mutating func record(_ registration: DefaultFocusCandidateRegistrationSnapshot) {
    if !candidates.contains(where: {
      $0.namespace == registration.namespace && $0.identity == registration.identity
    }) {
      candidates.append(registration)
    }
  }
}

extension LifecycleHandlerSnapshot: RuntimeNodeRecord {
  package init() {
    self.init(appearRegistrations: [:], disappearRegistrations: [:], changeRegistrations: [:])
  }
}

extension CommandRegistrySnapshot: RuntimeNodeRecord {
  package init() {
    self.init(keyCommandsByScope: [:], ownersByScope: [:])
  }

  package mutating func absorbAdopted(_ departing: CommandRegistrySnapshot) {
    keyCommandsByScope.merge(departing.keyCommandsByScope, uniquingKeysWith: mergeKeepingCurrent)
    ownersByScope.merge(departing.ownersByScope, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&ownersByScope, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(_ registration: CommandRegistrySnapshot) {
    for (identity, commands) in registration.keyCommandsByScope {
      keyCommandsByScope[identity] = commands
      ownersByScope[identity] =
        registration.ownersByScope[identity] ?? .current(identity: identity)
    }
  }
}

extension DropDestinationRegistrySnapshot: RuntimeNodeRecord {
  package init() {
    self.init(handlersByScope: [:], ownersByScope: [:])
  }

  package mutating func absorbAdopted(_ departing: DropDestinationRegistrySnapshot) {
    handlersByScope.merge(departing.handlersByScope, uniquingKeysWith: mergeKeepingCurrent)
    ownersByScope.merge(departing.ownersByScope, uniquingKeysWith: mergeKeepingCurrent)
  }

  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    rehomeAdoptedOwnerKeys(&ownersByScope, from: departing, to: adopter)
  }

  @MainActor
  package mutating func record(_ registration: DropDestinationRegistrySnapshot) {
    for (identity, handler) in registration.handlersByScope {
      handlersByScope[identity] = handler
      ownersByScope[identity] =
        registration.ownersByScope[identity] ?? .current(identity: identity)
    }
  }
}

@MainActor
package struct NodeHandlers {
  package var action = ActionNodeRecord()
  package var keyHandler = KeyHandlerNodeRecord()
  package var termination = TerminationNodeRecord()
  package var pointer = PointerNodeRecord()
  package var gesture = GestureNodeRecord()
  package var gestureState = GestureStateNodeRecord()
  package var defaultFocus = DefaultFocusRegistrationSnapshot()
  package var focusBinding = FocusBindingNodeRecord()
  package var focusedValues = FocusedValuesNodeRecord()
  package var scrollPosition = ScrollPositionNodeRecord()
  package var lifecycle = LifecycleHandlerSnapshot()
  package var task = TaskNodeRecord()
  package var preferenceObservation = PreferenceObservationNodeRecord()
  package var command = CommandRegistrySnapshot()
  package var dropDestination = DropDestinationRegistrySnapshot()

  package init() {}

  /// The uniform record operations of every family field above, in kind
  /// order. `absorbAdopted` and `hasRuntimeRegistrations` fold over this
  /// list, so a family cannot gain a field here without joining both — the
  /// totality suite's absorb-adoption and round-trip tests fail on a missing
  /// entry.
  private struct RecordField {
    let isEmpty: @MainActor (NodeHandlers) -> Bool
    let absorb: @MainActor (inout NodeHandlers, NodeHandlers) -> Void
    /// Re-points this family's adopted owner keys from the departing node to
    /// the adopter, or `nil` for a family that keeps no owner keys. Nil is a
    /// declaration, not an omission: a family that grows an owner map without
    /// filling this in loses the F04 ownership invariant silently.
    let rehomeOwners: (@MainActor (inout NodeHandlers, ViewNodeID, ViewNodeID) -> Void)?
  }

  private static let allRecordFields: [RecordField] = [
    .init(
      isEmpty: { $0.action.isEmpty },
      absorb: { $0.action.absorbAdopted($1.action) },
      rehomeOwners: { $0.action.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.keyHandler.isEmpty },
      absorb: { $0.keyHandler.absorbAdopted($1.keyHandler) },
      rehomeOwners: { $0.keyHandler.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.termination.isEmpty },
      absorb: { $0.termination.absorbAdopted($1.termination) },
      rehomeOwners: { $0.termination.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.pointer.isEmpty },
      absorb: { $0.pointer.absorbAdopted($1.pointer) },
      rehomeOwners: { $0.pointer.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.gesture.isEmpty },
      absorb: { $0.gesture.absorbAdopted($1.gesture) },
      rehomeOwners: { $0.gesture.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.gestureState.isEmpty },
      absorb: { $0.gestureState.absorbAdopted($1.gestureState) },
      rehomeOwners: { $0.gestureState.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.defaultFocus.isEmpty },
      absorb: { $0.defaultFocus.absorbAdopted($1.defaultFocus) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.focusBinding.isEmpty },
      absorb: { $0.focusBinding.absorbAdopted($1.focusBinding) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.focusedValues.isEmpty },
      absorb: { $0.focusedValues.absorbAdopted($1.focusedValues) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.scrollPosition.isEmpty },
      absorb: { $0.scrollPosition.absorbAdopted($1.scrollPosition) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.lifecycle.isEmpty },
      absorb: { $0.lifecycle.absorbAdopted($1.lifecycle) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.task.isEmpty },
      absorb: { $0.task.absorbAdopted($1.task) },
      rehomeOwners: { $0.task.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.preferenceObservation.isEmpty },
      absorb: { $0.preferenceObservation.absorbAdopted($1.preferenceObservation) },
      rehomeOwners: nil
    ),
    .init(
      isEmpty: { $0.command.isEmpty },
      absorb: { $0.command.absorbAdopted($1.command) },
      rehomeOwners: { $0.command.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
    .init(
      isEmpty: { $0.dropDestination.isEmpty },
      absorb: { $0.dropDestination.absorbAdopted($1.dropDestination) },
      rehomeOwners: { $0.dropDestination.rehomeAdoptedOwners(from: $1, to: $2) }
    ),
  ]

  package mutating func reset() {
    self = .init()
  }

  /// Absorbs a departing node's recorded registrations into this node's
  /// bookkeeping. Used when an absorbed shadowed interior mint is reclaimed
  /// (see `ViewGraph.pruneAbsorbedShadowedNodes`): the chain collapse already
  /// hands the interior's committed value to the absorber, so the interior's
  /// recorded registrations must follow — otherwise the next registration
  /// publication rebuilds from live nodes only and silently drops the
  /// interior's handlers and tasks ("no task registration at commit").
  /// Collisions keep this node's own entries; the departing node's identities
  /// are its own resolve products and disjoint from the absorber's in
  /// practice.
  package mutating func absorbAdopted(_ departing: NodeHandlers) {
    for field in Self.allRecordFields {
      field.absorb(&self, departing)
    }
  }

  /// Re-points every adopted owner key from `departing` onto `adopter`
  /// (F04). Adoption transfers ownership of the departing node's records, and
  /// an owner key is what the publication path's owner-liveness sweep reads:
  /// a key left naming the absorbed node makes a live, adopted registration
  /// look like a stale one and it is torn down. Previously only the gesture
  /// family did this, for exactly that reason; the sweep now reaches every
  /// owner-keyed family, so the rehome does too.
  package mutating func rehomeAdoptedOwners(
    from departing: ViewNodeID,
    to adopter: ViewNodeID
  ) {
    for field in Self.allRecordFields {
      field.rehomeOwners?(&self, departing, adopter)
    }
  }

  package var hasRuntimeRegistrations: Bool {
    Self.allRecordFields.contains { !$0.isEmpty(self) }
  }

  /// `true` when any effect family has content. The effect families are
  /// exactly the restore sources of the `isEffectRegistry` registries
  /// (lifecycle, task, preference observation); the always-full effect
  /// republication walk visits every live node each commit, and this guard
  /// lets the handler-less bulk skip the per-registry restore calls (F63).
  /// A new effect family must join this disjunction when its registry sets
  /// `isEffectRegistry` — `restoreEffectRegistrations` reads only these
  /// three today.
  package var hasEffectRegistrations: Bool {
    !lifecycle.isEmpty || !task.isEmpty || !preferenceObservation.isEmpty
  }

  package mutating func recordAction(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: .current(identity: identity)
    )
  }

  package mutating func recordAction(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    owner: RuntimeRegistrationOwnerKey
  ) {
    action.record(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: owner
    )
  }

  package mutating func recordKeyPressHandler(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    keyHandler.keyPress.record(identity: identity, ordinal: ordinal, handler: handler)
  }

  package mutating func recordPasteHandler(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    keyHandler.paste.record(identity: identity, ordinal: ordinal, handler: handler)
  }

  package mutating func recordTerminationHandler(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    termination.record(identity: identity, handler: handler)
  }

  package mutating func recordPointerHandler(
    routeID: RouteID,
    structuralKey: Identity? = nil,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    pointer.record(routeID: routeID, structuralKey: structuralKey, handler: handler)
  }

  package mutating func recordPointerHoverHandler(
    routeID: RouteID,
    structuralKey: Identity? = nil,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    pointer.recordHover(routeID: routeID, structuralKey: structuralKey, handler: handler)
  }

  package mutating func recordGesture(
    identity: Identity,
    structuralKey: Identity? = nil,
    recognizer: AnyGestureRecognizer
  ) {
    gesture.record(identity: identity, structuralKey: structuralKey, recognizer: recognizer)
  }

  package mutating func recordGestureStateBinding(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    gestureState.record(identity: identity, binding: binding)
  }

  package mutating func recordDefaultFocus(
    _ registration: DefaultFocusScopeRegistrationSnapshot
  ) {
    defaultFocus.record(registration)
  }

  package mutating func recordDefaultFocus(
    _ registration: DefaultFocusCandidateRegistrationSnapshot
  ) {
    defaultFocus.record(registration)
  }

  package mutating func recordFocusBinding(
    _ registration: FocusBindingRegistrationSnapshot
  ) {
    focusBinding.record(registration)
  }

  package mutating func recordFocusedValues(
    _ registration: FocusedValuesRegistrationSnapshot
  ) {
    focusedValues.record(registration)
  }

  package mutating func recordScrollPosition(
    _ registration: ScrollPositionRegistrationSnapshot
  ) {
    scrollPosition.record(registration)
  }

  package mutating func recordLifecycleAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycle.recordAppear(registration)
  }

  package mutating func recordLifecycleDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycle.recordDisappear(registration)
  }

  package mutating func recordLifecycleChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycle.recordChange(registration)
  }

  package mutating func recordTask(
    identity: Identity,
    registration: TaskRegistration
  ) {
    task.record(identity: identity, registration: registration)
  }

  package mutating func recordPreferenceObservation(
    _ registration: PreferenceObservationRegistrationSnapshot
  ) {
    preferenceObservation.record(registration)
  }

  package mutating func recordCommand(
    _ registration: CommandRegistrySnapshot
  ) {
    command.record(registration)
  }

  package mutating func recordDropDestination(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    dropDestination.record(registration)
  }
}
