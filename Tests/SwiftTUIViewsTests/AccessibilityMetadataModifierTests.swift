import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct AccessibilityMetadataModifierTests {
  @Test("SemanticMetadata stores accessibility fields")
  func semanticMetadataStoresAccessibilityFields() {
    let metadata = SemanticMetadata(
      accessibilityRole: .status,
      accessibilityLabel: "Upload status",
      accessibilityHint: "Updates as files finish uploading",
      accessibilityHidden: true,
      accessibilityLiveRegion: .polite
    )

    #expect(metadata.accessibilityRole == .status)
    #expect(metadata.accessibilityLabel == "Upload status")
    #expect(metadata.accessibilityHint == "Updates as files finish uploading")
    #expect(metadata.accessibilityHidden == true)
    #expect(metadata.accessibilityLiveRegion == .polite)
  }

  @Test("SemanticMetadata accessibility fields merge with override precedence")
  func semanticMetadataAccessibilityFieldsMerge() {
    let base = SemanticMetadata(
      accessibilityLabel: "Base label",
      accessibilityHint: "Base hint",
      accessibilityHidden: false,
      accessibilityLiveRegion: .polite
    )
    let override = SemanticMetadata(
      accessibilityLabel: "Override label",
      accessibilityHint: "Override hint",
      accessibilityHidden: true,
      accessibilityLiveRegion: .assertive
    )

    let merged = base.merging(override)

    #expect(merged.accessibilityLabel == "Override label")
    #expect(merged.accessibilityHint == "Override hint")
    #expect(merged.accessibilityHidden == true)
    #expect(merged.accessibilityLiveRegion == .assertive)
  }

  @Test("Accessibility modifiers write semantic metadata")
  func accessibilityModifiersWriteSemanticMetadata() {
    let resolved = Text("Decorative")
      .accessibilityRole(.status)
      .accessibilityLabel("Current status")
      .accessibilityHint("Updates when work changes")
      .accessibilityHidden()
      .accessibilityLiveRegion(.assertive)
      .resolve(in: .init(identity: testIdentity("Accessibility", "Metadata")))

    #expect(resolved.semanticMetadata.accessibilityRole == .status)
    #expect(resolved.semanticMetadata.accessibilityLabel == "Current status")
    #expect(resolved.semanticMetadata.accessibilityHint == "Updates when work changes")
    #expect(resolved.semanticMetadata.accessibilityHidden == true)
    #expect(resolved.semanticMetadata.accessibilityLiveRegion == .assertive)
  }
}
