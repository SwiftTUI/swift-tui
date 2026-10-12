@_spi(Runners) import SwiftTUI

/// Measures clipped ordinary and link-bearing text through the standard UI benchmark runner.
///
/// Each case retains the original benchmark's numbered Unicode payload, 24-column layout,
/// and 16-by-8 viewport. Cold runs include the full render pipeline; warm runs change the
/// text's opacity to repaint its clipped region without changing its content or wrapping.
struct TextClippingScenario: PerfScenario {
  /// Chooses an authored `Text` representation that reaches a production text painter.
  enum Painter: CaseIterable {
    /// Uses a literal string and the ordinary wrapped-text painter.
    case plain
    /// Uses one hyperlink spanning the payload and the rich-text painter.
    case rich
  }

  /// Chooses the visible source rows while keeping the text's original layout width.
  enum Position: CaseIterable {
    /// Displays an eight-line control with no hidden source rows.
    case visible
    /// Displays the first eight rows of a two-thousand-line document.
    case top
    /// Displays eight rows starting at source line one thousand.
    case middle

    /// Source height; tall cases retain all hidden lines in the authored text.
    var lineCount: Int { self == .visible ? 8 : 2_000 }
    /// Translation applied before the outer viewport clips the text.
    var originY: Int { self == .middle ? -1_000 : 0 }
  }

  /// Text command family selected for both cold and warm runs.
  let painter: Painter
  /// Fixed source height and placement used independently of environment overrides.
  let position: Position

  /// Registered scenario name used by selection, artifacts, and the committed baseline.
  var name: PerfScenarioName {
    switch (painter, position) {
    case (.plain, .visible): .textClippingPlainVisible
    case (.plain, .top): .textClippingPlainTop
    case (.plain, .middle): .textClippingPlainMiddle
    case (.rich, .visible): .textClippingRichVisible
    case (.rich, .top): .textClippingRichTop
    case (.rich, .middle): .textClippingRichMiddle
    }
  }

  /// Accommodates two control rows above the eight-row text viewport.
  let defaultTerminalSize = PerfTerminalSize(columns: 24, rows: 10)
  /// The standard warm runner records six closed-loop repaint inputs.
  let scriptedEvents = ["repaint clipped text six times by alternating its opacity"]
  /// Initial-frame marker outside the clipped document.
  let visualMarkers = ["clip phase 0"]
  /// Each input finishes when the corresponding phase marker is presented.
  let settlingDescription = "first frame showing the requested clip phase"

  /// Configures a fixed workload suitable for the standard cold-counter baseline.
  /// - Parameters:
  ///   - painter: Ordinary or link-bearing text to author.
  ///   - position: Control, top, or middle placement within the document.
  init(painter: Painter, position: Position) {
    self.painter = painter
    self.position = position
  }

  /// Records unchanged-content repaints using the existing window and artifact runner.
  /// - Parameter options: Standard render mode, terminal size, and artifact configuration.
  /// - Returns: Normal scenario artifacts and one event for each completed repaint.
  /// - Throws: Runner, artifact, or frame-marker errors if the scenario cannot complete.
  @MainActor
  func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(scenario: self, options: options) {
      makeColdRoot()
    } drive: { driver in
      var last = try await driver.waitForFrame(containing: "clip phase 0")
      let cell = try driver.cell(containing: "repaint text")
      var events: [PerfEventRecord] = []
      for phase in 1...6 {
        let dispatchTime = monotonicSeconds()
        driver.sendClick(at: cell)
        let marker = "clip phase \(phase)"
        let matching = try await driver.waitForFrame(
          containing: marker, afterFrame: last.frameNumber)
        events.append(
          PerfEventRecord(
            eventID: "text-clipping-repaint-\(phase)", eventType: "mouse_click",
            dispatchTimeSeconds: dispatchTime, expectedVisualMarker: marker,
            firstMatchingFrame: matching.frameNumber,
            firstMatchingTimeSeconds: matching.timestampSeconds,
            finalSettledFrame: matching.frameNumber,
            finalSettledTimeSeconds: matching.timestampSeconds))
        last = matching
      }
      return events
    }
  }
}

/// Supplies the same authored workload to the existing fresh-render benchmark lane.
extension TextClippingScenario: BenchColdRenderable {
  /// Constructs a fresh view with initial opacity and the scenario's pinned payload.
  /// - Returns: A root that can be rendered without a run loop or environment overrides.
  func makeColdRoot() -> TextClippingView {
    TextClippingView(painter: painter, position: position)
  }
}

/// Hosts the full document beneath a small clip so hidden source rows still reach rendering.
struct TextClippingView: View {
  /// Unchanged authored text, built before timing rather than regenerated on repaint.
  private let content: Text
  /// Original document height used for placement before clipping.
  private let lineCount: Int
  /// Vertical translation selecting the first or middle source rows.
  private let originY: Int
  /// Visible input acknowledgement and opacity selector for successive repaint frames.
  @State private var phase = 0

  /// Builds the original numbered payload with wide and combining characters.
  /// - Parameters:
  ///   - painter: Whether every payload character carries a hyperlink.
  ///   - position: Source height and offset relative to the viewport.
  init(painter: TextClippingScenario.Painter, position: TextClippingScenario.Position) {
    lineCount = position.lineCount
    originY = position.originY
    let payload = (0..<lineCount).map { "row \($0): a界 é" }.joined(separator: "\n")
    content =
      painter == .plain
      ? Text(payload) : Text("\(Link(payload, destination: "https://example.com/text"))")
  }

  /// Repaints through the control while the clipped document ignores pointer input.
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("clip phase \(phase)")
      Button("repaint text") { phase += 1 }
      content
        .foregroundStyle(.cyan)
        .opacity(phase.isMultiple(of: 2) ? 1 : 0.9)
        // Preserve the original layout before translating and clipping. Giving the text
        // only eight rows here would avoid the hidden-line workload we intend to measure.
        .frame(width: 24, height: lineCount, alignment: .topLeading)
        .offset(y: originY)
        .frame(width: 16, height: 8, alignment: .topLeading)
        .clipped()
        // Visual clipping leaves semantic bounds unchanged. A middle-document link can
        // overlap the controls, so this display-only payload must not intercept clicks.
        .allowsHitTesting(false)
    }
  }
}
