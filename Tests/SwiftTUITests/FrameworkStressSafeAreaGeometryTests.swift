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
