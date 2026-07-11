import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI safe-area and geometry stress behavior", .serialized)
struct FrameworkStressSafeAreaGeometryTests {}

@MainActor
private func safeAreaGeometryFrames<Content: View>(
  _ view: Content,
  renderer: DefaultRenderer,
  identity: Identity,
  generation: Int,
  size: CellSize = .init(width: 44, height: 14),
  safeAreaInsets: EdgeInsets = .zero,
  cellPixelMetrics: CellPixelMetrics = .estimated,
  pointerInputCapabilities: PointerInputCapabilities = .cellOnly
) -> (retained: RenderSnapshot, fresh: RenderSnapshot) {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = size
  environmentValues.safeAreaInsets = safeAreaInsets
  environmentValues.cellPixelMetrics = cellPixelMetrics
  environmentValues.pointerInputCapabilities = pointerInputCapabilities
  let proposal = ProposedSize(width: size.width, height: size.height)

  let retained = renderer.render(
    view,
    context: .init(
      identity: identity,
      environmentValues: environmentValues,
      invalidatedIdentities: generation == 0 ? [] : [identity]
    ),
    proposal: proposal
  )
  let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
    view,
    context: .init(identity: identity, environmentValues: environmentValues),
    proposal: proposal
  )
  return (retained, fresh)
}

private func safeAreaGeometryText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private func safeAreaGeometryMeasurementsMatch(
  _ lhs: MeasuredNode,
  _ rhs: MeasuredNode
) -> Bool {
  lhs.identity == rhs.identity
    && lhs.proposal == rhs.proposal
    && lhs.measuredSize == rhs.measuredSize
    && lhs.containerAllocationSnapshot == rhs.containerAllocationSnapshot
    && lhs.subtreeNodeCount == rhs.subtreeNodeCount
    && lhs.childMeasurements.count == rhs.childMeasurements.count
    && zip(lhs.childMeasurements, rhs.childMeasurements).allSatisfy {
      safeAreaGeometryMeasurementsMatch($0, $1)
    }
}

// MARK: - Attempt 001: root safe-area environment round trip

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 001 root inset round trip matches fresh placement")
  func safeAreaGeometry001RootInsetRoundTripMatchesFreshPlacement() {
    // Hypothesis: retained safe-area padding can preserve the first environment-derived insets
    // after the host moves through a different inset configuration and returns.
    struct Root: View {
      let generation: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "001 g\(generation) \(proxy.size.width)x\(proxy.size.height) "
              + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading),"
              + "\(proxy.safeAreaInsets.bottom),\(proxy.safeAreaInsets.trailing)"
          )
        }
        .safeAreaPadding()
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry001")
    let insets = [
      EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 3),
      EdgeInsets(top: 3, leading: 0, bottom: 2, trailing: 1),
      EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 3),
    ]

    for generation in 0..<15 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: insets[generation % insets.count]
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("001 g\(generation)"))
    }
  }
}

// MARK: - Attempt 020: GeometryReader pointer-capability churn

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 020 geometry adopts every pointer capability")
  func safeAreaGeometry020GeometryAdoptsEveryPointerCapability() {
    // Hypothesis: pointer capability metadata can remain captured by the first GeometryReader
    // realization even as a host switches precision, hover, and precise-scroll support.
    struct Root: View {
      let generation: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "020 g\(generation) sub\(proxy.pointerInputCapabilities.supportsSubCellLocation) "
              + "hover\(proxy.pointerInputCapabilities.supportsHover) "
              + "scroll\(proxy.pointerInputCapabilities.supportsPreciseScroll)"
          )
        }
      }
    }

    let reported = CellPixelMetrics(width: 10, height: 20, source: .reported)
    let capabilities = [
      PointerInputCapabilities.cellOnly,
      PointerInputCapabilities(
        precision: .subCell(source: .nativePixels, metrics: reported),
        supportsHover: true,
        supportsPreciseScroll: false
      ),
      PointerInputCapabilities(
        precision: .subCell(source: .webPixels, metrics: reported),
        supportsHover: false,
        supportsPreciseScroll: true
      ),
      PointerInputCapabilities(
        precision: .cell,
        supportsHover: true,
        supportsPreciseScroll: true
      ),
    ]
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry020")

    for generation in 0..<20 {
      let capability = capabilities[generation % capabilities.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        pointerInputCapabilities: capability
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(
        text.contains(
          "020 g\(generation) sub\(capability.supportsSubCellLocation) "
            + "hover\(capability.supportsHover) scroll\(capability.supportsPreciseScroll)"
        )
      )
    }
  }
}

