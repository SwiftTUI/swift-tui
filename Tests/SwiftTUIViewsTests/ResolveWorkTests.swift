import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
struct ResolveWorkTests {
  @Test("explicit continuations unwind a deep dependency chain")
  func deepContinuations() {
    func descend(_ depth: Int) -> ResolveWork<Int> {
      .deferred {
        guard depth > 0 else { return .value(0) }
        return descend(depth - 1).map { $0 + 1 }
      }
    }
    #expect(descend(20_000).run() == 20_000)
  }

  @Test("parent continuations restore the parent scope after child evaluation")
  func scopedContinuation() {
    let graph = ViewGraph()
    graph.beginFrame()
    let parent = graph.beginEvaluation(identity: Identity(components: ["parent"]), invalidator: nil)
    let child = graph.beginEvaluation(identity: Identity(components: ["child"]), invalidator: nil)
    let work = ViewNodeContext.withCurrentValue(parent) {
      let childWork = ViewNodeContext.withCurrentValue(child) {
        ResolveWork<Int>.deferred {
          #expect(ViewNodeContext.current === child)
          return .value(7)
        }
      }
      return childWork.map { value in
        #expect(ViewNodeContext.current === parent)
        return value + 1
      }
    }
    #expect(work.run() == 8)
    #expect(ViewNodeContext.current == nil)
  }
}
