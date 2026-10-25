import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct LazyStackViewportCacheTests {
  @Test(arguments: [false, true])
  func repeatedViewportJumpsPreserveAuthoredOffsets(selective: Bool) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["LazyStackScrollProbe"]),
      size: .init(width: 80, height: 32), selectiveEvaluation: selective
    ) { LazyStackScrollProbe() }
    defer { h.shutdown() }
    #expect(h.frame.contains("vrow 0"))
    for burst in 1...6 {
      _ = try h.scrollPointer(at: .init(x: 5.5, y: 5.5), deltaY: 30)
      #expect(h.frame.contains("vrow \(burst * 30)"), "\(h.frame)")
      let route = try #require(
        h.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
          h.runLoop.latestSemanticSnapshot.scrollRoutes
        ).first)
      #expect(route.contentOffset.y == min(burst * 30, 178))
    }
  }

  // MARK: - Fully offscreen lazy stacks (STUI-1231)

  // The gallery `navigation-collections` launch trap at <= 13 rows: the
  // scroll layout's first measure round declares a zero-height viewport,
  // where windowing is ineligible, so a fixed-frame outline measures
  // exhaustively and the hint-agnostic measurement cache serves that
  // product to the later finite rounds. A fully offscreen exhaustive lazy
  // stack then placed EVERY row (the visible-range helper's "no intersection"
  // collapsed into its "no applicable viewport" fallback), while the cold
  // layout shadow — windowed under the finite hint — placed none:
  // `layout-shadow-divergence`, then the DEBUG assertion. Scrolling.md and
  // Accessibility.md: offscreen lazy rows stay unrealized and outside Tab
  // traversal.
  @Test(
    "a fully offscreen lazy stack places no rows and keeps scroll estimates",
    arguments: [6, 11])
  func fullyOffscreenLazyStackPlacesNoRows(rows: Int) throws {
    let placed = try outlinePlacement(OffscreenOutlineProbe(scrollHosted: true), rows: rows)
    #expect(
      placed.children.count == 0, "rows=\(rows): placed \(placed.children.count) offscreen rows")
    #expect(placed.lazyChildScrollEstimates?.count == 7)
  }

  @Test("a partially visible lazy stack still places exactly its visible rows")
  func partiallyVisibleLazyStackPlacesVisibleRows() throws {
    // Viewport rows 1..<14; the outline starts at row 11 — three rows show.
    let partial = try outlinePlacement(OffscreenOutlineProbe(scrollHosted: true), rows: 14)
    #expect(partial.children.count == 3)
    let full = try outlinePlacement(OffscreenOutlineProbe(scrollHosted: true), rows: 24)
    #expect(full.children.count == 7)
  }

  @Test("a lazy stack outside any scroll viewport places every row")
  func unhostedLazyStackPlacesEveryRow() throws {
    let placed = try outlinePlacement(OffscreenOutlineProbe(scrollHosted: false), rows: 11)
    #expect(placed.children.count == 7)
  }

  @Test("an offscreen lazy stack denied the viewport claim places no rows either")
  func offscreenClaimDeniedLazyStackPlacesNoRows() throws {
    // The first lazy stack claims the scroll hint; the second measures
    // exhaustively (only the outermost indexed container may window) and
    // sits wholly below the 7-row viewport.
    let snapshot = renderWithoutLayoutShadow(
      TwoLazyStacksProbe(), identity: testIdentity("TwoLazyStacksProbe"), rows: 8)
    let lazyNodes = placedLazyStacks(in: snapshot.placedTree)
    try #require(lazyNodes.count == 2)
    #expect(lazyNodes[0].children.count == 4, "the visible first stack keeps its rows")
    #expect(
      lazyNodes[1].children.count == 0, "placed \(lazyNodes[1].children.count) offscreen rows")
  }

  @Test("the layout shadow agrees with short scroll-hosted outlines (probe armed)")
  func layoutShadowAgreesWithShortScrollHostedOutlines() async {
    // A divergence is a DEBUG assertion failure in the frame tail, so the
    // armed renders run in a child process: the trap fails this test alone.
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        let savedEnabled = SoundnessProbeConfiguration.isEnabled
        let savedSample = SoundnessProbeConfiguration.sampleEveryNFrames
        SoundnessProbeConfiguration.isEnabled = true
        SoundnessProbeConfiguration.sampleEveryNFrames = 1
        defer {
          SoundnessProbeConfiguration.isEnabled = savedEnabled
          SoundnessProbeConfiguration.sampleEveryNFrames = savedSample
        }
        for (rows, scrollHosted) in [(6, true), (11, true), (14, true), (24, true), (11, false)] {
          let before = SoundnessProbeConfiguration.layoutShadowDivergenceCount
          let renderer = DefaultRenderer()
          let identity = testIdentity("OffscreenOutlineShadow", "\(rows)", "\(scrollHosted)")
          for _ in 0..<2 {
            _ = renderer.render(
              OffscreenOutlineProbe(scrollHosted: scrollHosted),
              context: .init(identity: identity, invalidatedIdentities: [identity]),
              proposal: .init(width: .finite(40), height: .finite(rows))
            )
          }
          #expect(
            SoundnessProbeConfiguration.layoutShadowDivergenceCount == before,
            "rows=\(rows) scrollHosted=\(scrollHosted): \(SoundnessProbeConfiguration.lastViolationDetailByKind["layout-shadow-divergence"] ?? "")"
          )
        }
      }
    }
  }

  private func outlinePlacement(_ probe: OffscreenOutlineProbe, rows: Int) throws -> PlacedNode {
    let snapshot = renderWithoutLayoutShadow(
      probe, identity: testIdentity("OffscreenOutlineProbe", "\(rows)"), rows: rows)
    let lazyNodes = placedLazyStacks(in: snapshot.placedTree)
    try #require(lazyNodes.count == 1)
    return lazyNodes[0]
  }

  /// Placement-only renders: the layout shadow is the armed exit test's job,
  /// so these characterize what production places without its assertion.
  private func renderWithoutLayoutShadow(
    _ view: some View, identity: Identity, rows: Int
  ) -> RenderSnapshot {
    let savedEnabled = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = savedEnabled }
    return DefaultRenderer().render(
      view,
      context: .init(identity: identity),
      proposal: .init(width: .finite(40), height: .finite(rows))
    )
  }

  private func placedLazyStacks(in root: PlacedNode) -> [PlacedNode] {
    var found: [PlacedNode] = []
    var pending = [root]
    while let node = pending.popLast() {
      if node.lazyStackAllocationSnapshot != nil {
        found.append(node)
      }
      pending.append(contentsOf: node.children.reversed())
    }
    return found
  }
}

