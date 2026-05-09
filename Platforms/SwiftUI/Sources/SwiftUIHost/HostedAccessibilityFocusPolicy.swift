enum HostedAccessibilityFocusPolicy {
  static func requestedFocusID(
    in mappings: [AccessibilityNodeMapping]
  ) -> String? {
    mappings.first(where: \.isFocused)?.id
  }
}
