import Testing

@testable import Core

@Suite
struct StackSafetyRegressionTests {
  @Test("draw metadata preserves value semantics after copies mutate")
  func drawMetadataPreservesValueSemantics() {
    let original = DrawMetadata(
      foregroundStyle: .semantic(.foreground),
      listRowForegroundStyle: .semantic(.success),
      clipsToBounds: true
    )
    var copy = original

    copy.foregroundStyle = .semantic(.tint)
    copy.listRowForegroundStyle = .semantic(.warning)
    copy.clipsToBounds = false

    #expect(original.foregroundStyle == .semantic(.foreground))
    #expect(original.listRowForegroundStyle == .semantic(.success))
    #expect(original.clipsToBounds)

    #expect(copy.foregroundStyle == .semantic(.tint))
    #expect(copy.listRowForegroundStyle == .semantic(.warning))
    #expect(!copy.clipsToBounds)
  }

  @Test("post-layout render node metadata stays within stack-safety budgets")
  func renderNodeLayoutsStayWithinBudget() {
    #expect(MemoryLayout<DrawMetadata>.size <= 128)
    #expect(MemoryLayout<PlacedNode>.size <= 768)
    #expect(MemoryLayout<DrawNode>.size <= 256)
  }
}
