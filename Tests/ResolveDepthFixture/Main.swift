import SwiftTUICore
import SwiftTUIViews

@MainActor
private final class Probe {
  var bodyCount = 0
}

private struct DeepBody: View {
  let depth: Int
  let probe: Probe
  var body: some View {
    probe.bodyCount += 1
    return Group {
      if depth == 0 { Text("leaf") } else { DeepBody(depth: depth - 1, probe: probe) }
    }
  }
}

private struct DeepCollection: View {
  let depth: Int
  let probe: Probe
  var body: some View {
    probe.bodyCount += 1
    return VStack {
      ForEach(0..<1, id: \.self) { _ in
        if depth == 0 { Text("leaf") } else { DeepCollection(depth: depth - 1, probe: probe) }
      }
    }
  }
}

@main
private struct ResolveDepthFixture {
  @MainActor
  static func main() {
    let depth = Int(CommandLine.arguments.dropFirst().first ?? "256") ?? 256
    precondition(depth > 0)
    let bodyProbe = Probe()
    ResolveWorkDiagnostics.reset()
    let body = Resolver().resolve(DeepBody(depth: depth * 4, probe: bodyProbe))
    precondition(bodyProbe.bodyCount == depth * 4 + 1)
    precondition(body.subtreeNodeCount > 0)
    precondition(ResolveWorkDiagnostics.maximumDrains == 1)
    print("custom-body depth=\(depth * 4) bodies=\(bodyProbe.bodyCount) drains=1")

    // AnyView policy: runtime wrapper depth is the subject of this fixture.
    var wrappers = AnyView(Text("leaf"))
    for index in 0..<depth { wrappers = AnyView(wrappers.padding(0).id(index)) }
    ResolveWorkDiagnostics.reset()
    let wrapped = Resolver().resolve(wrappers)
    precondition(wrapped.subtreeNodeCount >= depth)
    precondition(ResolveWorkDiagnostics.maximumDrains == 1)
    print("erased-modifier-entity depth=\(depth) drains=1")

    let graph = ViewGraph()
    var context = ResolveContext(
      identity: Identity(components: ["Depth"]), environmentValues: .init(),
      applyEnvironmentValues: true)
    context.viewGraph = graph
    let collectionProbe = Probe()
    ResolveWorkDiagnostics.reset()
    graph.beginFrame()
    let collection = Resolver().resolve(
      DeepCollection(depth: depth, probe: collectionProbe), in: context)
    precondition(collectionProbe.bodyCount == depth + 1)
    precondition(ResolveWorkDiagnostics.maximumDrains == 1)
    _ = graph.finalizeFrame(rootIdentity: context.identity, resolved: collection, placed: nil)
    print("graph-collection depth=\(depth) bodies=\(collectionProbe.bodyCount) drains=1")
    print("PASS iterative resolve depth fixture")
  }
}
