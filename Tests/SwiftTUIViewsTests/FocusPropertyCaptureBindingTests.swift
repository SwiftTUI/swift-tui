import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

@MainActor
@Suite("Focus property capture binding", .serialized)
struct FocusPropertyCaptureBindingTests {
  private final class Log {
    var read: (() -> Bool)?
    var write: ((Bool) -> Void)?
    var projection: (() -> FocusState<Bool>.Binding)?
    var scope: AuthoringContext?
    var wrapper: FocusState<Bool>?
  }

  private struct Host: View {
    @FocusState var focus: Bool
    let log: Log

    var body: some View {
      log.read = { focus }
      log.write = { focus = $0 }
      log.projection = { $focus }
      log.scope = currentAuthoringContext()
      log.wrapper = _focus
      return Text(focus ? "focused" : "unfocused")
    }
  }

  private func resolve(_ host: Host, graph: ViewGraph) {
    graph.beginFrame()
    var context = ResolveContext(identity: testIdentity("focus-capture"))
    context.viewGraph = graph
    _ = Resolver().resolve(host, in: context)
  }

  @Test("captured focus uses its declaring graph under absent and foreign scopes")
  func independentGraphs() throws {
    let firstGraph = ViewGraph()
    let secondGraph = ViewGraph()
    let log = Log()
    let host = Host(log: log)
    resolve(host, graph: firstGraph)
    let firstRead = try #require(log.read)
    let firstWrite = try #require(log.write)
    let firstProjection = try #require(log.projection)
    let firstScope = log.scope
    resolve(host, graph: secondGraph)
    let secondRead = try #require(log.read)
    let secondProjection = try #require(log.projection)
    let secondScope = log.scope

    // Seed via the already-supported exact projected location, so local
    // fallback mutation cannot make a missing capture look correct.
    withAuthoringContext(firstScope) { firstProjection().wrappedValue = true }
    #expect(firstRead())
    #expect(!secondRead())
    withAuthoringContext(secondScope) {
      #expect(firstRead())
      firstWrite(false)
      #expect(!secondProjection().wrappedValue)
      firstWrite(true)
      #expect(!secondProjection().wrappedValue)
    }
    #expect(firstRead())
    #expect(!secondRead())
  }

  @Test("a callback invoked inside another evaluation keeps its owner")
  func nestedEvaluation() throws {
    let graph = ViewGraph()
    let log = Log()
    resolve(Host(log: log), graph: graph)
    let read = try #require(log.read)
    let projection = try #require(log.projection)
    withAuthoringContext(log.scope) { projection().wrappedValue = true }
    let other = graph.beginEvaluation(identity: testIdentity("other-reader"), invalidator: nil)
    let scope = AuthoringContext(
      viewIdentity: other.identity, focusedValues: .init(), viewNode: other)
    ViewNodeContext.withValue(other) {
      withAuthoringContext(scope) { #expect(read()) }
    }
  }

  @Test("captured direct access follows checkpoint storage but never a replacement owner")
  func checkpointAndRetirement() throws {
    let graph = ViewGraph()
    let log = Log()
    let host = Host(log: log)
    resolve(host, graph: graph)
    let read = try #require(log.read)
    let write = try #require(log.write)
    let projection = try #require(log.projection)
    let before = projection()
    let checkpoint = graph.makeCheckpoint()
    write(true)
    #expect(read())
    graph.restoreCheckpoint(checkpoint)
    #expect(!read())
    write(true)
    #expect(read())
    #expect(projection().bindingKey == before.bindingKey)

    let owner = try #require(graph.nodeForIdentity(testIdentity("focus-capture")))
    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)
    resolve(host, graph: graph)
    let successorProjection = try #require(log.projection)
    let successor = successorProjection()
    #expect(successor.bindingKey != before.bindingKey)
    write(true)
    #expect(read())
    #expect(!successor.wrappedValue)
    #expect(
      !before.applyRuntimeValue(
        false,
        observedRequestGeneration: before.requestGeneration, registrationIdentity: owner.identity))
    #expect(read())
    #expect(!successor.wrappedValue)
  }

  #if DEBUG
    @Test("a reused authored box retains only live owner locations")
    func boundedOwnerCache() throws {
      let graph = ViewGraph()
      let log = Log()
      let host = Host(log: log)
      var retired: [FocusState<Bool>] = []
      for _ in 0..<64 {
        resolve(host, graph: graph)
        let wrapper = try #require(log.wrapper)
        #expect(wrapper.rememberedLocationCountForTesting == 1)
        retired.append(wrapper)
        graph.beginFrame()
        graph.removeSubtree(
          rootedAt: try #require(graph.nodeForIdentity(testIdentity("focus-capture"))))
      }
      // Retained copies keep their own fallback, independently of cache pruning.
      retired[0].wrappedValue = true
      #expect(retired[0].wrappedValue)
      #expect(!retired[1].wrappedValue)
    }
  #endif

  private struct Pair: DynamicProperty {
    @FocusState var keyboard: Bool
    @AccessibilityFocusState var accessibility: Bool
  }

  private final class PairLog {
    var read: (() -> [Bool])?
    var write: (() -> Void)?
  }

  private struct PairHost: View {
    var first: Pair
    var second: Pair
    let log: PairLog

    var body: some View {
      log.read = { [first.keyboard, first.accessibility, second.keyboard, second.accessibility] }
      log.write = {
        first.keyboard = true
        second.accessibility = true
      }
      return Text("pairs")
    }
  }

  @Test("shared nested wrapper copies preserve qualified paths and focus domains")
  func composedFocusDomains() throws {
    let graph = ViewGraph()
    var context = ResolveContext(identity: testIdentity("focus-pairs"))
    context.viewGraph = graph
    let pair = Pair()
    let log = PairLog()
    let host = PairHost(first: pair, second: pair, log: log)
    _ = Resolver().resolve(host, in: context)
    let write = try #require(log.write)
    let read = try #require(log.read)
    write()
    #expect(read() == [true, false, false, true])
    _ = Resolver().resolve(host, in: context)
    let freshRead = try #require(log.read)
    #expect(freshRead() == [true, false, false, true])
  }
}
