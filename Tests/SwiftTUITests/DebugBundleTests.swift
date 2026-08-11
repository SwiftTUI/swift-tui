import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// Units for the `--debug` / `SWIFTTUI_DEBUG_DIR` session bundle: one
/// directory that collects every armed diagnostic under a fixed name plus a
/// `manifest.txt`. These pin the arming rules (debug off ⇒ inert) and the
/// manifest/announcement contract the CLI runner prints after teardown.
@MainActor
@Suite("Debug bundle", .serialized)
struct DebugBundleTests {
  private func resetProcessState() {
    DebugBundle.resetForTesting()
    DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
  }

  @Test("debug off with no explicit directory prepares nothing")
  func debugOffPreparesNothing() {
    resetProcessState()
    defer { resetProcessState() }

    DebugBundle.prepareIfNeeded(configuration: .default)

    #expect(DebugBundle.preparedDirectory == nil)
    #expect(DebugBundle.announcementLine() == nil)
  }

  @Test("debug on installs a default bundle with a manifest and announcement")
  func debugOnInstallsDefaultBundle() throws {
    resetProcessState()
    defer {
      if let directory = DebugBundle.preparedDirectory {
        try? FileManager.default.removeItem(atPath: directory)
      }
      resetProcessState()
    }

    DebugBundle.prepareIfNeeded(configuration: RuntimeConfiguration(debug: true))

    let directory = try #require(DebugBundle.preparedDirectory)
    #expect(directory.contains("swifttui"))
    #expect(DebugBundle.announcementLine() == "SwiftTUI debug bundle: \(directory)\n")
    #expect(DebugBundle.bundleFilePath(named: "frames.tsv") == directory + "/frames.tsv")

    let manifest = try String(contentsOfFile: directory + "/manifest.txt", encoding: .utf8)
    #expect(manifest.hasPrefix("SwiftTUI debug bundle manifest\n"))
    #expect(manifest.contains("configuration: ") && manifest.contains("debug=true"))
    #expect(manifest.contains("gates: SWIFTTUI_SOUNDNESS_PROBE="))
    #expect(manifest.contains("trace-selection: "))
    #expect(manifest.contains("armed: memo-emission="))

    // Idempotent: a second prepare neither reinstalls nor rewrites.
    DebugBundle.prepareIfNeeded(configuration: RuntimeConfiguration(debug: true))
    #expect(DebugBundle.preparedDirectory == directory)
    let unchanged = try String(contentsOfFile: directory + "/manifest.txt", encoding: .utf8)
    #expect(unchanged == manifest)
  }
}
