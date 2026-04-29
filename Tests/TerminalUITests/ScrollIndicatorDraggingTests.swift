import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite("Scroll indicator dragging")
struct ScrollIndicatorDraggingTests {
  @Test("ScrollView indicator drag uses fractional pointer locations")
  func scrollViewIndicatorDragUsesFractionalPointerLocations() throws {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let pointerRegistry = LocalPointerHandlerRegistry()
    let rootIdentity = testIdentity("ScrollIndicatorDragRoot")
    let scrollIdentity = testIdentity("PreciseScroll")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = .init(width: 16, height: 10)

    var context = ResolveContext(
      identity: rootIdentity,
      environmentValues: environmentValues,
      applyEnvironmentValues: true
    )
    context.localPointerHandlerRegistry = pointerRegistry

    let artifacts = DefaultRenderer().render(
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.position },
          set: { box.position = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<24) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(scrollIdentity)
      .frame(width: 10, height: 8, alignment: .topLeading),
      context: context,
      proposal: .init(width: 16, height: 10)
    )

    let indicatorRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first { region in
        region.identity == verticalScrollIndicatorIdentity(for: scrollIdentity)
      }
    )
    let scrollRoute = try #require(
      artifacts.semanticSnapshot.scrollRoutes.first { route in
        route.identity == scrollIdentity
      }
    )

    #expect(
      pointerRegistry.dispatch(
        routeID: indicatorRegion.routeID,
        event: .init(
          kind: .dragged(.primary),
          location: .subCell(
            location: .init(
              x: Double(indicatorRegion.rect.origin.x) + 0.5,
              y: Double(indicatorRegion.rect.origin.y) + 3.5
            ),
            source: .nativePixels,
            metrics: .init(width: 10, height: 20, source: .reported)
          ),
          targetRect: indicatorRegion.rect,
          scrollContext: .init(
            viewportRect: scrollRoute.viewportRect,
            contentBounds: scrollRoute.contentBounds
          )
        )
      )
    )
    #expect(box.position.y == 8)
  }
}