// MARK: - Attempt 019: GeometryReader cell-pixel metric churn

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 019 geometry adopts every cell metric")
  func safeAreaGeometry019GeometryAdoptsEveryCellMetric() {
    // Hypothesis: a layout-realized GeometryReader can retain the first host cell-pixel metadata
    // when its cell bounds and authored content topology remain unchanged.
    struct Root: View {
      let generation: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "019 g\(generation) px\(proxy.cellPixelMetrics.width)x"
              + "\(proxy.cellPixelMetrics.height) source \(proxy.cellPixelMetrics.source)"
          )
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry019")
    let metrics = [
      CellPixelMetrics.estimated,
      CellPixelMetrics(width: 10, height: 20, source: .reported),
      CellPixelMetrics(width: 12, height: 18, source: .reported),
      CellPixelMetrics(width: 8, height: 16, source: .reported),
    ]

    for generation in 0..<20 {
      let metric = metrics[generation % metrics.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        cellPixelMetrics: metric
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(text.contains("019 g\(generation) px\(metric.width)x\(metric.height)"))
    }
  }
}

// MARK: - Attempt 018: GeometryReader host proposal oscillation

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 018 geometry follows host proposal oscillation")
  func safeAreaGeometry018GeometryFollowsHostProposalOscillation() {
    // Hypothesis: revisiting a prior host size after an intervening proposal can reuse a stale
    // layout-realized child whose closure and placed bounds came from the wrong generation.
    struct Root: View {
      let generation: Int

      var body: some View {
        GeometryReader { proxy in
          Text("018 g\(generation) size \(proxy.size.width)x\(proxy.size.height)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry018")
    let sizes = [
      CellSize(width: 44, height: 14),
      CellSize(width: 30, height: 9),
      CellSize(width: 58, height: 18),
      CellSize(width: 44, height: 14),
    ]

    for generation in 0..<20 {
      let size = sizes[generation % sizes.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: size,
        safeAreaInsets: .init(top: 1, leading: 2, bottom: 1, trailing: 2)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(
        safeAreaGeometryText(frames.retained)
          .contains("018 g\(generation) size \(size.width - 4)x\(size.height - 2)")
      )
    }
  }
}

// MARK: - Attempt 017: GeometryReader closure freshness at unchanged bounds

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 017 geometry closure uses current capture")
  func safeAreaGeometry017GeometryClosureUsesCurrentCapture() {
    // Hypothesis: an unchanged LayoutDependentContent signature can reuse the first GeometryReader
    // realizer and its captured closure even though the owning view is reevaluated every frame.
    struct Root: View {
      let generation: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "017 capture \(generation) size \(proxy.size.width)x\(proxy.size.height)"
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 40, height: 8, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry017")

    for generation in 0..<24 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 12)
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(text.contains("017 capture \(generation) size 40x8"))
      if generation > 0 {
        #expect(!text.contains("017 capture \(generation - 1)"))
      }
    }
  }
}

// MARK: - Attempt 016: inset GeometryReader environment freshness

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 016 inset geometry sees current host safe area")
  func safeAreaGeometry016InsetGeometrySeesCurrentHostSafeArea() {
    // Hypothesis: the layout-realized boundary captured by a safe-area inset can refresh bounds
    // while continuing to expose the host safe-area insets from its first generation.
    struct Root: View {
      let generation: Int

      var body: some View {
        Text("016 base g\(generation)")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .safeAreaInset(edge: .top, alignment: .topLeading) {
            GeometryReader { proxy in
              Text(
                "016 inset g\(generation) "
                  + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading),"
                  + "\(proxy.safeAreaInsets.bottom),\(proxy.safeAreaInsets.trailing)"
              )
            }
            .frame(height: 2)
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry016")
    let insets = [
      EdgeInsets(top: 1, leading: 3, bottom: 2, trailing: 0),
      EdgeInsets(top: 3, leading: 0, bottom: 0, trailing: 3),
      EdgeInsets(top: 0, leading: 2, bottom: 3, trailing: 1),
    ]

    for generation in 0..<18 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 52, height: 16),
        safeAreaInsets: insets[generation % insets.count]
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("016 inset g\(generation)"))
    }
  }
}

