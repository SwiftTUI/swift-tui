package import SwiftTUIGraph

// The dynamic-property update pass — discovery and execution.
//
// Views (and dynamic properties) declare wrappers as stored properties; the
// framework discovers the ones conforming to `DynamicProperty` with a
// reflect-once-per-type descriptor and runs `update(in:)` on each before the
// body evaluates, under the same ambient authoring context the body will
// observe. Wrapper-free types pay one dictionary lookup per evaluation and no
// reflection after the first (the `.empty`-plan fast path).
//
// Per-evaluation application is plan-dispatched: struct containers whose
// discovered fields are statically wrapper-typed get an *offset plan* —
// applicator closures bound once per type via `RuntimeFieldReflection` that
// run each wrapper's update *in place*, at its byte offset inside the
// container's own value memory, replacing the per-instance `Mirror` walk
// (which allocated a mirror and boxed every child per body evaluation).
// Exotic shapes (enum containers, and fields whose *static* type does not
// conform — e.g. an existential- or `Any`-typed field boxing a wrapper) keep
// the legacy `Mirror` walk, so discovery semantics are unchanged; only the
// application mechanism differs. A class container is not an exotic shape but
// an invariant violation: authored containers are value types, and the
// builder traps on one (see `ValueTypeAuthoringInvariant`).
//
// `DynamicProperty.update(in:)` is mutating (plan 2026-08-30-001). The pass
// runs it through the container copy the *next body evaluation consumes* —
// `resolveView` names that copy `prepared` and threads it into
// `resolveViewElements`, where the capture-bind pass makes the final body
// value from it. A stored mutation is therefore visible to the body and to
// every closure the body creates.
//
// The `Mirror` tier cannot write back: a `Mirror` child is a copy and an enum
// payload has no addressable field slot. That tier updates an extracted copy,
// exactly as the whole pass did before, and DEBUG builds compare the wrapper's
// bytes before and after to report a discarded mutation as the
// `dynamic-property-mutation-discarded` soundness violation rather than losing
// it silently.

/// A type's discovered dynamic-property layout: the stored-property indices
/// (in `Mirror` child order) whose values conform to ``DynamicProperty``.
package struct DynamicPropertyDescriptor: Sendable {
  package struct Field: Sendable {
    /// Position in `Mirror(reflecting:).children` order.
    package var index: Int
    /// The stored-property label (`_count` for `@State var count`), for
    /// diagnostics only.
    package var label: String?
  }

  package var fields: [Field]

  package var isEmpty: Bool {
    fields.isEmpty
  }

  package static let empty = DynamicPropertyDescriptor(fields: [])
}

/// The container-scoped inputs one field applicator needs: the enclosing
/// container's type (for the lease registration key and diagnostics) and the
/// container's own discovered-property path. A field appends its index to that
/// path for its *nested* wrappers' slots, while its own `update(in:)` runs
/// under the container's path — a top-level built-in must keep the legacy
/// unqualified slot identity.
package struct DynamicPropertyFieldUpdateInputs {
  package var containerType: Any.Type
  package var containerPath: StateSlotPath

  package init(containerType: Any.Type, containerPath: StateSlotPath) {
    self.containerType = containerType
    self.containerPath = containerPath
  }
}

/// Updates one discovered dynamic-property field *in place*, at its byte
/// offset inside the container's value memory. The field's concrete type and
/// offset are bound at plan-build time; the closure body does no reflection.
///
/// Replaces the extract-a-copy shape this tier used before plan
/// 2026-08-30-001: `update(in:)` is mutating, so the write has to land in the
/// container copy the body evaluation consumes, not in a temporary. Removing
/// the extraction also removes an `any DynamicProperty` box per field per
/// evaluation.
///
/// `@unsafe` because applying the applicator to a raw base pointer is the
/// unsafe act; every application site spells `unsafe`.
@unsafe package struct DynamicPropertyFieldApplicator {
  /// Position in `Mirror(reflecting:).children` order — the slot-path
  /// ordinal nested wrappers key their state identity on.
  package let index: Int
  package let apply:
    @MainActor (UnsafeMutableRawPointer, DynamicPropertyFieldUpdateInputs) ->
      DynamicPropertyUpdateResult

  package init(
    index: Int,
    apply:
      @escaping @MainActor (
        UnsafeMutableRawPointer, DynamicPropertyFieldUpdateInputs
      ) -> DynamicPropertyUpdateResult
  ) {
    unsafe self.index = index
    unsafe self.apply = apply
  }
}

/// How the update pass reaches one container type's dynamic properties.
@unsafe package enum DynamicPropertyUpdatePlan {
  /// No discovered dynamic properties — the pass returns immediately.
  case empty
  /// Struct container with statically wrapper-typed fields: update each in
  /// place through its bound offset applicator.
  case offsets([DynamicPropertyFieldApplicator])
  /// Correctness fallback for shapes the offset tier cannot prove
  /// (class/enum containers, existential-typed fields, weak storage): the
  /// legacy per-instance `Mirror` walk.
  case mirrorWalk(DynamicPropertyDescriptor)
}

