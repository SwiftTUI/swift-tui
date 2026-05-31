import Foundation
import SwiftTUIArguments
import SwiftTUICore
import SwiftTUIPTYPrimitives
import SwiftTUITerminal
import Testing

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// End-to-end regression coverage for the app-launch entry point.
///
/// These tests exist because the synchronous-`main()` trap is invisible to a
/// "builds + unit tests pass" gate: it lives purely in `main()` overload
/// resolution. The only way to catch it is to *run a built executable* and
/// observe what it does. Each fixture is a tiny executable target
/// (`Tests/EntryPointLaunchFixtures/*`) that the test launches under a PTY via
/// `ChildProcessPty`.
///
/// Coverage:
///   - `@main` (the supported form) starts the runtime and renders a frame.
///   - a bare `MyApp.main()` selects the SwiftTUI `main() -> Never` diagnostic
///     shim (not swift-argument-parser's synchronous `ParsableCommand.main()`),
///     prints an accurate message, and exits non-zero — for the batteries-
///     included `SwiftTUI.App`, the `SwiftTUICLI`, and the `SwiftTUIWebHostCLI`
///     launch layers.
///
/// The fixtures are run in whichever configuration the test bundle was built
/// in, so the repo gate (DEBUG) exercises this suite directly. The fix is
/// `main()` overload resolution — a compile-time decision independent of the
/// optimization level — so DEBUG and release are equivalent by construction.
/// Release is additionally verified by building these fixtures with
/// `swift build -c release` and running the resulting binaries; the same does
/// not run via `swift test -c release` because other test targets in the
/// bundle do not currently compile under release optimization.
@Suite("EntryPointLaunch", .serialized)
struct EntryPointLaunchTests {
  /// A marker rendered by the `@main` fixture's single `Text` view. Its
  /// appearance in the PTY output proves the runtime actually started.
  static let frameMarker = "ENTRYPOINTOK"

