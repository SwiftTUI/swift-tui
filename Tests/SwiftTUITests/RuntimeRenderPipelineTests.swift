import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite
struct RuntimeRenderPipelineTests {
  @Test("runtime pipeline models the real composed stage order")
  func runtimePipelineModelsRealStageOrder() {
    let pipeline = RuntimeRenderPipeline()

    #expect(pipeline.stageOrder == RuntimeRenderStageName.orderedComposition)
    #expect(
      pipeline.stageOrder == [
        .head,
        .animationInjection,
        .latePreferenceReconciliation,
        .fusedFrameTail,
        .commit,
      ])
  }
}

/// The async executor's stage walk, exercised on its own.
///
/// One generic executor serves both asynchronous paths — abortable and
/// cancellable — which differ only in what their stages carry. Being generic
/// makes the walk testable with trivial stand-in types: the loop's rules are
/// asserted directly, rather than inferred from whichever concrete path a
/// higher-level test happens to drive.
@MainActor
@Suite
struct AsyncRenderStageWalkTests {
  @Test("a frame finished at reconciliation skips the tail and commit")
  func finishingAtReconciliationSkipsRemainingStages() async {
    // The cancelled-before-start shape, in the abstract: the reconciliation
    // stage reports a terminal outcome, so no later stage may run. Before the
    // executors were unified this leg existed only on the cancellable path and
    // had no test at all.
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      Text("finished"),
      context: .init(identity: testIdentity("StageWalkFinished")),
      proposal: .init(width: 8, height: 1)
    )
    let reached = StageWalkReachFlags()

    let result = await RuntimeRenderPipeline().renderAsync(
      head: draft,
      handlers: AsyncRenderStageHandlers<Int, String>(
        animationInjection: { $0 },
        commitElidedFrameIfOffscreen: { _ in false },
        latePreferenceReconciliation: { _ in .finished("cancelled-before-start") },
        fusedFrameTail: { _, _ in
          reached.fusedFrameTail = true
          Issue.record("fusedFrameTail ran after the frame finished at reconciliation")
          fatalError("unreachable: a finished frame must skip the fused frame tail")
        },
        commit: { _, _ in
          reached.commit = true
          Issue.record("commit ran after the frame finished at reconciliation")
          fatalError("unreachable: a finished frame must skip commit")
        }
      )
    )

    guard case .rendered(let outcome) = result else {
      Issue.record("expected the finished outcome to be reported as .rendered")
      renderer.abortPreparedFrameHeadForCancellationTesting(draft)
      return
    }
    #expect(outcome == "cancelled-before-start")
    #expect(!reached.fusedFrameTail)
    #expect(!reached.commit)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  @Test("elision after animation injection skips reconciliation onward")
  func elisionSkipsRemainingStages() async {
    // The same short-circuit the concrete paths rely on, asserted against the
    // shared walk rather than one path's handlers.
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      Text("elided"),
      context: .init(identity: testIdentity("StageWalkElided")),
      proposal: .init(width: 8, height: 1)
    )
    let reached = StageWalkReachFlags()

    let result = await RuntimeRenderPipeline().renderAsync(
      head: draft,
      handlers: AsyncRenderStageHandlers<Int, String>(
        animationInjection: { $0 },
        commitElidedFrameIfOffscreen: { _ in true },
        latePreferenceReconciliation: { _ in
          reached.latePreference = true
          Issue.record("latePreferenceReconciliation ran for an elided frame")
          fatalError("unreachable: an elided frame must skip reconciliation")
        },
        fusedFrameTail: { _, _ in
          reached.fusedFrameTail = true
          Issue.record("fusedFrameTail ran for an elided frame")
          fatalError("unreachable: an elided frame must skip the fused frame tail")
        },
        commit: { _, _ in
          reached.commit = true
          Issue.record("commit ran for an elided frame")
          fatalError("unreachable: an elided frame must skip commit")
        }
      )
    )

    guard case .elided = result else {
      Issue.record("expected the elided frame to report .elided")
      renderer.abortPreparedFrameHeadForCancellationTesting(draft)
      return
    }
    #expect(!reached.latePreference)
    #expect(!reached.fusedFrameTail)
    #expect(!reached.commit)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  @Test("elision wins over a commit outcome")
  func elisionTakesPrecedenceOverAnOutcome() async {
    // Ordering guard: elision is recorded at `.animationInjection`, which
    // precedes every stage that could record an outcome, so `.elided` is the
    // only reachable result once the gate fires. Pins that the terminal
    // unwrap checks elision first.
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      Text("both"),
      context: .init(identity: testIdentity("StageWalkPrecedence")),
      proposal: .init(width: 8, height: 1)
    )

    let result = await RuntimeRenderPipeline().renderAsync(
      head: draft,
      handlers: AsyncRenderStageHandlers<Int, String>(
        animationInjection: { $0 },
        commitElidedFrameIfOffscreen: { _ in true },
        latePreferenceReconciliation: { _ in .finished("should not be reached") },
        fusedFrameTail: { _, _ in
          fatalError("unreachable: an elided frame must skip the fused frame tail")
        },
        commit: { _, _ in
          fatalError("unreachable: an elided frame must skip commit")
        }
      )
    )

    guard case .elided = result else {
      Issue.record("expected .elided to win once the gate fired")
      renderer.abortPreparedFrameHeadForCancellationTesting(draft)
      return
    }

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }
}

private final class StageWalkReachFlags {
  var latePreference = false
  var fusedFrameTail = false
  var commit = false
}
