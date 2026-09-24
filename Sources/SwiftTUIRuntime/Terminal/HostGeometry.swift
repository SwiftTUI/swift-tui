import SwiftTUICore

/// Geometry input is separate from transport epoch/generation. UInt64 is
/// deliberate: the accepted JavaScript-safe range exceeds Int on wasm32.
package struct HostGeometryRequest: Equatable, Sendable {
  package static let maximumRevision: UInt64 = 9_007_199_254_740_991
  package static let maximumCellPitch = 8192
  package let revision: UInt64
  package let size: CellSize
  package let cellPixelSize: PixelSize

  package init?(revision: UInt64, size: CellSize, cellPixelSize: PixelSize) {
    guard revision > 0, revision <= Self.maximumRevision,
      size.width > 0, size.height > 0, HostWireBudget.admits(size),
      cellPixelSize.width > 0, cellPixelSize.height > 0,
      cellPixelSize.width <= Self.maximumCellPitch,
      cellPixelSize.height <= Self.maximumCellPitch
    else { return nil }
    self.revision = revision
    self.size = size
    self.cellPixelSize = cellPixelSize
  }
}

/// The session component stays inside Swift. It prevents queued input from a
/// retired WebSocket connection matching another connection's numeric revision.
package struct HostGeometryStamp: Equatable, Sendable {
  package let session: UInt64
  package let revision: UInt64

  package init(session: UInt64, revision: UInt64) {
    self.session = session
    self.revision = revision
  }
}

/// Captured once before a layout acquisition, including asynchronous renders.
/// Resolve context and size proposal must consume the same configuration.
package struct HostLayoutConfiguration: Sendable {
  package let size: CellSize
  package let appearance: TerminalAppearance
  package let theme: Theme?
  package let graphics: TerminalGraphicsCapabilities
  package let pointer: PointerInputCapabilities
  package let geometry: HostGeometryStamp?

  package init(
    size: CellSize,
    appearance: TerminalAppearance,
    theme: Theme?,
    graphics: TerminalGraphicsCapabilities,
    pointer: PointerInputCapabilities,
    geometry: HostGeometryStamp? = nil
  ) {
    self.size = size
    self.appearance = appearance
    self.theme = theme
    self.graphics = graphics
    self.pointer = pointer
    self.geometry = geometry
  }
}

/// Web transports implement the capture under their configuration lock. Other
/// presentation surfaces retain the existing metrics-provider contract.
package protocol HostGeometryPresentationSurface: PresentationSurfaceMetricsProvider {
  func captureHostLayoutConfiguration() -> HostLayoutConfiguration
}

extension PresentationSurfaceMetricsProvider {
  package func hostLayoutConfiguration() -> HostLayoutConfiguration {
    if let host = self as? any HostGeometryPresentationSurface {
      return host.captureHostLayoutConfiguration()
    }
    return HostLayoutConfiguration(
      size: surfaceSize, appearance: appearance, theme: theme,
      graphics: graphicsCapabilities, pointer: pointerInputCapabilities
    )
  }
}
