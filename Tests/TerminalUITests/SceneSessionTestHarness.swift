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
  let descriptors = collectWindowSceneDescriptors(from: scene)
  guard !descriptors.isEmpty else {
    throw AppLaunchError.noScenes
  }
  guard descriptors.count == 1 else {
    throw TestSceneSessionError.multipleScenesUnsupported(count: descriptors.count)
  }

  let terminalInputReader: any TerminalInputReading =
    if let terminalInputReader = inputReader as? any TerminalInputReading {
      terminalInputReader
    } else {
      TestKeyboardOnlyInputAdapter(inputReader: inputReader)
    }

  var visitor = TestSceneSessionSelectionVisitor(
    sessionName: sessionName
  )
  guard
    let selection = withFirstWindowSceneConfiguration(
      in: scene,
      visitor: &visitor
    )
  else {
    throw AppLaunchError.noScenes
  }

  return try await selection.run(
    SceneSessionResources(
      terminalHost: terminalHost,
      terminalInputReader: terminalInputReader,
      signalReader: signalReader,
      scheduler: scheduler
    ),
    StateContainer(
      initialState: TerminalUISceneSessionState(),
      invalidationIdentities: [selection.rootIdentity]
    ),
    FocusTracker(
      invalidationIdentities: [selection.rootIdentity]
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

@MainActor
private struct TestSceneSessionSelection {
  let rootIdentity: Identity
  let run:
    (
      SceneSessionResources,
      StateContainer<TerminalUISceneSessionState>,
      FocusTracker
    ) async throws -> RunLoopResult<TerminalUISceneSessionState>
}

@MainActor
private struct TestSceneSessionSelectionVisitor: WindowSceneConfigurationVisitor {
  let sessionName: String

  mutating func visit<Content: View>(
    descriptor _: TerminalUISceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<TestSceneSessionSelection> {
    let sessionName = self.sessionName

    return .finish(
      TestSceneSessionSelection(
        rootIdentity: configuration.rootIdentity,
        run: { resources, stateContainer, focusTracker in
          try await SceneSession.run(
            configuration: configuration,
            sessionName: sessionName,
            stateContainer: stateContainer,
            focusTracker: focusTracker,
            resources: resources
          )
        }
      )
    )
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
