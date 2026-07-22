import Observation
import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The draft-window observation deafness class (the amd64 stack-lean cadence
/// stall): in the abortable pipeline a frame's observation draft stays
/// unpublished across the async tail. A model write landing in that window
/// fires — and consumes — the one-shot registration armed during the frame's
/// resolve, whose pass is newer than anything published. Dropping that fire
/// outright leaves observation permanently deaf for the identity: no
/// invalidation, no next frame, and nothing ever re-arms the tracking.
///
/// The held raster gate makes the window deterministic on every machine
/// (frame latency ≥ writer cadence is the organic trigger, which only slow
/// runners hit): hold the write-driven frame's tail, write again mid-hold,
/// release, and require the second write's value to reach the surface.
@Observable
private final class DraftWindowModel {
  var value = 0
}

private struct DraftWindowProbeView: View {
  let model: DraftWindowModel

  var body: some View {
    Text("value \(model.value)")
  }
}

// The time limit is a HANG bound, not a performance assertion: under the
// full parallel gate ordinary sibling tests run 100+ seconds on main-actor
// contention alone (the PerTickPresentCadenceTests convention — a 1-minute
// bound trips on starvation without any defect).
@Suite(.serialized, .timeLimit(.minutes(5)))
struct ObservationDraftWindowRuntimeTests {
  @MainActor
  @Test("a model write during a held frame tail still drives the next frame")
  func writeDuringHeldTailStillDrivesNextFrame() async throws {
    let model = DraftWindowModel()
    let rootIdentity = testIdentity("DraftWindowRoot")
    let terminal = RecordingPresentationSurface(
      surfaceSize: CellSize(width: 32, height: 4)
    )
    let inputReader = InjectedTerminalInputReader()
    // Entry 1 is the bootstrap frame's raster; entry 2 is the first
    // write-driven frame — hold its tail to open the draft window.
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 2)
    let renderer = DefaultRenderer()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      presentationSurface: terminal,
      terminalInputReader: inputReader,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      keyHandler: { keyPress, _, _ in
        if keyPress == KeyPress(.character("d"), modifiers: .ctrl) {
          return .exit(.userExit(keyPress))
        }
        return .ignored
      },
      proposal: ProposedSize(width: 32, height: 4),
      viewBuilder: { _, _ in
        DraftWindowProbeView(model: model)
      }
    )
    runLoop.renderMode = .asyncNoCancel

    let runTask = Task {
      try await runLoop.run()
    }

    // Timestamped phase breadcrumbs, the cadence-suite pattern: when a slow
    // parallel-gate runner exceeds the suite time limit, the printed elapsed
    // times apportion the clock between starvation and a genuine wedge.
    let clock = ContinuousClock()
    let start = clock.now
    func phase(_ name: String) {
      print("[draft-window] +\(start.duration(to: clock.now)): \(name)")
    }

    // Bootstrap frame on the surface first, so the next write is the held
    // frame's trigger.
    phase("awaiting bootstrap frame")
    await terminal.frameSignal.wait {
      terminal.frames.contains { $0.contains("value 0") }
    }

    model.value = 1
    phase("awaiting held tail")
    await gate.waitUntilBlocked()

    // The window write: the held frame's draft is unpublished, and its
    // re-armed one-shot carries the draft's pass. This write must survive
    // the frame's publish as an invalidation.
    model.value = 2

    gate.release()

    // Without the held write, observation is deaf here: no frame ever
    // presents "value 2" and the suite time limit is the failure bound.
    phase("awaiting promoted write's frame")
    await terminal.frameSignal.wait {
      terminal.frames.contains { $0.contains("value 2") }
    }

    inputReader.send(.key(.character("d"), modifiers: .ctrl))
    inputReader.finish()
    phase("awaiting run-loop exit")
    _ = try await runTask.value
    phase("done")
  }
}
