// This whole module is compiled out on Windows: the dependency edges to
// SwiftTerm and the PTY layer are platform-conditional in Package.swift, so
// the target must compile to an empty module there.
#if !os(Windows)
  import SwiftTUICore
  import SwiftTUIRuntime
  import SwiftTUITerminalEmulation

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
    private let acceptsFocusedInput: Bool

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
      self.init(
        session: session,
        keyRouting: keyRouting,
        onTitleChange: onTitleChange,
        onExit: onExit,
        acceptsFocusedInput: true
      )
    }

    private init(
      session: Session,
      keyRouting: @escaping @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition,
      onTitleChange: (@MainActor @Sendable (String) -> Void)?,
      onExit: (@MainActor @Sendable (TerminalExitReason) -> Void)?,
      acceptsFocusedInput: Bool
    ) {
      self.session = session
      self.keyRouting = keyRouting
      self.onTitleChange = onTitleChange
      self.onExit = onExit
      self.acceptsFocusedInput = acceptsFocusedInput
    }

    public var body: some View {
      let generation = updateGeneration
      EnvironmentReader(\.terminalEventHandlers) { terminalEventHandlers in
        EnvironmentReader(\.clipboardWriteAction) { clipboardWriteAction in
          GeometryReader { proxy in
            let surface =
              ForeignSurface(payload: SessionGridPayload(session: session, generation: generation))
              .task(
                id: TerminalViewLifecycleID(session: ObjectIdentifier(session), size: proxy.size)
              ) {
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

            surface
              .focusable(acceptsFocusedInput)
              .onKeyPress { keyPress in
                acceptsFocusedInput ? handleFocusedKey(keyPress) : .ignored
              }
          }
        }
      }
    }

    @MainActor
    fileprivate func withoutFocusedInput() -> TerminalView<Session> {
      TerminalView(
        session: session,
        keyRouting: keyRouting,
        onTitleChange: onTitleChange,
        onExit: onExit,
        acceptsFocusedInput: false
      )
    }

    @MainActor
    fileprivate func handleFocusedKey(_ keyPress: KeyPress) -> KeyPressResult {
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
  }

  extension TerminalView {
    /// Binds host focus directly to this terminal's framework-owned input member.
    ///
    /// Use this modifier when an embedding host owns an enum-valued focus model.
    /// The focused member still applies ``TerminalViewKeyDisposition`` before
    /// forwarding keys to the child session.
    @MainActor
    public func hostFocused<Value: Hashable>(
      _ binding: FocusState<Value?>.Binding,
      equals value: Value
    ) -> some View {
      TerminalViewHostFocused(
        terminalView: self,
        binding: binding,
        value: value
      )
    }
  }

  @MainActor
  private struct TerminalViewHostFocused<Session: TerminalSession, Value: Hashable>: View {
    private let terminalView: TerminalView<Session>
    private let binding: FocusState<Value?>.Binding
    private let value: Value

    fileprivate init(
      terminalView: TerminalView<Session>,
      binding: FocusState<Value?>.Binding,
      value: Value
    ) {
      self.terminalView = terminalView
      self.binding = binding
      self.value = value
    }

    public var body: some View {
      terminalView.withoutFocusedInput()
        .focusable(true)
        .focused(binding, equals: value)
        .onKeyPress(perform: terminalView.handleFocusedKey)
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
#endif
