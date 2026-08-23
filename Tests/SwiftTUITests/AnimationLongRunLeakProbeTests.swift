import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Diagnostic probe: drives a real `RunLoop` hosting an auto-cycling
/// `PhaseAnimator` (the gallery AnimationsTab section-7 shape) for hundreds of
/// frames and samples every runtime container that could accumulate per frame
/// or per phase cycle. A strictly-increasing container between the two sample
/// points is the leak.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct AnimationLongRunLeakProbeTests {
  @Test("auto-cycling PhaseAnimator runtime containers stay bounded")
  func autoCyclingPhaseAnimatorContainersStayBounded() async throws {
    let terminal = RecordingPresentationSurface(
      surfaceSize: .init(width: 40, height: 8)
    )
    let rootIdentity = testIdentity("PhaseLeakProbeRoot")
    let renderer = DefaultRenderer()
    let inputReader = InjectedTerminalInputReader()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("c"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: ProposedSize(width: 40, height: 8),
      viewBuilder: { _, _ in
        AutoCyclingPhaseProbeView()
      }
    )

    let runTask = Task {
      try await runLoop.run()
    }

    await terminal.frameSignal.wait {
      terminal.frames.count >= 60
    }
    let sampleA = RuntimeContainerSample(renderer: renderer)
    let framesA = terminal.frames.count
    let timeA = ContinuousClock.now

    await terminal.frameSignal.wait {
      terminal.frames.count >= 360
    }
    let sampleB = RuntimeContainerSample(renderer: renderer)
    let framesB = terminal.frames.count
    let timeB = ContinuousClock.now

    inputReader.send(.key(.character("c"), modifiers: .ctrl))
    inputReader.finish()
    _ = try await runTask.value

    let elapsed = timeA.duration(to: timeB)
    let elapsedSeconds =
      Double(elapsed.components.seconds)
      + Double(elapsed.components.attoseconds) / 1e18
    let framesPerSecond = Double(framesB - framesA) / max(elapsedSeconds, 0.001)
    print("[leak-probe] frames \(framesA) -> \(framesB) in \(elapsedSeconds)s")
    print("[leak-probe] frames/sec ≈ \(framesPerSecond)")
    print("[leak-probe] sample A:\n\(sampleA.description)")
    print("[leak-probe] sample B:\n\(sampleB.description)")
    print("[leak-probe] deltas:\n\(sampleA.deltaDescription(to: sampleB))")

    // The animation pump runs on the 33 ms cadence; a busy loop would produce
    // far more frames than the deadline cadence allows.
    #expect(framesPerSecond < 45)

    // Per-frame transients are cleared together at every evaluation start
    // (ViewGraph.beginFrame's removeAll pair), so a point-in-time diff of
    // them measures sampling phase, not accumulation: on a slow runner the
    // frame-count signal can fire while the next frame's evaluation is
    // already in flight, and sample B reads a non-empty set (first fired on
    // the 2-vCPU amd64 CI runner, 0 -> 3 on both).
    let perFrameTransients: Set<String> = [
      "viewGraph.frameOrder",
      "viewGraph.evaluatedNodeIDsThisFrame",
    ]

    // No runtime container may grow across 300 frames of steady-state
    // animation cycling.
    for (name, a, b) in sampleA.pairedCounts(with: sampleB)
    where b > a + 2 && !perFrameTransients.contains(name) {
      Issue.record("container \(name) grew \(a) -> \(b) across 300 frames")
    }
  }
}

/// One point-in-time reading of every count-shaped runtime container.
private struct RuntimeContainerSample {
  var counts: [(name: String, count: Int)] = []

