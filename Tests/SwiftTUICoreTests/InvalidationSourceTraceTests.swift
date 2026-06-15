import Foundation
import Testing

@testable import SwiftTUICore

/// Locks the invalidation-source diagnostic that decomposes how a frame's
/// invalidation set is assembled (raw scheduler set vs portal-translation vs
/// force-root). Companion to `ReuseDenialTraceTests`. Serialized because the
/// trace is a process-global `@MainActor` sink; each test saves/restores it.
@MainActor
@Suite(.serialized)
struct InvalidationSourceTraceTests {
  private static func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("inval-trace-\(UUID().uuidString).log")
      .path
  }

  private func withTrace<T>(
    enabled: Bool,
    filePath: String?,
    _ body: () throws -> T
  ) rethrows -> T {
    let savedEnabled = InvalidationSourceTrace.isEnabled
    let savedPath = InvalidationSourceTrace.outputFilePath
    InvalidationSourceTrace.isEnabled = enabled
    InvalidationSourceTrace.outputFilePath = filePath
    InvalidationSourceTrace.reset()
    defer {
      InvalidationSourceTrace.isEnabled = savedEnabled
      InvalidationSourceTrace.outputFilePath = savedPath
      InvalidationSourceTrace.reset()
    }
    return try body()
  }

  @Test("disabled trace records nothing and writes no file")
  func disabledTraceIsInert() {
    let path = Self.temporaryPath()
    withTrace(enabled: false, filePath: path) {
      InvalidationSourceTrace.recordFrame(
        raw: [testIdentity("root")],
        translated: [testIdentity("root")],
        usesSelectiveEvaluation: true,
        disabledReasons: []
      )
      #expect(!FileManager.default.fileExists(atPath: path))
    }
  }

  @Test("records raw, translated, and force-root reasons")
  func recordsRawTranslatedAndReasons() throws {
    let path = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try withTrace(enabled: true, filePath: path) {
      InvalidationSourceTrace.recordFrame(
        raw: [testIdentity("overlay-entry")],
        translated: [testIdentity("portal-host")],
        usesSelectiveEvaluation: false,
        disabledReasons: ["focus_changed", "frame_state_force_root"]
      )
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      #expect(contents.contains("[INVAL-TRACE]"))
      #expect(contents.contains("raw={\(testIdentity("overlay-entry").path)}"))
      #expect(contents.contains("xlated={\(testIdentity("portal-host").path)}"))
      #expect(contents.contains("selective=false"))
      #expect(contents.contains("force-root-reasons=[focus_changed,frame_state_force_root]"))
    }
  }

  @Test("omits the xlated token when translation does not change the set")
  func omitsXlatedWhenUnchanged() throws {
    let path = Self.temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try withTrace(enabled: true, filePath: path) {
      let identity = testIdentity("content", "Layout[0]")
      InvalidationSourceTrace.recordFrame(
        raw: [identity],
        translated: [identity],
        usesSelectiveEvaluation: true,
        disabledReasons: []
      )
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      #expect(contents.contains("raw={\(identity.path)}"))
      #expect(!contents.contains("xlated="))
      #expect(contents.contains("selective=true"))
      #expect(!contents.contains("force-root-reasons"))
    }
  }
}
