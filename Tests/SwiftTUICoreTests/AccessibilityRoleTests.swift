import Testing
@testable import SwiftTUICore

struct AccessibilityRoleTests {
  @Test("AccessibilityRole exposes stable descriptions")
  func roleDescriptions() {
    #expect(AccessibilityRole.button.description == "button")
    #expect(AccessibilityRole.secureField.description == "secureField")
    #expect(AccessibilityRole.heading(level: 2).description == "heading(level: 2)")
    #expect(AccessibilityRole.custom("chart").description == "custom(chart)")
  }

  @Test("SemanticMetadata stores accessibility role")
  func semanticMetadataStoresAccessibilityRole() {
    let metadata = SemanticMetadata(accessibilityRole: .button)
    #expect(metadata.accessibilityRole == .button)
  }
}