/// Diagnostic plan-kind labels for ``DynamicPropertyDescriptorCache``'s safe
/// classification API.
package enum DynamicPropertyPlanKind: String, Sendable {
  case empty
  case offsets
  case mirrorWalk
}

/// Reflect-once-per-type cache of ``DynamicPropertyUpdatePlan``s.
///
/// Struct and class layouts are fixed per type, so their plans normally cache
/// permanently. Static fields that permit dynamically conforming values are
/// included proactively in a stable Mirror-walk plan even when the first
/// instance is plain. Enum values (whose reflected children vary by case)
/// are rebuilt per value and never cached — no view or wrapper in the framework
/// is enum-shaped, so this is a correctness backstop, not a hot path.
/// Computed properties are invisible to `Mirror` and to the runtime field
/// metadata — discovery sees stored properties only, matching SwiftUI.
@MainActor
package enum DynamicPropertyDescriptorCache {
  private static var plansByType: [ObjectIdentifier: DynamicPropertyUpdatePlan] = unsafe [:]

  /// Lookup-only fast path, keyed by the container's concrete type so warm
  /// evaluations never box the container into `Any`.
  package static func cachedUpdatePlan(for type: Any.Type) -> DynamicPropertyUpdatePlan? {
    unsafe plansByType[ObjectIdentifier(type)]
  }

  /// Build-if-missing (cold per type; per value for enum containers).
  package static func updatePlan(reflecting value: Any) -> DynamicPropertyUpdatePlan {
    let key = ObjectIdentifier(type(of: value))
    if let cached = unsafe plansByType[key] {
      return unsafe cached
    }
    let mirror = Mirror(reflecting: value)
    let storage = valueDependentStorage(
      buildDescriptor(from: mirror),
      containerType: type(of: value)
    )
    let descriptor = storage.descriptor
    // A container with no dynamic properties but with opaque reference storage
    // still needs a non-`.empty` plan: that is the whole fail-closed reuse
    // signal (see `valueDependentStorage`). An empty-descriptor `.mirrorWalk`
    // says "no update surface to walk, but do not certify me".
    let vacuousPlan: DynamicPropertyUpdatePlan =
      storage.hasOpaqueReferenceStorage ? unsafe .mirrorWalk(.empty) : unsafe .empty
    switch mirror.displayStyle {
    case .struct:
      if descriptor.isEmpty {
        return unsafe cachePlan(vacuousPlan, key: key)
      }
      return unsafe cachePlan(
        offsetsPlan(for: type(of: value), descriptor: descriptor)
          ?? .mirrorWalk(descriptor),
        key: key
      )
    case .class:
      // Unreachable from Swift source: every authoring protocol a container
      // can reach this builder through rejects class conformers at compile
      // time. See ValueTypeAuthoringInvariant.
      ValueTypeAuthoringInvariant.rejectClassContainer(type(of: value))
    default:
      return descriptor.isEmpty ? unsafe vacuousPlan : unsafe .mirrorWalk(descriptor)
    }
  }

  private static func cachePlan(
    _ plan: DynamicPropertyUpdatePlan,
    key: ObjectIdentifier
  ) -> DynamicPropertyUpdatePlan {
    unsafe plansByType[key] = plan
    return unsafe plan
  }

  /// Diagnostic classification of the plan a value's type gets (safe API for
  /// tests and traces).
  package static func diagnosticPlanKind(reflecting value: Any) -> DynamicPropertyPlanKind {
    switch unsafe updatePlan(reflecting: value) {
    case .empty: return .empty
    case .offsets: return .offsets
    case .mirrorWalk: return .mirrorWalk
    }
  }

  /// Whether a plan is cached for `type` (safe API for tests; enum
  /// containers never cache).
  package static func hasCachedPlan(for type: Any.Type) -> Bool {
    unsafe cachedUpdatePlan(for: type) != nil
  }

  /// Test seam: drops all cached plans.
  package static func resetForTesting() {
    unsafe plansByType.removeAll(keepingCapacity: false)
  }

  private static func buildDescriptor(from mirror: Mirror) -> DynamicPropertyDescriptor {
    var fields: [DynamicPropertyDescriptor.Field] = []
    for (index, child) in mirror.children.enumerated() where child.value is any DynamicProperty {
      fields.append(.init(index: index, label: child.label))
    }
    guard !fields.isEmpty else {
      return .empty
    }
    return DynamicPropertyDescriptor(fields: fields)
  }

  /// Classifies a container's value-dependent stored fields. Two unrelated
  /// jobs used to share one descriptor; they are separated here.
  ///
  /// **Discovery.** An existential field (`Any`, `any Protocol`) can carry a
  /// later concrete value whose conformance differs from this instance's, so it
  /// joins the descriptor: the resulting stable `Mirror` plan runtime-checks it
  /// each evaluation, and both plain-first and DynamicProperty-first orderings
  /// are sound.
  ///
  /// **Fail-closed reuse.** A class-typed field can no longer *gain* a
  /// `DynamicProperty` conformance — a class cannot conform (plan
  /// 2026-08-29-001) — but a plain stored reference is still not
  /// value-verifiable: its visible output can change with no change to the view
  /// value at all. A non-`.empty` plan is what makes
  /// `hasDynamicPropertyUpdateSurface` deny reuse for that shape, so class
  /// fields are reported as `hasOpaqueReferenceStorage` and the builder gives
  /// such a container an empty-descriptor `.mirrorWalk`. Pinned by
  /// `TabStripValueVerifiedSlotTests.storedReferenceContentRemainsFailClosed`.
  ///
  /// Keeping class fields *out* of the descriptor is what lets the common
  /// shape — wrappers alongside an `@Observable` model, a closure log, a
  /// resource handle — reach the in-place offsets tier. Listing them there
  /// made `offsetsPlan` bail on a field it could never bind, demoting the
  /// container to the copy-updating `Mirror` walk and silently dropping the
  /// stored mutations plan 2026-08-30-001 promises.
  private static func valueDependentStorage(
    _ descriptor: DynamicPropertyDescriptor,
    containerType: Any.Type
  ) -> (descriptor: DynamicPropertyDescriptor, hasOpaqueReferenceStorage: Bool) {
    var fieldsByIndex = Dictionary(
      uniqueKeysWithValues: descriptor.fields.map { ($0.index, $0) }
    )
    var hasOpaqueReferenceStorage = false
    let fieldCount = RuntimeFieldReflection.fieldCount(of: containerType)
    for index in 0..<fieldCount {
      let field = RuntimeFieldReflection.fieldInfo(
        of: containerType,
        at: index
      )
      switch RuntimeFieldReflection.metadataKind(of: field.fieldType) {
      case 0x303:
        fieldsByIndex[index] = .init(index: index, label: field.name)
      case 0, 0x203, 0x305:
        // Native/foreign classes and Objective-C class wrappers.
        hasOpaqueReferenceStorage = true
      default:
        continue
      }
    }
    return (
      DynamicPropertyDescriptor(
        fields: fieldsByIndex.values.sorted { $0.index < $1.index }
      ),
      hasOpaqueReferenceStorage
    )
  }

  /// Binds one extractor per discovered field, or `nil` when any field
  /// resists static binding (existential/`Any`-typed storage boxing a
  /// wrapper, weak references, or metadata that disagrees with the `Mirror`
  /// discovery) — those types keep the `Mirror` walk.
  private static func offsetsPlan(
    for containerType: Any.Type,
    descriptor: DynamicPropertyDescriptor
  ) -> DynamicPropertyUpdatePlan? {
    let fieldCount = RuntimeFieldReflection.fieldCount(of: containerType)
    var applicators: [DynamicPropertyFieldApplicator] = unsafe []
    unsafe applicators.reserveCapacity(descriptor.fields.count)
    for field in descriptor.fields {
      guard field.index < fieldCount else {
        return nil
      }
      let info = RuntimeFieldReflection.fieldInfo(of: containerType, at: field.index)
      guard info.isStrong else {
        return nil
      }
      if let label = field.label, label != info.name {
        return nil
      }
      guard
        let updating = openedFieldShim(boundTo: info.fieldType)
          as? any DynamicPropertyFieldUpdating.Type
      else {
        // The static field type does not conform (`any DynamicProperty`,
        // `Any`, a supertype) even though this instance's value does. There
        // is no writable, statically typed slot to update through.
        return nil
      }
      unsafe applicators.append(
        unsafe updating.applicator(atOffset: info.offset, index: field.index)
      )
    }
    return unsafe .offsets(applicators)
  }
}

