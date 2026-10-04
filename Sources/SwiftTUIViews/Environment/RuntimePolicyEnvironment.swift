public import SwiftTUICore

private enum AccessibilityPreferencesKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = AccessibilityPreferences()
}

private enum StableOutputKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = false
}

private enum CursorFollowsFocusKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// The effective host preferences; a subtree can override individual choices.
  public var accessibilityPreferences: AccessibilityPreferences {
    get { self[AccessibilityPreferencesKey.self] }
    set { self[AccessibilityPreferencesKey.self] = newValue }
  }

  /// Whether content should avoid nonessential motion.
  public var accessibilityReduceMotion: Bool {
    get { accessibilityPreferences.reduceMotion ?? false }
    set { accessibilityPreferences.reduceMotion = newValue }
  }

  /// Whether content should distinguish meaning with labels, shapes or patterns.
  public var accessibilityDifferentiateWithoutColor: Bool {
    get { accessibilityPreferences.differentiateWithoutColor ?? false }
    set { accessibilityPreferences.differentiateWithoutColor = newValue }
  }

  /// Whether content should prefer opaque surfaces.
  public var accessibilityReduceTransparency: Bool {
    get { accessibilityPreferences.reduceTransparency ?? false }
    set { accessibilityPreferences.reduceTransparency = newValue }
  }

  /// The user-selected color profile; unspecified hosts use the standard palette.
  public var accessibilityColorProfile: AccessibilityColorProfile {
    get { accessibilityPreferences.colorProfile ?? .standard }
    set { accessibilityPreferences.colorProfile = newValue }
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
