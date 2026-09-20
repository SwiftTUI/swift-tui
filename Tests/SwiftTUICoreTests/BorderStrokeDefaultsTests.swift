import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Anchors the framework's canonical border/stroke defaults so any
/// regression in the implicit `StrokeStyle()` defaults is caught
/// immediately.
///
/// An empty `StrokeStyle()` is a solid single line with square corners, as
/// SwiftUI's default stroke is, and it is inset, so an unlabeled stroke never
/// changes layout allocation.
///
/// The default was `.rounded` until the border and stroke redesign (ruling 4,
/// 2026-09-19). The built-in controls ask for rounded corners themselves, so
/// they did not change with it.
@Test("StrokeStyle.init is a solid single line with square corners by default")
func strokeStyleInitDefaultIsSquareSingleLine() {
  let style = StrokeStyle()
  #expect(style.borderSet == .single)
  #expect(style.lineJoin == .miter)
  #expect(style.dash.isEmpty)
  #expect(style.dashPhase == 0)
}

@Test("the deprecated lineWidth and placement still read and write, for the deprecation window")
@available(*, deprecated)
func deprecatedLineWidthAndPlacement() {
  #expect(StrokeStyle().lineWidth == 1)
  #expect(StrokeStyle().placement == .inset)
  #expect(StrokeStyle(placement: .outset).placement == .outset)
  #expect(StrokeStyle(lineWidth: 2).lineWidth == 2)
  // A width below one is one.
  #expect(StrokeStyle(lineWidth: 0).lineWidth == 1)

  var style = StrokeStyle()
  style.lineWidth = 3
  style.placement = .outset
  #expect(style == StrokeStyle(legacyLineWidth: 3, legacyPlacement: .outset))
  style.lineWidth = -4
  #expect(style.lineWidth == 1)

  // The old spelling of the type names the new one.
  let placement: StrokeStyle.Placement = .outset
  #expect(placement == BorderPlacement.outset)
}
