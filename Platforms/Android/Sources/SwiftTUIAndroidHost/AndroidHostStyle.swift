public import SwiftTUIRuntime

public struct AndroidHostStyle: Equatable, Sendable {
  public var renderStyle: TerminalRenderStyle
  public var initialSurfaceSize: CellSize

  public init(
    renderStyle: TerminalRenderStyle = TerminalRenderStyle(appearance: .fallback),
    initialSurfaceSize: CellSize = CellSize(width: 80, height: 24)
  ) {
    self.renderStyle = renderStyle
    self.initialSurfaceSize = initialSurfaceSize
  }

  public static let `default` = Self()
}
