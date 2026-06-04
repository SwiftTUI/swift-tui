import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Covers the foreground-defaulting shape overloads (`fill()`, `stroke()`,
/// `strokeBorder()`) that mirror SwiftUI's no-content forms. Each resolves a
/// `nil` shape style, which the draw pipeline maps to the inherited
/// `foregroundStyle` (and ultimately a semantic role), so the no-content form
/// must render byte-identically to passing that style explicitly.
@MainActor
@Suite("Shape foreground-defaulting overloads")
struct ShapeForegroundStyleOverloadTests {

  @Test("Circle().fill() matches Circle().fill(.foreground)")
  func fillDefaultsToForeground() {
    let implicit = DefaultRenderer().render(
      Circle().fill().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillImplicit"))
    )
    let explicit = DefaultRenderer().render(
      Circle().fill(.foreground).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillExplicit"))
    )
    #expect(implicit.rasterSurface == explicit.rasterSurface)
  }

  @Test("Circle().fill() matches a bare Circle()")
  func fillMatchesBareShape() {
    let modifier = DefaultRenderer().render(
      Circle().fill().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillModifier"))
    )
    let bare = DefaultRenderer().render(
      Circle().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillBare"))
    )
    #expect(modifier.rasterSurface == bare.rasterSurface)
  }

  @Test("Circle().stroke() matches Circle().stroke(.foreground)")
  func strokeDefaultsToForeground() {
    let implicit = DefaultRenderer().render(
      Circle().stroke().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("StrokeImplicit"))
    )
    let explicit = DefaultRenderer().render(
      Circle().stroke(.foreground).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("StrokeExplicit"))
    )
    #expect(implicit.rasterSurface == explicit.rasterSurface)
  }

  @Test("Rectangle().strokeBorder() matches Rectangle().strokeBorder(.separator)")
  func strokeBorderDefaultsToSeparator() {
    let implicit = DefaultRenderer().render(
      Rectangle().strokeBorder().frame(width: 12, height: 5),
      context: .init(identity: testIdentity("StrokeBorderImplicit"))
    )
    let explicit = DefaultRenderer().render(
      Rectangle().strokeBorder(.separator).frame(width: 12, height: 5),
      context: .init(identity: testIdentity("StrokeBorderExplicit"))
    )
    #expect(implicit.rasterSurface == explicit.rasterSurface)
  }

  @Test("fill() honors an inherited foregroundStyle")
  func fillHonorsInheritedForegroundStyle() {
    let inherited = DefaultRenderer().render(
      Circle().fill().foregroundStyle(Color.red).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillInherited"))
    )
    let direct = DefaultRenderer().render(
      Circle().fill(Color.red).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillDirect"))
    )
    #expect(inherited.rasterSurface == direct.rasterSurface)
  }

  @Test("Circle().stroke() draws an outline, not a filled disc")
  func strokeDrawsRing() {
    let stroked = DefaultRenderer().render(
      Circle().stroke().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("StrokeRing"))
    )
    let filled = DefaultRenderer().render(
      Circle().fill().frame(width: 10, height: 5),
      context: .init(identity: testIdentity("FillDisc"))
    )
    #expect(stroked.rasterSurface != filled.rasterSurface)
  }
}

/// Guards the inset plumbing after `kindName`/`insetAmount` moved behind the
/// `ShapeRendering` SPI: inset still flows into the rendered payload, and
/// nested `inset(by:)` calls still accumulate. Both rely on `insetAmount`
/// dispatching dynamically through `InsetShape` — they would silently break
/// if it were ever demoted to a non-requirement extension helper.
@MainActor
@Suite("Shape inset accumulation")
struct ShapeInsetAccumulationTests {

  @Test("inset(by:) shrinks the rendered shape")
  func insetShrinksShape() {
    let inset = DefaultRenderer().render(
      Rectangle().inset(by: 2).fill().frame(width: 12, height: 6),
      context: .init(identity: testIdentity("RectInset"))
    )
    let full = DefaultRenderer().render(
      Rectangle().fill().frame(width: 12, height: 6),
      context: .init(identity: testIdentity("RectFull"))
    )
    #expect(inset.rasterSurface != full.rasterSurface)
  }

  @Test("nested inset(by:) accumulates")
  func nestedInsetAccumulates() {
    let nested = DefaultRenderer().render(
      Rectangle().inset(by: 1).inset(by: 1).fill().frame(width: 12, height: 6),
      context: .init(identity: testIdentity("RectNestedInset"))
    )
    let summed = DefaultRenderer().render(
      Rectangle().inset(by: 2).fill().frame(width: 12, height: 6),
      context: .init(identity: testIdentity("RectSummedInset"))
    )
    #expect(nested.rasterSurface == summed.rasterSurface)
  }
}
