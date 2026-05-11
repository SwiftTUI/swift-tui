import SwiftTUI
import SwiftTUIArguments
import SwiftTUICLI
import SwiftTUICharts
import Testing

@testable import GitViz

@MainActor
struct RenderOnceSmokeTests {
  /// Smoke-test that pipes a tiny `BulletChart` (smallest chart shape) through
  /// `RenderOnce.render` and verifies the resulting cell buffer has the right
  /// height, contains the title, and has no ANSI escapes (no-color mode).
  @Test("RenderOnce + BulletChart produces deterministic plain-text output")
  func bulletChartSmoke() throws {
    let view = ChartCard(title: "Pulse smoke") {
      BulletChart(
        "Commits this week vs target",
        value: 3,
        target: 5,
        total: 10,
        tone: .info
      )
    }
    let options = try SwiftTUIOptions.parse(["--no-color", "--ascii"])
    let output = RenderOnce.render(
      view,
      width: 40,
      options: options,
      environment: [:],
      isStdoutTTY: false
    )

    #expect(output.contains("Pulse smoke"))
    #expect(output.contains("Commits this week"))
    // No ANSI SGR escapes anywhere in the rendered output (no-color mode).
    #expect(!output.contains("\u{001B}["))
    // The rendered surface should be at least 4 rows tall (title +
    // divider + chart + label).
    let rows = output.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(rows.count >= 4)
  }
}
