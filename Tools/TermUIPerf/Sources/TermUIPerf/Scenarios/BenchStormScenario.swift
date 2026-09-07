import Observation
@_spi(Runners) import SwiftTUI

/// `bench-storm` (plan 2026-08-11-005 D2): everything at once. A 200-row
/// keyed list under a chrome header carrying a perpetual Spinner and eight
/// live counter readouts. An off-main writer delays 4 ms before marshaling
/// each of 750 updates onto the main actor; 180 wheel notches are injected
/// open loop with a 16.6 ms delay after each send. Scheduling adds to those
/// delays, so these are not guaranteed 250 Hz/60 Hz arrivals under backlog.
/// Scheduler merge pressure,
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
    "750 updates of 8 observable counters after 4 ms delays + 180 open-loop wheel notches with 16.6 ms delays"
  ]
  public let visualMarkers = ["wrow 0"]
  public let settlingDescription =
    "one frame containing all final counter values and the expected last visible row"

  /// The tree shape is PINNED (it feeds the cold lane and the committed
  /// report); only the drive intensity below is env-tunable, so the smoke
  /// sweep can stay a wiring check.
  static let rowCount = 200
  /// 750 updates, each delayed by 4 ms; `SWIFTTUI_PERF_STORM_WRITER_TICKS` overrides.
  static let defaultWriterTicks = 750
  static let writerCadence = Duration.milliseconds(4)
  /// 180 notches, each followed by a 16.6 ms delay; `SWIFTTUI_PERF_STORM_NOTCHES` overrides.
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
    try await run(
      options: options,
      writerTicks: Self.resolvedWriterTicks(),
      notchCount: Self.resolvedNotchCount()
    )
  }

  @MainActor
  func run(
    options: PerfScenarioRunOptions,
    writerTicks: Int,
    notchCount: Int
  ) async throws -> PerfScenarioRunResult {
    precondition(writerTicks > 0 && notchCount > 0)
    let model = PerfStormModel()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfStormView(model: model, rowCount: Self.rowCount)
    } drive: { driver in
      let initial = try await driver.waitForFrame(containing: "wrow 0", timeout: .seconds(60))
      let scrollCell = try driver.cell(containing: "wrow 2")
      let completion = try StormFrameCompletion(
        initialFrame: initial, writerTicks: writerTicks, notchCount: notchCount,
        rowCount: Self.rowCount
      )
      let beforeDispatch = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      let dispatch = monotonicSeconds()
      // The off-main writer: a detached task that MARSHALS every mutation
      // onto the main actor — observed `@Observable` state must be mutated
      // on main (the runtime's fail-loud contract); "off-main" is where the
      // cadence lives, not where the writes land.
      try await Self.withOwnedWriter(
        ticks: writerTicks,
        cadence: Self.writerCadence,
        advance: { model.advance($0) }
      ) {
        try await driver.driveScroll(
          cadence: Self.notchCadence,
          notches: notchCount,
          at: scrollCell
        )
      }
      // A perpetual Spinner cannot become quiescent. Complete only when one
      // presented frame proves both final data and the clamped scroll result.
      // Remaining no-op notches can share an answered-input envelope with a
      // moving notch, or ask for no frame at all; answered counts are not a
      // one-to-one measure of effective movement at the bottom of the list.
      let settled: PerfPresentedFrame
      do {
        settled = try await driver.waitForFrame(
          afterFrame: beforeDispatch,
          timeout: .seconds(60),
          hardCap: .seconds(60),
          description: completion.description,
          matching: completion.matches
        )
      } catch let failure as PerfScenarioError {
        guard case .markerTimedOut = failure else { throw failure }
        let latest = driver.terminalHost.presentedFrames.last
        throw PerfScenarioError.markerTimedOut(
          "\(completion.description)\nModel counters: \(model.counters)\n"
            + "Latest presented frame size: \(String(describing: latest?.surface.size))\n"
            + (latest?.text ?? "<none>")
        )
      }

      return [
        PerfEventRecord(
          eventID: "bench-storm-burst",
          eventType: "scroll",
          dispatchTimeSeconds: dispatch,
          expectedVisualMarker: completion.description,
          firstMatchingFrame: settled.frameNumber,
          firstMatchingTimeSeconds: settled.timestampSeconds,
          finalSettledFrame: settled.frameNumber,
          finalSettledTimeSeconds: settled.timestampSeconds
        )
      ]
    }
  }

  @MainActor
  static func withOwnedWriter(
    ticks: Int,
    cadence: Duration,
    advance: @escaping @MainActor @Sendable (Int) -> Void,
    sleep: @escaping @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    },
    drive: @MainActor () async throws -> Void
  ) async throws {
    let writer = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      for tick in 1...ticks {
        try Task.checkCancellation()
        try await sleep(cadence)
        try Task.checkCancellation()
        try await MainActor.run {
          // Cancellation may arrive while this hop is queued.
          try Task.checkCancellation()
          advance(tick)
        }
      }
    }
    try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        try await drive()
        try Task.checkCancellation()
        try await writer.value
      } catch {
        writer.cancel()
        _ = try? await writer.value
        throw error
      }
    } onCancel: {
      writer.cancel()
    }
  }
}

/// Independent visible-output oracle shared by the full and reduced drives.
struct StormFrameCompletion {
  let counterTokens: [String]
  let expectedBottomRow: Int

  init(initialFrame: PerfPresentedFrame, writerTicks: Int, notchCount: Int, rowCount: Int) throws {
    guard let initialBottom = Self.visibleRows(in: initialFrame).last,
      initialBottom >= 0, initialBottom < rowCount
    else {
      throw PerfScenarioError.markerHasNoCell("wrow <initial bottom>")
    }
    counterTokens = (0..<8).flatMap { ["c\($0)", String(writerTicks &+ $0)] }
    expectedBottomRow = initialBottom + min(notchCount, rowCount - 1 - initialBottom)
  }

  var description: String {
    "\(counterTokens.joined(separator: " ")); last visible wrow \(expectedBottomRow)"
  }

  func matches(_ frame: PerfPresentedFrame) -> Bool {
    frame.text.split(separator: "\n").contains { Self.tokens(in: $0) == counterTokens }
      && Self.visibleRows(in: frame).last == expectedBottomRow
  }

  private static func visibleRows(in frame: PerfPresentedFrame) -> [Int] {
    frame.text.split(separator: "\n").compactMap { line in
      let words = tokens(in: line)
      guard words.count >= 2, words[0] == "wrow" else { return nil }
      return Int(words[1])
    }
  }

  private static func tokens(in line: Substring) -> [String] {
    line.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
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
