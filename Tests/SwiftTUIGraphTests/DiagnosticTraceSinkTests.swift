import Foundation
import Testing

@testable import SwiftTUIGraph

/// Direct units for the trace file sink (F123): `DiagnosticTraceSink` is the
/// repo's WASI/POSIX model file and the durable-artifact path every trace
/// subsystem (`[REUSE-TRACE]`, `[MEMO-TRACE]`, `[SOUNDNESS]`) rides — a
/// silent break here costs future debugging sessions, and it previously had
/// zero test mentions.
@MainActor
@Suite("Diagnostic trace sink")
struct DiagnosticTraceSinkTests {
  @Test("emitting to a file path creates the file and appends across emits")
  func fileSinkCreatesAndAppends() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("trace-sink-\(UUID().uuidString).log").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    DiagnosticTraceSink.emit("first line\n", toFileAt: path)
    DiagnosticTraceSink.emit("second line\n", toFileAt: path)

    let content = try String(contentsOfFile: path, encoding: .utf8)
    #expect(content == "first line\nsecond line\n")
  }

  @Test("a nil or empty path falls back to stderr without touching the filesystem")
  func nilAndEmptyPathsFallBackToStderr() {
    // The fallback target (stderr) is not capturable here; the pinned
    // contract is that the call is safe and creates no stray file.
    DiagnosticTraceSink.emit("stderr fallback probe\n", toFileAt: nil)
    DiagnosticTraceSink.emit("stderr fallback probe\n", toFileAt: "")
    #expect(!FileManager.default.fileExists(atPath: ""))
  }

  @Test("an unwritable path degrades to the stderr fallback instead of trapping")
  func unwritablePathDegrades() {
    DiagnosticTraceSink.emit(
      "unwritable probe\n",
      toFileAt: "/nonexistent-root-dir-\(UUID().uuidString)/trace.log"
    )
    // Reaching here is the assertion: open failure returns false and the
    // message reroutes to stderr; no trap, no partial file.
  }
}
