import Core
import TerminalUI
import View

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// A minimal state type used by SceneRuntime's RunLoop.
// MultiSceneLauncher (Task 9) will reference this type.
package struct MultiSceneRuntimeState: Equatable, Sendable {}

enum SceneRuntimeError: Error, CustomStringConvertible {
  case secondaryScenesUnavailableOnWASI

  var description: String {
    switch self {
    case .secondaryScenesUnavailableOnWASI:
      return "Secondary scenes are unavailable when building for WASI."
    }
  }
}

/// Manages the runtime for a single scene within a multi-scene app.
///
/// Each SceneRuntime owns its own TerminalHost, RunLoop, and state partitions.
/// The primary scene uses inherited stdio; secondary scenes use pty-backed hosts.
@MainActor
final class SceneRuntime {
  typealias SessionRunner =
    @MainActor (SceneRuntime, String) async throws -> RunLoopResult<MultiSceneRuntimeState>

  let configuration: WindowSceneConfiguration
  let isPrimary: Bool
  private(set) var lifecycle: SceneLifecycle
  private let ptyPair: PtyPair?
  private let resources: SceneSessionResources
  private let stateContainer: StateContainer<MultiSceneRuntimeState>
  private let focusTracker: FocusTracker
  private let dynamicStateStore: DynamicStateStore
  private let sessionRunner: SessionRunner

  init(
    configuration: WindowSceneConfiguration,
    isPrimary: Bool,
    resources: SceneSessionResources? = nil,
    sessionRunner: SessionRunner? = nil
  ) throws {
    self.configuration = configuration
    self.isPrimary = isPrimary
    self.lifecycle = SceneLifecycle(isPrimary: isPrimary)

    if let resources {
      ptyPair = nil
      self.resources = resources
    } else if isPrimary {
      ptyPair = nil
      #if canImport(WASILibc)
        self.resources = SceneSessionResources(
          terminalHost: WebTerminalHost(surfaceSize: .init(width: 80, height: 24)),
          terminalInputReader: InputReader(),
          signalReader: InProcessSignalReader(),
          surfaceName: "ghostty-web"
        )
      #else
        self.resources = SceneSessionResources(
          terminalHost: TerminalHost(),
          terminalInputReader: InputReader(),
          signalReader: defaultSignalReader()
        )
      #endif
    } else {
      #if canImport(WASILibc)
        throw SceneRuntimeError.secondaryScenesUnavailableOnWASI
      #else
        let pty = try PtyPair()
        ptyPair = pty
        self.resources = SceneSessionResources(
          terminalHost: TerminalHost(
            inputFileDescriptor: pty.masterFD,
            outputFileDescriptor: pty.masterFD
          ),
          terminalInputReader: InputReader(fileDescriptor: pty.masterFD)
        )
      #endif
    }

    stateContainer = StateContainer(
      initialState: MultiSceneRuntimeState(),
      invalidationIdentities: [configuration.rootIdentity]
    )
    focusTracker = FocusTracker(
      invalidationIdentities: [configuration.rootIdentity]
    )
    dynamicStateStore = DynamicStateStore(
      invalidationIdentities: [configuration.rootIdentity]
    )
    self.sessionRunner =
      sessionRunner ?? { runtime, sessionName in
        try await runtime.runSceneSession(sessionName: sessionName)
      }
  }

  var sceneInfo: SceneInfo {
    SceneInfo(
      id: configuration.identifier,
      title: configuration.title,
      ptyPath: ptyPair?.slavePath,
      isAttached: lifecycle.state == .rendering
    )
  }

  func run(
    sessionName: String,
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void = { _ in }
  ) async throws -> RunLoopResult<MultiSceneRuntimeState> {
    if isPrimary {
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
    ptyPair?.close()
  }

  private func runSceneSession(
    sessionName: String
  ) async throws -> RunLoopResult<MultiSceneRuntimeState> {
    try await SceneSession.run(
      configuration: configuration,
      sessionName: sessionName,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      dynamicStateStore: dynamicStateStore,
      resources: resources
    )
  }

  private func waitForClient(
    onAttachmentChanged: @escaping @Sendable (Bool) -> Void
  ) async -> Bool {
    guard let pty = ptyPair else { return true }

    while !Task.isCancelled {
      if pty.hasAttachedClient() {
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
