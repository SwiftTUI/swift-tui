/// The closed, total list of runtime registration families the frame
/// lifecycle fans out over. `RuntimeRegistrationSet` iterates its member
/// registries for every bulk operation (reset, subtree removal, restore,
/// fingerprinting, frame-drop blockers), so a family participates in every
/// fan-out by construction once its registry conforms to ``RuntimeRegistry``.
/// Case order is the canonical fan-out order.
package enum RuntimeRegistrationKind: CaseIterable, Sendable {
  case action
  case keyHandler
  case termination
  case pointerHandler
  case gesture
  case gestureState
  case defaultFocus
  case focusBinding
  case focusedValues
  case scrollPosition
  case lifecycle
  case task
  case preferenceObservation
  case command
  case dropDestination
}

/// Cross-registry teardown context for `reset`/`removeSubtrees`. Computed
/// once by ``RuntimeRegistrationSet`` BEFORE the fan-out loop so no registry's
/// teardown observes another registry's partial teardown through it.
package struct RuntimeRegistrationLifetimeContext: Sendable {
  /// Identities with a mid-interaction gesture recognizer. The pointer,
  /// gesture, and gesture-state registries spare these during teardown so an
  /// in-flight interaction survives republication; other registries ignore
  /// this.
  package var preservedGestureIdentities: Set<Identity>

  package init(preservedGestureIdentities: Set<Identity> = []) {
    self.preservedGestureIdentities = preservedGestureIdentities
  }
}

/// Cross-registry context for restoring one node's recorded registrations.
package struct RuntimeRegistrationRestoreContext: Sendable {
  /// The restoring node's visited-frame stamp; the hover registry uses it to
  /// let a fresher capture evict an abandoned node's shadowed copy.
  package var recency: UInt64

  /// Identities with a mid-interaction gesture recognizer at restore time.
  /// The pointer registry skips recorded route registrations that a live
  /// re-registered gesture handler already covers under a re-minted owner.
  package var activeGestureIdentities: Set<Identity>

  package init(
    recency: UInt64 = 0,
    activeGestureIdentities: Set<Identity> = []
  ) {
    self.recency = recency
    self.activeGestureIdentities = activeGestureIdentities
  }
}

/// Accumulates the order-insensitive `registry|key` count buckets the F04
/// publication oracle compares between a scoped restore and a scratch full
/// rebuild. Handlers are closures and cannot be compared for equality; keys
/// and per-key counts are exactly the surface the scoped-restore bug class
/// corrupts (missing, stale, or duplicated registrations after a partial
/// republication).
package struct RuntimeRegistrationFingerprintBuilder {
  package private(set) var fingerprint: [String: Int] = [:]

  package init() {}

  package mutating func add(_ registry: String, _ key: String, count: Int = 1) {
    guard count > 0 else {
      return
    }
    fingerprint["\(registry)|\(key)", default: 0] += count
  }
}

/// One registration family's per-node recorded slice: the registrations plus
/// their owner keys and ordinals, bundled as one value so `NodeHandlers` holds
/// exactly one field per family and its whole-bag operations (empty check,
/// absorb adoption) are uniform one-line folds instead of per-field merge
/// logic. Records must keep "absorb keeps the absorber's entries on
/// collision" semantics — see `NodeHandlers.absorbAdopted`.
package protocol RuntimeNodeRecord {
  init()
  var isEmpty: Bool { get }
  mutating func absorbAdopted(_ departing: Self)
}

/// The uniform lifecycle contract every runtime registry implements. The
/// bulk operations on ``RuntimeRegistrationSet`` are loops over its member
/// registries through this protocol, so a registry cannot join the set
/// without participating in reset, subtree removal, restore, publication
/// fingerprinting, and frame-drop blocking. Dispatch-side queries stay on the
/// concrete classes — only the frame lifecycle is unified here.
@MainActor
package protocol RuntimeRegistry: AnyObject {
  static var kind: RuntimeRegistrationKind { get }

  /// The frame-drop blocker this registry raises while it holds any state a
  /// dropped frame would fail to (re)install, or nil when currently empty.
  var activeFrameDropEligibilityBlocker: FrameDropEligibility.Blocker? { get }

  /// Whether this registry belongs to the low-volume effect subset
  /// (lifecycle/task/preference observation) that is re-published from EVERY
  /// live node even on scoped-publication frames.
  var isEffectRegistry: Bool { get }

  func reset(context: RuntimeRegistrationLifetimeContext)

  func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  )

  /// Restores this registry's slice of one node's recorded registrations.
  func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  )

  /// Re-sorts globally order-observable registration lists into canonical
  /// identity order after a scoped restore. No-op for the dict/route-keyed
  /// registries, whose restore order is not observable.
  func normalizeOrderByIdentity()

  /// Drops registrations owned by nodes that are no longer live. Only the
  /// gesture registries carry node-liveness-coupled interaction state; no-op
  /// elsewhere.
  func prune(keeping liveNodeIDs: Set<ViewNodeID>)

  /// Contributes this registry's keyed contents to the publication oracle
  /// fingerprint. Every family must project each registration into at least
  /// one `registry|key` bucket (with stacked-handler counts where handlers
  /// stack) or the F04 oracle is blind to its bug class.
  func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder)
}

extension RuntimeRegistry {
  package var isEffectRegistry: Bool {
    false
  }

  package func normalizeOrderByIdentity() {}

  package func prune(keeping liveNodeIDs: Set<ViewNodeID>) {}
}
