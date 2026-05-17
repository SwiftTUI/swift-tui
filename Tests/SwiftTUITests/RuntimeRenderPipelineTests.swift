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

  @Test("runtime frame head declares its transactional effects")
  func runtimeFrameHeadDeclaresTransactionalEffects() {
    let pipeline = RuntimeRenderPipeline()

    #expect(pipeline.headStage.isTransactionalWhenAbortable)
    #expect(
      pipeline.headStage.declaredEffects.effects == [
        .viewGraph,
        .frameState,
        .presentationPortalState,
        .observationBridge,
      ])
  }
}
