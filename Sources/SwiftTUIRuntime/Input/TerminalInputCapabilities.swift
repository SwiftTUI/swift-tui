import SwiftTUICore

package enum MouseCoordinateMode: Equatable, Sendable {
  case disabled
  case cells
  case pixels(metrics: CellPixelMetrics, source: PointerPrecisionSource)

  package static func resolving(
    policy: PointerPrecisionPolicy,
    metrics: CellPixelMetrics?
  ) -> Self {
    switch policy {
    case .cellOnly, .useHostSubCellWhenAvailable:
      return .cells
    case .forceTerminalPixels:
      guard let metrics else {
        return .cells
      }
      return .pixels(metrics: metrics, source: .terminalPixels)
    }
  }

  package var pointerInputCapabilities: PointerInputCapabilities {
    switch self {
    case .disabled, .cells:
      return .cellOnly
    case .pixels(let metrics, let source):
      return .init(
        precision: .subCell(source: source, metrics: metrics)
      )
    }
  }

  package var usesTerminalPixels: Bool {
    switch self {
    case .disabled, .cells:
      return false
    case .pixels(_, let source):
      return source == .terminalPixels
    }
  }

  package var reportsMouseInput: Bool {
    switch self {
    case .disabled:
      return false
    case .cells, .pixels:
      return true
    }
  }
}

package struct ResolvedTerminalInputCapabilities: Equatable, Sendable {
  package var mouseCoordinateMode: MouseCoordinateMode
  package var pointerInputCapabilities: PointerInputCapabilities

  package init(
    mouseCoordinateMode: MouseCoordinateMode = .cells,
    pointerInputCapabilities: PointerInputCapabilities? = nil
  ) {
    self.mouseCoordinateMode = mouseCoordinateMode
    self.pointerInputCapabilities =
      pointerInputCapabilities ?? mouseCoordinateMode.pointerInputCapabilities
  }
}

package protocol TerminalInputCapabilityProviding: AnyObject {
  var resolvedInputCapabilities: ResolvedTerminalInputCapabilities { get }
}

package protocol TerminalInputCapabilityConfiguring: AnyObject {
  func updateInputCapabilities(_ capabilities: ResolvedTerminalInputCapabilities)
}
