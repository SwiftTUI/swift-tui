import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import TermUIPerf

/// Checks benchmark output and repaint input through the ordinary composed runtime.
struct TextClippingScenarioTests {
  /// Verifies clipping, Unicode spans, and hyperlink preservation through the composed pipeline.
  /// - Parameters:
  ///   - painter: Literal or link-bearing authored text.
  ///   - position: First or middle document rows selected by the viewport.
  @Test(
    "text-clipping scenarios retain source rows and Unicode cells",
    arguments: TextClippingScenario.Painter.allCases, TextClippingScenario.Position.allCases)
  @MainActor
  func visibleOutput(
    painter: TextClippingScenario.Painter, position: TextClippingScenario.Position
  ) {
    let scenario = TextClippingScenario(painter: painter, position: position)
    let snapshot = DefaultRenderer().render(
      scenario.makeColdRoot(), proposal: ProposedSize(width: 24, height: 10))
    let surface = snapshot.rasterSurface
    let firstRow = position == .middle ? 1_000 : 0
    #expect(surface.size == CellSize(width: 24, height: 10))
    #expect(
      Array(surface.lines.dropFirst(2))
        == (firstRow..<(firstRow + 8)).map {
          "row \($0): a界 é"
        })
    for row in surface.cells.dropFirst(2) {
      #expect(row.dropFirst(16).allSatisfy { $0 == .empty })
      #expect(row.contains { $0.character == "é" })
      let lead = row.firstIndex { $0.character == "界" }
      if let lead {
        #expect(row[lead].spanWidth == 2)
        #expect(row[lead + 1].continuationLeadX == lead)
      } else {
        Issue.record("wide glyph missing from clipped text")
      }
      #expect(row[0].hyperlink == (painter == .rich ? "https://example.com/text" : nil))
    }
  }

  /// Uses each registered member's measurement toggle to pin eight lines plus two controls.
  /// - Parameters:
  ///   - painter: Literal or link-bearing text measured by the cold lane.
  ///   - position: Small control or tall document placement relative to the clip.
  /// - Throws: An expectation failure for a missing member or a cold-lane error if counters drift.
  @Test(
    "text clipping cold lanes visit only viewport lines and controls",
    arguments: TextClippingScenario.Painter.allCases, TextClippingScenario.Position.allCases)
  @MainActor
  func coldLineVisits(
    painter: TextClippingScenario.Painter, position: TextClippingScenario.Position
  ) throws {
    let scenario = TextClippingScenario(painter: painter, position: position)
    let member = try #require(BenchSuite.member(named: scenario.name))
    #expect(member.recordsTextLineVisits)
    let report = try BenchColdLane.run(member, iterations: 4)
    #expect(report.counters.textLineVisits == 10)
    #expect(report.counters.valuesByName["text_line_visits"] == 10)
  }

  /// Leaves traversal absent when an untoggled member runs the same clipping workload.
  /// - Throws: A cold-lane error if any measured work varies across fresh renders.
  @Test("text line measurement defaults off in benchmark metadata")
  @MainActor
  func lineVisitToggle() throws {
    let scenario = TextClippingScenario(painter: .plain, position: .visible)
    let member = BenchMember(
      scenario: scenario.name, warmModes: [.sync], warmSyncRatchets: false)
    #expect(!member.recordsTextLineVisits)
    let report = try BenchColdLane.run(member, iterations: 4)
    #expect(report.counters.textLineVisits == nil)
    #expect(report.counters.valuesByName["text_line_visits"] == nil)
  }

  /// Preserves measured zero and the absence of text counts in historical artifacts.
  /// - Throws: An artifact encoding or decoding error if the optional metric cannot round-trip.
  @Test("text line counters round-trip without inventing historical zeros")
  func lineVisitArtifacts() throws {
    let unmeasured = PerfDeterministicCounters()
    let historical = try JSONEncoder().encode(unmeasured)
    let decoded = try JSONDecoder().decode(PerfDeterministicCounters.self, from: historical)
    #expect(decoded.textLineVisits == nil)
    #expect(decoded.valuesByName["text_line_visits"] == nil)
    var measured = unmeasured
    measured.textLineVisits = 0
    let encoded = try JSONEncoder().encode(measured)
    #expect(String(decoding: encoded, as: UTF8.self).contains("\"text_line_visits\":0"))
    #expect(try JSONDecoder().decode(PerfDeterministicCounters.self, from: encoded) == measured)
  }

  /// Ensures hidden hyperlink bounds cannot swallow the benchmark's repaint clicks.
  /// - Parameter mode: Standard synchronous or asynchronous runtime rendering.
  /// - Throws: Runner, artifact, or frame-marker errors when an input fails to complete.
  @Test(
    "middle-document links leave repaint controls usable",
    arguments: [
      RuntimeRenderMode.sync, .async,
    ])
  @MainActor
  func richMiddleRepaints(mode: RuntimeRenderMode) async throws {
    let artifacts = FileManager.default.temporaryDirectory
      .appendingPathComponent("text-clipping-scenario-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: artifacts) }
    let result = try await TextClippingScenario(painter: .rich, position: .middle).run(
      options: PerfScenarioRunOptions(
        renderMode: mode, iterations: 1, artifactRoot: artifacts,
        configuration: PerfBuildConfiguration.detected, memoryIdleWindow: .zero))
    #expect(result.events.count == 6)
    #expect(result.events.last?.expectedVisualMarker == "clip phase 6")
    #expect(result.presentedFrameCount >= 7)
  }
}
