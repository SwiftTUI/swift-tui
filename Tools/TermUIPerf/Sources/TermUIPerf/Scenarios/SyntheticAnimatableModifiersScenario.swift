import SwiftTUI

/// Measures 64 `Animatable` view modifiers that tick together (STUI-1546).
///
/// The tree is the one `synthetic-single-tween` uses: a button, a state line
/// and 176 one-line rows in one `VStack`. Where the tween has one opacity, the
/// first 64 rows here each carry a modifier that conforms to `Animatable`. One
/// click changes the `animatableData` of all 64 under one `withAnimation`, so
/// every tick evaluates 64 modifier bodies again, and each body builds a new
/// string from its sample. A tick of the tween resolves no view at all; the
/// difference between the two scenarios is the cost of that re-evaluation.
///
/// The default terminal is 70 rows high, so that all 64 meters are on screen
/// and every sample of every meter is drawn and presented. Run with
/// `--terminal-size 80x40` for the tween's window, which shows 36 of them.
///
/// The file imports `SwiftTUI` with no SPI: the view, the modifier and the
/// drive use public API only, as an application would.
public struct SyntheticAnimatableModifiersScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticAnimatableModifiers
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 70)
  public let scriptedEvents = [
    "click start meters; observe 64 Animatable modifiers through one finite animation"
  ]
  public let visualMarkers = ["meter state 0"]
  public let settlingDescription = "first frame in which a meter shows its target value"

  /// The row count of `synthetic-single-tween`, so the two trees compare.
  static let rowCount = 176
  static let modifierCount = 64
  /// The duration of the single tween, at about thirty frames a second.
  static let animationDuration = Duration.milliseconds(1500)

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfAnimatableModifiersProbeView(
        modifierCount: Self.modifierCount,
        rowCount: Self.rowCount
      )
    } drive: { driver in
      try await Self.drive(driver)
    }
  }

  @MainActor
  static func drive(_ driver: PerfScenarioDriver) async throws -> [PerfEventRecord] {
    _ = try await driver.waitForFrame(containing: "meter state 0")
    let dispatchTime = monotonicSeconds()
    let frameBeforeClick = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
    let cell = try driver.cell(containing: "start meters")
    driver.sendClick(at: cell)
    let started = try await driver.waitForFrame(
      containing: "meter state 1",
      afterFrame: frameBeforeClick
    )
    // Sleep through the animation and look for its last frame afterwards. A
    // wait for that frame polls a thousand times a second, and over the whole
    // animation the run would charge that CPU time to the frames it measures.
    try await Task.sleep(for: animationDuration)
    // The frame of the click draws every meter at the value it had. The
    // animation has ended when a meter shows exactly its target. That frame
    // must come after the frame of the click: if the meters snapped, the two
    // would be one frame and this wait fails, so a run that does not animate
    // reports an error and not a measurement.
    let settled = try await driver.waitForFrame(
      containing: meterLabel(row: 0, cells: meterLength(row: 0)),
      afterFrame: started.frameNumber
    )
    return [
      PerfEventRecord(
        eventID: "synthetic-animatable-modifiers",
        eventType: "mouse_click",
        dispatchTimeSeconds: dispatchTime,
        expectedVisualMarker: "meter state 1",
        firstMatchingFrame: started.frameNumber,
        firstMatchingTimeSeconds: started.timestampSeconds,
        finalSettledFrame: settled.frameNumber,
        finalSettledTimeSeconds: settled.timestampSeconds
      )
    ]
  }

  /// The length a row's meter grows to, in cells. Rows differ, so the 64
  /// modifiers hold 32 different targets.
  static func meterLength(row: Int) -> Double {
    Double(16 + row % 32)
  }

  /// The start of the line a meter row draws for a sample of `cells`: its
  /// title and the sample in hundredths of a cell.
  static func meterLabel(row: Int, cells: Double) -> String {
    "meter row \(row) |\(meterHundredths(cells))|"
  }

  static func meterHundredths(_ cells: Double) -> Int {
    max(0, Int((cells * 100).rounded()))
  }
}

struct PerfAnimatableModifiersProbeView: View {
  let modifierCount: Int
  let rowCount: Int

  @State private var raised = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("start meters") {
        withAnimation(.linear(duration: SyntheticAnimatableModifiersScenario.animationDuration)) {
          raised.toggle()
        }
      }
      Text("meter state \(raised ? 1 : 0)")
      ForEach(Array(0..<modifierCount), id: \.self) { row in
        Text("meter row \(row)")
          .modifier(
            PerfMeterModifier(
              cells: raised ? SyntheticAnimatableModifiersScenario.meterLength(row: row) : 0
            ))
      }
      ForEach(Array(modifierCount..<rowCount), id: \.self) { row in
        Text("static row \(row)")
      }
    }
    .padding(1)
  }
}

/// Draws a meter after its one-line content: the sample in hundredths of a
/// cell, then one `#` for each whole cell. The readout changes with every
/// sample, and the bar changes the width of the row, so a tick resolves, lays
/// out and draws each row again.
private struct PerfMeterModifier: ViewModifier, Animatable {
  var cells: Double

  nonisolated var animatableData: Double {
    get { cells }
    set { cells = newValue }
  }

  func body(content: Content) -> some View {
    let hundredths = SyntheticAnimatableModifiersScenario.meterHundredths(cells)
    HStack(spacing: 0) {
      content
      Text(" |\(hundredths)| " + String(repeating: "#", count: hundredths / 100))
    }
  }
}