// MARK: - Attempt 015: stored inset payload freshness

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 015 stable inset publishes current capture")
  func safeAreaGeometry015StableInsetPublishesCurrentCapture() {
    // Hypothesis: CapturedSubviewScope can keep the first safeAreaInset builder payload when every
    // generation measures to the same size and the modifier's structural identity is unchanged.
    struct Root: View {
      let generation: Int

      var body: some View {
        Text("015 base")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .safeAreaInset(edge: .bottom, alignment: .bottomLeading) {
            Text("015 payload generation \(generation)")
              .frame(width: 32, height: 1, alignment: .leading)
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry015")

    for generation in 0..<20 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 12),
        safeAreaInsets: .init(bottom: 1)
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(text.contains("015 payload generation \(generation)"))
      if generation > 0 {
        #expect(!text.contains("015 payload generation \(generation - 1)"))
      }
    }
  }
}

// MARK: - Attempt 014: nested inset authored-order replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 014 nested inset order stays semantic")
  func safeAreaGeometry014NestedInsetOrderStaysSemantic() {
    // Hypothesis: two inset modifiers on different axes can be canonicalized by edge, causing a
    // retained tree to ignore authored-order changes that alter each adornment's proposal.
    struct Root: View {
      let generation: Int

      var body: some View {
        let base = GeometryReader { proxy in
          Text("014 base g\(generation) \(proxy.size.width)x\(proxy.size.height)")
        }

        if generation.isMultiple(of: 2) {
          AnyView(
            base
              .safeAreaInset(edge: .top, alignment: .topLeading) {
                Text("014 top g\(generation)")
              }
              .safeAreaInset(edge: .leading, alignment: .topLeading) {
                Text("014 lead g\(generation)").frame(width: 7)
              }
          )
        } else {
          AnyView(
            base
              .safeAreaInset(edge: .leading, alignment: .topLeading) {
                Text("014 lead g\(generation)").frame(width: 7)
              }
              .safeAreaInset(edge: .top, alignment: .topLeading) {
                Text("014 top g\(generation)")
              }
          )
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry014")

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 50, height: 16),
        safeAreaInsets: .init(top: 1, leading: 2)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        safeAreaGeometryMeasurementsMatch(frames.retained.measuredTree, frames.fresh.measuredTree)
      )
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("014 base g\(generation)"))
    }
  }
}

// MARK: - Attempt 013: nested inset removal and reinsertion

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 013 removed nested inset restores surviving base")
  func safeAreaGeometry013RemovedNestedInsetRestoresSurvivingBase() {
    // Hypothesis: tearing down one of two nested safe-area inset modifiers can strand its consumed
    // width in the surviving inset's base measurement or leave its old adornment painted.
    struct Root: View {
      let generation: Int

      var body: some View {
        let base = GeometryReader { proxy in
          Text("013 base g\(generation) \(proxy.size.width)x\(proxy.size.height)")
        }
        .safeAreaInset(edge: .top, alignment: .topLeading) {
          Text("013 top g\(generation)")
        }

        if generation.isMultiple(of: 2) {
          AnyView(
            base.safeAreaInset(edge: .leading, alignment: .topLeading) {
              Text("013 leading g\(generation)")
                .frame(width: 8)
            }
          )
        } else {
          AnyView(base)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry013")

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 50, height: 16),
        safeAreaInsets: .init(top: 1, leading: 2)
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        safeAreaGeometryMeasurementsMatch(frames.retained.measuredTree, frames.fresh.measuredTree)
      )
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(text.contains("013 top g\(generation)"))
    }
  }
}

