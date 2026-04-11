/// A view that cycles through a sequence of phases, applying an
/// animation between each pair of consecutive phases.
///
/// Matches SwiftUI's `phaseAnimator` family of APIs.  Two modes:
///
/// ### Loop mode
///
/// `init(_:content:animation:)` starts a background task that walks
/// the phases in a loop forever, advancing after each animation
/// completes via the ``withAnimation(_:_:completion:)`` batch drain.
///
///     PhaseAnimator([Phase.a, .b, .c]) { phase in
///       Text("hello").foregroundStyle(phase.color)
///     } animation: { phase in
///       .easeInOut(duration: .milliseconds(500))
///     }
///
/// ### Trigger mode
///
/// `init(_:trigger:content:animation:)` walks through the phases
/// exactly once whenever the external `trigger` value changes.
/// Starting from the current phase, the animator advances one step
/// at a time until it returns to phase 0 (the rest state).  This
/// matches SwiftUI's trigger-driven phase animator and produces the
/// classic "press button, bounce, return to rest" pattern:
///
///     @State private var tapCount = 0
///     PhaseAnimator([Phase.rest, .grow, .shrink], trigger: tapCount) {
///       phase in
///       Text("★").scaleEffect(phase.scale)
///     }
///     Button("bounce") { tapCount += 1 }
///
/// The initial mount is NOT treated as a trigger change — the view
/// renders at phase 0 quietly and only reacts to subsequent changes.
///
/// ### Animation curve
///
/// The `animation` closure returns the curve to use when
/// transitioning INTO the given phase.  Returning nil snaps to that
/// phase without animating (the content still updates but the
/// controller doesn't enqueue an animation).
///
/// - Note: The phases array must be non-empty.  Calling
///   `PhaseAnimator([])` is a programmer error and will trap in
///   debug builds.
public struct PhaseAnimator<Phase: Equatable & Sendable, Content: View>: View {
  private let phases: [Phase]
  private let content: @MainActor (Phase) -> Content
  private let animation: @Sendable (Phase) -> Animation?
  // nil → loop mode; concrete hash → trigger mode keyed on this value.
  private let triggerHash: Int?

  @State private var currentPhase: Phase
  // Set to true the first time the trigger-mode task fires so we
  // can skip the initial-mount invocation (trigger mode should not
  // animate on appear, only on subsequent trigger changes).
  @State private var didSeeInitialTrigger: Bool = false

  public init(
    _ phases: [Phase],
    @ViewBuilder content: @escaping @MainActor (Phase) -> Content,
    animation: @escaping @Sendable (Phase) -> Animation? = { _ in .default }
  ) {
    precondition(
      !phases.isEmpty,
      "PhaseAnimator requires at least one phase"
    )
    self.phases = phases
    self.content = content
    self.animation = animation
    self.triggerHash = nil
    _currentPhase = State(wrappedValue: phases[0])
  }

  public init<Trigger: Hashable & Sendable>(
    _ phases: [Phase],
    trigger: Trigger,
    @ViewBuilder content: @escaping @MainActor (Phase) -> Content,
    animation: @escaping @Sendable (Phase) -> Animation? = { _ in .default }
  ) {
    precondition(
      !phases.isEmpty,
      "PhaseAnimator requires at least one phase"
    )
    self.phases = phases
    self.content = content
    self.animation = animation
    var hasher = Hasher()
    hasher.combine(trigger)
    self.triggerHash = hasher.finalize()
    _currentPhase = State(wrappedValue: phases[0])
  }

  public var body: some View {
    if let triggerHash {
      // Touch `didSeeInitialTrigger` in body so `State.remember(...)`
      // registers a per-instance location for it during the normal
      // `withAuthoringContext` body evaluation. Without this read, the
      // only access to the property happens inside the `.task(id:)`
      // closure — which runs after the body has already returned, so
      // no authoring context is active and writes fall through to
      // `updateSeedValue(...)` (global seed) instead of persisting on
      // this PhaseAnimator instance.
      _ = didSeeInitialTrigger
      content(currentPhase)
        .task(id: triggerHash) { @MainActor in
          // .task(id:) fires on initial appearance too, so skip the
          // first invocation — trigger mode should only advance
          // phases on subsequent changes.
          if !didSeeInitialTrigger {
            didSeeInitialTrigger = true
            return
          }
          await runCycleOnce()
        }
    } else {
      content(currentPhase)
        .task { @MainActor in
          await runPhaseLoop()
        }
    }
  }

  @MainActor
  private func runPhaseLoop() async {
    // Find the index of the current phase in the array.  The loop
    // advances to (index + 1) % count and waits for that
    // transition's animation to drain before continuing.
    var currentIndex = phases.firstIndex(of: currentPhase) ?? 0
    while !Task.isCancelled {
      let nextIndex = (currentIndex + 1) % phases.count
      let nextPhase = phases[nextIndex]
      let nextAnimation = animation(nextPhase)

      await advance(to: nextPhase, with: nextAnimation)

      if Task.isCancelled { break }
      currentIndex = nextIndex
    }
  }

  @MainActor
  private func runCycleOnce() async {
    // Walk from the current phase through the remaining phases
    // and back around to phase 0 — exactly one full traversal.
    // If we're already at phase 0, this is (count - 1) + 1 = count
    // transitions, forming a complete round trip.
    guard phases.count > 1 else { return }
    var index = phases.firstIndex(of: currentPhase) ?? 0
    let restIndex = 0
    repeat {
      index = (index + 1) % phases.count
      let nextPhase = phases[index]
      let nextAnimation = animation(nextPhase)

      await advance(to: nextPhase, with: nextAnimation)

      if Task.isCancelled { return }
    } while index != restIndex
  }

  @MainActor
  private func advance(to phase: Phase, with animation: Animation?) async {
    await withCheckedContinuation {
      (continuation: CheckedContinuation<Void, Never>) in
      withAnimation(animation) {
        currentPhase = phase
      } completion: {
        MainActor.assumeIsolated {
          continuation.resume()
        }
      }
    }
  }
}
