import Foundation
import SwiftTUICore
import Testing

@_spi(Runners) @testable import SwiftTUIProfiling
@_spi(Runners) @testable import SwiftTUIRuntime

/// `presents.tsv`: the sibling artifact that carries write completion, which
/// cannot ride the frame row because it happens after commit on the writer's
/// own queue.
@Suite
struct PresentationWriteTSVSinkTests {
  @Test("The sink writes one header then one row per submission")
  func writesHeaderAndRows() throws {
    let path = Self.temporaryPath()
    let sink = try #require(PresentationWriteTSVSink(path: path))

    let submittedAt = MonotonicInstant(offset: .milliseconds(1_000))
    sink.record(
      PresentationWriteSample(
        frame: 7,
        submittedAt: submittedAt,
        writtenAt: submittedAt.advanced(by: .microseconds(2_500)),
        bytes: 4_096,
        outcome: .written
      )
    )
    sink.record(
      PresentationWriteSample(
        frame: 8,
        submittedAt: submittedAt.advanced(by: .milliseconds(3)),
        writtenAt: nil,
        bytes: 128,
        outcome: .superseded
      )
    )

    let lines = try String(contentsOfFile: path, encoding: .utf8)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map(String.init)
    #expect(lines.count == 3)
    #expect(lines[0] == PresentationWriteTSVSink.headerFields.joined(separator: "\t"))

    let written = lines[1].split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    #expect(written == ["7", "1000.00", "1002.50", "2.50", "4096", "written"])

    let superseded = lines[2].split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    // A superseded submission has no completion instant and no write duration,
    // but it still occupies a row so the join by `frame` stays total.
    #expect(superseded == ["8", "1003.00", "-", "-", "128", "superseded"])
  }

  @Test("The presents file is a fixed-name sibling of the frames file")
  func derivesSiblingPath() {
    #expect(
      ProfileActivation.presentsPath(besideFramesPath: "/tmp/run-17/frames.tsv")
        == "/tmp/run-17/presents.tsv"
    )
    // The name is fixed rather than derived from the frames file, so a reducer
    // can find it without knowing what the operator called the frames file.
    #expect(
      ProfileActivation.presentsPath(besideFramesPath: "/tmp/run-17/whatever.tsv")
        == "/tmp/run-17/presents.tsv"
    )
    #expect(ProfileActivation.presentsPath(besideFramesPath: "frames.tsv") == "presents.tsv")
  }

  private static func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("presents-\(UUID().uuidString).tsv")
      .path
  }
}
