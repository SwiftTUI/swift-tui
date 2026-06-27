import SwiftTUICore

/// Metrics describing how a frame was presented to the terminal.
public struct TerminalPresentationMetrics: Equatable, Sendable {
  /// The presentation strategy used for a frame commit.
  public enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  public enum GraphicsReplayScope: String, Equatable, Sendable {
    case none
    case targeted
    case full
  }

  public enum EditOperationLowering: String, Equatable, Sendable {
    case none
    case eraseToEndOfLine
  }

  public var bytesWritten: Int
  public var linesTouched: Int
  public var cellsChanged: Int
  public var strategy: Strategy
  public var usedSynchronizedOutput: Bool
  public var graphicsReplayScope: GraphicsReplayScope
  public var graphicsAttachmentsReplayed: Int
  public var editOperationLowering: EditOperationLowering
  public var editOperationCount: Int

  public init(
    bytesWritten: Int = 0,
    linesTouched: Int = 0,
    cellsChanged: Int = 0,
    strategy: Strategy = .fullRepaint,
    usedSynchronizedOutput: Bool = false,
    graphicsReplayScope: GraphicsReplayScope = .none,
    graphicsAttachmentsReplayed: Int = 0,
    editOperationLowering: EditOperationLowering = .none,
    editOperationCount: Int = 0
  ) {
    self.bytesWritten = max(0, bytesWritten)
    self.linesTouched = max(0, linesTouched)
    self.cellsChanged = max(0, cellsChanged)
    self.strategy = strategy
    self.usedSynchronizedOutput = usedSynchronizedOutput
    self.graphicsReplayScope = graphicsReplayScope
    self.graphicsAttachmentsReplayed = max(0, graphicsAttachmentsReplayed)
    self.editOperationLowering = editOperationLowering
    self.editOperationCount = max(0, editOperationCount)
  }

  public var usedFullRepaint: Bool {
    strategy == .fullRepaint
  }

  // `package`: lets the shared test recording surface in SwiftTUITestSupport
  // synthesize a presentation result without re-deriving write steps. Stays
  // below `public` — not API surface, just same-package (test-support) reach.
  package static func fullRepaint(
    for surface: RasterSurface,
    capabilityProfile: TerminalCapabilityProfile,
    origin: CellPoint = .zero
  ) -> Self {
    let cellCount = max(0, surface.size.width) * max(0, surface.size.height)
    let writeSteps = fullRepaintWriteSteps(
      for: surface,
      capabilityProfile: capabilityProfile
    )
    var bytesWritten = fullRepaintBytesWritten(
      writeSteps: writeSteps,
      origin: origin
    )
    if capabilityProfile.supportsSynchronizedOutput, bytesWritten > 0 {
      bytesWritten += "\u{001B}[?2026h".utf8.count
      bytesWritten += "\u{001B}[?2026l".utf8.count
    }

    return Self(
      bytesWritten: bytesWritten,
      linesTouched: max(0, surface.size.height),
      cellsChanged: cellCount,
      strategy: .fullRepaint,
      usedSynchronizedOutput: capabilityProfile.supportsSynchronizedOutput,
      graphicsReplayScope: surface.imageAttachments.isEmpty ? .none : .full,
      graphicsAttachmentsReplayed: surface.imageAttachments.count
    )
  }

  @_spi(Runners) public static func rasterHostMetrics(
    for surface: RasterSurface,
    damage: PresentationDamage?,
    bytesWritten: Int = 0,
    graphicsReplayScope: GraphicsReplayScope? = nil,
    graphicsAttachmentsReplayed: Int? = nil
  ) -> Self {
    let defaultGraphicsScope: GraphicsReplayScope =
      if damage == nil || damage?.requiresFullGraphicsReplay == true {
        surface.imageAttachments.isEmpty ? .none : .full
      } else if damage?.graphicsInvalidation.isEmpty == false {
        .targeted
      } else {
        .none
      }
    let replayedAttachments =
      graphicsAttachmentsReplayed
      ?? (defaultGraphicsScope == .none ? 0 : surface.imageAttachments.count)

    guard let damage, !damage.requiresFullTextRepaint else {
      return Self(
        bytesWritten: bytesWritten,
        linesTouched: max(0, surface.size.height),
        cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
        strategy: .fullRepaint,
        graphicsReplayScope: graphicsReplayScope ?? defaultGraphicsScope,
        graphicsAttachmentsReplayed: replayedAttachments
      )
    }

    let cellsChanged = damage.textRows.reduce(0) { partial, row in
      if row.columnRanges.isEmpty {
        return partial + max(0, surface.size.width)
      }
      return partial
        + row.columnRanges.reduce(0) { rowPartial, range in
          rowPartial + max(0, range.upperBound - range.lowerBound)
        }
    }

    return Self(
      bytesWritten: bytesWritten,
      linesTouched: damage.textRows.count,
      cellsChanged: cellsChanged,
      strategy: .incremental,
      graphicsReplayScope: graphicsReplayScope ?? defaultGraphicsScope,
      graphicsAttachmentsReplayed: replayedAttachments
    )
  }
}

/// Host-facing name for metrics describing a committed presentation frame.
public typealias PresentationMetrics = TerminalPresentationMetrics

