import Synchronization

/// Task-local storage for the current animation request.
///
/// `withAnimation` (View module) sets this before executing the user's
/// mutation closure.  State writes read it and forward the request through
/// the invalidation path.
package enum AnimationContextStorage {
  @TaskLocal package static var currentRequest: AnimationRequest = .inherit
  /// Explicit transaction scopes also exist when every field is default.
  /// Binding-stored intent must yield to those scopes without inspecting
  /// metadata values as a proxy for whether a scope was opened.
  @TaskLocal package static var isExplicitTransactionScope = false
  /// The batch ID associated with the innermost enclosing
  /// `withAnimation` scope, or `nil` at the root.  State writes thread
  /// it alongside the animation request so every animation in the same
  /// batch can be resolved to a single completion closure.
  @TaskLocal package static var currentBatchID: AnimationBatchID? = nil
  @TaskLocal package static var currentCompletionScope: AnimationCompletionScope?
  /// Continuity metadata scoped by `withTransaction` (View module).
  /// State writes thread it onto their invalidation segment so
  /// resolve-time transforms below the written subtree can observe it.
  @TaskLocal package static var currentIsContinuous: Bool = false
  /// Custom `TransactionKey` values scoped by `withTransaction` (View
  /// module), threaded onto invalidation segments like `currentIsContinuous`.
  @TaskLocal package static var currentCustomValues: [ObjectIdentifier: AnyHashableSendable] = [:]
  /// `Transaction.tracksVelocity` scoped by `withTransaction` (View module).
  /// Unlike continuity it is animation-explicit: a write under it must reach
  /// the animation controller so the value can be sampled into the velocity
  /// channel, so the write branches take the animation-aware path for it.
  @TaskLocal package static var currentTracksVelocity: Bool = false
}

/// Tracks only synchronous writes submitted by one completion-bearing scope.
/// Nested scopes replace this task local, so their writes do not claim an
/// otherwise empty outer batch.
package final class AnimationCompletionScope: Sendable {
  private let submitted = Atomic(false)

  package var didSubmitInvalidation: Bool {
    get { submitted.load(ordering: .relaxed) }
    set { submitted.store(newValue, ordering: .relaxed) }
  }

  package init() {}
}

/// Internal completion barrier carried across the graph/runtime boundary.
package enum AnimationCompletionBarrier: Sendable, Equatable {
  case logicallyComplete
  case removed
}

/// Sink used by the View-layer `withAnimation` to register completion
/// closures with the animation controller.  The controller fires the
/// closure once every animation and every removal overlay tagged with
/// the batch ID has drained.
@MainActor
package protocol AnimationCompletionSink: AnyObject, Sendable {
  func registerCompletion(
    batchID: AnimationBatchID,
    barrier: AnimationCompletionBarrier,
    closure: @escaping @MainActor @Sendable () -> Void
  )
  func finishEmptyCompletionScope(batchID: AnimationBatchID)
}

extension AnimationCompletionSink {
  package func finishEmptyCompletionScope(batchID: AnimationBatchID) {}
}

@MainActor
package enum AnimationCompletionStorage {
  @TaskLocal package static var currentTaskSink: (any AnimationCompletionSink)?

  /// The task-local sink, exclusively (F116): the `static weak var` fallback
  /// this used to fall through to was assigned only from tests — the
  /// "last-bound global" anti-pattern, and a cross-test interference hazard
  /// once suites toggled it across suspension points — and was deleted.
  /// Bind sinks with `withSink`.
  package static var effectiveSink: (any AnimationCompletionSink)? {
    currentTaskSink
  }

  package static func withSink<Result>(
    _ sink: any AnimationCompletionSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }

  package static func withSink<Result>(
    _ sink: any AnimationCompletionSink,
    operation: () throws -> Result
  ) rethrows -> Result {
    try $currentTaskSink.withValue(sink) {
      try operation()
    }
  }
}

/// Sink used by the View-layer `withAnimation` to deliver concrete
/// `Animation` values to the renderer's animation controller without
/// introducing a direct module dependency.
///
/// SwiftTUI installs a concrete sink on the ``RunLoop`` using task-local
/// storage so concurrent scenes keep their animation registrations isolated.
@MainActor
package protocol AnimationRegistrationSink: AnyObject, Sendable {
  func registerAnimationBox(_ box: AnimationBox, payload: any Sendable)
}

@MainActor
package enum AnimationRegistrationStorage {
  @TaskLocal package static var currentTaskSink: (any AnimationRegistrationSink)?

  /// The task-local sink, exclusively (F116): the `static weak var` fallback
  /// this used to fall through to was assigned only from tests — the
  /// "last-bound global" anti-pattern, and a cross-test interference hazard
  /// once suites toggled it across suspension points — and was deleted.
  /// Bind sinks with `withSink`.
  package static var effectiveSink: (any AnimationRegistrationSink)? {
    currentTaskSink
  }

  package static func withSink<Result>(
    _ sink: any AnimationRegistrationSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }

  package static func withSink<Result>(
    _ sink: any AnimationRegistrationSink,
    operation: () throws -> Result
  ) rethrows -> Result {
    try $currentTaskSink.withValue(sink) {
      try operation()
    }
  }
}

