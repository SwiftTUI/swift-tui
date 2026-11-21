import SwiftTUI

/// Measures a custom `Transition` that wipes a panel in and out through an
/// `Animatable` clip shape (STUI-1544, STUI-1545, STUI-1546).
///
/// The panel is 24 rows of 80 columns of text. Its transition clips it with a
/// shape whose `animatableData` goes from 0 to 1 on insertion and back on
/// removal, so `path(in:)` runs for every sample and each tick uncovers or
/// covers a few more columns of all 24 rows. One run inserts the panel, waits
/// for the insertion to end, removes it and waits for the removal to end,
/// three times.
///
/// Each insertion and each removal is one event. Its first matching frame is
/// the frame that starts the transition, the frame in which `panel state`
/// changes, so `events.tsv` names the start frames in `frames.tsv`.
///
/// The file imports `SwiftTUI` with no SPI: the view, the transition, the
/// shape and the drive use public API only, as an application would.
public struct SyntheticCustomTransitionScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticCustomTransition
  public let defaultTerminalSize = PerfTerminalSize(
    columns: Self.panelColumns,
    rows: Self.panelRows + 2
  )
  public let scriptedEvents = [
    "click toggle panel; observe a wipe insertion, then a wipe removal; three times"
  ]
  public let visualMarkers = ["panel state 0"]
  public let settlingDescription = "first frame that shows the panel whole, or not at all"

  static let panelColumns = 80
  static let panelRows = 24
  static let cycleCount = 3
  static let transitionDuration = Duration.milliseconds(800)

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let progress = PerfTransitionProgress()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfCustomTransitionProbeView(progress: progress)
    } drive: { driver in
      try await Self.drive(driver, progress: progress)
    }
  }

  @MainActor
  static func drive(
    _ driver: PerfScenarioDriver,
    progress: PerfTransitionProgress
  ) async throws -> [PerfEventRecord] {
    _ = try await driver.waitForFrame(containing: "panel state 0")
    var events: [PerfEventRecord] = []
    for cycle in 1...cycleCount {
      events.append(
        try await toggle(driver, progress: progress, inserting: true, cycle: cycle))
      events.append(
        try await toggle(driver, progress: progress, inserting: false, cycle: cycle))
    }
    return events
  }

  @MainActor
  private static func toggle(
    _ driver: PerfScenarioDriver,
    progress: PerfTransitionProgress,
    inserting: Bool,
    cycle: Int
  ) async throws -> PerfEventRecord {
    let stateMarker = "panel state \(inserting ? 1 : 0)"
    let completedBefore = progress.completedTransitions
    let frameBeforeClick = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
    let dispatchTime = monotonicSeconds()
    let cell = try driver.cell(containing: "toggle panel")
    driver.sendClick(at: cell)
    let started = try await driver.waitForFrame(
      containing: stateMarker,
      afterFrame: frameBeforeClick
    )
    // Sleep through the transition and look for its end afterwards. The
    // waits below poll a thousand times a second, and over the whole
    // transition the run would charge that CPU time to the frames it measures.
    try await Task.sleep(for: transitionDuration)
    // The completion of `withAnimation` is the end of the transition. A frame
    // can show the panel whole one tick before that, when the last sample
    // before the end already rounds to the full width, so the frame alone
    // would let the next click interrupt this transition.
    try await waitForCompletedTransitions(completedBefore + 1, in: progress)
    // The last frame of the transition must come after the frame that started
    // it. If the transition snapped, the two would be one frame and this wait
    // fails, so a run that does not animate reports an error and not a
    // measurement.
    let settled =
      inserting
      ? try await driver.waitForFrame(
        containing: panelLine(0),
        afterFrame: started.frameNumber
      )
      : try await driver.waitForFrame(
        notContaining: String(panelLeadingEdge),
        afterFrame: started.frameNumber
      )
    return PerfEventRecord(
      eventID: "synthetic-custom-transition-\(inserting ? "insert" : "remove")-\(cycle)",
      eventType: "mouse_click",
      dispatchTimeSeconds: dispatchTime,
      expectedVisualMarker: stateMarker,
      firstMatchingFrame: started.frameNumber,
      firstMatchingTimeSeconds: started.timestampSeconds,
      finalSettledFrame: settled.frameNumber,
      finalSettledTimeSeconds: settled.timestampSeconds
    )
  }

  @MainActor
  private static func waitForCompletedTransitions(
    _ count: Int,
    in progress: PerfTransitionProgress
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(30))
    while progress.completedTransitions < count {
      guard clock.now < deadline else {
        throw PerfScenarioError.markerTimedOut("<completion of transition \(count)>")
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  /// The first and the last character of every panel row. Nothing else on
  /// screen uses them, and no cell between them is blank, so the number of
  /// panel cells a frame shows in a row is the width of the wipe.
  static let panelLeadingEdge: Character = "{"
  static let panelTrailingEdge: Character = "}"

  /// One row of the panel: exactly `panelColumns` characters, none blank.
  static func panelLine(_ row: Int) -> String {
    let filler = Array("the.quick.brown.fox.jumps.over.the.lazy.dog.")
    var line = "\(panelLeadingEdge)panel.row.\(row < 10 ? "0" : "")\(row)."
    var index = row * 7
    while line.count < panelColumns - 1 {
      line.append(filler[index % filler.count])
      index += 1
    }
    line.append(panelTrailingEdge)
    return line
  }
}

/// Counts the transitions that have ended. The view's `withAnimation`
/// completion writes it and the drive reads it. It is not view state, so a
/// completion causes no frame.
@MainActor
final class PerfTransitionProgress {
  var completedTransitions = 0
}

struct PerfCustomTransitionProbeView: View {
  let progress: PerfTransitionProgress

  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("toggle panel") {
        withAnimation(.linear(duration: SyntheticCustomTransitionScenario.transitionDuration)) {
          shown.toggle()
        } completion: {
          progress.completedTransitions += 1
        }
      }
      Text("panel state \(shown ? 1 : 0)")
      if shown {
        PerfTransitionPanel()
          .transition(PerfWipeTransition())
      }
    }
    // Pinned to the top, so the button and the state line keep their cells
    // when the panel comes and goes.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct PerfTransitionPanel: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(0..<SyntheticCustomTransitionScenario.panelRows), id: \.self) { row in
        Text(SyntheticCustomTransitionScenario.panelLine(row))
      }
    }
  }
}

/// Uncovers its content from the leading edge on insertion and covers it
/// again on removal.
private struct PerfWipeTransition: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(PerfWipeShape(progress: phase.isIdentity ? 1 : 0))
  }
}

/// The leading `progress` of its rectangle.
private struct PerfWipeShape: Shape, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: Rect) -> Path {
    let open = max(0, min(1, progress))
    return Path(
      Rect(
        origin: rect.origin,
        size: Size(width: rect.size.width * open, height: rect.size.height)
      ))
  }
}
