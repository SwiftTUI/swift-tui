@_spi(Runners) import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

public enum TerminalWASIAppRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  case nativeExecutionUnsupported

  public var description: String {
    switch self {
    case .nativeExecutionUnsupported:
      return
        "TerminalWASIAppRunner can run natively only in manifest mode. Build for WASI to execute scenes."
    }
  }
}

package enum WASITransportMode: Equatable, Sendable {
  case surface
  case ansi
}

package func resolveWASITransportMode(
  environmentValue: (String) -> String?
) -> WASITransportMode {
  switch environmentValue("TUIGUI_TRANSPORT")?.lowercased() {
  case "ansi", "terminal", "xterm", "ghostty-web":
    return .ansi
  default:
    return .surface
  }
}

/// Orchestrates scene manifest output and WASI-hosted scene launch.
public enum TerminalWASIAppRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    let selections = collectWindowSceneSelections(from: app.body)
    if requestedManifestMode() {
      print(TerminalUISceneManifest(for: app).jsonString)
      return
    }

    guard !selections.isEmpty else {
      throw AppLaunchError.noScenes
    }

    #if canImport(WASILibc)
      _ = try await runSelectedScene(
        selection: selectedWASISelection(from: selections),
        sessionName: String(reflecting: A.self),
        resources: wasiSceneResources()
      )
    #else
      throw TerminalWASIAppRunnerError.nativeExecutionUnsupported
    #endif
  }

  @MainActor
  private static func runSelectedScene(
    selection: SelectedWindowScene,
    sessionName: String,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<TerminalUISceneSessionState> {
    let stateContainer = StateContainer(
      initialState: TerminalUISceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    )
    let focusTracker = FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
    )

    defer {
      if let inProcessSignalReader = resources.signalReader as? InProcessSignalReader {
        inProcessSignalReader.finish()
      }
    }

    return try await selection.run(
      sessionName: sessionName,
      resources: resources,
      stateContainer: stateContainer,
      focusTracker: focusTracker
    )
  }

  #if canImport(WASILibc)
    @MainActor
    private static func selectedWASISelection(
      from selections: [SelectedWindowScene]
    ) -> SelectedWindowScene {
      guard let selector = wasiSceneSelector() else {
        return selections[0]
      }

      return selections.first(where: { $0.identifier.rawValue == selector })
        ?? selections[0]
    }

    @MainActor
    private static func wasiSceneResources() -> SceneSessionResources {
      switch wasiTransportMode() {
      case .surface:
        return webSurfaceSceneResources()
      case .ansi:
        return ansiSceneResources()
      }
    }

    @MainActor
    private static func webSurfaceSceneResources() -> SceneSessionResources {
      let signalReader = InProcessSignalReader()
      let host = WebSurfaceTransportHost(
        surfaceSize: wasiSurfaceSize(),
        renderStyle: wasiRenderStyle()
          ?? .init(appearance: .fallback)
      )
      let inputReader = WebSurfaceInputReader { message in
        switch message {
        case .resize(let size, let cellPixelSize):
          host.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
          signalReader.send("SIGWINCH")
        case .style(let style):
          host.updateStyle(style)
          signalReader.send("SIGWINCH")
        }
      }

      return .init(
        terminalHost: host,
        terminalInputReader: inputReader,
        signalReader: signalReader,
        surfaceName: "web-surface"
      )
    }

    @MainActor
    private static func ansiSceneResources() -> SceneSessionResources {
      let signalReader = InProcessSignalReader()
      let initialStyle = wasiRenderStyle()
      let host = WebTerminalHost(
        surfaceSize: wasiSurfaceSize(),
        theme: initialStyle?.theme
      )
      if let initialStyle {
        host.updateStyle(initialStyle)
      }
      let inputReader = InputReader { message in
        switch message {
        case .resize(let size):
          host.updateSurfaceSize(size)
          signalReader.send("SIGWINCH")
        case .style(let style):
          host.updateStyle(style)
          signalReader.send("SIGWINCH")
        }
      }

      return .init(
        terminalHost: host,
        terminalInputReader: inputReader,
        signalReader: signalReader,
        surfaceName: "ghostty-web"
      )
    }

    private static func wasiTransportMode() -> WASITransportMode {
      resolveWASITransportMode { name in
        environmentValue(named: name)
      }
    }

    private static func wasiRenderStyle() -> TerminalRenderStyle? {
      guard let encoded = environmentValue(named: "TUIGUI_RENDER_STYLE"),
        !encoded.isEmpty
      else {
        return nil
      }

      return TerminalRenderStyleCodec.decodeBase64(encoded)
    }

    private static func wasiSceneSelector() -> String? {
      if let selector = environmentValue(named: "TUIGUI_SCENE"), !selector.isEmpty {
        return selector
      }

      if let selector = environmentValue(named: "WEBAPP_SCENE"), !selector.isEmpty {
        return selector
      }

      return CommandLine.arguments.dropFirst().first
    }

    private static func wasiSurfaceSize() -> CellSize {
      let width = max(
        40,
        integerEnvironmentValue(named: "COLUMNS")
          ?? integerEnvironmentValue(named: "TUIGUI_COLUMNS")
          ?? integerEnvironmentValue(named: "WEBAPP_COLUMNS")
          ?? 120
      )
      let height = max(
        20,
        integerEnvironmentValue(named: "LINES")
          ?? integerEnvironmentValue(named: "TUIGUI_ROWS")
          ?? integerEnvironmentValue(named: "WEBAPP_ROWS")
          ?? 36
      )

      return .init(width: width, height: height)
    }
  #endif
}

private func requestedManifestMode() -> Bool {
  environmentValue(named: "TUIGUI_MODE") == "manifest"
}

private func integerEnvironmentValue(
  named name: String
) -> Int? {
  guard let value = environmentValue(named: name) else {
    return nil
  }
  return Int(value)
}

private func environmentValue(
  named name: String
) -> String? {
  unsafe name.withCString { cName in
    guard let rawValue = unsafe getenv(cName) else {
      return nil
    }
    return unsafe String(cString: rawValue)
  }
}

extension App {
  /// Default entry point for WASI-hosted TerminalUI apps.
  ///
  /// Mark a WASI-targeted app with `@main` to use this automatically, or call
  /// `TerminalWASIAppRunner.run(Self.self)` from a custom launcher.
  public static func main() async throws {
    try await TerminalWASIAppRunner.run(Self.self)
  }
}
