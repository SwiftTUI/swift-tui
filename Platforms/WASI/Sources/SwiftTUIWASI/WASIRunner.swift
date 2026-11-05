import Foundation
@_spi(Runners) import SwiftTUIRuntime
import SwiftTUIWASISurfaceBridge

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

public enum WASIRunnerError: Error, Hashable, Sendable, CustomStringConvertible {
  case nativeExecutionUnsupported
  case sceneNotFound(WindowIdentifier)

  public var description: String {
    switch self {
    case .sceneNotFound(let identifier):
      return "wasi.scene.notFound: no scene named \(identifier.rawValue)."
    case .nativeExecutionUnsupported:
      return
        "WASIRunner can run natively only in manifest mode. Build for WASI to execute scenes."
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
  switch environmentValue(SwiftTUIEnvironmentVariable.transport.rawValue)?.lowercased() {
  case "ansi", "terminal", "xterm", "ghostty-web":
    return .ansi
  default:
    return .surface
  }
}

package func wasiSurfaceDeltaEnabled(
  environmentValue: (String) -> String?
) -> Bool {
  FeatureFlags.booleanValue(environmentValue(SwiftTUIEnvironmentVariable.surfaceDelta.rawValue))
    ?? false
}

/// Resolves the WASI browser host's ``HostWireCapabilities`` from the
/// environment — the WASI capability ingress, named so the manifest has a
/// declaration site to point at. `SWIFTTUI_SURFACE_DELTA` is the pre-existing
/// delta opt-in and is the whole declaration; an absent key keeps the
/// default, which is today's bytes. See `HostWireSchema.capabilityMappings`.
///
/// The retired `SWIFTTUI_SURFACE_MAX_VERSION` key used to override a declared
/// version ceiling. Capabilities are named feature bits now, so there is no
/// ceiling to override: setting it has no effect.
package func wasiHostWireCapabilities(
  environmentValue: (String) -> String?
) -> HostWireCapabilities {
  HostWireCapabilities(
    acceptsDeltaFrames: wasiSurfaceDeltaEnabled(environmentValue: environmentValue),
    styleAppend: FeatureFlags.booleanValue(
      environmentValue(SwiftTUIEnvironmentVariable.surfaceStyleAppend.rawValue)) ?? false,
    geometryRevisions: FeatureFlags.booleanValue(
      environmentValue(SwiftTUIEnvironmentVariable.geometryRevisions.rawValue)) ?? false
  )
}

package func wasiFrameDiagnosticsEnabled(
  environmentValue: (String) -> String?
) -> Bool {
  parseDiagnosticsFlag(environmentValue(SwiftTUIEnvironmentVariable.frameDiagnostics.rawValue))
    ?? parseDiagnosticsFlag(environmentValue(SwiftTUIEnvironmentVariable.diagnostics.rawValue))
    ?? false
}

/// A non-boolean diagnostics destination requests recording on the browser host too.
private func parseDiagnosticsFlag(_ value: String?) -> Bool? {
  value.map { FeatureFlags.booleanValue($0) ?? true }
}

/// Orchestrates scene manifest output and WASI-hosted scene launch.
public enum WASIRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    let selections = collectWindowSceneSelections(from: app.body)
    try validateWindowSceneIdentifiers(selections.map(\.descriptor))
    if requestedManifestMode() {
      let manifest = SceneManifest(for: app)
      let selected = try wasiManifest(
        scenes: manifest.scenes,
        selector: environmentValue(named: SwiftTUIEnvironmentVariable.scene.rawValue))
      print(selected.jsonString)
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
      throw WASIRunnerError.nativeExecutionUnsupported
    #endif
  }

  @MainActor
  private static func runSelectedScene(
    selection: SelectedWindowScene,
    sessionName: String,
    resources: SceneSessionResources
  ) async throws -> RunLoopResult<SceneSessionState> {
    let stateContainer = StateContainer(
      initialState: SceneSessionState(),
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

      return selections.first(where: { $0.identifier == selector })
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
      let host = WebSurfaceTransport(
        surfaceSize: wasiSurfaceSize(),
        renderStyle: wasiRenderStyle()
          ?? .init(appearance: .fallback),
        wireCapabilities: wasiHostWireCapabilities { name in
          environmentValue(named: name)
        }
      )
      let inputReader = WebSurfaceInputReader(wireCapabilities: host.wireCapabilities) { message in
        switch message {
        case .geometry(let request):
          if host.updateGeometry(request) { signalReader.send(.windowChange) }
        case .resize(let size, let cellPixelSize):
          host.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
          signalReader.send(.windowChange)
        case .style(let style):
          host.updateStyle(style)
          signalReader.send(.windowChange)
        case .pointerCapabilities(let supportsScrollPanning):
          // Live on this transport, unlike `caps:` below: the pointer
          // paradigm is a property of the browsing device, not of the WASI
          // environment, and a device can switch paradigm mid-session. The
          // SIGWINCH re-resolves so views see the new declaration.
          host.updatePointerCapabilities(
            supportsScrollPanning: supportsScrollPanning
          )
          signalReader.send(.windowChange)
        case .capabilities:
          // The WASI ingress is environment-owned (resolved above at
          // transport construction); a stray caps record on stdin is not a
          // declaration channel here. Deliberate, not an oversight: this
          // transport never reconnects — a browser reload re-instantiates it
          // with freshly resolved environment — so there is no moment a
          // mid-session declaration would serve. The shared parser produces
          // this message for the WebSocket transport, which does have one.
          break
        case .resync(let request):
          host.requestResync(request)
          // Repair must progress even when the app has no further input or
          // animation. Encoding state alone only affects the next presentation.
          signalReader.send(.windowChange)
        }
      }

      let resources = SceneSessionResources(
        presentationSurface: host,
        terminalInputReader: inputReader,
        signalReader: signalReader,
        sceneSurface: .webSurface,
        frameSink: wasiFrameDiagnosticsEnabled { name in
          environmentValue(named: name)
        }
          ? WASIFrameDiagnosticsSink(notify: { record in
            try? host.notifyFrameDiagnostic(record)
          }) : nil
      )
      resources.runtimeIssueSink = RuntimeIssueSink { issue in
        try? host.notifyRuntimeIssue(issue)
      }
      return resources
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
          signalReader.send(.windowChange)
        case .style(let style):
          host.updateStyle(style)
          signalReader.send(.windowChange)
        }
      }

      let resources = SceneSessionResources(
        presentationSurface: host,
        terminalInputReader: inputReader,
        signalReader: signalReader,
        sceneSurface: .ghosttyWeb
      )
      resources.runtimeIssueSink = RuntimeIssueSink { issue in
        try? host.write(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue))
      }
      return resources
    }

    private static func wasiTransportMode() -> WASITransportMode {
      resolveWASITransportMode { name in
        environmentValue(named: name)
      }
    }

    private static func wasiRenderStyle() -> TerminalRenderStyle? {
      guard let encoded = environmentValue(named: SwiftTUIEnvironmentVariable.renderStyle.rawValue),
        !encoded.isEmpty
      else {
        return nil
      }

      return TerminalRenderStyleCodec.decodeBase64(encoded)
    }

    private static func wasiSceneSelector() -> WindowIdentifier? {
      if let selector = environmentValue(named: SwiftTUIEnvironmentVariable.scene.rawValue),
        !selector.isEmpty
      {
        return WindowIdentifier(selector)
      }

      return CommandLine.arguments.dropFirst().first.map { WindowIdentifier($0) }
    }

    private static func wasiSurfaceSize() -> CellSize {
      let width = max(
        40,
        integerEnvironmentValue(named: "COLUMNS")
          ?? integerEnvironmentValue(named: SwiftTUIEnvironmentVariable.columns.rawValue)
          ?? 120
      )
      let height = max(
        20,
        integerEnvironmentValue(named: "LINES")
          ?? integerEnvironmentValue(named: SwiftTUIEnvironmentVariable.rows.rawValue)
          ?? 36
      )

      return .init(width: width, height: height)
    }
  #endif
}

private func requestedManifestMode() -> Bool {
  environmentValue(named: SwiftTUIEnvironmentVariable.mode.rawValue) == "manifest"
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
  // Routed through the shared reader so the Windows secure-CRT spelling
  // (`_dupenv_s`) lives in exactly one place.
  FeatureFlags.environmentValue(named: name)
}

extension App {
  /// Default entry point for WASI-hosted SwiftTUI apps.
  ///
  /// Mark a WASI-targeted app with `@main` to use this automatically, or call
  /// `WASIRunner.run(Self.self)` from a custom launcher.
  public static func main() async throws {
    try await WASIRunner.run(Self.self)
  }
}

/// Native discovery uses the same explicit scene selector as browser launch.
package func wasiManifest(scenes: [SceneDescriptor], selector: String?) throws -> SceneManifest {
  let identifier = selector.flatMap { $0.isEmpty ? nil : WindowIdentifier($0) }
  if let identifier, !scenes.contains(where: { $0.id == identifier }) {
    throw WASIRunnerError.sceneNotFound(identifier)
  }
  return SceneManifest(defaultSceneID: identifier, scenes: scenes)
}
