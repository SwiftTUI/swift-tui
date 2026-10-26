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

  // MARK: - Viewport-dependent lazy products (STUI-1269)

  // The scroll layout's zero-height first round makes the first lazy stack
  // claim a hint it cannot window, so it measures exhaustively. A cache
  // serve of that product to the finite round skipped the claim, and the
  // claim-denied second stack claimed and windowed instead: production
  // windowed the wrong stack, and the fresh shadow (first windowed) diverged
  // wherever the first stack's later rows are wider than its window.
  @Test("the outermost lazy stack keeps the viewport claim across measure rounds")
  func outermostLazyStackKeepsTheViewportClaim() throws {
    let snapshot = renderWithoutLayoutShadow(
      ClaimOrderProbe(), identity: testIdentity("ClaimOrderProbe"), rows: 8)
    var stacks: [MeasuredNode] = []
    var pending = [snapshot.measuredTree]
    while let node = pending.popLast() {
      if node.containerAllocationSnapshot?.lazyStack != nil { stacks.append(node) }
      pending.append(contentsOf: node.childMeasurements.reversed())
    }
    try #require(stacks.count == 2)
    #expect(
      stacks[0].containerAllocationSnapshot?.lazyStack?.measuredWindow != nil,
      "the first (outermost) lazy stack measured exhaustively")
    #expect(
      stacks[1].containerAllocationSnapshot?.lazyStack?.measuredWindow == nil,
      "the claim-denied second stack windowed")
  }

  @Test(
    "the layout shadow agrees with viewport-dependent lazy shapes (probe armed)",
    arguments: [
      "claim-order", "framed-outline", "horizontal", "wrapped", "vacuous-then-finite",
      "empty-first",
    ])
  func layoutShadowAgreesWithViewportDependentLazyShapes(shape: String) async {
    // Rows of varying width or height, both axes, wrapped and fixed-frame
    // stacks, and a zero-height viewport followed by a finite one under one
    // renderer (the retained session then holds the vacuous product). A
    // divergence traps the child, which fails this case alone.
    await #expect(processExitsWith: .success) { [shape] in
      await MainActor.run {
        SoundnessProbeConfiguration.isEnabled = true
        SoundnessProbeConfiguration.sampleEveryNFrames = 1
        let failures: [String]
        switch shape {
        case "claim-order":
          failures = LazyStackViewportCacheTests.armedDivergences(
            ClaimOrderProbe(), name: shape, sizes: [(40, 6), (40, 8), (40, 10)])
        case "framed-outline":
          failures = LazyStackViewportCacheTests.armedDivergences(
            FramedOutlineProbe(), name: shape, sizes: (4...9).map { (60, $0) })
        case "horizontal":
          failures = LazyStackViewportCacheTests.armedDivergences(
            HorizontalClaimProbe(), name: shape, sizes: [(24, 3), (24, 4)])
        case "wrapped":
          failures = LazyStackViewportCacheTests.armedDivergences(
            WrappedLazyProbe(), name: shape, sizes: [(40, 6), (40, 8)])
        case "empty-first":
          failures = LazyStackViewportCacheTests.armedDivergences(
            ClaimOrderProbe(firstCount: 0, fillerCount: 2, secondCount: 20), name: shape,
            sizes: [(40, 6), (40, 8)])
        default:
          failures = LazyStackViewportCacheTests.armedDivergences(
            ClaimOrderProbe(), name: shape, sizes: [(40, 1), (40, 8), (40, 1)])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
      }
    }
  }

  /// Renders `view` at each size in turn with one renderer (twice per size)
  /// and returns a line per layout-shadow divergence.
  private static func armedDivergences(
    _ view: some View, name: String, sizes: [(Int, Int)]
  ) -> [String] {
    let renderer = DefaultRenderer()
    let identity = testIdentity("ViewportDependentShadow", name)
    var failures: [String] = []
    for (width, height) in sizes {
      for _ in 0..<2 {
        let before = SoundnessProbeConfiguration.layoutShadowDivergenceCount
        _ = renderer.render(
          view,
          context: .init(identity: identity, invalidatedIdentities: [identity]),
          proposal: .init(width: .finite(width), height: .finite(height)))
        if SoundnessProbeConfiguration.layoutShadowDivergenceCount != before {
          failures.append(
            "\(name) \(width)x\(height): "
              + (SoundnessProbeConfiguration.lastViolationDetailByKind["layout-shadow-divergence"]
                ?? ""))
        }
      }
    }
    return failures
  }

  // MARK: - Anchor preservation inside longer scroll content (STUI-1270)

  // A windowed lazy stack followed by other content preserved its anchor on
  // a re-render at an unchanged offset and clamped the correction to its OWN
  // scroll range, so the scroll view snapped back (to 0 for a stack shorter
  // than the viewport). The same reset undid the focus-sync reveal of a
  // claim-denied row after a viewport shrink (STUI-1270).
  @Test(
    "a re-render keeps the offset of content scrolled past a windowed lazy stack",
    arguments: [(4, 3), (20, 16)])
  func reRenderKeepsAnOffsetPastAWindowedLazyStack(firstCount: Int, offset: Int) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("AnchorPastStack", "\(firstCount)"),
      size: .init(width: 40, height: 8)
    ) { ClaimOrderProbe(firstCount: firstCount, wideFrom: firstCount, fillerCount: 18) }
    defer { h.shutdown() }
    func currentOffset() -> Int? {
      h.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
        h.runLoop.latestSemanticSnapshot.scrollRoutes
      ).first?.contentOffset.y
    }
    _ = try h.scrollPointer(at: .init(x: 2.5, y: 3.5), deltaY: offset)
    try #require(currentOffset() == offset, "\(h.frame)")
    let scrolled = h.frame
    _ = try h.renderAfterExternalMutation()
    #expect(currentOffset() == offset)
    _ = try h.renderAfterExternalMutation()
    #expect(currentOffset() == offset)
    #expect(h.frame == scrolled, "\(h.frame)")
  }

  // Neighbours of STUI-1270: viewport growth after the reveal, and a shrink
  // that leaves the claim-denied stack partly visible, keep the row shown
  // and focused (Scrolling.md, "A viewport change ... can also reveal a
  // previously visible focused control").
  @Test("a focused claim-denied row stays revealed and focused across resizes")
  func focusedClaimDeniedRowSurvivesResizes() throws {
    let log = W3FAStackLog()
    let h = try W3FAResizeHarness(name: "ClaimDeniedResize", size: .init(width: 40, height: 16)) {
      W3FATwoStacks(firstCount: 4, log: log)
    }
    defer { h.shutdown() }
    try h.focusText("second 2")
    let focus = try #require(h.loop.focusTracker.currentFocusIdentity)
    for height in [12, 6, 16, 5, 9] {
      try h.resize(width: 40, height: height)
      #expect(h.frame.contains("second 2"), "40x\(height): \(h.frame)")
      #expect(h.loop.focusTracker.currentFocusIdentity == focus, "40x\(height)")
    }
  }

  // Cost neighbour: the repaired cache rule must not make a scroll-hosted
  // lazy stack realize or measure more per steady frame.
  @Test("scroll-hosted lazy stacks keep their per-frame layout work", arguments: [40, 1000])
  func scrollHostedLazyStacksKeepTheirPerFrameWork(count: Int) {
    let saved = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = saved }
    let renderer = DefaultRenderer()
    let identity = testIdentity("ScrollHostedLazyWork", "\(count)")
    for (frame, offset) in [0, 0, 5, 9].enumerated() {
      IndexedChildRealizationProbe.reset()
      let result = renderer.render(
        PositionedLazyWorkProbe(count: count, offset: offset),
        context: .init(identity: identity, invalidatedIdentities: frame == 0 ? [] : [identity]),
        proposal: .init(width: .finite(40), height: .finite(8)))
      let realized = IndexedChildRealizationProbe.realizedChildCount
      if frame == 0 {
        #expect(realized <= min(count, 40), "frame 0 realized \(realized)")
      } else {
        #expect(realized <= 12, "frame \(frame) realized \(realized)")
        #expect(
          result.diagnostics.work.measuredNodesComputed <= 31,
          "frame \(frame) computed \(result.diagnostics.work.measuredNodesComputed)")
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

/// Header, then a scroll view holding a windowed lazy stack (rows from
/// `wideFrom` on are wider), fillers and an optional claim-denied second
/// lazy stack.
private struct ClaimOrderProbe: View {
  var firstCount = 20
  var wideFrom = 10
  var fillerCount = 6
  var secondCount = 5

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<firstCount, id: \.self) { index in
              Text(index < wideFrom ? "first \(index)" : "first \(index) wide")
            }
          }
          ForEach(0..<fillerCount, id: \.self) { index in
            Text("filler \(index)")
          }
          if secondCount > 0 {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<secondCount, id: \.self) { index in
                Text("second \(index)")
              }
            }
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

