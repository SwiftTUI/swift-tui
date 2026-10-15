import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Scroll-latency R4-C (app-tier finding 1, report 2026-08-01-001 §4b and
/// appendix): an enclosing stack's IDEAL round proposes an unspecified main
/// dimension, the scroll layout maps that to "no measure viewport", and the
/// indexed lazy stack fell to the exhaustive arm — realizing every element.
/// The bisection's v5 shape (chrome `VStack { header; Divider; … }`) realized
/// 300/300 where v7 (fixed-height pane) windowed <= 60.
///
/// The fix serves the hintless ideal round as an estimate (retained
/// allocation snapshot, else an element-0 stride probe above the count
/// threshold), so the chrome shape windows like the fixed-height one and the
/// app-side fixed-height dodge is no longer necessary.
@MainActor
@Suite(.serialized)
struct LazyStackIdealPassWindowingTests {
  @Test(
    "estimate-derived wrappers cannot populate the exact measurement cache",
    arguments: [false, true])
  func wrapperProbeDoesNotPoisonCommit(custom: Bool) {
    @ViewBuilder func content() -> some View {
      LazyVStack(spacing: 0) {
        ForEach(0..<100, id: \.self) { row in
          Text(row.isMultiple(of: 2) ? "short" : "tall\nsecond")
        }
      }
    }
    @ViewBuilder func wrapped() -> some View {
      if custom { EstimatePassThroughLayout { content() } } else { content().padding(1) }
    }
    var node = resolveView(
      wrapped(), in: .init(identity: testIdentity("EstimateWrapper", "\(custom)")))
    node.viewNodeID = .init(rawValue: 999)
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let proposal = ProposedSize(width: 20, height: nil)
    _ = engine.measure(node, proposal: proposal, passContext: .init(), grade: .probe)
    let wasCached = cache.lookup(resolved: node, proposal: proposal) != nil
    #expect(
      !wasCached, "a wrapper inherits approximation even when its own size computation is exact")
    let committed = engine.measure(node, proposal: proposal)
    let fresh = LayoutEngine().measure(node, proposal: proposal)
    #expect(committed.measuredSize == fresh.measuredSize)
    #expect(committed.subtreeNodeCount == fresh.subtreeNodeCount)
    if !custom { #expect(committed.measuredSize.height == 152) }
  }

  private static let blockCount = 300

  /// The appendix document: `LazyVStack(spacing: 1) { ForEach(0..<300) }`
  /// with padding, hosted by the v1–v4 wrappers (indicators + max frame +
  /// reader + HStack).
  private struct DocumentPane: View {
    var paneHeight: Int?

    var body: some View {
      VStack(spacing: 0) {
        Text("header")
        Divider()
        HStack(alignment: .top, spacing: 2) {
          Spacer(minLength: 0)
          ScrollViewReader { _ in
            ScrollView(.vertical, position: .constant(.zero)) {
              LazyVStack(spacing: 1) {
                ForEach(0..<LazyStackIdealPassWindowingTests.blockCount, id: \.self) { index in
                  Text("block \(index)")
                }
              }
              .padding(.init(horizontal: 1, vertical: 1))
            }
            .frame(
              maxWidth: .finite(118),
              maxHeight: paneHeight == nil ? .infinity : nil,
              alignment: .topLeading
            )
            .frame(height: paneHeight)
          }
        }
      }
    }
  }

  @Test("v5: the chrome-stack ideal round no longer realizes the whole document")
  func chromeStackIdealRoundWindows() {
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      DocumentPane(paneHeight: nil),
      context: .init(identity: testIdentity("ChromeIdealV5"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(120), height: .finite(40))
    )
    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 60,
      """
      realized \(IndexedChildRealizationProbe.realizedChildCount) of 300 blocks — the \
      ideal round fell back to exhaustive realization
      """
    )
  }

  @Test("v7: the fixed-height pane keeps windowing")
  func fixedHeightPaneStillWindows() {
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      DocumentPane(paneHeight: 37),
      context: .init(identity: testIdentity("ChromeIdealV7"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(120), height: .finite(40))
    )
    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 60,
      "realized \(IndexedChildRealizationProbe.realizedChildCount) of 300 blocks"
    )
  }

  @Test("the chrome shape renders the document's visible head")
  func chromeShapeStillRendersContent() {
    let snapshot = DefaultRenderer().render(
      DocumentPane(paneHeight: nil),
      context: .init(identity: testIdentity("ChromeIdealOutput"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(120), height: .finite(40))
    )
    let surface = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("header"))
    #expect(surface.contains("block 0"), "the document's first block is visible:\n\(surface)")
    #expect(surface.contains("block 10"), "the pane fills its allocated height:\n\(surface)")
    #expect(
      !surface.contains("block 299"),
      "the tail must not be drawn into the 40-row viewport:\n\(surface)"
    )
  }

  @Test("steady-state notches over the chrome shape stay windowed")
  func steadyStateNotchesStayWindowed() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ChromeIdealSteady"),
      size: .init(width: 60, height: 20)
    ) {
      DocumentPane(paneHeight: nil)
    }
    defer { harness.shutdown() }

    let anchor = try #require(harness.point(forText: "block 1"))
    _ = try harness.scrollPointer(at: anchor, deltaY: 1)
    IndexedChildRealizationProbe.reset()
    for _ in 0..<3 {
      _ = try harness.scrollPointer(at: anchor, deltaY: 1)
    }
    #expect(
      harness.frame.contains("block 4"),
      "the wheel really scrolled the chrome-hosted document:\n\(harness.frame)"
    )
    #if DEBUG
      #expect(
        IndexedChildRealizationProbe.realizedChildCount <= 90,
        """
        3 notches realized \(IndexedChildRealizationProbe.realizedChildCount) blocks — \
        the per-notch ideal round is re-realizing the document
        """
      )
    #endif
  }

  /// Below the cold-arm threshold the exhaustive ideal round stays: a small
  /// collection granted its unbounded ideal (`.fixedSize()`) keeps exact
  /// sizing even for heterogeneous rows.
  @Test("small collections granted their ideal keep exact exhaustive sizing")
  func smallGrantedIdealStaysExact() {
    IndexedChildRealizationProbe.reset()
    let snapshot = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
              // Heterogeneous: row heights 1, 2, 1, 2, ...
              if index % 2 == 0 {
                Text("row \(index)")
              } else {
                Text("row \(index)\ntail \(index)")
              }
            }
          }
        }
        .fixedSize()
        Text("below")
      },
      context: .init(identity: testIdentity("SmallGrantedIdeal"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(30), height: .finite(20))
    )
    let surface = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("row 0"))
    #expect(surface.contains("row 5"), "all 6 rows fit the granted ideal:\n\(surface)")
    #expect(
      surface.contains("below"), "the sibling renders after the exact-sized pane:\n\(surface)")
    #expect(IndexedChildRealizationProbe.realizedChildCount >= 6)
  }

  /// Above the threshold with uniform rows the cold estimate equals the
  /// exact ideal, so granted-ideal output is unchanged. Uniformity includes
  /// the cross axis: the cold estimate derives cross from the element-0
  /// probe, so a granted-both-axes (`.fixedSize()`) large lazy stack with
  /// *non*-uniform widths would clamp to the probe's width — accepted
  /// estimate semantics for a shape that defeats laziness by construction.
  @Test("uniform large collections granted their ideal size exactly via the estimate")
  func uniformLargeGrantedIdealSizesExactly() {
    let snapshot = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(100..<200, id: \.self) { index in
              Text("row \(index)")
            }
          }
        }
        .fixedSize()
        Text("below")
      },
      context: .init(identity: testIdentity("UniformGrantedIdeal"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(30), height: .finite(120))
    )
    let surface = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("row 100"))
    #expect(surface.contains("row 199"), "the estimate matches the exact content:\n\(surface)")
    #expect(surface.contains("below"))
  }
}

private struct EstimatePassThroughLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void)
    -> LayoutSize
  {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void
  ) {
    subviews.first?.place(at: bounds.origin, proposal: proposal)
  }
}