/// Rebinds the shim's generic parameter to `fieldType` so the conditional
/// conformance (`where T: DynamicProperty`) can be tested at runtime.
@MainActor
private func openedFieldShim(boundTo fieldType: Any.Type) -> Any.Type {
  func open<F>(_ concrete: F.Type) -> Any.Type {
    DynamicPropertyFieldShim<F>.self
  }
  return _openExistential(fieldType, do: open)
}

@MainActor
package protocol AdditionalDynamicPropertyUpdating {
  /// True when this transparent container forwards the stored field itself.
  /// Outer discovery must not also traverse that field under the container's
  /// scope and path.
  func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool

  /// Mutating: a transparent container's forwarded payload is updated in
  /// place, in the same working copy the body evaluation consumes (plan
  /// 2026-08-30-001 §3.4).
  mutating func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult

  /// Whether the explicitly forwarded payload currently carries any update
  /// surface. Containers answer recursively so a wrapper-free transparent
  /// value does not turn a local fail-closed policy into an enclosing reuse
  /// denial merely because it participates in forwarding.
  func hasAdditionalDynamicPropertyUpdateSurface() -> Bool
}

@MainActor
package struct AdditionalDynamicPropertyUpdateContext {
  package let resolveContext: ResolveContext
  package let graphNode: SwiftTUICore.ViewNode?

  package var destinationAuthoringContext: AuthoringContext {
    makeAuthoringContext(for: resolveContext, viewNode: graphNode)
  }
}

