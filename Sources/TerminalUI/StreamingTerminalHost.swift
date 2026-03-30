import Synchronization

package final class StreamingTerminalHost: TerminalHosting, @unchecked Sendable {
  private struct State {
    var surfaceSize: Size
    var appearance: TerminalAppearance
  }

  private let state: Mutex<State>
  private let writeLock = Mutex(())
  private let outputHandler: @Sendable (String) -> Void

  package let capabilityProfile: TerminalCapabilityProfile
  package let graphicsCapabilities: TerminalGraphicsCapabilities

  package init(
    surfaceSize: Size,
    appearance: TerminalAppearance? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none,
    environment: [String: String]? = nil,
    outputHandler: @escaping @Sendable (String) -> Void
  ) {
    self.outputHandler = outputHandler
    self.capabilityProfile = capabilityProfile
    self.graphicsCapabilities = graphicsCapabilities

    let resolvedAppearance =
      appearance
      ?? TerminalAppearance.detect(
        environment: environment ?? currentProcessEnvironment(),
        capabilityProfile: capabilityProfile
      )

    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        appearance: resolvedAppearance
      )
    )
  }

  package var surfaceSize: Size {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.appearance)
  }

  package func updateSurfaceSize(
    _ surfaceSize: Size
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
    }
  }

  package func updateAppearance(
    _ appearance: TerminalAppearance
  ) {
    state.withLock { state in
      state.appearance = appearance
    }
  }

  package func enableRawMode() throws {
    var setup = "\u{001B}[?1049h"
    setup += "\u{001B}[?25l"
    if capabilityProfile.supportsMouseReporting {
      setup += "\u{001B}[?1002h\u{001B}[?1006h"
    }
    try write(setup)
  }

  package func disableRawMode() throws {
    var teardown = ""
    if capabilityProfile.supportsMouseReporting {
      teardown += "\u{001B}[?1002l\u{001B}[?1006l"
    }
    teardown += "\u{001B}[?25h"
    teardown += "\u{001B}[0m"
    teardown += "\u{001B}[?1049l"
    try write(teardown)
  }

  package func write(
    _ output: String
  ) throws {
    writeLock.withLock { _ in
      outputHandler(output)
    }
  }

  package func clearScreen() throws {
    try write("\u{001B}[2J")
  }

  package func moveCursor(
    to point: Point
  ) throws {
    let row = max(1, point.y + 1)
    let column = max(1, point.x + 1)
    try write("\u{001B}[\(row);\(column)H")
  }
}
