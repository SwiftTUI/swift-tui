import Foundation
import SwiftTUI
import Testing

@testable import TermUIPerf

/// `synthetic-animatable-modifiers` and `synthetic-custom-transition` measure
/// the frames of an animation. A run in which the meters or the wipe jumped
/// to their end values would still write its artifacts, and its numbers would
/// describe nothing. These tests read what the scenarios present and fail if
/// the frames between the two ends are missing.
@Suite(.serialized)
struct AnimatableScenarioTests {
  @Test("every meter of the Animatable modifiers scenario presents the samples between its ends")
  @MainActor
  func modifiersScenarioPresentsIntermediateSamples() async throws {
    // The scenario's own view, modifier and drive, over a smaller tree. A
    // debug build presents about ten frames of the whole tree during the
    // animation, and fewer when the machine is busy: too few to count on.
    let modifierCount = 8
    let run = try await presentedFrames(of: SyntheticAnimatableModifiersScenario()) {
      PerfAnimatableModifiersProbeView(modifierCount: modifierCount, rowCount: 2 * modifierCount)
    } drive: { driver in
      try await SyntheticAnimatableModifiersScenario.drive(driver)
    }
    defer { try? FileManager.default.removeItem(at: run.artifactRoot) }

    // What each frame shows for each meter: the sample in hundredths of a
    // cell, and the number of cells the bar has.
    var samples: [Int: [Int]] = [:]
    for text in run.texts {
      for line in text.split(separator: "\n") {
        let fields = line.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3,
          let title = fields.first?.split(separator: " "), title.count == 3,
          title[0] == "meter", title[1] == "row",
          let row = Int(title[2]), let hundredths = Int(fields[1])
        else { continue }
        #expect(fields[2].filter { $0 == "#" }.count == hundredths / 100, "\(line)")
        samples[row, default: []].append(hundredths)
      }
    }

    #expect(samples.count == modifierCount)
    for (row, values) in samples.sorted(by: { $0.key < $1.key }) {
      let target = Int(SyntheticAnimatableModifiersScenario.meterLength(row: row) * 100)
      #expect(values.first == 0 && values.last == target, "row \(row): \(values)")
      #expect(values == values.sorted(), "row \(row): \(values)")
      let between = Set(values.filter { $0 > 0 && $0 < target })
      #expect(between.count >= 3, "row \(row): \(values)")
    }

    // Every frame of the animation evaluated the modifiers again: a frame a
    // deadline woke resolved at least one node for each of them.
    let ticks = try PerfFrameDiagnosticsTSVReader.read(
      from: run.result.runDirectory.appendingPathComponent("frames.tsv"), presentedFrames: []
    ).filter { $0.causes.contains("deadline") && !$0.elided && $0.tailJobState == "completed" }
    #expect(ticks.count >= 3)
    for tick in ticks {
      let resolved = try #require(tick.workCounters.resolvedComputed)
      #expect(resolved >= modifierCount, "frame \(tick.frameNumber)")
    }
    #expect(run.result.events.count == 1)
    let event = try #require(run.result.events.first)
    let first = try #require(event.firstMatchingFrame)
    let last = try #require(event.finalSettledFrame)
    #expect(last > first)
  }

  @Test("the custom transition scenario presents the wipe between its ends, in and out")
  @MainActor
  func transitionScenarioPresentsIntermediateWidths() async throws {
    let progress = PerfTransitionProgress()
    let run = try await presentedFrames(of: SyntheticCustomTransitionScenario()) {
      PerfCustomTransitionProbeView(progress: progress)
    } drive: { driver in
      try await SyntheticCustomTransitionScenario.drive(driver, progress: progress)
    }
    defer { try? FileManager.default.removeItem(at: run.artifactRoot) }

    // The number of columns of the panel each frame shows. No cell of the
    // panel is blank, so the width of a row is the width of the wipe, and
    // the wipe has one edge, so every row has the same width.
    let widths = run.texts.map { text -> Int in
      let rows = text.split(separator: "\n").filter {
        $0.first == SyntheticCustomTransitionScenario.panelLeadingEdge
      }
      let rowWidths = Set(rows.map { $0.filter { $0 != " " }.count })
      #expect(rowWidths.count <= 1, "\(text)")
      #expect(rows.isEmpty || rows.count == SyntheticCustomTransitionScenario.panelRows)
      return rowWidths.first ?? 0
    }

    let columns = SyntheticCustomTransitionScenario.panelColumns
    #expect(run.result.events.count == 2 * SyntheticCustomTransitionScenario.cycleCount)
    #expect(Set(run.result.events.map(\.eventID)).count == run.result.events.count)
    #expect(progress.completedTransitions == run.result.events.count)
    for event in run.result.events {
      let first = try #require(event.firstMatchingFrame)
      let last = try #require(event.finalSettledFrame)
      // Presented frames are numbered from one.
      let wipe = Array(widths[(first - 1)...(last - 1)])
      let inserting = event.eventID.contains("insert")
      #expect(wipe == (inserting ? wipe.sorted() : wipe.sorted(by: >)), "\(event.eventID): \(wipe)")
      #expect(wipe.first == (inserting ? 0 : columns), "\(event.eventID): \(wipe)")
      #expect(wipe.last == (inserting ? columns : 0), "\(event.eventID): \(wipe)")
      let between = Set(wipe.filter { $0 > 0 && $0 < columns })
      #expect(between.count >= 3, "\(event.eventID): \(wipe)")
    }
  }

  private struct PresentedRun {
    var texts: [String]
    var result: PerfScenarioRunResult
    var artifactRoot: URL
  }

  /// Runs `drive` over `content` as `scenario` does, in the render mode the
  /// scenarios are measured in, and returns the text of every presented frame.
  @MainActor
  private func presentedFrames<Content: View>(
    of scenario: any PerfScenario,
    @ViewBuilder content: @escaping @MainActor () -> Content,
    drive: @escaping @MainActor (PerfScenarioDriver) async throws -> [PerfEventRecord]
  ) async throws -> PresentedRun {
    let artifactRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("termui-perf-animatable-\(UUID().uuidString)", isDirectory: true)
    var texts: [String] = []
    do {
      let result = try await PerfScenarioRunner.runWindow(
        scenario: scenario,
        options: PerfScenarioRunOptions(
          renderMode: .async, iterations: 1, artifactRoot: artifactRoot,
          configuration: "debug", cpuSampleInterval: .milliseconds(5), memoryIdleWindow: .zero
        ),
        content: content
      ) { driver in
        let events = try await drive(driver)
        texts = driver.terminalHost.presentedFrames.map(\.text)
        return events
      }
      return PresentedRun(texts: texts, result: result, artifactRoot: artifactRoot)
    } catch {
      try? FileManager.default.removeItem(at: artifactRoot)
      throw error
    }
  }
}
