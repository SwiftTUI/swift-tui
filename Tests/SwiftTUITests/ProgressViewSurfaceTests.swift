import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
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
extension ProgressViewSurfaceTests {
  @Test("T249: indeterminate progress advances while idle and cancels on removal")
  func indeterminateProgressAdvancesAndCancels() async throws {
    let harness = try AnimatorRuntimeHarness(size: .init(width: 24, height: 5)) {
      ProgressTickFixture()
    }
    defer { harness.shutdown() }
    let initial = harness.frame
    #expect(harness.activeTaskCount == 1)
    try await harness.wait(until: { harness.frame != initial }, timeout: .seconds(3))
    #expect(harness.frame.contains("█"))
    try harness.clickText("Remove")
    #expect(harness.activeTaskCount == 0)
    let framesAfterRemoval = harness.frameRecords.count
    try await harness.hold(for: .milliseconds(250))
    #expect(harness.frameRecords.count == framesAfterRemoval)
  }

  @Test("T249: determinate and reduced-motion progress have no tick task")
  func inactiveProgressHasNoTask() throws {
    let determinate = try AnimatorRuntimeHarness {
      ProgressView(value: 1, total: 2)
    }
    defer { determinate.shutdown() }
    #expect(determinate.activeTaskCount == 0)
    let reduced = try AnimatorRuntimeHarness(motion: .reduced) {
      ProgressView("Loading")
    }
    defer { reduced.shutdown() }
    #expect(reduced.activeTaskCount == 0)
    #expect(reduced.frame.contains("Loading"))
  }
}

private struct ProgressTickFixture: View {
  @State private var visible = true

  var body: some View {
    VStack(alignment: .leading) {
      Button("Remove") { visible = false }
      if visible {
        ProgressView(barWidth: 12)
      }
    }
  }
}