// MARK: - Attempt 012: inset adornment cardinality churn

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 012 inset row cardinality leaves no phantom strip")
  func safeAreaGeometry012InsetRowCardinalityLeavesNoPhantomStrip() {
    // Hypothesis: a zero-to-many inset child transition can retain the prior adornment height or
    // departed rows in the safe-area placement request after the indexed source changes shape.
    struct Root: View {
      let generation: Int
      let rowCount: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "012 base g\(generation) c\(rowCount) "
              + "\(proxy.size.width)x\(proxy.size.height)"
          )
        }
        .safeAreaInset(edge: .top, alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
              Text("012 inset g\(generation) r\(row)")
            }
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry012")
    let counts = [0, 3, 1, 5, 0, 2]

    for generation in 0..<18 {
      let rowCount = counts[generation % counts.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, rowCount: rowCount),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 18),
        safeAreaInsets: .init(top: 1)
      )

      let text = safeAreaGeometryText(frames.retained)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        safeAreaGeometryMeasurementsMatch(frames.retained.measuredTree, frames.fresh.measuredTree)
      )
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(text.contains("012 base g\(generation) c\(rowCount)"))
      #expect(text.contains("012 inset g\(generation)") == (rowCount > 0))
    }
  }
}

// MARK: - Attempt 011: inset adornment size churn

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 011 inset height churn remeasures surviving base")
  func safeAreaGeometry011InsetHeightChurnRemeasuresSurvivingBase() {
    // Hypothesis: retained safe-area inset measurement can refresh the adornment frame while
    // leaving the surviving GeometryReader at the base proposal from an earlier height.
    struct Root: View {
      let generation: Int
      let insetHeight: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "011 base g\(generation) h\(insetHeight) "
              + "\(proxy.size.width)x\(proxy.size.height)"
          )
        }
        .safeAreaInset(edge: .bottom, alignment: .bottomLeading) {
          Text("011 inset g\(generation)")
            .frame(height: insetHeight, alignment: .bottomLeading)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry011")
    let heights = [1, 4, 2, 6, 1, 3]

    for generation in 0..<18 {
      let height = heights[generation % heights.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, insetHeight: height),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 18),
        safeAreaInsets: .init(bottom: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("011 base g\(generation) h\(height)"))
    }
  }
}

