import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct PanelTests {
  @Test("Panel with explicit id exposes that id via ActionScope.ID")
  func panelExposesExplicitID() {
    let panel = Panel(id: "editor") { EmptyView() }
    #expect(panel.id == "editor")
  }

  @Test("Panel sets focusScopeBoundary in its resolved node metadata")
  func panelMarksFocusScopeBoundary() {
    let panel = Panel(id: "editor") { EmptyView() }
    let resolved = resolveForTest(panel)
    #expect(resolved.semanticMetadata.focusScopeBoundary == true)
  }

  @Test("Panel is focusable")
  func panelIsFocusable() {
    let panel = Panel(id: "editor") { EmptyView() }
    let resolved = resolveForTest(panel)
    #expect(resolved.semanticMetadata.isFocusable == true)
  }

  @Test(".panel() produces stable AnyID across re-resolves at the same source location")
  func panelPseudonymousIDIsStable() {
    // Drive a full resolve pass twice over the same view hierarchy
    // (`Text("x").panel()` nested inside a parent view body). During
    // body evaluation `withAuthoringContext` is set up by the resolver,
    // so `.panel()` exercises the `scope?.viewIdentity` branch rather
    // than falling back to `Identity(components: [])`. Each resolve
    // records the Panel's synthesised `AnyID` and the Panel's
    // `ResolvedNode.identity` via a side-effecting probe; both must be
    // equal across resolves for stability to hold.
    let capture1 = PanelIDCapture()
    let capture2 = PanelIDCapture()

    let tree1 = PseudonymousPanelProbe(capture: capture1)
    let tree2 = PseudonymousPanelProbe(capture: capture2)

    let resolver = Resolver()
    let resolved1 = resolver.resolve(
      AnyView(tree1),
      in: ResolveContext(identity: testIdentity("panel-stability-root"))
    )
    let resolved2 = resolver.resolve(
      AnyView(tree2),
      in: ResolveContext(identity: testIdentity("panel-stability-root"))
    )

    // Each resolve must have actually run the probe's body and
    // captured a non-fallback AnyID (i.e. the authoring context was
    // populated). The fallback would be derived from an empty Identity.
    let emptyFallback = AnyID(Identity(components: [] as [String]))
    #expect(capture1.ids.count == 1)
    #expect(capture2.ids.count == 1)
    #expect(capture1.ids.first != emptyFallback)
    #expect(capture2.ids.first != emptyFallback)

    // Stability: the same source location resolved twice yields the
    // same pseudonymous AnyID (exercising `scope?.viewIdentity`).
    #expect(capture1.ids.first == capture2.ids.first)

    // Stability at the resolved-tree level: find the Panel in each
    // resolved tree and compare its identity. Panel nodes are marked
    // with `focusScopeBoundary == true` and `kind == .view("Panel")`.
    let panel1 = findPanelNode(in: resolved1)
    let panel2 = findPanelNode(in: resolved2)
    #expect(panel1 != nil)
    #expect(panel2 != nil)
    #expect(panel1?.identity == panel2?.identity)
  }

  @Test(".focusContainment(.sealed) prevents descendant focus regions from being reachable")
  func sealedPanelBlocksDescendantFocus() {
    // A sealed Panel containing a focusable leaf should, after
    // semantic extraction, produce exactly one focus region — the
    // Panel's own. Descendant focusables inside a sealed panel do not
    // appear in the focus region list.
    let sealedPanel = Panel(id: "outer") {
      Text("inner").focusable(true)
    }
    .focusContainment(.sealed)

    let regions = extractFocusRegionsForTest(sealedPanel)
    #expect(regions.count == 1)
  }

  @Test(
    ".focusContainment(.sealed) suppresses link focus regions emitted from rich-text payload semantics"
  )
  func sealedPanelBlocksRichTextLinkFocusRegions() {
    // A Text with an interpolated inline Link carries a richText draw
    // payload whose runs are tagged with a `linkIdentifier`. The
    // semantic extractor's rich-text path (`appendRichTextSemantics`)
    // emits one focus region per distinct link identifier. Inside a
    // sealed Panel those descendant focus regions must be suppressed
    // — only the Panel's own focus region may remain.
    let sealedPanel = Panel(id: "outer") {
      Text("see \(Link("docs", destination: "https://example.com")) now")
    }
    .focusContainment(.sealed)

    let regions = extractFocusRegionsForTest(sealedPanel)
    #expect(regions.count == 1)
  }

  @Test(".panel() inside ForEach assigns distinct, per-iteration-stable identities")
  func panelInForEachProducesDistinctStableIDs() {
    // Resolve a view containing ForEach with `.panel()` inside its
    // row body. The structural identity at each iteration must differ
    // (so three rows yield three distinct Panel AnyIDs), and re-
    // resolving the same hierarchy must produce pairwise-equal ids at
    // each iteration position (structural identity is stable).
    let capture1 = PanelIDCapture()
    let capture2 = PanelIDCapture()

    let tree1 = ForEachPanelProbe(capture: capture1)
    let tree2 = ForEachPanelProbe(capture: capture2)

    let resolver = Resolver()
    _ = resolver.resolve(
      AnyView(tree1),
      in: ResolveContext(identity: testIdentity("foreach-panel-root"))
    )
    _ = resolver.resolve(
      AnyView(tree2),
      in: ResolveContext(identity: testIdentity("foreach-panel-root"))
    )

    // Three iterations, three distinct ids on the first resolve.
    #expect(capture1.ids.count == 3)
    #expect(Set(capture1.ids).count == 3)

    // Second resolve: three ids pairwise equal to the first.
    #expect(capture2.ids.count == 3)
    #expect(capture1.ids == capture2.ids)
  }

  @Test(".focusContainment(.sealed) suppresses descendant focus regions from list children")
  func sealedPanelBlocksListDescendantFocusRegions() {
    // A sealed Panel containing a List with focusable row content
    // should still yield a single focus region (the Panel). The List
    // itself and any focusable row content live under a sealed
    // ancestor and must not contribute focus regions.
    let sealedPanel = Panel(id: "outer") {
      List(selection: .constant(0)) {
        Text("row 0").focusable(true).tag(0)
        Text("row 1").focusable(true).tag(1)
      }
    }
    .focusContainment(.sealed)

    let regions = extractFocusRegionsForTest(sealedPanel)
    #expect(regions.count == 1)
  }
}

/// A probe view whose body constructs `Text("x").panel()` during each
/// resolve pass. The probe runs inside `withAuthoringContext` (set up by
/// `resolveView`), so `.panel()` takes the `scope?.viewIdentity` branch.
/// The probe captures the Panel's `AnyID` into `capture` so tests can
/// assert pseudonymous-ID stability across re-resolves.
private struct PseudonymousPanelProbe: View {
  let capture: PanelIDCapture

  var body: some View {
    let panel = Text("content").panel()
    capture.ids.append(panel.id)
    return panel
  }
}

@MainActor
private final class PanelIDCapture {
  var ids: [AnyID] = []
}

/// A probe view that runs `.panel()` inside a `ForEach` body. Each
/// iteration appends the resulting Panel's `AnyID` to `capture`, so a
/// single resolve produces one id per element.
private struct ForEachPanelProbe: View {
  let capture: PanelIDCapture

  var body: some View {
    ForEach([0, 1, 2], id: \.self) { _ in
      let panel = Text("row").panel()
      capture.ids.append(panel.id)
      return panel
    }
  }
}

/// Traverses `root` to find the resolved node produced by a `Panel`.
/// Panels set `kind == .view("Panel")` and mark themselves as focus
/// scope boundaries; either predicate uniquely identifies the node.
@MainActor
private func findPanelNode(in root: ResolvedNode) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if case .view(let name) = node.kind, name == "Panel" {
      return node
    }
    stack.append(contentsOf: node.children)
  }
  return nil
}

/// Extracts the focus regions produced for `view` under the full render
/// pipeline. Uses `DefaultRenderer` so that semantic extraction runs
/// over a concretely placed tree, matching the runtime's behavior.
@MainActor
private func extractFocusRegionsForTest<V: View>(_ view: V) -> [FocusRegion] {
  let artifacts = DefaultRenderer().render(
    view,
    context: .init(identity: testIdentity("panel-focus-root")),
    proposal: .init(width: 20, height: 5)
  )
  return artifacts.semanticSnapshot.focusRegions
}

/// Resolves `view` by running it through the full resolver once and
/// returning the root `ResolvedNode`. Mirrors what existing tests do in
/// `Tests/ViewTests/ViewResolutionTests.swift` but keeps Panel tests
/// scoped to the `TerminalUITests` target where `DefaultRenderer` lives.
@MainActor
private func resolveForTest<V: View>(_ view: V) -> ResolvedNode {
  let resolver = Resolver()
  return resolver.resolve(
    AnyView(view),
    in: ResolveContext(identity: testIdentity("panel-test-root"))
  )
}
