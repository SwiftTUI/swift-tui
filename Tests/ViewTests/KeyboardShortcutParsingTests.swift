import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct KeyboardShortcutParsingTests {
  @Test("parses single character shortcut")
  func singleCharacter() {
    let result = parseShortcutKey("q")
    #expect(result == LocalKeyPress(.character("q")))
  }

  @Test("parses single special character")
  func specialCharacter() {
    let result = parseShortcutKey("?")
    #expect(result == LocalKeyPress(.character("?")))
  }

  @Test("parses Ctrl+letter")
  func ctrlLetter() {
    let result = parseShortcutKey("Ctrl+S")
    #expect(result == LocalKeyPress(.character("S"), modifiers: .control))
  }

  @Test("parses ctrl+letter case-insensitive modifier")
  func ctrlLetterLowercase() {
    let result = parseShortcutKey("ctrl+s")
    #expect(result == LocalKeyPress(.character("s"), modifiers: .control))
  }

  @Test("parses Alt+letter")
  func altLetter() {
    let result = parseShortcutKey("Alt+X")
    #expect(result == LocalKeyPress(.character("X"), modifiers: .option))
  }

  @Test("parses Option+letter")
  func optionLetter() {
    let result = parseShortcutKey("Option+X")
    #expect(result == LocalKeyPress(.character("X"), modifiers: .option))
  }

  @Test("parses Shift+Tab")
  func shiftTab() {
    let result = parseShortcutKey("Shift+Tab")
    #expect(result == LocalKeyPress(.tab, modifiers: .shift))
  }

  @Test("parses Ctrl+Shift+A")
  func ctrlShiftA() {
    let result = parseShortcutKey("Ctrl+Shift+A")
    #expect(result == LocalKeyPress(.character("A"), modifiers: [.control, .shift]))
  }

  @Test("parses Enter key name")
  func enterKey() {
    let result = parseShortcutKey("Enter")
    #expect(result == LocalKeyPress(.enter))
  }

  @Test("parses Escape key name")
  func escapeKey() {
    let result = parseShortcutKey("Escape")
    #expect(result == LocalKeyPress(.escape))
  }

  @Test("parses Space key name")
  func spaceKey() {
    let result = parseShortcutKey("Space")
    #expect(result == LocalKeyPress(.space))
  }

  @Test("parses Backspace key name")
  func backspaceKey() {
    let result = parseShortcutKey("Backspace")
    #expect(result == LocalKeyPress(.backspace))
  }

  @Test("parses arrow key names")
  func arrowKeys() {
    #expect(parseShortcutKey("Up") == LocalKeyPress(.arrowUp))
    #expect(parseShortcutKey("Down") == LocalKeyPress(.arrowDown))
    #expect(parseShortcutKey("Left") == LocalKeyPress(.arrowLeft))
    #expect(parseShortcutKey("Right") == LocalKeyPress(.arrowRight))
  }

  @Test("parses Ctrl+Up arrow")
  func ctrlArrow() {
    let result = parseShortcutKey("Ctrl+Up")
    #expect(result == LocalKeyPress(.arrowUp, modifiers: .control))
  }

  @Test("returns nil for empty string")
  func emptyString() {
    let result = parseShortcutKey("")
    #expect(result == nil)
  }

  @Test("returns nil for modifiers only")
  func modifiersOnly() {
    let result = parseShortcutKey("Ctrl+Shift")
    #expect(result == nil)
  }

  @Test("returns nil for unknown key name")
  func unknownKey() {
    let result = parseShortcutKey("Ctrl+FooBar")
    #expect(result == nil)
  }
}
