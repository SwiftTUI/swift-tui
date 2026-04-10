package import Core

/// A view that cycles through a sequence of phases, applying an
/// animation between each pair of consecutive phases.
///
/// Matches SwiftUI's `phaseAnimator(_:content:animation:)` higher-
/// level API.  On first appearance the view renders at phase 0;
/// a background task then walks the phases in a loop, advancing
/// to the next phase only after the previous animation completes
/// via the ``withAnimation(_:_:completion:)`` batch drain.
///
/// The animation closure returns the curve to use when transitioning
/// INTO the given phase.  Returning nil makes the transition to
/// that phase snap immediately (the content still updates but the
/// controller doesn't enqueue an animation).
///
/// Usage:
///
///     enum Phase { case a, b, c }
///
///     PhaseAnimator([Phase.a, .b, .c]) { phase in
///       Text("hello")
///         .foregroundStyle(phase == .a ? .red : .blue)
///         .offset(x: phase == .c ? 20 : 0)
///     } animation: { phase in
///       switch phase {
///       case .a: .linear(duration: .milliseconds(500))
///       case .b: .easeInOut(duration: .milliseconds(700))
///       case .c: .spring(duration: .milliseconds(500), bounce: 0.3)
///       }
///     }
///
/// - Note: The phases array must be non-empty.  Calling
///   `PhaseAnimator([])` is a programmer error and will trap in
///   debug builds.
public struct PhaseAnimator<Phase: Equatable & Sendable, Content: View>: View {
  private let phases: [Phase]
  private let content: @MainActor (Phase) -> Content
  private let animation: @Sendable (Phase) -> Animation?

  @State private var currentPhase: Phase

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
    _currentPhase = State(wrappedValue: phases[0])
  }

  public var body: some View {
    content(currentPhase)
      .task { @MainActor in
        await runPhaseLoop()
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

      // Capture the phase write into the controller's animation
      // machinery, then suspend until the matching completion
      // closure fires.
      await withCheckedContinuation {
        (continuation: CheckedContinuation<Void, Never>) in
        withAnimation(nextAnimation) {
          currentPhase = nextPhase
        } completion: {
          MainActor.assumeIsolated {
            continuation.resume()
          }
        }
      }

      if Task.isCancelled { break }
      currentIndex = nextIndex
    }
  }
}
