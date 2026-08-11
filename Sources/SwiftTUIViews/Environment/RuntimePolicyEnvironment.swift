private enum AccessibilityReduceMotionKey: EnvironmentKey {
  static let defaultValue = false
}

private enum CursorFollowsFocusKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  public var accessibilityReduceMotion: Bool {
    get { self[AccessibilityReduceMotionKey.self] }
    set { self[AccessibilityReduceMotionKey.self] = newValue }
  }

  package var cursorFollowsFocus: Bool {
    get { self[CursorFollowsFocusKey.self] }
    set { self[CursorFollowsFocusKey.self] = newValue }
  }
}
