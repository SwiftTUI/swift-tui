import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// `StyleEnvironmentSnapshot.resolvedStyle(for:)` is the public seam a
/// third-party style uses to match built-in foreground resolution.
struct StyleEnvironmentSnapshotTests {
  @Test("resolvedStyle honors the ambient foreground and tint overrides")
  func resolvedStyleHonorsAmbientOverrides() {
    let plain = StyleEnvironmentSnapshot()
    #expect(plain.resolvedStyle(for: .foreground) == plain.theme.style(for: .foreground))
    #expect(plain.resolvedStyle(for: .tint) == plain.theme.style(for: .tint))

    let ambient = StyleEnvironmentSnapshot(
      foregroundStyle: AnyShapeStyle(Color.red),
      tintStyle: AnyShapeStyle(Color.yellow)
    )
    #expect(ambient.resolvedStyle(for: .foreground) == AnyShapeStyle(Color.red))
    #expect(ambient.resolvedStyle(for: .tint) == AnyShapeStyle(Color.yellow))
    #expect(ambient.resolvedStyle(for: .background) == ambient.theme.style(for: .background))
  }
}
