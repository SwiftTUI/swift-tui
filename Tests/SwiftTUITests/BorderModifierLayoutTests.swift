import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Layout, raster, and interaction assertions for the public inset default.
@MainActor
struct BorderModifierLayoutTests {
  @Test("public .border defaults to non-layout-affecting inset placement")
  func borderDefaultsToInsetLayout() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single),
      context: .init(identity: testIdentity("BorderDefaultsToInset"))
    )

    #expect(artifacts.rasterSurface.size.width == 2)
    #expect(artifacts.rasterSurface.size.height == 1)
  }

  @Test("explicit outset placement keeps the layout-growing behavior")
  func explicitOutsetGrowsLayout() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single, placement: .outset),
      context: .init(identity: testIdentity("BorderExplicitOutset"))
    )

    #expect(artifacts.rasterSurface.size.width == 4)
    #expect(artifacts.rasterSurface.size.height == 3)
  }

  @Test("every public border overload defaults to inset placement")
  func everyBorderOverloadDefaultsToInset() {
    let expectedSize = CellSize(width: 3, height: 3)
    let content = VStack(spacing: 0) {
      Text("abc")
      Text("def")
      Text("ghi")
    }

    let styled = DefaultRenderer().render(
      content.border(Color.red, set: .single),
      context: .init(identity: testIdentity("BorderStyleOverloadDefault"))
    )
    let perEdge = DefaultRenderer().render(
      content.border(BorderEdgeStyle(Color.red), set: .single),
      context: .init(identity: testIdentity("BorderEdgeOverloadDefault"))
    )
    let blended = DefaultRenderer().render(
      content.border(
        blend: BorderBlend([Color.red, Color.blue]),
        set: .single
      ),
      context: .init(identity: testIdentity("BorderBlendOverloadDefault"))
    )

    #expect(styled.rasterSurface.size == expectedSize)
    #expect(perEdge.rasterSurface.size == expectedSize)
    #expect(blended.rasterSurface.size == expectedSize)
  }

  @Test("default inset border leaves sibling allocation unchanged")
  func defaultInsetLeavesSiblingAllocationUnchanged() {
    func renderedWidth<Content: View>(_ content: Content, name: String) -> Int {
      DefaultRenderer().render(
        content,
        context: .init(identity: testIdentity(name))
      ).rasterSurface.size.width
    }

    let baseline = renderedWidth(
      HStack(spacing: 0) {
        Text("abc")
        Text("xyz")
      },
      name: "BorderSiblingBaseline"
    )
    let inset = renderedWidth(
      HStack(spacing: 0) {
        Text("abc").border(set: .ascii)
        Text("xyz")
      },
      name: "BorderSiblingInset"
    )
    let outset = renderedWidth(
      HStack(spacing: 0) {
        Text("abc").border(set: .ascii, placement: .outset)
        Text("xyz")
      },
      name: "BorderSiblingOutset"
    )

    #expect(baseline == 6)
    #expect(inset == baseline)
    #expect(outset == baseline + 2)
  }

  @Test("default ASCII border rasterizes inside and clips to the content frame")
  func defaultInsetASCIIRasterAndClipping() {
    let artifacts = DefaultRenderer().render(
      VStack(spacing: 0) {
        Text("abc")
        Text("def")
        Text("ghi")
      }
      .border(set: .ascii),
      context: .init(identity: testIdentity("BorderDefaultASCIIRaster"))
    )

    #expect(artifacts.rasterSurface.size.width == 3)
    #expect(artifacts.rasterSurface.size.height == 3)
    #expect(artifacts.rasterSurface.lines == ["+-+", "|e|", "+-+"])
  }

  @Test("default inset border does not enlarge its hit region")
  func defaultInsetHitRegionDoesNotGrow() throws {
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: testIdentity("BorderDefaultHitRegion"))
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      VStack(spacing: 0) {
        Text("abc")
        Text("def")
        Text("ghi")
      }
      .border(set: .ascii)
      .gesture(TapGesture().onEnded {}),
      context: context
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)

    #expect(region.rect.size == CellSize(width: 3, height: 3))
  }
}
