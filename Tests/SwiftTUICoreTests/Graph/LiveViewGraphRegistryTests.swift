import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Covers ``LiveViewGraphRegistry`` — the scope-to-graph map that lets `@State`
/// reads and writes outside a resolve pass recover their live owner graph.
///
/// The registry's two correctness properties are weak retirement (a retired
/// graph resolves to `nil`, so an imperative read falls back to the seed) and
/// scope isolation (a scope only ever resolves *its own* graph, never a
/// different live one — the structural guarantee against cross-session leaks).
@MainActor
struct LiveViewGraphRegistryTests {
  @Test("a registered graph resolves from its scope identity")
  func registeredGraphResolves() {
    let graph = ViewGraph()
    #expect(LiveViewGraphRegistry.graph(for: StateGraphScopeID(graph)) === graph)
  }

  @Test("distinct live graphs resolve independently")
  func distinctGraphsResolveIndependently() {
    let a = ViewGraph()
    let b = ViewGraph()
    let scopeA = StateGraphScopeID(a)
    let scopeB = StateGraphScopeID(b)

    #expect(scopeA != scopeB)
    #expect(LiveViewGraphRegistry.graph(for: scopeA) === a)
    #expect(LiveViewGraphRegistry.graph(for: scopeB) === b)
  }

  @Test("a retired graph's scope resolves to nil, never a different live graph")
  func retiredScopeResolvesToNil() {
    // Allocate both while live so their scope IDs are captured from distinct
    // addresses — never confused even if the allocator later reuses memory.
    let b = ViewGraph()
    let scopeB = StateGraphScopeID(b)
    var a: ViewGraph? = ViewGraph()
    let scopeA = StateGraphScopeID(a!)

    #expect(scopeA != scopeB)
    #expect(LiveViewGraphRegistry.graph(for: scopeA) === a)

    a = nil  // retire graph A; the registry holds it weakly

    // A's scope now resolves to nil (the imperative read will fall back to the
    // box seed) — and crucially it does NOT resolve to the still-live B.
    #expect(LiveViewGraphRegistry.graph(for: scopeA) == nil)
    #expect(LiveViewGraphRegistry.graph(for: scopeB) === b)
  }
}