/// One synchronous `resolveView` invocation's forwarded-preparation entries.
///
/// Transparent primitive modifiers prepare their base before the modifier's
/// own reuse door. The later nested central resolve consumes that preparation
/// instead of clearing the same node's lease census and walking the value a
/// second time. Frames form a strict synchronous stack: an entry is scoped to
/// the exact graph node, resolve identity/path, value type, producer
/// generation, and LIFO occurrence. Unconsumed entries disappear with the
/// producer frame on memo service, early return, or abort.
@MainActor
package enum ForwardedDynamicPropertyPreparationScope {
  private final class Frame {
    let generation: UInt64
    var entries: [Entry] = []

    init(generation: UInt64) {
      self.generation = generation
    }
  }

  private struct Entry {
    let producerGeneration: UInt64
    let occurrence: UInt64
    let graphID: ObjectIdentifier?
    let graphNodeID: ViewNodeID?
    let identity: Identity
    let structuralPath: StructuralPath
    let valueType: ObjectIdentifier
    let context: ResolveContext
    let result: DynamicPropertyUpdateResult
    /// The producer's prepared value, so the consumer resolves the copy whose
    /// dynamic properties actually updated rather than its own unprepared one
    /// (plan 2026-08-30-001 §3.5). `nil` for a container with no update
    /// surface — the overwhelming majority — so that case boxes nothing.
    let preparedValue: Any?
  }

  package struct Token {
    fileprivate let generation: UInt64
  }

  private static var frames: [Frame] = []
  private static var nextGeneration: UInt64 = 0
  private static var nextOccurrence: UInt64 = 0

  package static func begin() -> Token {
    nextGeneration &+= 1
    let frame = Frame(generation: nextGeneration)
    frames.append(frame)
    return Token(generation: frame.generation)
  }

  package static func end(_ token: Token) {
    precondition(frames.last?.generation == token.generation)
    _ = frames.popLast()
  }

  package static func record<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?,
    result: DynamicPropertyUpdateResult
  ) {
    guard let frame = frames.last else { return }
    nextOccurrence &+= 1
    frame.entries.append(
      Entry(
        producerGeneration: frame.generation,
        occurrence: nextOccurrence,
        graphID: context.viewGraph.map(ObjectIdentifier.init),
        graphNodeID: graphNode?.viewNodeID,
        identity: context.identity,
        structuralPath: context.structuralPath,
        valueType: ObjectIdentifier(type(of: value)),
        context: context,
        result: result,
        preparedValue: carriesPreparation(value) ? value : nil
      )
    )
  }

  /// A cheap *sufficient* condition for "the producer may have mutated this
  /// value": its own plan is non-empty, or it forwards a payload it may have
  /// mutated. A wrapper-free view answers `false` from one dictionary lookup
  /// and its entry boxes nothing.
  ///
  /// Deliberately not `hasDynamicPropertyUpdateSurface`, whose recursive answer
  /// would walk a whole modifier chain once per chain edge — quadratic in the
  /// chain length, for a question this only needs a conservative `true` for.
  @MainActor
  private static func carriesPreparation<V>(_ value: V) -> Bool {
    if value is any AdditionalDynamicPropertyUpdating {
      return true
    }
    let plan =
      unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: value))
      ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: value)
    switch unsafe plan {
    case .empty:
      return false
    case .offsets, .mirrorWalk:
      return true
    }
  }

  package static func preparedContext<V>(
    for value: V,
    fallback: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> ResolveContext? {
    matchingProducerEntry(
      value,
      context: fallback,
      graphNode: graphNode
    )?.context
  }

  /// Consumes the nearest matching ancestor preparation, substituting the
  /// producer's prepared value for `value`. The entry match already requires
  /// an identical concrete type (plus graph, node, identity, and structural
  /// path) under strict LIFO, so the downcast cannot pick a foreign value.
  package static func take<V>(
    _ value: inout V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> DynamicPropertyUpdateResult? {
    guard
      let index = matchingFrameIndex(
        value,
        context: context,
        graphNode: graphNode
      )
    else { return nil }
    // Strict LIFO is the occurrence proof for nested same-identity/same-type
    // transparent layers. Never search past a mismatching latest entry.
    let entry = frames[index].entries.removeLast()
    if let prepared = entry.preparedValue as? V {
      value = prepared
    }
    return entry.result
  }

  private static func matchingProducerEntry<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> Entry? {
    guard
      let index = matchingFrameIndex(
        value,
        context: context,
        graphNode: graphNode,
        includesCurrentFrame: true
      )
    else { return nil }
    return frames[index].entries.last
  }

  private static func matchingFrameIndex<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?,
    includesCurrentFrame: Bool = false
  ) -> Int? {
    let start = frames.count - (includesCurrentFrame ? 1 : 2)
    guard start >= 0 else { return nil }
    let graphID = context.viewGraph.map(ObjectIdentifier.init)
    let valueType = ObjectIdentifier(type(of: value))
    // The current frame is the consumer. Only an active ancestor may have
    // prepared it, and the nearest ancestor with pending work owns the next
    // occurrence.
    for index in stride(from: start, through: 0, by: -1) {
      guard let entry = frames[index].entries.last else { continue }
      guard entry.producerGeneration == frames[index].generation,
        entry.occurrence <= nextOccurrence,
        entry.graphID == graphID,
        entry.graphNodeID == graphNode?.viewNodeID,
        entry.identity == context.identity,
        entry.structuralPath == context.structuralPath,
        entry.valueType == valueType
      else {
        return nil
      }
      return index
    }
    return nil
  }
}

