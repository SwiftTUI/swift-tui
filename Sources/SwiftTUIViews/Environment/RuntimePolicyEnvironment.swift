private enum AccessibilityReduceMotionKey: EnvironmentKey {
  static let defaultValue = false
}

private enum StableOutputKey: EnvironmentKey {
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

  /// Framework rendering policy that produces deterministic captured output
  /// without changing the public accessibility preference observed by apps.
  package var stableOutput: Bool {
    get { self[StableOutputKey.self] }
    set { self[StableOutputKey.self] = newValue }
  }

  /// The combined policy built-in animated views use.
  package var renderingReduceMotion: Bool {
    accessibilityReduceMotion || stableOutput
  }

  package var cursorFollowsFocus: Bool {
    get { self[CursorFollowsFocusKey.self] }
    set { self[CursorFollowsFocusKey.self] = newValue }
  }
}
