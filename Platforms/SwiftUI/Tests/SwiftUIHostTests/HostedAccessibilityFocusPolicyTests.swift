import CoreGraphics
import SwiftTUI
import Testing

@testable import SwiftUIHost

@MainActor
@Suite
struct HostedAccessibilityFocusPolicyTests {
  @Test("requests the focused mapping id")
  func requestsFocusedMappingID() {
    let focused = mapping(id: "root.button", isFocused: true)
    let other = mapping(id: "root.other", isFocused: false)

    #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: [other, focused]) == "root.button")
  }

  @Test("clears focus when focused node is absent")
  func clearsFocusWhenFocusedNodeIsAbsent() {
    #expect(
      HostedAccessibilityFocusPolicy.requestedFocusID(
        in: [mapping(id: "root.button", isFocused: false)]
      ) == nil
    )
  }

  @Test("keeps the first focused mapping when duplicate focus metadata appears")
  func keepsFirstFocusedMapping() {
    let first = mapping(id: "root.first", isFocused: true)
    let second = mapping(id: "root.second", isFocused: true)

    #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: [first, second]) == "root.first")
  }
}

private func mapping(
  id: String,
  isFocused: Bool
) -> AccessibilityNodeMapping {
  AccessibilityNodeMapping(
    id: id,
    identity: Identity(components: [id]),
    parentIdentity: nil,
    frame: CGRect(x: 0, y: 0, width: 8, height: 16),
    role: .button,
    roleDescription: AccessibilityRole.button.description,
    label: id,
    hint: nil,
    traits: [.button],
    controlKind: .action,
    isFocused: isFocused,
    liveRegion: nil
  )
}
