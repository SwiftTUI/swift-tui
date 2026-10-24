import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCFocusGestureTests {
  private func resolve<V: View>(_ view: V, graph: ViewGraph, id: Int) {
    graph.beginFrame()
    var context = ResolveContext(identity: testIdentity("setC\(id)"))
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)
  }

  @Test(arguments: [11, 12, 13, 14])
  func nestedPropertyPaths(id: Int) throws {
    let graph = ViewGraph()
    let log = SetCDomainLog()
    defer { log.entries.removeAll() }
    let shared = SetCDomains()
    resolve(SetCDomainHost(first: shared, second: shared, log: log), graph: graph, id: id)
    let entry = try #require(log.entries.last)
    var expected: [Int?] = [nil, nil, 0, nil, nil, 0]
    switch id {
    case 11:
      entry.keyboard.wrappedValue = 1
      expected[0] = 1
    case 12:
      entry.assistive.wrappedValue = 2
      expected[1] = 2
    case 13:
      entry.gesture.setValue(7)
      expected[2] = 7
    default:
      entry.keyboard.wrappedValue = 1
      entry.secondAssistive.wrappedValue = 2
      expected[0] = 1
      expected[4] = 2
    }
    #expect(entry.read() == expected)
  }

  @Test func setC015MixedCapturesIgnoreForeignGraphScope() throws {
    let first = ViewGraph()
    let second = ViewGraph()
    let log = SetCDomainLog()
    defer { log.entries.removeAll() }
    let shared = SetCDomains()
    let host = SetCDomainHost(first: shared, second: shared, log: log)
    resolve(host, graph: first, id: 15)
    let a = try #require(log.entries.last)
    resolve(host, graph: second, id: 15)
    let b = try #require(log.entries.last)
    withAuthoringContext(b.scope) {
      a.keyboard.wrappedValue = 3
      a.assistive.wrappedValue = 4
      a.gesture.setValue(5)
    }
    #expect(a.read() == [3, 4, 5, nil, nil, 0])
    #expect(b.read() == [nil, nil, 0, nil, nil, 0])
  }

  @Test func setC016MixedCapturesFollowCheckpointStorage() throws {
    let graph = ViewGraph()
    let log = SetCDomainLog()
    defer { log.entries.removeAll() }
    let shared = SetCDomains()
    resolve(SetCDomainHost(first: shared, second: shared, log: log), graph: graph, id: 16)
    let entry = try #require(log.entries.last)
    let checkpoint = graph.makeCheckpoint()
    entry.keyboard.wrappedValue = 3
    entry.assistive.wrappedValue = 4
    entry.gesture.setValue(5)
    #expect(entry.read() == [3, 4, 5, nil, nil, 0])
    graph.restoreCheckpoint(checkpoint)
    #expect(entry.read() == [nil, nil, 0, nil, nil, 0])
    entry.gesture.setValue(6)
    #expect(entry.read() == [nil, nil, 6, nil, nil, 0])
  }

  @Test(arguments: [17, 18, 19])
  func retiredLocationsDoNotAddressSuccessors(id: Int) throws {
    let graph = ViewGraph()
    let log = SetCDomainLog()
    defer { log.entries.removeAll() }
    let shared = SetCDomains()
    let host = SetCDomainHost(first: shared, second: shared, log: log)
    resolve(host, graph: graph, id: id)
    let old = try #require(log.entries.last)
    let owner = try #require(graph.nodeForIdentity(testIdentity("setC\(id)")))
    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)
    resolve(host, graph: graph, id: id)
    let fresh = try #require(log.entries.last)
    var expected: [Int?] = [nil, nil, 0, nil, nil, 0]
    switch id {
    case 17: old.keyboard.wrappedValue = 9
    case 18: old.assistive.wrappedValue = 9
    default:
      fresh.gesture.setValue(8)
      old.gesture.setValue(9)
      old.gesture.resetToSeed()
      expected[2] = 8
    }
    #expect(fresh.read() == expected)
  }

  @Test func setC020ForwardedMixedCapturesSurviveReevaluation() throws {
    let graph = ViewGraph()
    let log = SetCDomainLog()
    defer { log.entries.removeAll() }
    let shared = SetCDomains()
    let host = SetCDomainHost(first: shared, second: shared, log: log)
      .padding(1).frame(width: 20)
    resolve(host, graph: graph, id: 20)
    let old = try #require(log.entries.last)
    resolve(host, graph: graph, id: 20)
    let fresh = try #require(log.entries.last)
    old.keyboard.wrappedValue = 2
    old.secondAssistive.wrappedValue = 3
    old.gesture.setValue(4)
    #expect(fresh.read() == [2, nil, 4, nil, 3, 0])
  }
}

private struct SetCDomains: DynamicProperty {
  @FocusState var keyboard: Int?
  @AccessibilityFocusState var assistive: Int?
  @GestureState var gesture = 0
}

@MainActor
private final class SetCDomainLog {
  struct Entry {
    var read: () -> [Int?]
    var keyboard: FocusState<Int?>.Binding
    var assistive: AccessibilityFocusState<Int?>.Binding
    var gesture: GestureStateBinding<Int>
    var secondAssistive: AccessibilityFocusState<Int?>.Binding
    var scope: AuthoringContext?
  }
  var entries: [Entry] = []
}

private struct SetCDomainHost: View {
  var first: SetCDomains
  var second: SetCDomains
  let log: SetCDomainLog

  var body: some View {
    log.entries.append(
      .init(
        read: {
          [
            first.keyboard, first.assistive, first.gesture,
            second.keyboard, second.assistive, second.gesture,
          ]
        },
        keyboard: first.$keyboard, assistive: first.$assistive,
        gesture: first.$gesture, secondAssistive: second.$assistive,
        scope: currentAuthoringContext()))
    return Text("domains")
  }
}