/// Provides surface metrics needed to resolve and lay out frames.
///
/// Metrics providers can be terminal devices, web transports, native host
/// surfaces, or pure semantic-frame consumers. This role intentionally excludes
/// terminal raw-mode and byte-writing obligations.
public protocol PresentationSurfaceMetricsProvider: AnyObject {
  var surfaceSize: CellSize { get }
  var capabilityProfile: TerminalCapabilityProfile { get }
  var appearance: TerminalAppearance { get }
  var theme: Theme? { get }
  var graphicsCapabilities: TerminalGraphicsCapabilities { get }
  var pointerInputCapabilities: PointerInputCapabilities { get }
}

/// Terminal-control role for presentation targets that emit terminal bytes.
public protocol TerminalCommandPresentationSurface: AnyObject {
  func enableRawMode() throws
  func disableRawMode() throws
  func write(_ output: String) throws
  func clearScreen() throws
  func moveCursor(to point: CellPoint) throws
  func setPointerHoverEnabled(_ enabled: Bool) throws
}

/// Presents committed raster frames.
public protocol RasterPresentationSurface: AnyObject {
  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics
}

/// Terminal-shaped aggregate presentation target used by terminal hosts.
///
/// Non-terminal hosts should conform to the narrower roles they need, such as
/// ``PresentationSurfaceMetricsProvider`` and
/// ``SemanticHostFramePresentationSurface``.
public protocol PresentationSurface:
  PresentationSurfaceMetricsProvider, TerminalCommandPresentationSurface,
  RasterPresentationSurface
{}

package protocol DamageAwarePresentationSurface: RasterPresentationSurface {
  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics
}

/// Capabilities requested by a surface that consumes semantic host frames.
public struct SemanticHostFrameCapabilities: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The surface can use raster damage hints to avoid full repaint work.
  public static let rasterDamage = Self(rawValue: 1 << 0)

  /// The surface consumes the frame's accessibility tree.
  public static let accessibilityTree = Self(rawValue: 1 << 1)

  /// The surface can publish imperative accessibility announcements.
  public static let accessibilityAnnouncements = Self(rawValue: 1 << 2)

  /// The surface consumes interaction regions for host-side routing.
  public static let interactionRouting = Self(rawValue: 1 << 3)

  /// The surface consumes focus regions or focused identity.
  public static let focusRouting = Self(rawValue: 1 << 4)

  /// Default capability set for current semantic host-frame consumers.
  public static let standard: Self = [
    .rasterDamage,
    .accessibilityTree,
    .accessibilityAnnouncements,
    .interactionRouting,
    .focusRouting,
  ]
}

/// A committed raster frame plus the semantic data needed by non-terminal hosts.
///
/// ``sequence`` is monotonically increasing for each runtime producer. Hosts
/// can use it to detect stale asynchronous work without inferring freshness
/// from callback ordering.
///
/// ``rasterDamage`` describes changed raster rows/ranges relative to the
/// previous committed raster frame. It is not a semantic-tree diff.
///
/// ``preferredLayoutSize`` is the measured window content size before the
/// host's raster surface minimum is applied. Native hosts can use it as an
/// ideal size when negotiating with an outer layout system.
public struct SemanticHostFrame: Equatable, Sendable {
  public var sequence: UInt64
  public var raster: RasterSurface
  public var semantics: SemanticSnapshot
  public var focusedIdentity: Identity?
  public var rasterDamage: PresentationDamage?
  public var preferredLayoutSize: CellSize?

  public init(
    sequence: UInt64,
    raster: RasterSurface,
    semantics: SemanticSnapshot,
    focusedIdentity: Identity?,
    rasterDamage: PresentationDamage? = nil,
    preferredLayoutSize: CellSize? = nil
  ) {
    self.sequence = sequence
    self.raster = raster
    self.semantics = semantics
    self.focusedIdentity = focusedIdentity
    self.rasterDamage = rasterDamage
    self.preferredLayoutSize = preferredLayoutSize
  }
}

@_spi(Runners)
public protocol SemanticHostFramePresentationSurface:
  PresentationSurfaceMetricsProvider
{
  var semanticHostFrameCapabilities: SemanticHostFrameCapabilities { get }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics
}

extension SemanticHostFramePresentationSurface {
  public var semanticHostFrameCapabilities: SemanticHostFrameCapabilities {
    .standard
  }
}

extension PresentationSurfaceMetricsProvider {
  public var theme: Theme? {
    nil
  }

  public var graphicsCapabilities: TerminalGraphicsCapabilities {
    .none
  }

  public var pointerInputCapabilities: PointerInputCapabilities {
    .cellOnly
  }
}

extension TerminalCommandPresentationSurface {
  public func setPointerHoverEnabled(_: Bool) throws {}
}

extension PresentationSurface {
  public var theme: Theme? {
    nil
  }

  public var graphicsCapabilities: TerminalGraphicsCapabilities {
    .none
  }

  public var pointerInputCapabilities: PointerInputCapabilities {
    .cellOnly
  }

  public func setPointerHoverEnabled(_: Bool) throws {}

  @discardableResult
  public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let origin = CellPoint.zero
    let writeSteps = fullRepaintWriteSteps(
      for: surface,
      capabilityProfile: capabilityProfile,
      terminalBackgroundColor: appearance.backgroundColor
    )
    let metrics = TerminalPresentationMetrics(
      bytesWritten: fullRepaintBytesWritten(
        writeSteps: writeSteps,
        origin: origin
      ),
      linesTouched: max(0, surface.size.height),
      cellsChanged: max(0, surface.size.width) * max(0, surface.size.height),
      strategy: .fullRepaint
    )

    try clearScreen()
    try moveCursor(to: origin)

    for writeStep in writeSteps {
      try write(writeStep)
    }
    return metrics
  }
}