/// Runs the update pass over the working copy `view`, in place.
///
/// `inout` is the whole point: `update(in:)` is mutating, and the copy this
/// call writes through is the one `resolveView` hands to `resolveViewElements`
/// and therefore to the body. The *authored* value stays untouched at the
/// caller — memo comparison, value-verified reuse, the stored evaluator, and
/// deferred descent all keep using it.
@MainActor
package func prepareDynamicProperties<V>(
  of view: inout V,
  in context: ResolveContext,
  routeIdentity: EntityIdentity?,
  authoringContextOverride: AuthoringContext?
) -> DynamicPropertyUpdateResult {
  let existingGraphNode: SwiftTUICore.ViewNode?
  if let routeIdentity,
    let routed = context.viewGraph?.nodeForEntityIdentity(routeIdentity)
  {
    existingGraphNode = routed
  } else {
    existingGraphNode = context.viewGraph?.nodeForIdentity(context.identity)
  }
  if let prepared = ForwardedDynamicPropertyPreparationScope.take(
    &view,
    context: context,
    graphNode: existingGraphNode
  ) {
    // `take` also substituted the ancestor's prepared value into `view`.
    return prepared
  }
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: view))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: view)
  let hasDirectProperties: Bool
  switch unsafe plan {
  case .empty: hasDirectProperties = false
  case .offsets, .mirrorWalk: hasDirectProperties = true
  }
  let additional = view as? any AdditionalDynamicPropertyUpdating
  let graphNode = context.viewGraph?.prepareDynamicPropertyUpdate(
    identity: context.identity,
    entityIdentity: routeIdentity
  )
  guard hasDirectProperties || additional != nil else {
    return .unchanged
  }
  let scope =
    authoringContextOverride.map { rebasedAuthoringContext($0, viewNode: graphNode) }
    ?? dynamicPropertyAuthoringContext(
      for: context,
      current: currentAuthoringContext(),
      viewNode: graphNode
    )
  let additionalContext = AdditionalDynamicPropertyUpdateContext(
    resolveContext: context,
    graphNode: graphNode
  )

  return EnvironmentValuesStorage.binding(context.environmentValues) {
    ViewNodeContext.withCurrentValue(graphNode) {
      withAuthoringContext(scope) {
        runDynamicPropertyUpdates(on: &view, in: additionalContext)
      }
    }
  }
}

/// Runs every update source carried directly by `value`: discovered stored
/// properties plus a transparent container's explicitly forwarded payload.
/// Callers own graph preparation and the authoring scope.
@MainActor
package func runDynamicPropertyUpdates<V>(
  on value: inout V,
  in context: AdditionalDynamicPropertyUpdateContext
) -> DynamicPropertyUpdateResult {
  // Read-only: names the fields the container forwards itself, so the outer
  // walk skips them. The forwarded update below is the mutating half.
  let traversalOwner = value as? any AdditionalDynamicPropertyUpdating
  var result = runDynamicPropertyUpdatePass(
    on: &value,
    excludingFieldsOwnedBy: traversalOwner
  )
  if traversalOwner != nil {
    result = result.merging(
      updateAdditionalDynamicPropertiesInPlace(of: &value, in: context)
    )
  }
  return result
}

/// Runs a transparent container's forwarded update through its own value
/// memory. The conformance is bound once per container type by a shim, so the
/// mutating call costs no existential box — `ModifiedContent` is on the warm
/// path of every modified view.
@MainActor
private func updateAdditionalDynamicPropertiesInPlace<V>(
  of value: inout V,
  in context: AdditionalDynamicPropertyUpdateContext
) -> DynamicPropertyUpdateResult {
  unsafe withMutableConcreteValue(&value) { base, concreteType in
    guard
      let forwarding = openedAdditionalShim(boundTo: concreteType)
        as? any AdditionalDynamicPropertyForwarding.Type
    else {
      return .unchanged
    }
    return unsafe forwarding.forwardUpdate(atBase: base, in: context)
  }
}

/// Whether `value` has a direct or explicitly forwarded update surface.
///
/// Containers use this before conservatively denying an enclosing reuse door.
/// Wrapper-free values must not turn a local fail-closed traversal policy into
/// a global reuse shutdown.
@MainActor
package func hasDynamicPropertyUpdateSurface<V>(_ value: V) -> Bool {
  if value is any DynamicProperty {
    return true
  }
  if let additional = value as? any AdditionalDynamicPropertyUpdating {
    return additional.hasAdditionalDynamicPropertyUpdateSurface()
  }
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: value))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: value)
  switch unsafe plan {
  case .empty:
    return false
  case .offsets, .mirrorWalk:
    return true
  }
}

/// Runs a transparent payload as its own root value. Its stored properties use
/// root-relative paths, and a payload that is itself DynamicProperty receives
/// its own update after those nested properties.
@MainActor
package func runForwardedDynamicPropertyUpdates<V>(
  on value: inout V,
  in context: AdditionalDynamicPropertyUpdateContext
) -> DynamicPropertyUpdateResult {
  let result = runDynamicPropertyUpdates(on: &value, in: context)
  guard value is any DynamicProperty else {
    return result
  }
  let ownResult = unsafe withMutableConcreteValue(&value) { base, concreteType in
    guard
      let updating = openedFieldShim(boundTo: concreteType)
        as? any DynamicPropertyFieldUpdating.Type
    else {
      return .uncertified
    }
    return unsafe updating.updateRootValue(atBase: base, containerType: concreteType)
  }
  return result.merging(ownResult)
}