/// A fixed-frame outline below ten filler rows, beneath a one-row header:
/// the header makes the scroll layout's first measure round a zero-height
/// viewport, and the fixed frame keeps the outline's proposal identical
/// across rounds, so the measurement cache serves the exhaustive product.
private struct OffscreenOutlineProbe: View {
  let scrollHosted: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      if scrollHosted {
        ScrollView {
          content
        }
      } else {
        content
      }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<10, id: \.self) { index in
        Text("filler \(index)")
      }
      OutlineGroup(OffscreenOutlineNode.roots, children: \.children) { node in
        Text(node.title)
      }
      .frame(width: 24, height: 8, alignment: .topLeading)
    }
  }
}

private struct OffscreenOutlineNode: Identifiable, Sendable {
  let id: String
  let children: [OffscreenOutlineNode]?
  var title: String { id }

  static let roots: [OffscreenOutlineNode] = [
    .init(
      id: "Examples",
      children: [.init(id: "Terminal"), .init(id: "SwiftUI host"), .init(id: "Web/WASI")]),
    .init(id: "Coverage", children: [.init(id: "Build lanes"), .init(id: "Focused tests")]),
  ]

  init(id: String, children: [OffscreenOutlineNode]? = nil) {
    self.id = id
    self.children = children
  }
}

private struct TwoLazyStacksProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
              Text("first \(index)")
            }
          }
          ForEach(0..<6, id: \.self) { index in
            Text("filler \(index)")
          }
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
              Text("second \(index)")
            }
          }
        }
      }
    }
  }
}
private struct LazyStackScrollProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy vstack scroll workload")
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<200, id: \.self) { index in
            HStack(spacing: 1) {
              Text("vrow \(index)")
              Spacer(minLength: 1)
              Text("meta \(index % 89)")
            }
          }
        }.padding(1)
      }.frame(height: 24).border(.separator)
    }.padding(1)
  }
}