// MARK: - Attempt 010: safe-area inset spacing replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 010 inset spacing recomputes base proposal")
  func safeAreaGeometry010InsetSpacingRecomputesBaseProposal() {
    // Hypothesis: changing only inset spacing can reuse the old consumed amount, especially when
    // negative input clamps to zero and later returns to a positive value.
    struct Root: View {
      let generation: Int
      let spacing: Int

      var body: some View {
        GeometryReader { proxy in
          Text("010 base g\(generation) p\(spacing) \(proxy.size.width)x\(proxy.size.height)")
        }
        .safeAreaInset(edge: .top, alignment: .topLeading, spacing: spacing) {
          Text("010 inset g\(generation)")
            .frame(height: 2)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry010")
    let spacings = [-4, 0, 3, 1, 6, -1]

    for generation in 0..<18 {
      let spacing = spacings[generation % spacings.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, spacing: spacing),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 16),
        safeAreaInsets: .init(top: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("010 base g\(generation)"))
    }
  }
}

// MARK: - Attempt 009: safe-area inset alignment replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 009 inset alignment follows every replacement")
  func safeAreaGeometry009InsetAlignmentFollowsEveryReplacement() {
    // Hypothesis: inset placement can retain a prior alignment guide when edge, content size, and
    // consumed amount remain constant across generations.
    struct Root: View {
      let generation: Int
      let alignment: Alignment

      var body: some View {
        Text("009 base g\(generation)")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .safeAreaInset(edge: .top, alignment: alignment) {
            Text("009 inset g\(generation)")
              .frame(width: 20, height: 1, alignment: .center)
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry009")
    let alignments: [Alignment] = [.topLeading, .top, .topTrailing, .top]

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, alignment: alignments[generation % alignments.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 52, height: 12),
        safeAreaInsets: .init(top: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("009 inset g\(generation)"))
    }
  }
}

// MARK: - Attempt 008: safe-area inset edge replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 008 inset migrates across every edge")
  func safeAreaGeometry008InsetMigratesAcrossEveryEdge() {
    // Hypothesis: retained safe-area inset placement can update the stored edge while reusing the
    // previous base proposal or leaving the adornment painted at its departed edge.
    struct Root: View {
      let generation: Int
      let edge: Edge

      var body: some View {
        GeometryReader { proxy in
          Text("008 base g\(generation) \(proxy.size.width)x\(proxy.size.height)")
        }
        .safeAreaInset(edge: edge, alignment: .topLeading) {
          Text("008 inset g\(generation)")
            .frame(width: 18, height: 2, alignment: .topLeading)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry008")
    let edges: [Edge] = [.top, .trailing, .bottom, .leading]

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, edge: edges[generation % edges.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        size: .init(width: 48, height: 16),
        safeAreaInsets: .init(top: 1, leading: 2, bottom: 1, trailing: 2)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("008 inset g\(generation)"))
    }
  }
}

// MARK: - Attempt 007: nested ignore removal and reinsertion

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 007 removed inner ignore cannot leak reclamation")
  func safeAreaGeometry007RemovedInnerIgnoreCannotLeakReclamation() {
    // Hypothesis: an inner IgnoreSafeArea node can leave reclaimed leading space attached to a
    // surviving outer ignore after the conditional owner is removed and later recreated.
    struct Root: View {
      let generation: Int

      var body: some View {
        Group {
          if generation.isMultiple(of: 3) {
            GeometryReader { proxy in
              Text(
                "007 g\(generation) inner \(proxy.size.width)x\(proxy.size.height) "
                  + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
              )
            }
            .ignoresSafeArea(.leading)
          } else {
            GeometryReader { proxy in
              Text(
                "007 g\(generation) outer \(proxy.size.width)x\(proxy.size.height) "
                  + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
              )
            }
          }
        }
        .ignoresSafeArea(.top)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry007")

    for generation in 0..<18 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: .init(top: 2, leading: 4, bottom: 1, trailing: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("007 g\(generation)"))
    }
  }
}

// MARK: - Attempt 006: padding and ignore authored-order replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 006 padding and ignore preserve authored order")
  func safeAreaGeometry006PaddingAndIgnorePreserveAuthoredOrder() {
    // Hypothesis: modifier-chain equivalence can treat safe-area padding and reclamation as
    // commutative, retaining the prior measurement when their authored order reverses.
    struct Root: View {
      let generation: Int

      var body: some View {
        let content = GeometryReader { proxy in
          Text(
            "006 g\(generation) \(proxy.size.width)x\(proxy.size.height) "
              + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
          )
        }

        if generation.isMultiple(of: 2) {
          AnyView(
            content
              .safeAreaPadding([.top, .leading], 1)
              .ignoresSafeArea(.top)
          )
        } else {
          AnyView(
            content
              .ignoresSafeArea(.top)
              .safeAreaPadding([.top, .leading], 1)
          )
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry006")

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: .init(top: 2, leading: 3, bottom: 1, trailing: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("006 g\(generation)"))
    }
  }
}

// MARK: - Attempt 005: ignored safe-area edge replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 005 ignored edges reclaim only current sides")
  func safeAreaGeometry005IgnoredEdgesReclaimOnlyCurrentSides() {
    // Hypothesis: replacing an ignore mask can retain reclaimed space from a departed edge while
    // updating the GeometryProxy environment to report the new mask.
    struct Root: View {
      let generation: Int
      let edges: Edge.Set

      var body: some View {
        GeometryReader { proxy in
          Text(
            "005 g\(generation) \(proxy.size.width)x\(proxy.size.height) "
              + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading),"
              + "\(proxy.safeAreaInsets.bottom),\(proxy.safeAreaInsets.trailing)"
          )
        }
        .ignoresSafeArea(edges)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry005")
    let masks: [Edge.Set] = [.top, .leading, .bottom, .trailing, [.top, .trailing], .all]

    for generation in 0..<18 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, edges: masks[generation % masks.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: .init(top: 1, leading: 2, bottom: 3, trailing: 4)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("005 g\(generation)"))
    }
  }
}

// MARK: - Attempt 004: nested safe-area padding removal

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 004 nested padding removal restores outer contract")
  func safeAreaGeometry004NestedPaddingRemovalRestoresOuterContract() {
    // Hypothesis: removing an inner safe-area environment transform can leave its insets folded
    // into the surviving outer padding node after repeated branch reconstruction.
    struct Root: View {
      let generation: Int

      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            GeometryReader { proxy in
              Text(
                "004 g\(generation) inner \(proxy.size.width)x\(proxy.size.height) "
                  + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
              )
            }
            .safeAreaPadding(.leading, 2)
          } else {
            GeometryReader { proxy in
              Text(
                "004 g\(generation) outer \(proxy.size.width)x\(proxy.size.height) "
                  + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading)"
              )
            }
          }
        }
        .safeAreaPadding(.top, 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry004")

    for generation in 0..<16 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: .init(top: 2, leading: 3, bottom: 1, trailing: 1)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("004 g\(generation)"))
    }
  }
}

