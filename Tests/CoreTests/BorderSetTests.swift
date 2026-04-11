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
  #expect(set.bottomDisplayWidth == 1)
  #expect(set.leftDisplayWidth == 1)
  #expect(set.rightDisplayWidth == 1)
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
    top: "界", bottom: "界", left: "┃", right: "┃",
    topLeading: "╔", topTrailing: "╗",
    bottomLeading: "╚", bottomTrailing: "╝"
  )
  #expect(set.topDisplayWidth == 2)
}

@Test("Edge widths route each property to its own edge")
func edgeWidthsRoutePerEdge() {
  // Use a distinct width on each side so a wiring bug surfaces.
  let set = BorderSet(
    top: "─",  // width 1
    bottom: "界",  // width 2
    left: "│",  // width 1
    right: "界",  // width 2
    topLeading: "┌", topTrailing: "┐",
    bottomLeading: "└", bottomTrailing: "┘"
  )
  #expect(set.topDisplayWidth == 1)
  #expect(set.bottomDisplayWidth == 2)
  #expect(set.leftDisplayWidth == 1)
  #expect(set.rightDisplayWidth == 2)
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

@Test("BorderSet.single uses ─ │ ┌ ┐ └ ┘")
func builtinSingle() {
  let s = BorderSet.single
  #expect(s.top == "─")
  #expect(s.left == "│")
  #expect(s.topLeading == "┌")
  #expect(s.bottomTrailing == "┘")
  #expect(s.placement == .outset)
}

@Test("BorderSet.rounded uses ╭ ╮ ╰ ╯ corners")
func builtinRounded() {
  let s = BorderSet.rounded
  #expect(s.topLeading == "╭")
  #expect(s.topTrailing == "╮")
  #expect(s.bottomLeading == "╰")
  #expect(s.bottomTrailing == "╯")
}

@Test("BorderSet.outerHalfBlock uses ▀ ▄ ▌ ▐ ▛ ▜ ▙ ▟")
func builtinOuterHalf() {
  let s = BorderSet.outerHalfBlock
  #expect(s.top == "▀")
  #expect(s.bottom == "▄")
  #expect(s.left == "▌")
  #expect(s.right == "▐")
  #expect(s.topLeading == "▛")
  #expect(s.topTrailing == "▜")
  #expect(s.bottomLeading == "▙")
  #expect(s.bottomTrailing == "▟")
  #expect(s.placement == .decorative)
}

@Test("BorderSet.dashed cycles ─· and │·")
func builtinDashed() {
  let s = BorderSet.dashed
  #expect(s.top == "─·")
  #expect(s.left == "│·")
}

@Test("BorderSet.singleDouble has single horizontals, double verticals")
func builtinSingleDouble() {
  let s = BorderSet.singleDouble
  #expect(s.top == "─")
  #expect(s.left == "║")
  #expect(s.topLeading == "╓")
  #expect(s.topTrailing == "╖")
}

@Test("BorderSet.none has zero frame contribution")
func builtinNone() {
  let s = BorderSet.none
  #expect(s.topDisplayWidth == 0)
  #expect(s.leftDisplayWidth == 0)
}

@Test("BorderSet.hidden has frame contribution but invisible glyphs")
func builtinHidden() {
  let s = BorderSet.hidden
  #expect(s.topDisplayWidth == 1)
  #expect(s.top == " ")
}

@Test("Single-rune top edge returns the same glyph at every index")
func cyclingSingleRune() {
  let s = BorderSet.single
  #expect(s.topGlyph(at: 0) == "─")
  #expect(s.topGlyph(at: 1) == "─")
  #expect(s.topGlyph(at: 99) == "─")
}

@Test("Two-rune top edge alternates")
func cyclingTwoRune() {
  let s = BorderSet.dashed
  #expect(s.topGlyph(at: 0) == "─")
  #expect(s.topGlyph(at: 1) == "·")
  #expect(s.topGlyph(at: 2) == "─")
  #expect(s.topGlyph(at: 3) == "·")
}

@Test("Empty edge returns nil")
func cyclingEmpty() {
  let s = BorderSet.none
  #expect(s.topGlyph(at: 0) == nil)
}

@Test("Negative index returns nil instead of trapping")
func cyclingNegativeIndex() {
  let s = BorderSet.single
  #expect(s.topGlyph(at: -1) == nil)
  #expect(s.bottomGlyph(at: -5) == nil)
  #expect(s.leftGlyph(at: -99) == nil)
  #expect(s.rightGlyph(at: -1) == nil)
}

@Test("Every built-in has a non-empty top glyph except .none")
func builtinTopGlyphsNonEmpty() {
  let allBuiltins: [(name: String, set: BorderSet, expectEmpty: Bool)] = [
    ("single", BorderSet.single, false),
    ("rounded", BorderSet.rounded, false),
    ("double", BorderSet.double, false),
    ("heavy", BorderSet.heavy, false),
    ("block", BorderSet.block, false),
    ("outerHalfBlock", BorderSet.outerHalfBlock, false),
    ("innerHalfBlock", BorderSet.innerHalfBlock, false),
    ("singleDouble", BorderSet.singleDouble, false),
    ("doubleSingle", BorderSet.doubleSingle, false),
    ("ascii", BorderSet.ascii, false),
    ("hidden", BorderSet.hidden, false),
    ("none", BorderSet.none, true),  // the only one that should be empty
    ("dashed", BorderSet.dashed, false),
    ("dashedHeavy", BorderSet.dashedHeavy, false),
    ("markdown", BorderSet.markdown, false),
  ]
  for (name, set, expectEmpty) in allBuiltins {
    if expectEmpty {
      #expect(set.top.isEmpty, "\(name) should have an empty top")
    } else {
      #expect(!set.top.isEmpty, "\(name) should have a non-empty top")
    }
  }
}
