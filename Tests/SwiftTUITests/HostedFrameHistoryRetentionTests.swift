import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Regression pins for hosted-surface frame retention.
///
/// A production host (SwiftUI/Android) consumes frames through `onFrame` and
/// never reads the surface's retained history — that history exists for the
/// `@_spi(Runners)` frame waiters. Retaining the deep (256-frame) window in a
/// live host held hundreds of raster + semantics frames at animation cadence
/// and read as a strictly-increasing footprint on continuously animating
/// screens (the gallery AnimationsTab under the SwiftUI host). Production
/// constructions now keep a small bounded window; the deep window is opt-in
/// via the designated `@_spi(Runners)` initializer (see
/// `FrameworkStressSceneHostTests` attempts 011-013/017 for that coverage).
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct HostedFrameHistoryRetentionTests {
  private struct PhaseProbeApp: App {
    var body: some Scene {
      WindowGroup("Primary", id: WindowIdentifier("primary")) {
        HostedAutoCyclingPhaseProbeView()
      }
    }
  }

  @Test("production-default hosted surface keeps a small bounded frame history")
  func productionDefaultHostedSurfaceKeepsSmallBoundedHistory() async throws {
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 60, height: 16),
      appearance: .fallback,
      onFrame: { _ in }
    )
    let session = try HostedSceneSession(
      for: PhaseProbeApp(),
      sceneID: WindowIdentifier("primary"),
      surface: surface
    )
    let runTask = Task {
      try await session.start()
    }

    // Deterministic pin for the production construction path: once more
    // frames than the default window have been presented, the retained
    // history must sit exactly at the bounded window and stay there.
    //
    // No process-footprint assertion here on purpose: `swift test` runs
    // hundreds of suites concurrently in this process, so a wall-clock RSS
    // window measures the whole run's allocation churn, not this surface
    // (observed as a 574 MiB "growth" under the full parallel lane). The
    // bounded window is the mechanism the pre-fix leak needed; pinning it is
    // the deterministic form of the same regression guard.
    _ = await surface.waitForFrame { $0.sequence >= 40 }
    let historyPastPlateau = await surface.waitForFrames { _ in true }.count

    _ = await surface.waitForFrame { $0.sequence >= 64 }
    let historyAtEnd = await surface.waitForFrames { _ in true }.count

    session.stop()
    _ = try? await runTask.value

    #expect(historyPastPlateau == 32)
    #expect(historyAtEnd == 32)
  }
}

/// The gallery AnimationsTab section-7 shape: a trigger-free `PhaseAnimator`
/// cycling forever on its own — the steady 30 fps frame producer that made
/// per-frame retention visible.
private struct HostedAutoCyclingPhaseProbeView: View {
  var body: some View {
    PhaseAnimator([HostedProbePhase.a, .b, .c, .d]) { phase in
      Text("●●●●●●●●")
        .foregroundStyle(phase.color)
        .offset(x: phase.offsetX, y: 0)
    } animation: { _ in
      .linear(duration: .milliseconds(40))
    }
  }
}

private enum HostedProbePhase: Equatable, Sendable {
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
