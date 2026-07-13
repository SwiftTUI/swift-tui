import Foundation
@_spi(Runners) import SwiftTUIRuntime
import SwiftTUIVendorUnixSignals

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Manages the runtime for a single scene within a multi-scene app.
///
/// Each SceneRuntime owns its own TerminalHost, RunLoop, and state partitions.
/// The primary scene uses inherited stdio; secondary scenes use pty-backed hosts.
@MainActor
final class SceneRuntime {
  typealias SessionRunner =
    @MainActor (SceneRuntime, String) async throws -> RunLoopResult<SceneSessionState>

  let selection: SelectedWindowScene
  let isPrimary: Bool
  private(set) var lifecycle: SceneLifecycle
  private let ptyPair: ScenePty?
  private let resources: SceneSessionResources
  private let stateContainer: StateContainer<SceneSessionState>
  private let focusTracker: FocusTracker
  private let sessionRunner: SessionRunner

  init(
    selection: SelectedWindowScene,
    isPrimary: Bool,
    configuration: RuntimeConfiguration = .default,
    resources: SceneSessionResources? = nil,
    sessionRunner: SessionRunner? = nil
  ) throws {
    self.selection = selection
    self.isPrimary = isPrimary
    self.lifecycle = SceneLifecycle(isPrimary: isPrimary)

    let frameSink: (any FrameDiagnosticSink)? =
      if isPrimary, let path = Self.diagnosticsFilePath(configuration: configuration) {
        FrameDiagnosticsFileSink(path: path)
      } else {
        nil
      }

    if let resources {
      ptyPair = nil
      self.resources = resources
    } else if isPrimary {
      ptyPair = nil
      let environment = ProcessInfo.processInfo.environment
      let isTTY = isatty(STDOUT_FILENO) != 0
      let capabilityProfile = TerminalCapabilityProfile.detect(
        environment: environment,
        isTTY: isTTY
      )
      .applying(configuration)
      let terminalHost = TerminalHost(capabilityProfile: capabilityProfile)
      let inputReader = InputReader()
      // The capability probes read the same input descriptor the reader's
      // dispatch source owns; the gate suspends the reader for each probe's
      // write→read cycle so the reply cannot be consumed by the reader (F42).
      terminalHost.inputSuspensionGate = inputReader
      let resources = SceneSessionResources(
        presentationSurface: terminalHost,
        terminalInputReader: inputReader,
        signalReader: defaultSignalReader(),
        frameSink: frameSink,
        runtimeConfiguration: configuration
      )
      resources.runtimeIssueSink = .standardError
      self.resources = resources
    } else {
      let pty = try ScenePty()
      ptyPair = pty
      let environment = ProcessInfo.processInfo.environment
      let isTTY = isatty(pty.masterFD) != 0
      let capabilityProfile = TerminalCapabilityProfile.detect(
        environment: environment,
        isTTY: isTTY
      )
      .applying(configuration)
      let terminalHost = TerminalHost(
        inputFileDescriptor: pty.masterFD,
        outputFileDescriptor: pty.masterFD,
        capabilityProfile: capabilityProfile
      )
      let inputReader = InputReader(fileDescriptor: pty.masterFD)
      // Same shared-descriptor probe race as the primary path (F42).
      terminalHost.inputSuspensionGate = inputReader
      let resources = SceneSessionResources(
        presentationSurface: terminalHost,
        terminalInputReader: inputReader,
        runtimeConfiguration: configuration
      )
      resources.runtimeIssueSink = .standardError
      self.resources = resources
    }

    stateContainer = StateContainer(
      initialState: SceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
    )
    self.sessionRunner =
      sessionRunner ?? { runtime, sessionName in
        try await runtime.runSceneSession(sessionName: sessionName)
      }
  }

  var sceneInfo: SceneInfo {
    SceneInfo(
      id: selection.identifier.rawValue,
      title: selection.title,
      ptyPath: ptyPair?.slavePath,
      isAttached: lifecycle.state == .rendering
    )
  }

