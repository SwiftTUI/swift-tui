import SwiftTUICore
import SwiftTUIRuntime

public struct TerminalView<Session: TerminalSession>: View {
  @State private var updateGeneration: UInt64 = 0

  private let session: Session
  private let onTitleChange: (@MainActor @Sendable (String) -> Void)?
  private let onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)?

  public init(
    session: Session,
    onTitleChange: (@MainActor @Sendable (String) -> Void)? = nil,
    onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)? = nil
  ) {
    self.session = session
    self.onTitleChange = onTitleChange
    self.onExit = onExit
  }

  public var body: some View {
    let generation = updateGeneration
    EnvironmentReader(\.terminalEventHandlers) { terminalEventHandlers in
      EnvironmentReader(\.clipboardWriteAction) { clipboardWriteAction in
        GeometryReader { proxy in
          ForeignSurface(payload: SessionGridPayload(session: session, generation: generation))
            .focusable(true)
            .onKeyPress { keyPress in
              guard let key = TerminalEmulatorKey(keyPress: keyPress) else {
                return .ignored
              }
              Task {
                await session.send(key: key)
              }
              return .handled
            }
            .task(id: TerminalViewLifecycleID(session: ObjectIdentifier(session), size: proxy.size))
          {
            let events = session.events()
            try? await session.start()
            try? await session.resize(proxy.size)

            for await event in events {
              updateGeneration &+= 1
              switch event {
              case .titleChanged(let title):
                onTitleChange?(title)
                terminalEventHandlers.titleChanged?(title)
              case .workingDirectoryChanged(let directory):
                terminalEventHandlers.workingDirectoryChanged?(directory)
              case .clipboardWriteRequested(let bytes):
                _ = clipboardWriteAction(String(decoding: bytes, as: UTF8.self))
              default:
                break
              }
            }

            if case .exited(let reason) = await session.currentLifecycle() {
              onExit?(reason)
            }
          }
        }
      }
    }
  }
}

private struct TerminalViewLifecycleID: Equatable {
  var session: ObjectIdentifier
  var size: CellSize
}

private struct SessionGridPayload<Session: TerminalSession>: ForeignSurfacePayload {
  let session: Session
  let generation: UInt64

  var grid: ForeignGrid {
    _ = generation
    return session.cachedSnapshot
  }
}
