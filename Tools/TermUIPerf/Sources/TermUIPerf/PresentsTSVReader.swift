import Foundation

/// One terminal write submission, read back from `presents.tsv`.
///
/// Written by the runtime's presentation writer, not by this harness: the
/// `write(2)` that puts a frame's bytes on the wire completes after commit, on
/// the writer's own queue, so it cannot ride the frame row. Joined to
/// `frames.tsv` on `frame`.
public struct PerfPresentRecord: Equatable, Sendable {
  public var frameNumber: Int
  public var submittedMs: Double?
  public var writtenMs: Double?
  /// `written_ms - submitted_ms`; `nil` for a superseded submission, which
  /// never reached the terminal.
  public var writeMs: Double?
  public var bytes: Int
  /// `written` or `superseded`.
  public var outcome: String

  public init(
    frameNumber: Int,
    submittedMs: Double? = nil,
    writtenMs: Double? = nil,
    writeMs: Double? = nil,
    bytes: Int = 0,
    outcome: String = "written"
  ) {
    self.frameNumber = frameNumber
    self.submittedMs = submittedMs
    self.writtenMs = writtenMs
    self.writeMs = writeMs
    self.bytes = bytes
    self.outcome = outcome
  }

  public var wasWritten: Bool {
    outcome == "written"
  }
}

/// Reads the optional `presents.tsv` sibling.
///
/// Absence is not an error and must not be treated as one: only the real
/// terminal host runs an asynchronous presentation writer, so a scenario run
/// against the in-process perf host legitimately produces no file. A
/// synchronous host's "write latency" would be a fabricated zero — an absent
/// measurement is more honest than an invented one.
enum PerfPresentsTSVReader {
  static func read(from url: URL) -> [Int: PerfPresentRecord] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      return [:]
    }
    return parse(text)
  }

  static func parse(_ text: String) -> [Int: PerfPresentRecord] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard let headerLine = lines.first else {
      return [:]
    }
    let header = split(headerLine)
    let column = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
    guard let frameColumn = column["frame"] else {
      return [:]
    }

    var records: [Int: PerfPresentRecord] = [:]
    for line in lines.dropFirst() {
      let fields = split(line)
      guard frameColumn < fields.count, let frameNumber = Int(fields[frameColumn]) else {
        continue
      }
      let record = PerfPresentRecord(
        frameNumber: frameNumber,
        submittedMs: double("submitted_ms", fields, column),
        writtenMs: double("written_ms", fields, column),
        writeMs: double("write_ms", fields, column),
        bytes: int("bytes", fields, column),
        outcome: string("outcome", fields, column, default: "written")
      )
      // A frame can legitimately appear more than once only if the runtime
      // reused an ordinal, which it does not; last write wins rather than
      // silently dropping, so a malformed file is visible in the numbers
      // instead of half-ignored.
      records[frameNumber] = record
    }
    return records
  }

  private static func split<S: StringProtocol>(_ line: S) -> [String] {
    String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
  }

  private static func string(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int],
    default defaultValue: String
  ) -> String {
    guard let index = column[name], index < fields.count else {
      return defaultValue
    }
    let value = fields[index]
    return value.isEmpty ? defaultValue : value
  }

  private static func int(_ name: String, _ fields: [String], _ column: [String: Int]) -> Int {
    guard let index = column[name], index < fields.count else {
      return 0
    }
    return Int(fields[index]) ?? 0
  }

  private static func double(
    _ name: String,
    _ fields: [String],
    _ column: [String: Int]
  ) -> Double? {
    guard let index = column[name], index < fields.count else {
      return nil
    }
    let value = fields[index]
    guard value != "-", !value.isEmpty else {
      return nil
    }
    return Double(value)
  }
}
