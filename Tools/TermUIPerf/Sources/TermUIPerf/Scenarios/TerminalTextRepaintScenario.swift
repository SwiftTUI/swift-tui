@_spi(Runners) import SwiftTUI

/// Full-row terminal encoding after a real input-driven repaint. Run
/// with SWIFTTUI_PERF_EMISSION=1 to include the terminal planner and encoder.
/// The mixed fixture has twelve linked cells per 120-cell row; the plain
/// fixture isolates batching work without URL sanitization.
public struct TerminalTextRepaintScenario: PerfScenario {
  public let linked: Bool
  public var name: PerfScenarioName {
    linked ? .terminalTextRepaintMixed : .terminalTextRepaintPlain
  }
  public let defaultTerminalSize = PerfTerminalSize(columns: 120, rows: 42)
  public let scriptedEvents = ["repaint forty text rows eight times through a button"]
  public let visualMarkers = ["terminal repaint 0"]
  public let settlingDescription = "the exact numbered frame after each repaint"

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(scenario: self, options: options) {
      TerminalTextRepaintView(linked: linked)
    } drive: { driver in
      var previous = try await driver.waitForFrame(containing: "terminal repaint 0").frameNumber
      let button = try driver.cell(containing: "repaint text")
      var events: [PerfEventRecord] = []
      for pass in 1...8 {
        let dispatched = monotonicSeconds()
        driver.sendClick(at: button)
        let marker = "terminal repaint \(pass)"
        let frame = try await driver.waitForFrame(containing: marker, afterFrame: previous)
        previous = frame.frameNumber
        events.append(
          PerfEventRecord(
            eventID: "terminal-repaint-\(pass)", eventType: "terminal_repaint",
            dispatchTimeSeconds: dispatched, expectedVisualMarker: marker,
            firstMatchingFrame: frame.frameNumber, firstMatchingTimeSeconds: frame.timestampSeconds,
            finalSettledFrame: frame.frameNumber, finalSettledTimeSeconds: frame.timestampSeconds))
      }
      return events
    }
  }
}

private struct TerminalTextRepaintView: View {
  let linked: Bool
  @State private var pass = 0

  private static let destination = "https://example.test/" + String(repeating: "a", count: 108)
  private static let plain = Text(String(repeating: ".", count: 120))
  // Links own their foreground style, so changing the surrounding Text's
  // color alone leaves them clean. Change every linked glyph as well to
  // ensure the measured incremental frame actually encodes its hyperlinks.
  private static let mixedEven = Text(
    "\(Link("aaaaaaaaaaaa", destination: .init(destination)))\(String(repeating: ".", count: 108))")
  private static let mixedOdd = Text(
    "\(Link("bbbbbbbbbbbb", destination: .init(destination)))\(String(repeating: ".", count: 108))")

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("repaint text") { pass += 1 }
        .buttonStyle(TerminalRepaintButtonStyle())
      Text("terminal repaint \(pass)")
      ForEach(0..<40) { _ in
        (linked ? (pass.isMultiple(of: 2) ? Self.mixedEven : Self.mixedOdd) : Self.plain)
          .foregroundStyle(pass.isMultiple(of: 2) ? Color.red : Color.blue)
          .frame(width: 120, height: 1, alignment: .leading)
      }
    }
  }
}

/// Keep button down/up paint invariant so input coalescing cannot change
/// emitted byte counts for the measured text repaints.
private struct TerminalRepaintButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}
