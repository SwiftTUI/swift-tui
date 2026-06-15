import Foundation
import Testing

@testable import SwiftTUICore

/// Locks the reuse-denial diagnostic's recording and file-sink behavior. The
/// trace is the cone diagnostic the sheet/palette reuse-denial investigation
/// depends on; these tests guard that (a) it is inert when disabled, (b) the
/// `SWIFTTUI_REUSE_TRACE_FILE` sink durably captures recorded reasons as a
/// run artifact rather than only emitting to easily-lost stderr, and (c) the
/// histogram resets per frame.
///
/// Serialized because `ReuseDenialTrace` is a process-global `@MainActor`
/// accumulator; each test saves and restores the global state.
@MainActor
@Suite(.serialized)
struct ReuseDenialTraceTests {
  private static func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("reuse-trace-\(UUID().uuidString).log")
      .path
  }

  private func withTrace<T>(
    enabled: Bool,
    filePath: String?,
    _ body: () throws -> T
  ) rethrows -> T {
    let savedEnabled = ReuseDenialTrace.isEnabled
    let savedPath = ReuseDenialTrace.outputFilePath
    ReuseDenialTrace.isEnabled = enabled
    ReuseDenialTrace.outputFilePath = filePath
    ReuseDenialTrace.reset()
    defer {
      ReuseDenialTrace.reset()
      ReuseDenialTrace.isEnabled = savedEnabled
      ReuseDenialTrace.outputFilePath = savedPath
    }
    return try body()
  }

  @Test("disabled trace records nothing and writes no file")
  func disabledTraceIsInert() {
    let path = Self.temporaryPath()
    withTrace(enabled: false, filePath: path) {
      ReuseDenialTrace.record("invalidation-conflict")
      ReuseDenialTrace.recordInvalidatedIdentity("App/Root/Layout[0]")
      #expect(ReuseDenialTrace.reasonCounts.isEmpty)
      ReuseDenialTrace.dumpAndReset(frameID: 1)
      #expect(!FileManager.default.fileExists(atPath: path))
    }
  }

  @Test("file sink captures recorded reasons and the invalidated cone source")
  func fileSinkCapturesRecordedReasons() throws {
    let path = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try withTrace(enabled: true, filePath: path) {
      ReuseDenialTrace.record("invalidation-conflict")
      ReuseDenialTrace.record("invalidation-conflict")
      ReuseDenialTrace.recordInvalidatedIdentity("App/sheet/Layout[0]")
      ReuseDenialTrace.dumpAndReset(frameID: 7)

      let contents = try String(contentsOfFile: path, encoding: .utf8)
      #expect(contents.contains("[REUSE-TRACE] frame=7"))
      #expect(contents.contains("invalidation-conflict=2"))
      #expect(contents.contains("invalidated: App/sheet/Layout[0]"))
    }
  }

  @Test("an empty histogram opens no file and emits no line")
  func emptyHistogramWritesNothing() {
    let path = Self.temporaryPath()
    withTrace(enabled: true, filePath: path) {
      ReuseDenialTrace.dumpAndReset(frameID: 3)
      #expect(!FileManager.default.fileExists(atPath: path))
    }
  }

  @Test("dump resets the histogram so frames do not accumulate")
  func dumpResetsBetweenFrames() throws {
    let path = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try withTrace(enabled: true, filePath: path) {
      ReuseDenialTrace.record("suppressed")
      ReuseDenialTrace.dumpAndReset(frameID: 1)
      #expect(ReuseDenialTrace.reasonCounts.isEmpty)

      ReuseDenialTrace.record("dirty")
      ReuseDenialTrace.dumpAndReset(frameID: 2)

      let lines = try String(contentsOfFile: path, encoding: .utf8)
        .split(separator: "\n")
      #expect(lines.count == 2)
      // Frame 2 must not carry frame 1's "suppressed" reason.
      #expect(lines[1].contains("frame=2"))
      #expect(lines[1].contains("dirty=1"))
      #expect(!lines[1].contains("suppressed"))
    }
  }
}