  func run(
    sessionName: String,
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void = { _ in }
  ) async throws -> RunLoopResult<SceneSessionState> {
    if isPrimary {
      installCrashGuard()
      defer { CrashSignalHandler.uninstall() }
      return try await sessionRunner(self, sessionName)
    }

    while !Task.isCancelled {
      guard await waitForClient(onAttachmentChanged: onAttachmentChanged) else {
        break
      }

      let result = try await sessionRunner(self, sessionName)
      if Task.isCancelled {
        return result
      }

      if result.exitReason == .inputEnded {
        if lifecycle.clientDetached() {
          onAttachmentChanged(false)
        }
        continue
      }

      return result
    }

    return RunLoopResult(
      finalState: stateContainer.state,
      renderedFrames: 0,
      exitReason: .inputEnded
    )
  }

  func shutdown() {
    guard let ptyPair else { return }
    Task {
      await ptyPair.close()
    }
  }

  // ---------------------------------------------------------------------------
  // MARK: - Crash guard
  // ---------------------------------------------------------------------------

  /// Installs the crash signal handler so that fatal signals (SIGABRT, SIGSEGV,
  /// etc.) reset the terminal before the process dies.
  ///
  /// Only meaningful for the primary scene, which owns the real tty via stdio.
  private func installCrashGuard() {
    // Read the current terminal attributes before the session enters raw mode.
    // These are the attributes we want to restore on crash.
    var savedTermios = termios()
    let hasTermios = unsafe tcgetattr(STDIN_FILENO, &savedTermios) == 0

    // Build the reset sequence: disable mouse reporting, show cursor,
    // reset style, exit alternate screen.
    let resetSequence =
      "\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1016l\u{1B}[?1006l"  // disable mouse reporting
      + "\u{1B}[?25h"  // show cursor
      + "\u{1B}[0m"  // reset style
      + "\u{1B}[?1049l"  // exit alternate screen
    let resetBytes = Array(resetSequence.utf8)

    let resetAction = CrashSignalHandler.ResetAction(
      outputFileDescriptor: STDOUT_FILENO,
      resetBytes: resetBytes,
      termiosFileDescriptor: hasTermios ? STDIN_FILENO : nil,
      savedTermios: hasTermios ? savedTermios : nil
    )
    CrashSignalHandler.install(
      for: CrashSignalHandler.fatalSignals,
      reset: resetAction
    )
  }

  private func runSceneSession(
    sessionName: String
  ) async throws -> RunLoopResult<SceneSessionState> {
    try await selection.run(
      sessionName: sessionName,
      resources: resources,
      stateContainer: stateContainer,
      focusTracker: focusTracker
    )
  }

  /// Returns a diagnostics output file path when debug instrumentation or the
  /// legacy `TERMUI_DIAGNOSTICS` environment variable is enabled.
  ///
  /// A value of `1` or `true` writes to `/tmp/termui-diagnostics.tsv`; any
  /// other truthy value is treated as a custom file path. `--debug` /
  /// `SWIFTTUI_DEBUG=1` uses the same default path when no custom diagnostics
  /// path is present.
  static func diagnosticsFilePath(
    configuration: RuntimeConfiguration,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    if let string = environment["TERMUI_DIAGNOSTICS"],
      let path = diagnosticsFilePath(from: string)
    {
      return path
    }
    return configuration.debug ? defaultDiagnosticsFilePath : nil
  }

  private static let defaultDiagnosticsFilePath = "/tmp/termui-diagnostics.tsv"

  private static func diagnosticsFilePath(from string: String) -> String? {
    switch string.lowercased() {
    case "", "0", "false", "no":
      return nil
    case "1", "true", "yes":
      return defaultDiagnosticsFilePath
    default:
      return string
    }
  }

  private func waitForClient(
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void
  ) async -> Bool {
    guard let pty = ptyPair else { return true }

    while !Task.isCancelled {
      if await pty.hasAttachedClient() {
        if lifecycle.clientAttached() {
          onAttachmentChanged(true)
        }
        return true
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    return false
  }
}
