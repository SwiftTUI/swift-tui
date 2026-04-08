import Synchronization

package final class StreamingTerminalHost: TerminalHosting, DamageAwareTerminalHosting, Sendable
{
  private struct State: Sendable {
    var surfaceSize: Size
    var renderStyle: TerminalRenderStyle
    var lastSubmittedSurface: RasterSurface?
  }

  private let state: Mutex<State>
  private let writeLock = Mutex(())
  private let outputHandler: @Sendable (String) -> Void

  package let capabilityProfile: TerminalCapabilityProfile
  package let graphicsCapabilities: TerminalGraphicsCapabilities

  package init(
    surfaceSize: Size,
    appearance: TerminalAppearance? = nil,
    theme: Theme? = nil,
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
        renderStyle: .init(
          appearance: resolvedAppearance,
          theme: theme
        ),
        lastSubmittedSurface: nil
      )
    )
  }

  package var surfaceSize: Size {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  package var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  package func updateSurfaceSize(
    _ surfaceSize: Size
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.lastSubmittedSurface = nil
    }
  }

  package func updateAppearance(
    _ appearance: TerminalAppearance
  ) {
    state.withLock { state in
      state.renderStyle.appearance = appearance
      state.lastSubmittedSurface = nil
    }
  }

  package func updateTheme(
    _ theme: Theme?
  ) {
    state.withLock { state in
      state.renderStyle.theme = theme
      state.lastSubmittedSurface = nil
    }
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
      state.lastSubmittedSurface = nil
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

  @discardableResult
  package func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    try present(
      surface,
      damage: nil
    )
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    let previousSurface = state.withLock(\.lastSubmittedSurface)
    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: previousSurface,
      currentSurface: surface,
      damage: damage
    )

    var output: String
    switch plan.strategy {
    case .fullRepaint:
      let rendered = TerminalSurfaceRenderer(
        capabilityProfile: capabilityProfile
      ).render(surface)
      output = "\u{001B}[2J\u{001B}[1;1H\(rendered)"
    case .incremental:
      let estimatedSize = plan.spanUpdates.reduce(0) { $0 + 16 + $1.renderedSpan.utf8.count }
      output = ""
      output.reserveCapacity(estimatedSize)
      for spanUpdate in plan.spanUpdates {
        output += "\u{001B}[\(max(1, spanUpdate.row + 1));\(max(1, spanUpdate.column + 1))H"
        output += spanUpdate.renderedSpan
      }
    }

    if !output.isEmpty {
      try write(output)
    }

    state.withLock { state in
      state.lastSubmittedSurface = surface
    }

    return TerminalPresentationMetrics(
      bytesWritten: output.utf8.count,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
  }
}
