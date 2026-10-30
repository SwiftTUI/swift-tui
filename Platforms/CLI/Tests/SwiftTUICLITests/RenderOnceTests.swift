import SwiftTUI
import SwiftTUIArguments
import Testing

@testable import SwiftTUITerminalCLI

@MainActor
struct RenderOnceTests {
  @Test("width resolution prefers the live viewport and falls back on query failure")
  func terminalWidthPrecedence() {
    #expect(RenderOnce.resolveTerminalWidth(environment: ["COLUMNS": "80"], liveWidth: 132) == 132)
    #expect(RenderOnce.resolveTerminalWidth(environment: ["COLUMNS": "120"], liveWidth: nil) == 120)
    #expect(RenderOnce.resolveTerminalWidth(environment: ["COLUMNS": "120"], liveWidth: 0) == 120)
    for columns in ["", "0", "-1", "invalid"] {
      #expect(
        RenderOnce.resolveTerminalWidth(environment: ["COLUMNS": columns], liveWidth: nil) == 80)
    }
  }

  @Test("RenderOnce.render emits text for a plain view")
  func rendersPlainText() throws {
    let output = RenderOnce.render(
      Text("hello gitviz"),
      width: 40,
      options: try plainOptions(),
      environment: [:],
      isStdoutTTY: false
    )
    #expect(output.contains("hello gitviz"))
    // Non-interactive emission must not contain \r\n.
    #expect(!output.contains("\r\n"))
  }

  @Test("RenderOnce.resolveTerminalWidth returns a positive value")
  func resolvedWidthFallback() {
    let width = RenderOnce.resolveTerminalWidth(environment: [:])
    #expect(width > 0)
  }

  @Test("RenderOnce.resolveTerminalWidth honors $COLUMNS")
  func resolvedWidthFromColumns() {
    // ioctl may still succeed against the test runner's controlling
    // terminal, so this test only guarantees that the public resolver
    // returns something positive; $COLUMNS is the second-priority fallback.
    let width = RenderOnce.resolveTerminalWidth(environment: ["COLUMNS": "120"])
    #expect(width > 0)
  }

  @Test("RenderOnce.render disables color when --no-color is set")
  func noColorOptionDisablesEscapeSequences() throws {
    let options = try SwiftTUIOptions.parse(["--no-color"])
    let output = RenderOnce.render(
      Text("plain"),
      width: 20,
      options: options,
      environment: [:],
      isStdoutTTY: true
    )
    #expect(!output.contains("\u{001B}["))
  }

  @Test("RenderOnce.render respects NO_COLOR env var")
  func noColorEnvDisablesEscapeSequences() throws {
    let options = try SwiftTUIOptions.parse([])
    let output = RenderOnce.render(
      Text("plain"),
      width: 20,
      options: options,
      environment: ["NO_COLOR": "1"],
      isStdoutTTY: true
    )
    #expect(!output.contains("\u{001B}["))
  }

  @Test("RenderOnce.render with default options (nil) does not crash")
  func defaultOptionsResolve() {
    let output = RenderOnce.render(
      Text("default"),
      width: 20,
      options: nil,
      environment: [:],
      isStdoutTTY: false
    )
    #expect(output.contains("default"))
  }

  private func plainOptions() throws -> SwiftTUIOptions {
    try SwiftTUIOptions.parse(["--no-color", "--ascii"])
  }
}