  @Test("@main launches the runtime and renders a frame")
  func atMainLaunchesRuntimeAndRendersFrame() async throws {
    let result = try await runFixture(
      "EntryPointFixtureAtMain",
      stoppingAt: Self.frameMarker,
      watchdog: .seconds(20)
    )
    #expect(
      result.output.contains(Self.frameMarker),
      "expected a rendered frame; got:\n\(result.output)"
    )
    // The supported path must never surface either failure message.
    #expect(!result.output.contains("availability annotation"))
    #expect(!result.output.contains("synchronous `main()`"))
  }

  @Test(
    "a bare MyApp.main() prints the SwiftTUI diagnostic and exits non-zero",
    arguments: [
      "EntryPointFixtureBare",
      "EntryPointFixtureCLIBare",
      "EntryPointFixtureWebHostCLIBare",
    ]
  )
  func bareMainProducesDiagnostic(fixture: String) async throws {
    let result = try await runFixture(fixture, stoppingAt: nil, watchdog: .seconds(20))

    // The SwiftTUI diagnostic, not swift-argument-parser's misleading message.
    #expect(
      result.output.contains("was launched through the synchronous `main()`"),
      "expected the SwiftTUI synchronous-launch diagnostic; got:\n\(result.output)"
    )
    #expect(result.output.contains("@main"))
    // The diagnostic names the offending command type.
    #expect(result.output.contains(fixture))
    // It must NOT be swift-argument-parser's DEBUG-only availability message.
    #expect(!result.output.contains("availability annotation"))
    // The runtime never started; the marker must be absent.
    #expect(!result.output.contains(Self.frameMarker))

    // Loud failure: a non-zero exit, identical in DEBUG and release.
    guard case .exited(let code) = result.exit else {
      Issue.record("expected a normal exit, got \(result.exit)")
      return
    }
    #expect(code != 0)
  }

  @Test("the diagnostic message is accurate and framework-specific")
  func diagnosticMessageIsAccurate() {
    let message = synchronousLaunchDiagnosticMessage(commandTypeName: "MyApp")
    #expect(message.contains("MyApp"))
    #expect(message.contains("@main"))
    #expect(message.contains("synchronous `main()`"))
    #expect(message.contains("`App.main()` is `async`"))
    // Explicitly not swift-argument-parser's misleading wording.
    #expect(!message.contains("availability annotation"))
  }

  // MARK: - Harness

  private struct FixtureRun {
    var output: String
    var exit: ChildProcessPty.ExitStatus
  }

  /// Launches a fixture executable under a PTY and collects its combined
  /// stdout/stderr.
  ///
  /// When `marker` is set, reading stops as soon as it appears (and the child
  /// is terminated). A watchdog sends `SIGTERM` after `watchdog` elapses so a
  /// hung or never-rendering fixture cannot wedge the suite — the forced EOF
  /// ends the read loop deterministically.
  private func runFixture(
    _ name: String,
    stoppingAt marker: String?,
    watchdog: Duration
  ) async throws -> FixtureRun {
    let binary = try Self.fixtureExecutableURL(named: name)
    let pty = ChildProcessPty(
      executable: binary.path,
      arguments: [],
      environment: Self.fixtureEnvironment(),
      workingDirectory: nil,
      initialSize: CellSize(width: 100, height: 30)
    )
    try await pty.start()

    // SIGKILL, not SIGTERM: the interactive runtime installs handlers and does
    // not reliably exit on SIGTERM, so the bare backstop must be uncatchable.
    // The bare fixtures exit on their own (the diagnostic calls `exit`), so the
    // watchdog only ever fires for the long-lived `@main` fixture.
    let watchdogTask = Task {
      try? await Task.sleep(for: watchdog)
      try? await pty.sendSignal(SIGKILL)
    }
    defer { watchdogTask.cancel() }

    var bytes: [UInt8] = []
    for await chunk in await pty.pair.read() {
      bytes.append(contentsOf: chunk)
      if let marker, String(decoding: bytes, as: UTF8.self).contains(marker) {
        // The frame rendered; stop the running runtime deterministically.
        try? await pty.sendSignal(SIGKILL)
        break
      }
    }
    let status = await pty.waitForExit()
    return FixtureRun(output: String(decoding: bytes, as: UTF8.self), exit: status)
  }

  /// A minimal, deterministic terminal environment for the fixtures.
  private static func fixtureEnvironment() -> [String: String] {
    var environment: [String: String] = ["TERM": "xterm-256color", "LANG": "en_US.UTF-8"]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
      environment["PATH"] = path
    }
    return environment
  }

  /// Resolves a sibling fixture executable in the test bundle's products
  /// directory.
  ///
  /// `Bundle`/`CommandLine` are unreliable here: under SwiftPM's testing
  /// helper they point at the toolchain, not the package `.build` directory.
  /// Instead, `dladdr` on this module's metadata yields the loaded test image
  /// path (inside `.build/<triple>/<config>/…`); we then ascend to the
  /// directory that actually contains the fixture binary. This works for both
  /// the macOS `.xctest` bundle layout and the flat Linux layout, and naturally
  /// follows the DEBUG/release configuration the suite was built in.
  private static func fixtureExecutableURL(named name: String) throws -> URL {
    let imagePath = try #require(testImagePath(), "could not resolve the test image path")
    var directory = URL(fileURLWithPath: imagePath).deletingLastPathComponent()
    for _ in 0..<8 {
      let candidate = directory.appendingPathComponent(name)
      if FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
      directory = directory.deletingLastPathComponent()
    }
    throw EntryPointLaunchError.fixtureNotFound(name: name, searchedFrom: imagePath)
  }

  private static func testImagePath() -> String? {
    var info = unsafe Dl_info()
    let address = unsafe unsafeBitCast(ImageAnchor.self, to: UnsafeRawPointer.self)
    guard unsafe dladdr(address, &info) != 0, let name = unsafe info.dli_fname else {
      return nil
    }
    return unsafe String(cString: name)
  }
}

/// Anchors `dladdr` to this test module's loaded image.
private final class ImageAnchor {}

private enum EntryPointLaunchError: Error, CustomStringConvertible {
  case fixtureNotFound(name: String, searchedFrom: String)

  var description: String {
    switch self {
    case .fixtureNotFound(let name, let searchedFrom):
      return "Fixture executable '\(name)' not found ascending from \(searchedFrom)"
    }
  }
}
