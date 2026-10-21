import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct GesturePropertyCaptureBindingTests {
  private final class Log {
    var read: (() -> Int)?
    var projection: (() -> GestureStateBinding<Int>)?
    var wrapper: GestureState<Int>?
    var scope: AuthoringContext?
  }

  private struct Host: View {
    @GestureState var value = 0
    let log: Log

    var body: some View {
      log.read = { value }
      log.projection = { $value }
      log.wrapper = _value
      log.scope = currentAuthoringContext()
      return Text("\(value)")
    }
  }

  private func resolve(_ host: Host, graph: ViewGraph) {
    graph.beginFrame()
    var context = ResolveContext(identity: testIdentity("gesture-capture"))
    context.viewGraph = graph
    _ = Resolver().resolve(host, in: context)
  }

  @Test("direct reads and fresh projections keep their graph during wrong-scope callbacks")
  func independentGraphs() throws {
    let first = ViewGraph()
    let second = ViewGraph()
    let log = Log()
    let host = Host(log: log)
    resolve(host, graph: first)
    let read = try #require(log.read)
    let projection = try #require(log.projection)
    let binding = projection()
    binding.setValue(7)
    resolve(host, graph: second)
    let otherProjection = try #require(log.projection)
    let other = otherProjection()
    other.setValue(12)
    #expect(read() == 7)
    withAuthoringContext(log.scope) {
      #expect(read() == 7)
      #expect(projection().hasSameStorage(as: binding))
      projection().setValue(9)
      #expect(other.currentValue() == 12)
    }
    let reader = second.beginEvaluation(identity: testIdentity("gesture-reader"), invalidator: nil)
    ViewNodeContext.withValue(reader) {
      withAuthoringContext(log.scope) { #expect(read() == 9) }
    }
    projection().resetToSeed()
    #expect(read() == 0)
    #expect(other.currentValue() == 12)
  }

  @Test("checkpoint storage and replacement owners remain authoritative")
  func checkpointAndRemint() throws {
    let graph = ViewGraph()
    let log = Log()
    let host = Host(log: log)
    resolve(host, graph: graph)
    let read = try #require(log.read)
    let projection = try #require(log.projection)
    let checkpoint = graph.makeCheckpoint()
    projection().setValue(8)
    #expect(read() == 8)
    graph.restoreCheckpoint(checkpoint)
    #expect(read() == 0)
    graph.beginFrame()
    graph.removeSubtree(
      rootedAt: try #require(graph.nodeForIdentity(testIdentity("gesture-capture"))))
    resolve(host, graph: graph)
    let replacementProjection = try #require(log.projection)
    let replacement = replacementProjection()
    replacement.setValue(3)
    #expect(!projection().hasSameStorage(as: replacement))
    projection().setValue(99)
    #expect(replacement.currentValue() == 3)
    projection().resetToSeed()
    #expect(replacement.currentValue() == 3)
  }

  #if DEBUG
    @Test("prepared copies do not accumulate retired box locations")
    func boundedLocations() throws {
      let graph = ViewGraph()
      let log = Log()
      let host = Host(log: log)
      for _ in 0..<64 {
        resolve(host, graph: graph)
        let wrapper = try #require(log.wrapper)
        #expect(wrapper.rememberedLocationCountForTesting == 1)
        graph.beginFrame()
        graph.removeSubtree(
          rootedAt: try #require(graph.nodeForIdentity(testIdentity("gesture-capture"))))
      }
    }
  #endif
}