  @MainActor
  init(renderer: DefaultRenderer) {
    let subsystems = renderer.debugRuntimeSubsystemSnapshot()
    let animation = subsystems.animationController
    append("animation.previousSnapshotIdentities", animation.previousSnapshotIdentities.count)
    append("animation.previousParentByIdentity", animation.previousParentByIdentity.count)
    append("animation.previousChildIndexByIdentity", animation.previousChildIndexByIdentity.count)
    append("animation.previousIdentities", animation.previousIdentities.count)
    append("animation.previousMatchedGeometryBounds", animation.previousMatchedGeometryBounds.count)
    append("animation.previousMatchedKeyIdentities", animation.previousMatchedKeyIdentities.count)
    append("animation.activeAnimationKeys", animation.activeAnimationKeys.count)
    append("animation.registeredAnimationCount", animation.registeredAnimationCount)
    append("animation.completionClosureBatchIDs", animation.completionClosureBatchIDs.count)
    append("animation.batchRefCounts", animation.batchRefCounts.count)
    append("animation.pendingEmptyBatchCompletions", animation.pendingEmptyBatchCompletions.count)
    append("animation.removalAnimationBoxes", animation.removalAnimationBoxesByNodeID.count)
    append("animation.transitionNodeIDs", animation.transitionNodeIDs.count)
    append("animation.previousTransitionNodeIDs", animation.previousTransitionNodeIDs.count)
    append("animation.pendingTransitionNodeIDs", animation.pendingTransitionNodeIDs.count)
    append("animation.removingNodeIDs", animation.removingNodeIDs.count)
    append("animation.deferredFrameHeadCompletions", animation.deferredFrameHeadCompletionCount)

    let frameTail = renderer.frameTailRenderer.memoryMetricSnapshot
    append("frameTail.\(frameTail.name)", frameTail.count)
    for (key, value) in (frameTail.detail ?? [:]).sorted(by: { $0.key < $1.key }) {
      append("frameTail.detail.\(key)", value)
    }

    appendMirrorCounts(prefix: "viewGraph", of: subsystems.viewGraph)
    appendMirrorCounts(prefix: "frameState", of: subsystems.frameState)
    appendMirrorCounts(prefix: "frameInputs", of: subsystems.frameInputs)
    if let bridge = subsystems.observationBridge {
      append("observationBridge.observedPasses", bridge.observedPasses.count)
    }
  }

  private mutating func append(_ name: String, _ count: Int) {
    counts.append((name, count))
  }

  /// Records the `count` of every collection-shaped child (recursing one
  /// level into structs) so unfamiliar snapshot layouts still get covered.
  private mutating func appendMirrorCounts(prefix: String, of subject: Any, depth: Int = 0) {
    let mirror = Mirror(reflecting: subject)
    for child in mirror.children {
      guard let label = child.label else {
        continue
      }
      let name = "\(prefix).\(label)"
      let childMirror = Mirror(reflecting: child.value)
      switch childMirror.displayStyle {
      case .collection, .dictionary, .set:
        append(name, childMirror.children.count)
      case .struct,
        .class where depth < 2:
        appendMirrorCounts(prefix: name, of: child.value, depth: depth + 1)
      default:
        continue
      }
    }
  }

  func pairedCounts(with other: RuntimeContainerSample) -> [(String, Int, Int)] {
    var byName: [String: Int] = [:]
    for entry in counts {
      byName[entry.name] = entry.count
    }
    return other.counts.compactMap { entry in
      guard let before = byName[entry.name] else {
        return nil
      }
      return (entry.name, before, entry.count)
    }
  }

  var description: String {
    counts.map { "  \($0.name) = \($0.count)" }.joined(separator: "\n")
  }

  func deltaDescription(to other: RuntimeContainerSample) -> String {
    pairedCounts(with: other)
      .filter { $0.1 != $0.2 }
      .map { "  \($0.0): \($0.1) -> \($0.2)" }
      .joined(separator: "\n")
  }
}

/// The gallery AnimationsTab section-7 shape: a trigger-free `PhaseAnimator`
/// that cycles phases forever on its own.
private struct AutoCyclingPhaseProbeView: View {
  var body: some View {
    PhaseAnimator([ProbePhase.a, .b, .c, .d]) { phase in
      Text("●●●●●●●●")
        .foregroundStyle(phase.color)
        .offset(x: phase.offsetX, y: 0)
    } animation: { _ in
      .linear(duration: .milliseconds(40))
    }
  }
}

private enum ProbePhase: Equatable, Sendable {
  case a, b, c, d

  var color: Color {
    switch self {
    case .a: .red
    case .b: .yellow
    case .c: .green
    case .d: .cyan
    }
  }

  var offsetX: Int {
    switch self {
    case .a: 0
    case .b: 4
    case .c: 8
    case .d: 4
    }
  }
}