/// Conditional-conformance shim: `DynamicPropertyFieldShim<F>` conforms only
/// when `F: DynamicProperty`, so an `as? any ...Updating.Type` cast is the
/// runtime conformance test — and inside the conformance, `T` is bound with
/// its constraint so every access is statically typed and the mutating
/// `update(in:)` is callable through a pointer.
private protocol DynamicPropertyFieldUpdating {
  /// The offset-bound applicator the `.offsets` plan stores.
  @MainActor static func applicator(atOffset offset: Int, index: Int)
    -> DynamicPropertyFieldApplicator

  /// A transparently forwarded payload that is itself a dynamic property:
  /// its own `update(in:)` at root paths, after its nested walk.
  @MainActor static func updateRootValue(
    atBase base: UnsafeMutableRawPointer,
    containerType: Any.Type
  ) -> DynamicPropertyUpdateResult

  /// The `Mirror` tier's write-back-less path: update an extracted copy and
  /// report whether the wrapper mutated itself, so the discard is loud.
  @MainActor static func updateExtracted(
    _ property: any DynamicProperty,
    index: Int,
    inputs: DynamicPropertyFieldUpdateInputs
  ) -> (result: DynamicPropertyUpdateResult, mutated: Bool)
}

private enum DynamicPropertyFieldShim<T> {}

extension DynamicPropertyFieldShim: DynamicPropertyFieldUpdating where T: DynamicProperty {
  static func applicator(atOffset offset: Int, index: Int) -> DynamicPropertyFieldApplicator {
    unsafe DynamicPropertyFieldApplicator(index: index) { base, inputs in
      unsafe applyDynamicPropertyField(
        at: (base + offset).assumingMemoryBound(to: T.self),
        index: index,
        inputs: inputs
      )
    }
  }

  static func updateRootValue(
    atBase base: UnsafeMutableRawPointer,
    containerType: Any.Type
  ) -> DynamicPropertyUpdateResult {
    unsafe updateDynamicPropertyValue(
      at: base.assumingMemoryBound(to: T.self),
      containerType: containerType,
      propertyPath: .root,
      updatePath: .root
    )
  }

  static func updateExtracted(
    _ property: any DynamicProperty,
    index: Int,
    inputs: DynamicPropertyFieldUpdateInputs
  ) -> (result: DynamicPropertyUpdateResult, mutated: Bool) {
    guard var copy = property as? T else {
      return (.uncertified, false)
    }
    return unsafe withUnsafeMutablePointer(to: &copy) { pointer in
      // Snapshot and compare at the SAME address: a value-witness copy into a
      // second buffer leaves padding indeterminate, which would make the
      // comparison report phantom mutations.
      let detects = discardDetectionEnabled
      let size = MemoryLayout<T>.size
      let before: [UInt8]
      if detects, size > 0 {
        before = unsafe [UInt8](UnsafeRawBufferPointer(start: pointer, count: size))
      } else {
        before = []
      }
      let result = unsafe applyDynamicPropertyField(
        at: pointer,
        index: index,
        inputs: inputs
      )
      guard detects, size > 0 else {
        return (result, false)
      }
      let after = unsafe UnsafeRawBufferPointer(start: pointer, count: size)
      return (result, unsafe !before.elementsEqual(after))
    }
  }
}

