@_spi(Runners) import TerminalUI
import View

@MainActor
func runTestSceneSession<S: Scene>(
  scene: S,
  sessionName: String,
  terminalHost: any TerminalHosting,
  inputReader: any InputReading,
  signalReader: (any SignalReading)? = nil,
  scheduler: any FrameScheduling = FrameScheduler()
) async throws -> RunLoopResult<TerminalUISceneSessionState> {
  let configurations = collectWindowSceneConfigurations(from: scene)
  guard !configurations.isEmpty else {
    throw AppLaunchError.noScenes
  }
  guard configurations.count == 1 else {
    throw TestSceneSessionError.multipleScenesUnsupported(count: configurations.count)
  }

  let configuration = configurations[0]
  let terminalInputReader: any TerminalInputReading =
    if let terminalInputReader = inputReader as? any TerminalInputReading {
      terminalInputReader
    } else {
      TestKeyboardOnlyInputAdapter(inputReader: inputReader)
    }

  return try await SceneSession.run(
    configuration: configuration,
    sessionName: sessionName,
    stateContainer: StateContainer(
      initialState: TerminalUISceneSessionState(),
      invalidationIdentities: [configuration.rootIdentity]
    ),
    focusTracker: FocusTracker(
      invalidationIdentities: [configuration.rootIdentity]
    ),
    resources: .init(
      terminalHost: terminalHost,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler
    )
  )
}

private enum TestSceneSessionError: Error, Equatable, Sendable, CustomStringConvertible {
  case multipleScenesUnsupported(count: Int)

  var description: String {
    switch self {
    case .multipleScenesUnsupported(let count):
      return "Expected exactly one scene, but received \(count)."
    }
  }
}

private final class TestKeyboardOnlyInputAdapter: TerminalInputReading {
  private let inputReader: any InputReading

  init(inputReader: any InputReading) {
    self.inputReader = inputReader
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let keyEvents = inputReader.events()
      let task = Task {
        for await keyPress in keyEvents {
          continuation.yield(.key(keyPress))
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
