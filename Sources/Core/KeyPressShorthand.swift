// MARK: - KeyPress authoring shorthands

/// Convenience factories for the most common ``KeyPress`` authoring
/// patterns. These let command and hotkey declarations express single-line
/// key bindings such as `.ctrl("s")` or `.escape`.
extension KeyPress {
  /// A `Ctrl+<character>` key press, e.g. `.ctrl("s")` for *Save*.
  public static func ctrl(_ character: Character) -> KeyPress {
    KeyPress(.character(character), modifiers: .ctrl)
  }

  /// An `Alt+<character>` key press.
  public static func alt(_ character: Character) -> KeyPress {
    KeyPress(.character(character), modifiers: .alt)
  }

  /// A `Shift+<character>` key press.
  public static func shift(_ character: Character) -> KeyPress {
    KeyPress(.character(character), modifiers: .shift)
  }
}

extension KeyPress {
  /// An unmodified `Escape` key press.
  public static let escape: KeyPress = KeyPress(.escape)

  /// An unmodified `Return` key press.
  public static let `return`: KeyPress = KeyPress(.return)

  /// An unmodified `Space` key press.
  public static let space: KeyPress = KeyPress(.space)

  /// An unmodified `Tab` key press.
  public static let tab: KeyPress = KeyPress(.tab)
}