/// Conditional-conformance shim for the transparent-forwarding protocol, so a
/// container's mutating forwarded update is reachable through its value memory
/// without boxing the container into an existential.
private protocol AdditionalDynamicPropertyForwarding {
  @MainActor static func forwardUpdate(
    atBase base: UnsafeMutableRawPointer,
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult
}

private enum AdditionalDynamicPropertyShim<T> {}

extension AdditionalDynamicPropertyShim: AdditionalDynamicPropertyForwarding
where T: AdditionalDynamicPropertyUpdating {
  static func forwardUpdate(
    atBase base: UnsafeMutableRawPointer,
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    unsafe base.assumingMemoryBound(to: T.self).pointee
      .updateAdditionalDynamicProperties(in: context)
  }
}

/// Rebinds the shim's generic parameter to `containerType` so the conditional
/// conformance (`where T: AdditionalDynamicPropertyUpdating`) can be tested at
/// runtime.
@MainActor
private func openedAdditionalShim(boundTo containerType: Any.Type) -> Any.Type {
  func open<C>(_ concrete: C.Type) -> Any.Type {
    AdditionalDynamicPropertyShim<C>.self
  }
  return _openExistential(containerType, do: open)
}

/// Whether the `Mirror` tier pays for discarded-mutation detection.
///
/// DEBUG only — the byte snapshot allocates. Deliberately *not* gated on
/// `SoundnessProbeConfiguration.isEnabled` the way the hot-path oracles are:
/// this tier is a rare correctness backstop, and a test that switches the probe
/// off for tracing reasons would otherwise make the discard silent again.
@MainActor
private var discardDetectionEnabled: Bool {
  #if DEBUG
    return true
  #else
    return false
  #endif
}

/// Runs `body` over `value`'s concrete value memory, mutably.
///
/// For a concrete `V` — every current caller — that is a pointer to `value`
/// itself. For an existential `V` the boxed value is opened into a local,
/// mutated, and written back: a pointer to `value` would address the box, not
/// the value a plan's offsets describe.
@MainActor
private func withMutableConcreteValue<V>(
  _ value: inout V,
  _ body: (UnsafeMutableRawPointer, Any.Type) -> DynamicPropertyUpdateResult
) -> DynamicPropertyUpdateResult {
  let concreteType = type(of: value)
  if V.self == concreteType {
    return unsafe withUnsafeMutablePointer(to: &value) { pointer in
      unsafe body(UnsafeMutableRawPointer(pointer), concreteType)
    }
  }
  func open<P>(_ opened: P) -> (Any, DynamicPropertyUpdateResult) {
    var copy = opened
    let result = unsafe withUnsafeMutablePointer(to: &copy) { pointer in
      unsafe body(UnsafeMutableRawPointer(pointer), P.self)
    }
    return (copy, result)
  }
  let (updated, result) = _openExistential(value as Any, do: open)
  if let back = updated as? V {
    value = back
  }
  return result
}

#if DEBUG
  /// Test-only observation of the update pass: fires once per `update(in:)` call
  /// with the container type hosting the property and the property's own type.
  /// Production behavior is unchanged; tests install the hook to pin pass
  /// coverage on every body-evaluation surface.
  @MainActor
  package enum DynamicPropertyUpdatePassProbe {
    package static var onUpdate: ((_ containerType: Any.Type, _ propertyType: Any.Type) -> Void)?
  }
#endif

/// The ambient discovered-property path while the update pass runs: the
/// field-index path of the dynamic property whose nested properties are
/// currently updating. Built-in wrappers' `update(in:)` implementations read it
/// to claim path-qualified slot identities; it is `.root` outside the pass
/// (and for top-level properties, whose identity must stay the legacy
/// ordinal-only key). A plain save/restore slot, not a task-local: the pass
/// is synchronous main-actor work with no suspension points.
@MainActor
package enum DynamicPropertyPathScope {
  package private(set) static var current: StateSlotPath = .root

  package static func withPath<Result>(
    _ path: StateSlotPath,
    _ apply: () -> Result
  ) -> Result {
    let saved = current
    current = path
    defer { current = saved }
    return apply()
  }
}

/// Runs the dynamic-property update pass over `view`'s discovered stored
/// properties. Call under the ambient authoring context the body will
/// observe — the pass must see exactly the scope the body's own wrapper
/// accesses will bind against (the ambient-wins rule).
@MainActor
@discardableResult
package func runDynamicPropertyUpdatePass<V>(on view: inout V) -> DynamicPropertyUpdateResult {
  runDynamicPropertyUpdatePass(on: &view, excludingFieldsOwnedBy: nil)
}

@MainActor
private func runDynamicPropertyUpdatePass<V>(
  on view: inout V,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)?
) -> DynamicPropertyUpdateResult {
  // Plans key on the DYNAMIC type: for a concrete `V` (every current caller)
  // it equals `V.self`; an existential `V` boxes a differently-typed value,
  // and its plan describes the boxed value's layout — `withMutableConcreteValue`
  // opens it and writes the mutated value back.
  let concreteType = type(of: view)
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: concreteType)
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: view)
  switch unsafe plan {
  case .empty:
    return .unchanged
  case .offsets(let fields):
    return unsafe withMutableConcreteValue(&view) { base, openedType in
      unsafe updatePlannedDynamicProperties(
        atBase: base,
        containerType: openedType,
        fields: fields,
        path: .root,
        excludingFieldsOwnedBy: owner
      )
    }
  case .mirrorWalk(let descriptor):
    return updateDiscoveredDynamicProperties(
      of: view,
      descriptor: descriptor,
      path: .root,
      excludingFieldsOwnedBy: owner
    )
  }
}

/// Installs the primitive dynamic-property authoring scope for `view`'s
/// resolve and runs the update pass inside it. The `ResolvableView` surfaces
/// that build their own scopes via `dynamicPropertyAuthoringContext(for:)`
/// route through this so the pass runs under the exact context their stored
/// wrappers bind against.
@MainActor
package func withDynamicPropertyUpdateScope<V, Result>(
  _ view: V,
  for context: ResolveContext,
  _ apply: () -> Result
) -> Result {
  let scope = dynamicPropertyAuthoringContext(for: context)
  return withAuthoringContext(scope) {
    return apply()
  }
}

@MainActor
private func updatePlannedDynamicProperties(
  atBase base: UnsafeMutableRawPointer,
  containerType: Any.Type,
  fields: [DynamicPropertyFieldApplicator],
  path: StateSlotPath,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)? = nil
) -> DynamicPropertyUpdateResult {
  let inputs = DynamicPropertyFieldUpdateInputs(
    containerType: containerType,
    containerPath: path
  )
  var result = DynamicPropertyUpdateResult.unchanged
  // Index loop on purpose: `for unsafe x in` is mangled by swift-format
  // (see the env-cleanup 2026-08-10 lesson), so spell the unsafe access per
  // element instead.
  for index in 0..<(unsafe fields.count) {
    if owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: unsafe fields[index].index)
      == true
    {
      continue
    }
    result = result.merging(unsafe fields[index].apply(base, inputs))
  }
  return result
}

