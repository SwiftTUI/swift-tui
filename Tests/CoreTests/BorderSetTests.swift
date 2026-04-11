import Testing

@testable import Core

@Test("BorderSet stores 13 string slots")
func borderSetStoresAllSlots() {
  let set = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘",
    middleLeading: "├", middleTrailing: "┤",
    middle: "┼", middleTop: "┬", middleBottom: "┴",
    placement: .outset
  )
  #expect(set.top == "─")
  #expect(set.middle == "┼")
  #expect(set.placement == .outset)
}

@Test("BorderSet placement defaults to outset")
func borderSetPlacementDefault() {
  let set = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  #expect(set.placement == .outset)
}

@Test("BorderSet is Equatable")
func borderSetEquatable() {
  let a = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  let b = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  let differentTop = BorderSet(
    top: "━", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  let differentPlacement = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘",
    placement: .inset
  )
  #expect(a == b)
  #expect(a != differentTop)
  #expect(a != differentPlacement)
}

@Test("Edge widths are 1 for single-line glyphs")
func edgeWidthSingleLine() {
  let set = BorderSet(
    top: "─", bottom: "─", left: "│", right: "│",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  #expect(set.topDisplayWidth == 1)
  #expect(set.leftDisplayWidth == 1)
}

@Test("Edge widths handle multi-rune cycling edges")
func edgeWidthMultiRune() {
  let set = BorderSet(
    top: "─·", bottom: "─·", left: "│·", right: "│·",
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  // widest rune in "─·" is 1 cell wide; cycling doesn't change vertical contribution
  #expect(set.topDisplayWidth == 1)
}

@Test("Edge widths handle wide graphemes")
func edgeWidthWide() {
  let set = BorderSet(
    top: "★", bottom: "★", left: "┃", right: "┃",
    topLeading: "╔", topTrailing: "╗",
    bottomLeading: "╚", bottomTrailing: "╝"
  )
  #expect(set.topDisplayWidth == 1)
}

@Test("Empty edge contributes zero")
func edgeWidthEmpty() {
  let set = BorderSet(
    top: "", bottom: "─", left: "│", right: "│",
    topLeading: "", topTrailing: "",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  #expect(set.topDisplayWidth == 0)
}
