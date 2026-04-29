import Synchronization

package final class StreamingTerminalHost: TerminalHosting, DamageAwareTerminalHosting,
  TerminalInputCapabilityProviding, Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var pointerHoverEnabled: Bool
    var lastSubmittedSurface: RasterSurface?
  }

  private let state: Mutex<State>
  private let writeLock = Mutex(())
  private let outputHandler: @Sendable (String) -> Void

  package let capabilityProfile: TerminalCapabilityProfile

  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  package var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  package var resolvedInputCapabilities: ResolvedTerminalInputCapabilities {
    state.withLock { state in
      ResolvedTerminalInputCapabilities(
        mouseCoordinateMode: Self.mouseCoordinateMode(
          for: state.pointerInputCapabilities
        ),
        pointerInputCapabilities: state.pointerInputCapabilities
      )
    }
  }

  private static func mouseCoordinateMode(
    for pointerInputCapabilities: PointerInputCapabilities
  ) -> MouseCoordinateMode {
    switch pointerInputCapabilities.precision {
    case .cell:
      return .cells
    case .subCell(let source, let metrics):
      guard source == .terminalPixels else {
        return .cells
      }
      return .pixels(metrics: metrics, source: source)
    }
  }

  package init(
    surfaceSize: CellSize,
    appearance: TerminalAppearance? = nil,
    theme: Theme? = nil,
    capabilityProfile: TerminalCapabilityProfile = .trueColor,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none,
    pointerInputCapabilities: PointerInputCapabilities = .cellOnly,
    environment: [String: String]? = nil,
    outputHandler: @escaping @Sendable (String) -> Void
  ) {
    self.outputHandler = outputHandler
    self.capabilityProfile = capabilityProfile

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
        graphicsCapabilities: graphicsCapabilities,
        pointerInputCapabilities: pointerInputCapabilities,
        pointerHoverEnabled: false,
        lastSubmittedSurface: nil
      )
    )
  }

  package var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  package var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  package func updateSurfaceSize(
    _ surfaceSize: CellSize
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

  package func updateSurfaceCapabilities(
    _ capabilities: TerminalSurfaceCapabilities
  ) {
    state.withLock { state in
      state.graphicsCapabilities.cellPixelSize = capabilities.cellPixelSize
      state.pointerInputCapabilities = capabilities.pointerInputCapabilities
      state.lastSubmittedSurface = nil
    }
  }

  package func enableRawMode() throws {
    var setup = "\u{001B}[?1049h"
    setup += "\u{001B}[?25l"
    if capabilityProfile.supportsMouseReporting {
      setup += enableMouseReportingSequence(
        hoverEnabled: state.withLock(\.pointerHoverEnabled)
      )
    }
    setup += "\u{001B}[?2004h"  // enable bracketed paste
    try write(setup)
  }

  package func disableRawMode() throws {
    var teardown = ""
    if capabilityProfile.supportsMouseReporting {
      if state.withLock(\.pointerHoverEnabled) {
        teardown += "\u{001B}[?1003l"
      }
      if usesTerminalPixelMouseReporting {
        teardown += "\u{001B}[?1016l\u{001B}[?1006l\u{001B}[?1002l"
      } else {
        teardown += "\u{001B}[?1002l\u{001B}[?1006l"
      }
    }
    teardown += "\u{001B}[?2004l"  // disable bracketed paste
    teardown += "\u{001B}[?25h"
    teardown += "\u{001B}[0m"
    teardown += "\u{001B}[?1049l"
    try write(teardown)
  }

  package func setPointerHoverEnabled(_ enabled: Bool) throws {
    guard capabilityProfile.supportsMouseReporting else {
      state.withLock { state in
        state.pointerHoverEnabled = false
      }
      return
    }

    let shouldWrite = state.withLock { state in
      guard state.pointerHoverEnabled != enabled else {
        return false
      }
      state.pointerHoverEnabled = enabled
      return true
    }
    if shouldWrite {
      let sequence =
        if enabled {
          enableMouseReportingSequence(hoverEnabled: true)
        } else {
          "\u{001B}[?1003l" + enableMouseReportingSequence(hoverEnabled: false)
        }
      try write(sequence)
    }
  }

  private func enableMouseReportingSequence(hoverEnabled: Bool) -> String {
    var sequence = "\u{001B}[?1002h\u{001B}[?1006h"
    if usesTerminalPixelMouseReporting {
      sequence += "\u{001B}[?1016h"
    }
    if hoverEnabled {
      sequence += "\u{001B}[?1003h"
    }
    return sequence
  }

  private var usesTerminalPixelMouseReporting: Bool {
    switch state.withLock(\.pointerInputCapabilities.precision) {
    case .cell:
      return false
    case .subCell(let source, metrics: _):
      return source == .terminalPixels
    }
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
    to point: CellPoint
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
      capabilityProfile: capabilityProfile,
      graphicsCapabilities: graphicsCapabilities
    ).plan(
      previousSurface: previousSurface,
      currentSurface: surface,
      damage: damage
    )

    var output: String
    switch plan.strategy {
    case .fullRepaint:
      output = fullRepaintOutput(
        for: surface,
        capabilityProfile: capabilityProfile
      )
    case .incremental:
      let estimatedSize = plan.rowBatches.reduce(0) { partial, rowBatch in
        partial + 16 + rowBatch.renderedBatch.utf8.count
      }
      output = ""
      output.reserveCapacity(estimatedSize)
      for rowBatch in plan.rowBatches {
        output += "\u{001B}[\(max(1, rowBatch.row + 1));\(max(1, rowBatch.anchorColumn + 1))H"
        output += rowBatch.renderedBatch
      }
    }

    let usedSynchronizedOutput =
      !output.isEmpty
      && plan.strategy == .fullRepaint
      && capabilityProfile.supportsSynchronizedOutput
    output = wrappedPresentationOutput(
      output,
      strategy: plan.strategy
    )

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
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental,
      usedSynchronizedOutput: usedSynchronizedOutput
    )
  }

  private func wrappedPresentationOutput(
    _ output: String,
    strategy: TerminalPresentationPlan.Strategy
  ) -> String {
    guard !output.isEmpty,
      strategy == .fullRepaint,
      capabilityProfile.supportsSynchronizedOutput
    else {
      return output
    }

    return "\u{001B}[?2026h" + output + "\u{001B}[?2026l"
  }
}
