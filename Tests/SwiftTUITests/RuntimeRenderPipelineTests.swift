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

  @Test("runtime frame head remains abortable without declared rollback effects")
  func runtimeFrameHeadRemainsAbortableWithoutDeclaredRollbackEffects() {
    let pipeline = RuntimeRenderPipeline()

    #expect(pipeline.headStage.isTransactionalWhenAbortable)
  }
}