// MARK: - Attempt 003: safe-area padding amount replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 003 padding amount follows every replacement")
  func safeAreaGeometry003PaddingAmountFollowsEveryReplacement() {
    // Hypothesis: the environment-derived portion of safe-area padding can update while the
    // explicit additional amount remains cached from an earlier generation.
    struct Root: View {
      let generation: Int
      let amount: Int

      var body: some View {
        GeometryReader { proxy in
          Text(
            "003 g\(generation) a\(amount) \(proxy.size.width)x\(proxy.size.height) "
              + "s\(proxy.safeAreaInsets.leading),\(proxy.safeAreaInsets.trailing)"
          )
        }
        .safeAreaPadding([.leading, .trailing], amount)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry003")
    let amounts = [0, 4, 1, -3, 7, 0]

    for generation in 0..<18 {
      let amount = amounts[generation % amounts.count]
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, amount: amount),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: .init(top: 1, leading: 2, bottom: 1, trailing: 3)
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("003 g\(generation) a\(amount)"))
    }
  }
}

// MARK: - Attempt 002: safe-area padding edge replacement

extension FrameworkStressSafeAreaGeometryTests {
  @Test("stress safe area geometry 002 padding drops every departed edge")
  func safeAreaGeometry002PaddingDropsEveryDepartedEdge() {
    // Hypothesis: an equal-total edge-mask replacement can reuse the prior padding node because
    // retained measurement observes only the aggregate horizontal and vertical insets.
    struct Root: View {
      let generation: Int
      let edges: Edge.Set

      var body: some View {
        GeometryReader { proxy in
          Text(
            "002 g\(generation) \(proxy.size.width)x\(proxy.size.height) "
              + "s\(proxy.safeAreaInsets.top),\(proxy.safeAreaInsets.leading),"
              + "\(proxy.safeAreaInsets.bottom),\(proxy.safeAreaInsets.trailing)"
          )
        }
        .safeAreaPadding(edges)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("SafeAreaGeometry002")
    let masks: [Edge.Set] = [.top, .leading, .bottom, .trailing, [.top, .bottom], .all]
    let insets = EdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 3)

    for generation in 0..<18 {
      let frames = safeAreaGeometryFrames(
        Root(generation: generation, edges: masks[generation % masks.count]),
        renderer: renderer,
        identity: identity,
        generation: generation,
        safeAreaInsets: insets
      )

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
      #expect(safeAreaGeometryText(frames.retained).contains("002 g\(generation)"))
    }
  }
}
