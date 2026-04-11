import Testing

@testable import Core

@Test("BorderEdgeStyle stores per-side foreground styles")
func borderEdgeStyleStoresColors() {
  let style = BorderEdgeStyle(
    top: AnyShapeStyle(Color.red),
    right: AnyShapeStyle(Color.green),
    bottom: AnyShapeStyle(Color.blue),
    left: AnyShapeStyle(Color.yellow)
  )
  #expect(style.top != nil)
  #expect(style.right != nil)
  #expect(style.bottom != nil)
  #expect(style.left != nil)
}

@Test("BorderEdgeStyle single-color shorthand fills all four sides")
func borderEdgeStyleSingleColor() {
  let style = BorderEdgeStyle(Color.red)
  #expect(style.top != nil)
  #expect(style.right != nil)
  #expect(style.bottom != nil)
  #expect(style.left != nil)
}

@Test("BorderEdgeStyle topBottom/leftRight shorthand maps to all sides")
func borderEdgeStyleTopBottomLeftRight() {
  let style = BorderEdgeStyle(topBottom: Color.red, leftRight: Color.blue)
  #expect(style.top != nil)
  #expect(style.right != nil)
  #expect(style.bottom != nil)
  #expect(style.left != nil)
}

@Test("BorderEdgeStyle top/leftRight/bottom shorthand maps to all sides")
func borderEdgeStyleThreeWay() {
  let style = BorderEdgeStyle(top: Color.red, leftRight: Color.blue, bottom: Color.green)
  #expect(style.top != nil)
  #expect(style.right != nil)
  #expect(style.bottom != nil)
  #expect(style.left != nil)
}

@Test("BorderEdgeStyle is all-nil by default")
func borderEdgeStyleAllNilDefault() {
  let style = BorderEdgeStyle()
  #expect(style.top == nil)
  #expect(style.right == nil)
  #expect(style.bottom == nil)
  #expect(style.left == nil)
}

@Test("BorderEdgeStyle.foregroundStyle(for:) returns the matching side")
func borderEdgeStyleForegroundLookup() {
  let style = BorderEdgeStyle(
    top: AnyShapeStyle(Color.red),
    right: AnyShapeStyle(Color.green),
    bottom: AnyShapeStyle(Color.blue),
    left: AnyShapeStyle(Color.yellow)
  )
  #expect(style.foregroundStyle(for: .top) == AnyShapeStyle(Color.red))
  #expect(style.foregroundStyle(for: .right) == AnyShapeStyle(Color.green))
  #expect(style.foregroundStyle(for: .bottom) == AnyShapeStyle(Color.blue))
  #expect(style.foregroundStyle(for: .left) == AnyShapeStyle(Color.yellow))
}