/// Sink used by the View-layer `.transition()` modifier to register
/// per-node transitions with the renderer's animation controller.
@MainActor
package protocol TransitionRegistrationSink: AnyObject, Sendable {
  func registerTransition(for identity: Identity, transition: any Sendable)
  func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    transition: any Sendable
  )
  /// Registers a transition for the node `viewNodeID`, declared by the node
  /// `declaringNodeID`: the node whose evaluation ran the `.transition()`
  /// modifier.
  ///
  /// The two differ when the modifier's content has graph nodes of its own,
  /// as each view of a transition body with several roots does. The
  /// registration then stands until the declaring node is evaluated again
  /// without declaring it. An evaluation of the registered node alone says
  /// nothing about it: that node never declared the transition.
  func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    declaringNodeID: ViewNodeID?,
    transition: any Sendable
  )
}

extension TransitionRegistrationSink {
  package func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    transition: any Sendable
  ) {
    registerTransition(for: identity, transition: transition)
  }

  package func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    declaringNodeID: ViewNodeID?,
    transition: any Sendable
  ) {
    registerTransition(for: identity, viewNodeID: viewNodeID, transition: transition)
  }
}

@MainActor
package enum TransitionRegistrationStorage {
  @TaskLocal package static var currentTaskSink: (any TransitionRegistrationSink)?

  /// The task-local sink, exclusively (F116): the `static weak var` fallback
  /// this used to fall through to was assigned only from tests — the
  /// "last-bound global" anti-pattern, and a cross-test interference hazard
  /// once suites toggled it across suspension points — and was deleted.
  /// Bind sinks with `withSink`.
  package static var effectiveSink: (any TransitionRegistrationSink)? {
    currentTaskSink
  }

  package static func withSink<Result>(
    _ sink: any TransitionRegistrationSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }

  package static func withSink<Result>(
    _ sink: any TransitionRegistrationSink,
    operation: () throws -> Result
  ) rethrows -> Result {
    try $currentTaskSink.withValue(sink) {
      try operation()
    }
  }
}

/// One place in the view tree whose `animatableData` the animation system
/// may animate: a view, or a modifier in a modifier chain, that conforms to
/// `Animatable`.
///
/// Several sites can resolve at one identity: a view and the modifiers
/// around it share their identity. `ordinal` is the site's outer-first
/// position among them, so the pair is stable from one resolve to the next.
package struct AnimatableValueSite: Hashable, Sendable {
  package var identity: Identity
  package var ordinal: Int

  package init(identity: Identity, ordinal: Int) {
    self.identity = identity
    self.ordinal = ordinal
  }
}

/// Sink the View layer asks for the `animatableData` a site presents on the
/// current frame.
///
/// The resolver passes the data the author wrote, which is the site's
/// target, and the transaction the site resolves under. The sink returns the
/// data the body evaluates with: the target when nothing animates, or the
/// sample of the animation toward it. With no sink bound a site evaluates
/// with its target.
///
/// A phase of a transition body that is evaluated outside the graph binds a
/// sink of its own, which answers from values the animation engine supplies
/// and tells the controller nothing: its sites have the names of the live
/// ones, and their data is another phase's.
///
/// `ownerNodeID` is the graph node that evaluates the site, when there is
/// one. The site's identity is the one its view resolves at, which is not
/// always an identity of the resolved tree: a view whose body root is a
/// conditional or a lone `Group` commits its branch's node in its place. The
/// node tells the sink that such a site is still there, and which identity
/// to invalidate for it.
@MainActor
package protocol AnimatableValueSink: AnyObject, Sendable {
  func presentedAnimatableData<Data: VectorArithmetic>(
    for target: Data,
    at site: AnimatableValueSite,
    ownerNodeID: ViewNodeID?,
    transaction: TransactionSnapshot,
    reducesMotion: Bool
  ) -> Data
}

extension AnimatableValueSink {
  /// The pull of a site that no graph node evaluates.
  package func presentedAnimatableData<Data: VectorArithmetic>(
    for target: Data,
    at site: AnimatableValueSite,
    transaction: TransactionSnapshot,
    reducesMotion: Bool
  ) -> Data {
    presentedAnimatableData(
      for: target,
      at: site,
      ownerNodeID: nil,
      transaction: transaction,
      reducesMotion: reducesMotion
    )
  }
}

@MainActor
package enum AnimatableValueStorage {
  @TaskLocal package static var currentTaskSink: (any AnimatableValueSink)?

  /// The task-local sink, exclusively, as for the other animation sinks.
  package static var effectiveSink: (any AnimatableValueSink)? {
    currentTaskSink
  }

  package static func withSink<Result>(
    _ sink: (any AnimatableValueSink)?,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }

  package static func withSink<Result>(
    _ sink: (any AnimatableValueSink)?,
    operation: () throws -> Result
  ) rethrows -> Result {
    try $currentTaskSink.withValue(sink) {
      try operation()
    }
  }
}