/// The gallery's Navigation & Collections shape, reduced: a fixed-frame
/// outline whose last row is its widest, in a scroll view below a header.
private struct FramedOutlineProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView {
        VStack(alignment: .leading, spacing: 1) {
          Text("Navigation")
          HStack(alignment: .top, spacing: 2) {
            Text("Side")
            OutlineGroup(OffscreenOutlineNode.wideLast, children: \.children) { node in
              Text(node.title)
            }
            .frame(width: 34, height: 8, alignment: .topLeading)
          }
        }
      }
    }
  }
}

/// A horizontal scroll view after a leading label: its first measure round
/// has a zero-width viewport. The first LazyHStack's later cells are taller
/// (its cross axis), at one width so the main-axis estimate is exact.
private struct HorizontalClaimProbe: View {
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Text("H")
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 1) {
          LazyHStack(alignment: .top, spacing: 1) {
            ForEach(0..<20, id: \.self) { index in
              VStack(alignment: .leading, spacing: 0) {
                Text("a\(index % 10)")
                if index >= 10 { Text("+") }
              }
            }
          }
          ForEach(0..<4, id: \.self) { index in
            Text("f\(index)")
          }
          LazyHStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
              Text("b\(index)")
            }
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

/// A windowed lazy stack of varying-width rows inside padding and a fixed
/// frame, followed by fillers.
private struct WrappedLazyProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { index in
              Text(index < 10 ? "row \(index)" : "row \(index) is wider")
            }
          }
          .padding(.horizontal, 1)
          .frame(width: 30, alignment: .leading)
          ForEach(0..<6, id: \.self) { index in
            Text("filler \(index)")
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

private struct PositionedLazyWorkProbe: View {
  let count: Int
  let offset: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Header")
      ScrollView(position: .constant(ScrollCellOffset(y: offset))) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<count, id: \.self) { index in
            Text("row \(index)")
          }
        }
      }
    }
  }
}

extension OffscreenOutlineNode {
  fileprivate static let wideLast: [OffscreenOutlineNode] = [
    .init(
      id: "Examples",
      children: [.init(id: "Terminal"), .init(id: "SwiftUI host"), .init(id: "Web/WASI")]),
    .init(
      id: "Coverage",
      children: [.init(id: "Build lanes"), .init(id: "Focused tests and more")]),
  ]
}
