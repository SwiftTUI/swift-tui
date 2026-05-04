import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
struct ProgressViewSurfaceTests {
  @Test("ProgressView renders an indeterminate loading bar without a numeric summary")
  func indeterminateProgressViewRendersLoadingBar() {
    let artifacts = DefaultRenderer().render(
      ProgressView(barWidth: 8),
      context: .init(identity: testIdentity("Progress"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("█"))
    #expect(surface.contains("─"))
    #expect(!surface.contains("/"))
  }

  @Test("ProgressView keeps an indeterminate label visible")
  func indeterminateProgressViewKeepsLabelVisible() {
    let artifacts = DefaultRenderer().render(
      ProgressView("Loading", barWidth: 8),
      context: .init(identity: testIdentity("Loading"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Loading"))
    #expect(surface.contains("█"))
    #expect(!surface.contains("/"))
  }

  @Test("ProgressView supports an indeterminate builder label")
  func indeterminateProgressViewSupportsBuilderLabel() {
    let artifacts = DefaultRenderer().render(
      ProgressView(barWidth: 8) {
        Text("Buffering")
      },
      context: .init(identity: testIdentity("Buffering"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Buffering"))
    #expect(surface.contains("█"))
    #expect(!surface.contains("/"))
  }

  @Test("ProgressView still renders determinate progress summaries")
  func determinateProgressViewStillRendersSummary() {
    let artifacts = DefaultRenderer().render(
      ProgressView("Sync", value: 3, total: 4, barWidth: 8),
      context: .init(identity: testIdentity("Sync"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Sync"))
    #expect(surface.contains("3/4"))
    #expect(surface.contains("█"))
  }
}