/// Updates one dynamic-property field in place: its nested wrappers first (so
/// the field's own `update(in:)` observes live composed state), then the field
/// itself.
///
/// The nested pass runs under this field's own path — that qualification is
/// what gives two instances of one composed wrapper distinct nested slots. The
/// field's own `update(in:)` runs under the CONTAINER's path: a top-level
/// built-in must bind the legacy empty-path identity.
@MainActor
private func applyDynamicPropertyField<T: DynamicProperty>(
  at pointer: UnsafeMutablePointer<T>,
  index: Int,
  inputs: DynamicPropertyFieldUpdateInputs
) -> DynamicPropertyUpdateResult {
  let fieldPath = inputs.containerPath.appending(index)
  let nestedPlan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: T.self)
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: unsafe pointer.pointee)
  let nestedResult: DynamicPropertyUpdateResult
  switch unsafe nestedPlan {
  case .empty:
    nestedResult = .unchanged
  case .offsets(let fields):
    nestedResult = unsafe updatePlannedDynamicProperties(
      atBase: UnsafeMutableRawPointer(pointer),
      containerType: T.self,
      fields: fields,
      path: fieldPath
    )
  case .mirrorWalk(let descriptor):
    nestedResult = unsafe updateDiscoveredDynamicProperties(
      of: pointer.pointee,
      descriptor: descriptor,
      path: fieldPath
    )
  }
  let ownResult = unsafe updateDynamicPropertyValue(
    at: pointer,
    containerType: inputs.containerType,
    propertyPath: fieldPath,
    updatePath: inputs.containerPath
  )
  return nestedResult.merging(ownResult)
}

@MainActor
private func updateDynamicPropertyValue<T: DynamicProperty>(
  at pointer: UnsafeMutablePointer<T>,
  containerType: Any.Type,
  propertyPath: StateSlotPath,
  updatePath: StateSlotPath
) -> DynamicPropertyUpdateResult {
  let result = DynamicPropertyPathScope.withPath(updatePath) {
    let context: DynamicPropertyContext
    if T.self is any DynamicPropertyLeaseIndependent.Type {
      context = .leaseIndependent
    } else {
      context = DynamicPropertyContext.current(
        containerType: containerType,
        structuralPath: currentAuthoringContext()?.structuralPath.description ?? "",
        fieldPath: propertyPath.description
      )
    }
    return unsafe pointer.pointee.update(in: context)
  }
  #if DEBUG
    DynamicPropertyUpdatePassProbe.onUpdate?(containerType, T.self)
  #endif
  return result
}

/// The `Mirror` correctness fallback: enum containers and existential-typed
/// fields. A `Mirror` child is a copy and an enum payload has no addressable
/// field slot, so this tier updates an extracted copy exactly as the whole
/// pass did before plan 2026-08-30-001. Discovery semantics are identical to
/// the offsets tier; only the write-back is missing, and
/// `updateExtractedDynamicProperty` makes a dropped write loud.
@MainActor
private func updateDiscoveredDynamicProperties(
  of container: Any,
  descriptor: DynamicPropertyDescriptor,
  path: StateSlotPath,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)? = nil
) -> DynamicPropertyUpdateResult {
  let inputs = DynamicPropertyFieldUpdateInputs(
    containerType: type(of: container),
    containerPath: path
  )
  let mirror = Mirror(reflecting: container)
  var result = DynamicPropertyUpdateResult.unchanged
  var fieldIterator = descriptor.fields.makeIterator()
  var pendingField = fieldIterator.next()
  var index = 0
  for child in mirror.children {
    guard let field = pendingField else {
      return result
    }
    if index == field.index {
      if owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: field.index) == true {
        pendingField = fieldIterator.next()
        index += 1
        continue
      }
      if let property = child.value as? any DynamicProperty {
        result = result.merging(
          updateExtractedDynamicProperty(
            property,
            index: field.index,
            inputs: inputs
          ))
      }
      pendingField = fieldIterator.next()
    }
    index += 1
  }
  return result
}

@MainActor
private func updateExtractedDynamicProperty(
  _ property: any DynamicProperty,
  index: Int,
  inputs: DynamicPropertyFieldUpdateInputs
) -> DynamicPropertyUpdateResult {
  let propertyType = type(of: property)
  guard
    let updating = openedFieldShim(boundTo: propertyType)
      as? any DynamicPropertyFieldUpdating.Type
  else {
    // The extracted value conforms, so the shim always binds. Answer
    // conservatively rather than trapping if a future metadata shape differs.
    return .uncertified
  }
  let outcome = updating.updateExtracted(property, index: index, inputs: inputs)
  if outcome.mutated {
    SoundnessProbeConfiguration.recordDynamicPropertyMutationDiscardedViolation(
      "dynamic-property-mutation-discarded: \(propertyType) stored in \(inputs.containerType)"
    )
  }
  return outcome.result
}
