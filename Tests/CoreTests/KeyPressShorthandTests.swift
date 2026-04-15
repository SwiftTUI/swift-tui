import Testing

@testable import Core

@MainActor
@Suite
struct KeyPressShorthandTests {
  @Test("ctrl shorthand wires character and ctrl modifier")
  func ctrlShorthand() {
    #expect(
      KeyPress.ctrl("s") == KeyPress(.character("s"), modifiers: .ctrl)
    )
  }

  @Test("alt shorthand wires character and alt modifier")
  func altShorthand() {
    #expect(
      KeyPress.alt("x") == KeyPress(.character("x"), modifiers: .alt)
    )
  }

  @Test("shift shorthand wires character and shift modifier")
  func shiftShorthand() {
    #expect(
      KeyPress.shift("a") == KeyPress(.character("a"), modifiers: .shift)
    )
  }

  @Test("escape shorthand is an unmodified escape")
  func escapeShorthand() {
    #expect(KeyPress.escape == KeyPress(.escape))
  }

  @Test("return shorthand is an unmodified return")
  func returnShorthand() {
    #expect(KeyPress.return == KeyPress(.return))
  }

  @Test("space shorthand is an unmodified space")
  func spaceShorthand() {
    #expect(KeyPress.space == KeyPress(.space))
  }

  @Test("tab shorthand is an unmodified tab")
  func tabShorthand() {
    #expect(KeyPress.tab == KeyPress(.tab))
  }

  @Test("two shorthand calls with the same args are equal and hash equal")
  func shorthandsAreHashable() {
    let a = KeyPress.ctrl("s")
    let b = KeyPress.ctrl("s")
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)

    let set: Set<KeyPress> = [.ctrl("s"), .ctrl("s"), .alt("x")]
    #expect(set.count == 2)
  }
}
