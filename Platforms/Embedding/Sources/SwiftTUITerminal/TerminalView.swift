import SwiftTUICore
import SwiftTUIRuntime

/// Chooses whether a `TerminalView` key press belongs to its host or child session.
public enum TerminalViewKeyDisposition: Equatable, Sendable {
  /// Convert the key press to a ``TerminalEmulatorKey`` and send it to the child session.
  case forwardToChild
  /// Consume the key press without sending it to the child session.
  case handledByHost
}

public struct TerminalView<Session: TerminalSession>: View {
  @State private var updateGeneration: UInt64 = 0

  private let session: Session
  private let keyRouting: @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition
  private let onTitleChange: (@MainActor @Sendable (String) -> Void)?
  private let onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)?

  /// Creates a view that presents and drives a terminal session, forwarding focused keys to the
  /// child.
  ///
  /// - Parameters:
  ///   - session: The child terminal session to present.
  ///   - onTitleChange: An optional callback for child terminal title changes.
  ///   - onExit: An optional callback when the child session exits.
  public init(
    session: Session,
    onTitleChange: (@MainActor @Sendable (String) -> Void)? = nil,
    onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)? = nil
  ) {
    self.init(
      session: session,
      keyRouting: { _ in .forwardToChild },
      onTitleChange: onTitleChange,
      onExit: onExit
    )
  }

  /// Creates a view that presents and drives a terminal session with host-level key routing.
  ///
  /// - Parameters:
  ///   - session: The child terminal session to present.
  ///   - keyRouting: A host-level interceptor called with the original focused key press, before
  ///     conversion to ``TerminalEmulatorKey``. Return
  ///     ``TerminalViewKeyDisposition/handledByHost`` to consume it in the host or
  ///     ``TerminalViewKeyDisposition/forwardToChild`` to preserve terminal forwarding.
  ///   - onTitleChange: An optional callback for child terminal title changes.
  ///   - onExit: An optional callback when the child session exits.
  public init(
    session: Session,
    keyRouting: @escaping @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition,
    onTitleChange: (@MainActor @Sendable (String) -> Void)? = nil,
    onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)? = nil
  ) {
    self.session = session
    self.keyRouting = keyRouting
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
              guard keyRouting(keyPress) == .forwardToChild else {
                return .handled
              }
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
