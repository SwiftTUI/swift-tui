import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Composed-runtime coverage for the chunked resolve driver with a
/// Life-shaped autonomous tick task authored DEEPER than the depth cap: the
/// task registers from a drained chunk, and its state writes must keep
/// producing frames (the WASI Game-of-Life freeze class).
@MainActor
@Suite("Deferred-resolve deep task runtime frames")
struct DeferredResolveDeepTaskTests {
  private struct DeepTickProbe: View {
    @State private var generation = 0

    var body: some View {
      Text("gen \(generation)")
        .task(id: "tick") {
          // One yield + one write, mirroring AsyncLifecycleTaskFrameProbe:
          // the covered defect class is "a task registered from a drained
          // chunk writes state and no frame follows", which a single write
          // catches; a free-running tick loop starves the parallel test
          // lane's MainActor.
          await Task.yield()
          generation += 1
        }
    }
  }

  private struct NestingLevel<Content: View>: View {
    let content: Content

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        content
      }
    }
  }

  private static func nested(_ levels: Int, leaf: some View) -> AnyView {
    var current = AnyView(leaf)
    for _ in 0..<levels {
      let wrapped = current
      current = AnyView(NestingLevel(content: wrapped))
    }
    return current
  }

  @Test("a tick task authored below the chunk boundary keeps presenting frames")
  func deepTickTaskKeepsPresentingFrames() async throws {
    let terminal = RecordingPresentationSurface(
      surfaceSize: .init(width: 40, height: 24)
    )
    let rootIdentity = testIdentity("DeferredDeepTaskRoot")
    let inputReader = ScriptedAutonomousWakeInputReader(
      frameSignal: terminal.frameSignal,
      steps: [
        .awaitCondition {
          terminal.frames.contains { $0.contains("gen 1") }
        }
      ])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: inputReader,
      signalReader: ImmediateFinishSignalReader(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 40, height: 24),
      viewBuilder: { _, _ in
        Self.nested(8, leaf: DeepTickProbe())
      }
    )
    runLoop.renderer.viewGraph.setDeferredResolveDepthLimitForTesting(3)

    let result = try await runLoop.run()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(terminal.frames.contains { $0.contains("gen 0") })
    #expect(
      terminal.frames.contains { $0.contains("gen 1") },
      "the deep tick task's write never presented a frame"
    )
  }
}
