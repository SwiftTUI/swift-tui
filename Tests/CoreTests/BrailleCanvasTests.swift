import Testing

@testable import Core

// MARK: - BrailleCell

@Test("BrailleCell empty mask yields U+2800")
func brailleCellEmpty() {
  let cell = BrailleCell()
  #expect(cell.glyph == "\u{2800}")
  #expect(cell.mask == 0)
}

@Test("BrailleCell all 8 dots set yields ⣿")
func brailleCellAllDots() {
  var cell = BrailleCell()
  for x in 0..<2 {
    for y in 0..<4 {
      cell.set(x: x, y: y)
    }
  }
  #expect(cell.glyph == "⣿")
  #expect(cell.mask == 0xFF)
}

@Test("BrailleCell top-left dot yields ⠁")
func brailleCellTopLeftDot() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 0)
  #expect(cell.glyph == "⠁")
}

@Test("BrailleCell top-right dot yields ⠈")
func brailleCellTopRightDot() {
  var cell = BrailleCell()
  cell.set(x: 1, y: 0)
  #expect(cell.glyph == "⠈")
  #expect(cell.mask == 0x08)
}

@Test("BrailleCell bottom dots use 0x40 / 0x80")
func brailleCellBottomDots() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 3)
  #expect(cell.mask == 0x40)
  cell.set(x: 1, y: 3)
  #expect(cell.mask == 0xC0)
}

@Test("BrailleCell clear removes a dot")
func brailleCellClear() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 0)
  cell.set(x: 1, y: 0)
  cell.clear(x: 0, y: 0)
  #expect(cell.mask == 0x08)
  #expect(cell.contains(x: 0, y: 0) == false)
  #expect(cell.contains(x: 1, y: 0) == true)
}

@Test("BrailleCell out-of-range coordinates are ignored")
func brailleCellOutOfRange() {
  var cell = BrailleCell()
  cell.set(x: 2, y: 0)
  cell.set(x: 0, y: 4)
  cell.set(x: -1, y: 0)
  #expect(cell.mask == 0)
}
