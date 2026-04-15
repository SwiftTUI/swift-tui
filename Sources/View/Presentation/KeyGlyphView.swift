public import Core

// MARK: - Display helper

/// The terminal-safe display string for a ``KeyPress``, rendered as a
/// bracketed glyph (e.g. `"[^S]"` for `Ctrl+s`).
///
/// This is the single source of truth for key-glyph presentation inside
/// the help strip, the help sheet, command-palette rows, and Stage-4
/// toolbar items that render a bound command. The modifiers stack in
/// the order `Ctrl → Alt → Shift → key`, using the symbol-based variants
/// as the default because they are terminal-safe (they decode to single
/// code points in any UTF-8 aware terminal) and match the visual density
/// that modern TUIs have converged on.
///
/// Exposed at package visibility so unit tests can assert strings
/// directly without going through view rendering.
package func keyDisplayString(for key: KeyPress) -> String {
  "[\(keyGlyphInnerString(for: key))]"
}

/// The inner display characters of a key glyph, without the enclosing
/// brackets. Split out of ``keyDisplayString(for:)`` so tests can mix
/// bracketed and unbracketed comparisons cheaply.
private func keyGlyphInnerString(for key: KeyPress) -> String {
  var result = ""
  if key.modifiers.contains(.ctrl) {
    result += "^"
  }
  if key.modifiers.contains(.alt) {
    result += "⌥"
  }
  if key.modifiers.contains(.shift) {
    result += "⇧"
  }
  result += keyBodyDisplayString(for: key.key, hasModifiers: !key.modifiers.isEmpty)
  return result
}

/// The "body" portion of a key glyph — the part that represents the
/// underlying key identity, independent of the Ctrl/Alt/Shift modifiers.
private func keyBodyDisplayString(
  for event: KeyEvent,
  hasModifiers: Bool
) -> String {
  switch event {
  case .character(let character):
    // Named modifiers uppercase the character by convention (matching
    // macOS menu shortcuts, Textual footers, and Charm's `bubbles/help`);
    // unmodified characters stay lowercase so `[s]` renders the same
    // shape the user types.
    hasModifiers
      ? String(character).uppercased()
      : String(character).lowercased()
  case .return:
    "⏎"
  case .space:
    "Space"
  case .tab:
    "Tab"
  case .arrowLeft:
    "←"
  case .arrowRight:
    "→"
  case .arrowUp:
    "↑"
  case .arrowDown:
    "↓"
  case .backspace:
    "⌫"
  case .escape:
    "Esc"
  case .home:
    "Home"
  case .end:
    "End"
  }
}

// MARK: - Public view

/// A single rendering of a keyboard shortcut, used by the help strip,
/// the help sheet, and command-palette rows.
///
/// The view renders a bracketed glyph like `[^S]` or `[⏎]` as a
/// single ``Text`` run. It is intentionally stateless and layout-light —
/// pack it into any host layout you please.
public struct KeyGlyphView: View {
  public let key: KeyPress

  public init(_ key: KeyPress) {
    self.key = key
  }

  public var body: some View {
    Text(keyDisplayString(for: key))
      .bold()
  }
}
