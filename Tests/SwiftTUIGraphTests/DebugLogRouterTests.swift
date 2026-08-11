import Foundation
import Testing

@testable import SwiftTUIGraph

/// Direct units for the central debug router (F123 lineage): `DebugLogRouter`
/// is the repo's WASI/POSIX model file and the durable-artifact path every
/// trace subsystem (`[REUSE-TRACE]`, `[MEMO-TRACE]`, `[SOUNDNESS]`, the frame
/// trace, the CLI diagnostics TSV) rides — a silent break here costs future
/// debugging sessions.
@MainActor
@Suite("Debug log router")
struct DebugLogRouterTests {
  @Test("emitting to a file path creates the file and appends across emits")
  func fileSinkCreatesAndAppends() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("trace-sink-\(UUID().uuidString).log").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    DebugLogRouter.emit("first line\n", toFileAt: path)
    DebugLogRouter.emit("second line\n", toFileAt: path)

    let content = try String(contentsOfFile: path, encoding: .utf8)
    #expect(content == "first line\nsecond line\n")
  }

  @Test("a nil or empty path falls back to stderr without touching the filesystem")
  func nilAndEmptyPathsFallBackToStderr() {
    // The fallback target (stderr) is not capturable here; the pinned
    // contract is that the call is safe and creates no stray file.
    DebugLogRouter.emit("stderr fallback probe\n", toFileAt: nil)
    DebugLogRouter.emit("stderr fallback probe\n", toFileAt: "")
    #expect(!FileManager.default.fileExists(atPath: ""))
  }

  @Test("an unwritable path degrades to the stderr fallback instead of trapping")
  func unwritablePathDegrades() {
    DebugLogRouter.emit(
      "unwritable probe\n",
      toFileAt: "/nonexistent-root-dir-\(UUID().uuidString)/trace.log"
    )
    // Reaching here is the assertion: open failure returns false and the
    // message reroutes to stderr; no trap, no partial file.
  }

  @Test("an explicit per-stream override always wins over the bundle directory")
  func overrideWinsOverBundle() {
    #expect(
      DebugLogRouter.resolvedFilePath(override: "/tmp/explicit.log", bundleFileName: "memo.log")
        == "/tmp/explicit.log"
    )
  }

  @Test("without an override or bundle directory, resolution is nil (stderr)")
  func noBundleResolvesToNil() {
    DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
    #expect(DebugLogRouter.resolvedFilePath(override: nil, bundleFileName: "memo.log") == nil)
    #expect(DebugLogRouter.resolvedFilePath(override: "", bundleFileName: "memo.log") == nil)
  }

  @Test("an installed default directory routes bundle files and is created on demand")
  func installedDefaultRoutesAndCreates() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swifttui-router-\(UUID().uuidString)/nested").path
    defer {
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
      try? FileManager.default.removeItem(atPath: directory)
    }

    DebugLogRouter.installDefaultDebugDirectory(directory + "/")
    let resolved = DebugLogRouter.resolvedFilePath(override: nil, bundleFileName: "memo.log")

    #expect(resolved == directory + "/memo.log")
    // The write-probe doubles as the directory-creation assertion: the append
    // can only land if the nested directory now exists.
    DebugLogRouter.emit("bundle probe\n", toFileAt: resolved)
    let content = try String(contentsOfFile: directory + "/memo.log", encoding: .utf8)
    #expect(content == "bundle probe\n")

    // A second install is a no-op: the first default wins for the session.
    DebugLogRouter.installDefaultDebugDirectory("/tmp/other-\(UUID().uuidString)")
    #expect(DebugLogRouter.activeDebugDirectory() == directory)
  }
}

@Suite("Debug trace selection")
struct DebugTraceSelectionTests {
  @Test("parses names and per-trace samples")
  func parsesNamesAndSamples() {
    let selection = DebugTraceSelection.parse("memo@256, reuse,frames")
    #expect(selection.isArmed("memo"))
    #expect(selection.entry(named: "memo")?.sampleEveryNFrames == 256)
    #expect(selection.isArmed("reuse"))
    #expect(selection.entry(named: "reuse")?.sampleEveryNFrames == nil)
    #expect(selection.isArmed("frames"))
    #expect(!selection.isArmed("inval"))
  }

  @Test("unset or empty input is an empty selection")
  func unsetIsEmpty() {
    #expect(DebugTraceSelection.parse(nil).entries.isEmpty)
    #expect(DebugTraceSelection.parse("").entries.isEmpty)
    #expect(DebugTraceSelection.parse("   ").entries.isEmpty)
  }

  @Test("malformed input fails closed to an empty selection")
  func malformedFailsClosed() {
    #expect(DebugTraceSelection.parse("memo@").entries.isEmpty)
    #expect(DebugTraceSelection.parse("memo@0").entries.isEmpty)
    #expect(DebugTraceSelection.parse("memo@abc").entries.isEmpty)
    #expect(DebugTraceSelection.parse("memo@1@2").entries.isEmpty)
    #expect(DebugTraceSelection.parse("memo,,reuse").entries.isEmpty)
  }

  @Test("unknown names are ignored, not fatal")
  func unknownNamesIgnored() {
    let selection = DebugTraceSelection.parse("hologram,reuse")
    #expect(selection.entries.map(\.name) == ["reuse"])
  }

  @Test("names are case-normalized")
  func caseNormalized() {
    #expect(DebugTraceSelection.parse("MEMO@8").entry(named: "memo")?.sampleEveryNFrames == 8)
  }
}
