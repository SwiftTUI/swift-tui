import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUIProfiling
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite(.serialized)
struct ProfilingEncodingContractTests {
  @Test func jsonAndTSVShareTheEntireDiagnosticSchema() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("profile.jsonl")
    let sink = try #require(FileProfileSink(path: path.path, format: .jsonl))
    var record = FrameDiagnosticRecord(frameNumber: 42, causeSummary: "input\r\nnext\tcolumn")
    record.firstCustomLayoutFallbackIdentity = "Root/\u{0}\r\n\towner"
    record.damageTextCellCount = 73
    record.presentationDuration = .microseconds(-250)
    sink.emit(.frame(record))
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    let columns = try #require(object["columns"] as? [String: String])
    let raw = FrameDiagnosticsTSVFormatting.recordFields(for: record)
    #expect(columns.count == FrameDiagnosticsTSVFormatting.headerFields.count)
    for (key, value) in zip(FrameDiagnosticsTSVFormatting.headerFields, raw) {
      #expect(columns[key] == value)
    }
    #expect(columns.values.contains("Root/\u{0}\r\n\towner"))
    let tsv = FrameDiagnosticsTSVFormatting.fields(for: record)
    #expect(tsv.count == columns.count)
    #expect(tsv.allSatisfy { !$0.unicodeScalars.contains { $0.value < 32 } })
    #expect(columns["present_ms"] == "-0.25")
  }

  @Test func durationFormattingCoversTheEntireDurationRange() {
    #expect(
      FrameDiagnosticsTSVFormatting.formatMs(.seconds(Int64.max)) == "9223372036854775807000.00")
    #expect(
      FrameDiagnosticsTSVFormatting.formatMs(.seconds(Int64.min)) == "-9223372036854775808000.00")
    #expect(FrameDiagnosticsTSVFormatting.formatMs(.microseconds(-1_999)) == "-1.99")
    #expect(FrameDiagnosticsTSVFormatting.formatMs(nil) == "-")
  }

  @Test func sidecarsDoNotAliasOtherDestinationsOrDuplicateSameDirectoryWrites() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldFrame = ProfilingRegistry.shared.frameSink
    let oldWrites = ProfilingRegistry.shared.presentationWriteSink
    defer {
      ProfilingRegistry.shared.frameSink = oldFrame
      ProfilingRegistry.shared.presentationWriteSink = oldWrites
    }
    let activation = ProfileActivation()
    defer { activation.finish() }
    let occupied = directory.appendingPathComponent("presents.tsv")
    activation.activateIfNeeded(
      config: .init(
        signals: [.frames],
        sinks: [
          .tsv(path: directory.appendingPathComponent("one.tsv").path),
          .tsv(path: directory.path + "/./two.tsv"),
          .jsonl(path: occupied.path),
        ]))
    // A JSONL destination occupies the conventional name even though it has
    // not emitted a record yet. Completion must select an independent file.
    try #require(ProfilingRegistry.shared.presentationWriteSink).record(
      .init(frame: 8, submittedAt: .zero, writtenAt: .zero, bytes: 3, outcome: .written))
    #expect(try Data(contentsOf: occupied).isEmpty)
    let sidecar = directory.appendingPathComponent("presents.tsv.presents.tsv")
    let lines = try String(contentsOf: sidecar, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines.last?.hasPrefix("8\t") == true)
  }
}
