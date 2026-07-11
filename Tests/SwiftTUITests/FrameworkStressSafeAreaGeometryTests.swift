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
