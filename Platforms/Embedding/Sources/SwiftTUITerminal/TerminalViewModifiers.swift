import SwiftTUIRuntime

struct TerminalEventHandlers: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  var titleChanged: (@MainActor @Sendable (String) -> Void)?
  var workingDirectoryChanged: (@MainActor @Sendable (String) -> Void)?

  var description: String {
    "TerminalEventHandlers(titleChanged:\(titleChanged != nil),workingDirectoryChanged:\(workingDirectoryChanged != nil))"
  }

  var debugDescription: String {
    description
  }
}

private enum TerminalEventHandlersKey: EnvironmentKey {
  static let defaultValue = TerminalEventHandlers()
}

extension EnvironmentValues {
  var terminalEventHandlers: TerminalEventHandlers {
    get { self[TerminalEventHandlersKey.self] }
    set { self[TerminalEventHandlersKey.self] = newValue }
  }
}

extension View {
  @MainActor
  public func terminalTitleChanged(
    _ handler: @escaping @MainActor @Sendable (String) -> Void
  ) -> some View {
    transformEnvironment(\.terminalEventHandlers) { handlers in
      handlers.titleChanged = handler
    }
  }

  @MainActor
  public func terminalWorkingDirectoryChanged(
    _ handler: @escaping @MainActor @Sendable (String) -> Void
  ) -> some View {
    transformEnvironment(\.terminalEventHandlers) { handlers in
      handlers.workingDirectoryChanged = handler
    }
  }
}
