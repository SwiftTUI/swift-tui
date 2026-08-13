import Observation
@_spi(Runners) import SwiftTUI

/// `bench-storm` (plan 2026-08-11-005 D2): everything at once. A 200-row
/// keyed list under a chrome header carrying a `.repeatForever` shimmer
/// segment and eight live counter readouts; an off-main writer marshals all
/// eight counters onto the main actor at 250 Hz for 3 s while 60 Hz wheel
/// notches inject OPEN LOOP over the list. Scheduler merge pressure,
/// animation injection, coalescing, and input latency under backlog — plan
/// 003's storm vehicle.
///
/// Latency is read from the runtime's own `input_to_commit_*` columns and
/// `presents.tsv`, never from per-notch marker waits (that would close the
/// loop). **Async modes only**: under `--mode sync` the frame driver drains
/// to quiescence inside the injection task's suspension points and the drive
/// stops being open-loop — see `ScrollCadence60HzScenario`'s header. The
/// suite runs this member async, and its counters never ratchet (D4): its
/// frame census depends on scheduling by design.
public struct BenchStormScenario: PerfScenario {
  public let name: PerfScenarioName = .benchStorm
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 40)
  public let scriptedEvents = [
    "8 observable counters marshaled at 250 Hz for 3 s + 180 open-loop wheel notches at 60 Hz"
  ]
  public let visualMarkers = ["wrow 0"]
  public let settlingDescription = "first frame showing the storm list's first row"

  /// The tree shape is PINNED (it feeds the cold lane and the committed
  /// report); only the drive intensity below is env-tunable, so the smoke
  /// sweep can stay a wiring check.
  static let rowCount = 200
  /// 3 s at 250 Hz by default; `SWIFTTUI_PERF_STORM_WRITER_TICKS` overrides.
  static let defaultWriterTicks = 750
  static let writerCadence = Duration.milliseconds(4)
  /// 3 s at 60 Hz by default; `SWIFTTUI_PERF_STORM_NOTCHES` overrides.
  static let defaultNotchCount = 180
  static let notchCadence = Duration.microseconds(16_600)

  public init() {}

  static func resolvedWriterTicks() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_STORM_WRITER_TICKS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultWriterTicks
    }
    return parsed
  }

  static func resolvedNotchCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_STORM_NOTCHES"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultNotchCount
    }
    return parsed
  }

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let model = PerfStormModel()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfStormView(model: model, rowCount: Self.rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "wrow 0", timeout: .seconds(60))
      let scrollCell = try driver.cell(containing: "wrow 2")
      let writerTicks = Self.resolvedWriterTicks()
      let notchCount = Self.resolvedNotchCount()

      let dispatch = monotonicSeconds()
      // The off-main writer: a detached task that MARSHALS every mutation
      // onto the main actor — observed `@Observable` state must be mutated
      // on main (the runtime's fail-loud contract); "off-main" is where the
      // cadence lives, not where the writes land.
      let writer = Task.detached(priority: .userInitiated) {
        for tick in 1...writerTicks {
          try? await Task.sleep(for: Self.writerCadence)
          await model.advance(tick)
        }
      }
      await driver.driveScroll(
        cadence: Self.notchCadence,
        notches: notchCount,
        at: scrollCell
      )
      await writer.value
      // The settle tail is part of the storm's cost: everything the burst
      // left queued lands inside the measured window.
      await driver.waitForQuiescence(idle: .milliseconds(400), timeout: .seconds(60))
      let settled = driver.terminalHost.presentedFrames.last

      return [
        PerfEventRecord(
          eventID: "bench-storm-burst",
          eventType: "scroll",
          dispatchTimeSeconds: dispatch,
          expectedVisualMarker: "<open-loop storm; see runtime latency columns>",
          firstMatchingFrame: settled?.frameNumber,
          firstMatchingTimeSeconds: settled?.timestampSeconds,
          finalSettledFrame: settled?.frameNumber,
          finalSettledTimeSeconds: settled?.timestampSeconds
        )
      ]
    }
  }
}

extension BenchStormScenario: BenchColdRenderable {
  /// Cold-renders the full storm scene at rest: model at tick 0, no writer,
  /// no notches — construction + first layout of the same tree the warm
  /// storm churns.
  func makeColdRoot() -> PerfStormView {
    PerfStormView(model: PerfStormModel(), rowCount: Self.rowCount)
  }
}

/// `@MainActor` (and therefore Sendable): the off-main writer holds the
/// cadence, but every mutation lands on the main actor — observed
/// `@Observable` state must be mutated on main (the runtime's fail-loud
/// contract).
@Observable
@MainActor
final class PerfStormModel {
  var counters = [Int](repeating: 0, count: 8)

  /// One writer tick: all eight counters move, so every readout in the
  /// chrome is invalidated on every tick.
  func advance(_ tick: Int) {
    for index in counters.indices {
      counters[index] = tick &+ index
    }
  }
}

struct PerfStormView: View {
  let model: PerfStormModel
  let rowCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text("bench-storm")
          .foregroundStyle(.tint)
        Text("shimmer")
        Spinner()
      }
      HStack(spacing: 1) {
        ForEach(0..<8, id: \.self) { index in
          Text("c\(index) \(model.counters[index])")
        }
      }
      List(0..<rowCount, id: \.self) { index in
        HStack(spacing: 1) {
          Text("wrow \(index)")
          Spacer(minLength: 1)
          Text("meta \(index % 89)")
            .foregroundStyle(.separator)
        }
      }
      .frame(height: 32)
      .border(.separator)
    }
    .padding(1)
  }
}
