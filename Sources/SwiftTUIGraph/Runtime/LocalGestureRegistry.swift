/// Holds gesture recognizers attached to the view tree. Mirrors the
/// structure of `LocalPointerHandlerRegistry` and `LocalActionRegistry`:
/// keyed by the attaching `Identity`, drained on subtree teardown.
package enum GestureAttachmentRole: Equatable, Sendable {
  case ordinary
  case highPriority
  case simultaneous
}

@MainActor
private struct GestureRegistration {
  var recognizer: AnyGestureRecognizer
  var role: GestureAttachmentRole
}

@MainActor
package final class LocalGestureRegistry: Equatable {
  private var recognizers: [Identity: AnyGestureRecognizer] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalGestureRegistry,
    rhs: LocalGestureRegistry
  ) -> Bool {
    lhs === rhs
  }

  /// The fresh recognizers a resolve pass has authored per identity, in
  /// authored order. `register` (the pass's first call for an identity)
  /// resets the list; `registerStacked` appends. Reconciliation is
  /// positional against the previous entry, so a mid-interaction recognizer
  /// keeps its state (and adopts the fresh registration's authored
  /// callbacks) while inactive positions are rebuilt fresh — the entry
  /// never nests stacks across passes.
  ///
  /// The same-pass signal is `(recency, firstNode)`: chain levels sharing a
  /// derived registration key can record on DIFFERENT nodes (an inner level
  /// under the entity-rerooted node, the outer under the enclosing chain
  /// node), so checking `ViewNodeContext.current`'s record would reset the
  /// stack mid-chain. The recency stamp rejects a stale list from an
  /// earlier frame; the FIRST registering node's record — reset when its
  /// capture session begins — rejects a stale list from an earlier pass of
  /// the same frame.
  private struct PassAuthoredList {
    var recency: UInt64
    weak var firstNode: ViewNode?
    var registrations: [GestureRegistration]
  }

  private var passAuthoredRecognizers: [Identity: PassAuthoredList] = [:]
  /// The registering site's structural identity per registration key —
  /// threaded into the committed record so a site whose derived key changed
  /// replaces its previous record entry (see
  /// ``GestureNodeRecord/structuralKeys``).
  private var structuralKeysByIdentity: [Identity: Identity] = [:]

  /// A committed record authored AFTER the identity's live recognizer began
  /// its interaction, held until that interaction ends.
  ///
  /// `restore` must not replace a mid-interaction recognizer (the capture it
  /// holds would be lost), so it adopts the record's callbacks and keeps the
  /// live entry — including the live entry's SHAPE. A gesture stacked onto,
  /// or removed from, the same identity during an active drag therefore
  /// reaches the live registry only when a later restore finds the entry
  /// inactive. A root evaluation re-authors and restores every frame, so
  /// that happens on the next frame; a selective frame restores only the
  /// nodes it re-evaluated, and nothing re-evaluates a chain whose state
  /// write already happened — the live entry kept a removed tap that fired
  /// on the next click, and never gained an added one (org task T173).
  /// Holding the authoritative record here and installing it the moment the
  /// interaction is over (on the next lookup, restore, or snapshot) makes the
  /// selective path converge where the root path converged by brute force.
  private struct PendingReplacement {
    var recognizer: AnyGestureRecognizer
    var owner: RuntimeRegistrationOwnerKey
  }

  private var pendingReplacements: [Identity: PendingReplacement] = [:]

  package func register(
    identity: Identity,
    structuralKey: Identity? = nil,
    recognizer: AnyGestureRecognizer,
    role: GestureAttachmentRole = .ordinary
  ) {
    passAuthoredRecognizers[identity] = PassAuthoredList(
      recency: ViewNodeContext.current?.runtimeRegistrationRecency ?? 0,
      firstNode: ViewNodeContext.current,
      registrations: [GestureRegistration(recognizer: recognizer, role: role)]
    )
    if let structuralKey {
      structuralKeysByIdentity[identity] = structuralKey
    }
    applyPassRegistrations(for: identity)
  }

  package func registerStacked(
    identity: Identity,
    structuralKey: Identity? = nil,
    recognizer: AnyGestureRecognizer,
    role: GestureAttachmentRole = .ordinary
  ) {
    guard var authored = passAuthoredRecognizers[identity],
      authored.recency == (ViewNodeContext.current?.runtimeRegistrationRecency ?? 0),
      authored.firstNode?.gestureRegistration(for: identity) != nil
    else {
      register(
        identity: identity,
        structuralKey: structuralKey,
        recognizer: recognizer,
        role: role
      )
      return
    }

    authored.registrations.append(GestureRegistration(recognizer: recognizer, role: role))
    passAuthoredRecognizers[identity] = authored
    applyPassRegistrations(for: identity)
  }

  /// Rebuilds the identity's entry from the pass's authored list,
  /// positionally preserving mid-interaction recognizers from the previous
  /// entry. A preserved recognizer adopts the same position's fresh
  /// authored callbacks (so an active drag writes the re-authored binding,
  /// not the one captured when the interaction began); the discarded fresh
  /// recognizer is torn down. Without preservation, any re-resolve between
  /// `.down` and the first `.dragged` — `setPressedIdentity`, a parent
  /// state change — would destroy the state the recognizer just captured.
  /// A gesture *added* mid-interaction lands in a fresh position and joins
  /// the entry immediately instead of being discarded.
  private func applyPassRegistrations(for identity: Identity) {
    let authored = passAuthoredRecognizers[identity]?.registrations ?? []
    let previousEntry = recognizers[identity]
    let previousElements = previousEntry.map(stackElements(of:)) ?? []

    var result: [GestureRegistration] = []
    result.reserveCapacity(authored.count)
    for (index, incoming) in authored.enumerated() {
      if index < previousElements.count,
        previousElements[index].recognizer.isActive,
        previousElements[index].recognizer !== incoming.recognizer
      {
        let preserved = previousElements[index].recognizer
        if preserved.adoptAuthoredCallbacks(from: incoming.recognizer) {
          preserved.noteCarriedAuthoredMint(
            incoming.recognizer.carriedAuthoredMintGeneration
          )
        }
        incoming.recognizer.tearDown()
        result.append(GestureRegistration(recognizer: preserved, role: incoming.role))
      } else {
        if index < previousElements.count,
          previousElements[index].recognizer !== incoming.recognizer
        {
          previousElements[index].recognizer.tearDown()
        }
        result.append(incoming)
      }
    }
    // Previous elements beyond the authored positions: tear down the
    // inactive ones; keep active ones attached so a gesture the pass has
    // not (yet) re-authored cannot be cancelled mid-interaction — if the
    // pass authors it next, positional reconciliation re-claims it.
    for (index, element) in previousElements.enumerated()
    where index >= authored.count {
      if element.recognizer.isActive {
        result.append(element)
      } else if !authored.contains(where: { $0.recognizer === element.recognizer }) {
        element.recognizer.tearDown()
      }
    }

    let entry: AnyGestureRecognizer
    if let previousEntry,
      let previousStack = previousEntry.base as? StackedGestureRecognizer,
      previousStack.isActive
    {
      // Keep the wrapper as well as its active leaves. Re-wrapping preserved
      // leaves makes the committed snapshot and fresh registry entry hold
      // distinct stack owners around the same recognizers; restoring that
      // snapshot tears down one owner and cancels the shared active leaf.
      previousStack.replaceRegistrations(with: result)
      entry = previousEntry
    } else if result.count == 1 && result[0].role == .ordinary {
      entry = result[0].recognizer
    } else {
      entry = AnyGestureRecognizer(StackedGestureRecognizer(registrations: result))
    }
    recognizers[identity] = entry
    ownersByIdentity[identity] = .current(identity: identity)
    // Record on the pass's FIRST registering node: stacked levels can run
    // under different node contexts, and splitting one entry across two
    // records would double-restore it.
    let recordingNode = passAuthoredRecognizers[identity]?.firstNode ?? ViewNodeContext.current
    recordingNode?.recordGestureRegistration(
      identity: identity,
      structuralKey: structuralKeysByIdentity[identity],
      recognizer: entry
    )
  }

  private func stackElements(
    of recognizer: AnyGestureRecognizer
  ) -> [GestureRegistration] {
    guard let stacked = recognizer.base as? StackedGestureRecognizer else {
      return [GestureRegistration(recognizer: recognizer, role: .ordinary)]
    }
    return stacked.registrations
  }

  package func recognizer(for identity: Identity) -> AnyGestureRecognizer? {
    settlePendingReplacement(for: identity)
    return recognizers[identity]
  }

  package func hasRecognizer(for identity: Identity) -> Bool {
    recognizers[identity] != nil
  }

  package func hasCurrentPassRecognizer(for identity: Identity) -> Bool {
    guard let authored = passAuthoredRecognizers[identity] else {
      return false
    }
    return authored.recency == (ViewNodeContext.current?.runtimeRegistrationRecency ?? 0)
      && authored.firstNode?.gestureRegistration(for: identity) != nil
  }

  package func reset() {
    // `RuntimeRegistrationSet.resetAll()` fires on every full-resolve
    // frame (SwiftTUI.swift:188). Without an in-flight guard, a
    // `.down` event that lands between two full-resolve frames would
    // register its captured state on a recognizer that is then
    // silently torn down — the next `.dragged` arrives at a fresh
    // recognizer with no `startLocation` and is ignored forever.
    //
    // Preserve active recognizers across reset; tear down the rest.
    // Subtree teardown (`removeSubtrees`) remains aggressive: if the
    // owning view genuinely disappears, its recognizer should die.
    // A full resolve re-authors every record, so a held record is superseded
    // by the one this frame restores.
    for pending in pendingReplacements.values {
      pending.recognizer.tearDown()
    }
    pendingReplacements.removeAll(keepingCapacity: true)
    var preserved: [Identity: AnyGestureRecognizer] = [:]
    var preservedOwners: [Identity: RuntimeRegistrationOwnerKey] = [:]
    for (identity, recognizer) in recognizers {
      if recognizer.isActive {
        preserved[identity] = recognizer
        preservedOwners[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
      } else {
        recognizer.tearDown()
      }
    }
    recognizers = preserved
    ownersByIdentity = preservedOwners
    passAuthoredRecognizers.removeAll(keepingCapacity: true)
  }

  package func activeIdentities(
    rootedAt roots: [Identity]
  ) -> Set<Identity> {
    guard !roots.isEmpty else { return [] }
    return Set(
      recognizers.compactMap { identity, recognizer in
        guard recognizer.isActive,
          (ownersByIdentity[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots)
        else {
          return nil
        }
        return identity
      }
    )
  }

  package func activeIdentitySnapshot() -> Set<Identity> {
    Set(
      recognizers.compactMap { identity, recognizer in
        recognizer.isActive ? identity : nil
      }
    )
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    preserving preservedIdentities: Set<Identity> = []
  ) {
    guard !roots.isEmpty else { return }
    for identity in recognizers.keys.filter({
      (ownersByIdentity[$0] ?? .init(identity: $0)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
      ownersByIdentity.removeValue(forKey: identity)
      passAuthoredRecognizers.removeValue(forKey: identity)
      structuralKeysByIdentity.removeValue(forKey: identity)
      discardPendingReplacement(for: identity)
    }
  }

  /// Tears down recognizers the caller determined have genuinely departed
  /// the rendered tree (no paired interaction region — see the focus-sync
  /// region-liveness pass). Every structural teardown layer deliberately
  /// spares ACTIVE recognizers (a mid-interaction re-mint must not cancel a
  /// live capture), and the owner key can be a live ancestor (the
  /// registering body's node), so `prune(keeping:)` cannot distinguish a
  /// branch-removed active recognizer either — without this backstop it
  /// stays event- and deadline-eligible forever.
  package func removeDepartedRecognizers(
    _ identities: [Identity]
  ) {
    for identity in identities {
      recognizers.removeValue(forKey: identity)?.tearDown()
      ownersByIdentity.removeValue(forKey: identity)
      passAuthoredRecognizers.removeValue(forKey: identity)
      structuralKeysByIdentity.removeValue(forKey: identity)
      discardPendingReplacement(for: identity)
    }
  }

  package func prune(
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    for identity in recognizers.keys.filter({
      guard let viewNodeID = ownersByIdentity[$0]?.viewNodeID else {
        return true
      }
      return !liveNodeIDs.contains(viewNodeID)
    }) {
      recognizers.removeValue(forKey: identity)?.tearDown()
      ownersByIdentity.removeValue(forKey: identity)
      discardPendingReplacement(for: identity)
    }
  }

  /// Re-populates the registry from a snapshot captured by `NodeHandlers`.
  /// Used during cache-hit frames where resolve doesn't run but
  /// registrations must still be live.
  package func snapshot() -> [Identity: AnyGestureRecognizer] {
    settlePendingReplacements()
    return recognizers
  }

  package func restore(
    _ snapshot: [Identity: AnyGestureRecognizer],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else { return }
    settlePendingReplacements()
    for (identity, recognizer) in snapshot {
      if let existing = recognizers[identity] {
        if existing.isActive {
          if existing !== recognizer {
            // The record-refresh seam: the committed record can carry a
            // recognizer authored AFTER this preserved one began its
            // interaction (the owner re-resolved mid-gesture, and the
            // resolve pass's registry starts empty so its reconciliation
            // never saw the active recognizer). Adopt the record's authored
            // callbacks so dispatch writes the re-authored bindings; the
            // mint gate keeps a stale record re-published on a cache-hit
            // frame from regressing callbacks backward, and makes the
            // per-frame double restore idempotent.
            let recordIsFresher =
              recognizer.carriedAuthoredMintGeneration > existing.carriedAuthoredMintGeneration
            if recordIsFresher, existing.adoptAuthoredCallbacks(from: recognizer) {
              existing.noteCarriedAuthoredMint(recognizer.carriedAuthoredMintGeneration)
            }
            // Adoption refreshes callbacks, never shape: hold a fresher
            // record as the entry to install once the interaction ends (see
            // `PendingReplacement`). A stale record is torn down as before.
            if recordIsFresher || pendingReplacements[identity]?.recognizer === recognizer {
              holdPendingReplacement(
                recognizer,
                for: identity,
                owner: ownersByIdentity[identity] ?? self.ownersByIdentity[identity]
                  ?? .init(identity: identity)
              )
            } else {
              recognizer.tearDown()
            }
          }
          // Triple fallback, unique in the registry family (F100): when the
          // incoming snapshot carries no owner for an ACTIVE recognizer, keep
          // the current live owner (with its `viewNodeID`) rather than
          // minting an unowned key. `prune(keeping:)` force-drops any
          // identity whose owner has `viewNodeID == nil`, so collapsing this
          // to the family's two-term form would strand and tear down a
          // mid-interaction recognizer on the next prune pass. Pinned by
          // LocalGestureRegistryTests "restore with an empty owner map
          // preserves an active recognizer's live owner across prune".
          self.ownersByIdentity[identity] =
            ownersByIdentity[identity] ?? self.ownersByIdentity[identity]
            ?? .init(identity: identity)
          continue
        }
        if existing !== recognizer {
          existing.tearDown()
        }
      }
      if pendingReplacements[identity]?.recognizer === recognizer {
        pendingReplacements.removeValue(forKey: identity)
      } else {
        discardPendingReplacement(for: identity)
      }
      recognizers[identity] = recognizer
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  private func holdPendingReplacement(
    _ recognizer: AnyGestureRecognizer,
    for identity: Identity,
    owner: RuntimeRegistrationOwnerKey
  ) {
    if let held = pendingReplacements[identity], held.recognizer !== recognizer {
      held.recognizer.tearDown()
    }
    pendingReplacements[identity] = PendingReplacement(recognizer: recognizer, owner: owner)
  }

  private func discardPendingReplacement(for identity: Identity) {
    pendingReplacements.removeValue(forKey: identity)?.recognizer.tearDown()
  }

  /// Installs every held record whose live recognizer has finished its
  /// interaction. Cheap when nothing is held (a dictionary emptiness read).
  private func settlePendingReplacements() {
    guard !pendingReplacements.isEmpty else { return }
    for identity in Array(pendingReplacements.keys) {
      settlePendingReplacement(for: identity)
    }
  }

  private func settlePendingReplacement(for identity: Identity) {
    guard let pending = pendingReplacements[identity] else { return }
    if let existing = recognizers[identity] {
      guard !existing.isActive else { return }
      if existing !== pending.recognizer {
        existing.tearDown()
      }
    }
    pendingReplacements.removeValue(forKey: identity)
    recognizers[identity] = pending.recognizer
    ownersByIdentity[identity] = pending.owner
  }

  /// Iterates all active recognizers. Called from the RunLoop to drain
  /// deadlines when the scheduler fires `.deadline`.
  package func activeRecognizers() -> [(Identity, AnyGestureRecognizer)] {
    settlePendingReplacements()
    return recognizers.map { ($0.key, $0.value) }
  }
}

@MainActor
private final class StackedGestureRecognizer: GestureRecognizer, RoleAwarePointerDispatching {
  typealias Value = Never

  fileprivate private(set) var registrations: [GestureRegistration]
  private var highPriorityOwnsStream = false

  init(registrations: [GestureRegistration]) {
    self.registrations = registrations
    highPriorityOwnsStream = registrations.contains {
      $0.role == .highPriority && $0.recognizer.isActive
    }
  }

  func replaceRegistrations(with registrations: [GestureRegistration]) {
    self.registrations = registrations
    if registrations.contains(where: {
      $0.role == .highPriority && $0.recognizer.isActive
    }) {
      highPriorityOwnsStream = true
    }
  }

  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? StackedGestureRecognizer,
      other.registrations.count == registrations.count
    else {
      return false
    }
    var adoptedAll = true
    for (mine, theirs) in zip(registrations, other.registrations) {
      adoptedAll = mine.recognizer.adoptAuthoredCallbacks(from: theirs.recognizer) && adoptedAll
    }
    return adoptedAll
  }

  func reArm() {
    if !isActive {
      highPriorityOwnsStream = false
    }
    for registration in registrations {
      registration.recognizer.reArm()
    }
  }

  var phase: GestureRecognizerPhase {
    if registrations.contains(where: { $0.recognizer.phase == .changed }) {
      return .changed
    }
    if registrations.contains(where: { $0.recognizer.phase == .began }) {
      return .began
    }
    if registrations.contains(where: { !$0.recognizer.phase.isTerminal }) {
      return .possible
    }
    if registrations.contains(where: { $0.recognizer.phase == .ended }) {
      return .ended
    }
    if registrations.contains(where: { $0.recognizer.phase == .failed }) {
      return .failed
    }
    return .cancelled
  }

  var isActive: Bool {
    registrations.contains { $0.recognizer.isActive }
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    switch handleClassified(event: event) {
    case .claimed, .observed:
      return .handled
    case .failed:
      return .failed
    case .ignored:
      return .ignored
    }
  }

  func handleClassified(event: LocalPointerEvent) -> PointerDispatchOutcome {
    var sawClaimed = false
    var sawObserved = false
    var sawFailed = false

    // High-priority recognizers receive the stream first. A claiming high
    // lane defeats ordinary siblings, while simultaneous recognizers always
    // participate. Multiple recognizers in one lane preserve the framework's
    // established authored-order broadcast semantics.
    var highPriorityHandled = false
    for registration in registrations where registration.role == .highPriority {
      switch registration.recognizer.handle(event: event) {
      case .handled:
        sawClaimed = true
        highPriorityHandled = true
      case .failed:
        sawFailed = true
      case .ignored:
        break
      }
    }
    if highPriorityHandled {
      highPriorityOwnsStream = true
    }

    for registration in registrations where registration.role == .simultaneous {
      switch registration.recognizer.handle(event: event) {
      case .handled:
        sawObserved = true
      case .failed:
        sawFailed = true
      case .ignored:
        break
      }
    }

    if !highPriorityOwnsStream {
      for registration in registrations where registration.role == .ordinary {
        switch registration.recognizer.handle(event: event) {
        case .handled:
          sawClaimed = true
        case .failed:
          sawFailed = true
        case .ignored:
          break
        }
      }
    }

    if sawClaimed {
      return .claimed
    }
    if sawObserved {
      return .observed
    }
    return sawFailed ? .failed : .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    handleDeadlineClassified(at: instant) != .ignored
  }

  func handleDeadlineClassified(
    at instant: MonotonicInstant
  ) -> PointerDispatchOutcome {
    var sawClaimed = false
    var sawObserved = false
    var sawFailed = false

    for registration in registrations {
      switch registration.recognizer.handleDeadlineClassified(at: instant) {
      case .claimed, .observed:
        if registration.role == .simultaneous {
          sawObserved = true
        } else {
          sawClaimed = true
        }
      case .failed:
        sawFailed = true
      case .ignored:
        break
      }
    }

    if sawClaimed {
      return .claimed
    }
    if sawObserved {
      return .observed
    }
    return sawFailed ? .failed : .ignored
  }

  func currentValue() -> Never? {
    nil
  }

  func tearDown() {
    for registration in registrations {
      registration.recognizer.tearDown()
    }
  }
}
