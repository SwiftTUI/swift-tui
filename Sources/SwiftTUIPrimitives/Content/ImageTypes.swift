/// A high-level image source used by the public view surface.
public enum ImageSource: Equatable, Hashable, Sendable {
  case path(String)
  case fileURL(String)
  case data([UInt8])
}

/// A normalized image reference used by the renderer and host runtime.
public enum ImageAssetReference: Equatable, Hashable, Sendable {
  case namedResource(String)
  case filePath(String)
  case embeddedImage([UInt8])
}

/// Layout behavior used when an image participates in resizable measurement.
public enum ImageScalingMode: String, CaseIterable, Equatable, Sendable {
  case stretch
  case fit
  case fill
}

/// Image metadata resolved before layout and presentation.
public struct ResolvedImageAsset: Equatable, Sendable {
  public var reference: ImageAssetReference
  public var pixelSize: PixelSize
  public var intrinsicCellSize: CellSize
  /// Pixel dimensions of a single terminal cell at the time of resolution.
  /// Carried here so the layout engine can reconcile pixel-space aspect
  /// ratios (source image) with cell-space frames (parent proposals) when
  /// measuring `.scaledToFit()` / `.scaledToFill()` images.
  public var cellPixelSize: PixelSize

  public init(
    reference: ImageAssetReference,
    pixelSize: PixelSize,
    intrinsicCellSize: CellSize,
    cellPixelSize: PixelSize
  ) {
    self.reference = reference
    self.pixelSize = pixelSize
    self.intrinsicCellSize = intrinsicCellSize
    self.cellPixelSize = cellPixelSize
  }
}

/// The draw payload used for image leaves.
public struct ImagePayload: Equatable, Sendable {
  public var source: ImageSource
  public var resolvedAsset: ResolvedImageAsset?
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode
  /// Effective opacity accumulated by draw extraction. Authored image values
  /// start at `1`; ancestor and local opacity modifiers multiply into this
  /// value before the raster attachment boundary clamps it.
  package var opacity: Double

  public init(
    source: ImageSource,
    resolvedAsset: ResolvedImageAsset? = nil,
    isResizable: Bool = false,
    scalingMode: ImageScalingMode = .stretch
  ) {
    self.source = source
    self.resolvedAsset = resolvedAsset
    self.isResizable = isResizable
    self.scalingMode = scalingMode
    self.opacity = 1
  }

  public var intrinsicCellSize: CellSize {
    resolvedAsset?.intrinsicCellSize ?? .zero
  }
}

/// A captured cell backdrop used to precompose a blended image.
public struct RasterImageBackdrop: Equatable, Sendable {
  public var bounds: CellRect
  public var cells: [RasterImageBackdropCell]

  public init(
    bounds: CellRect,
    cells: [RasterImageBackdropCell]
  ) {
    self.bounds = bounds
    self.cells = cells
  }
}

/// A single cell in a captured image-compositing backdrop.
public struct RasterImageBackdropCell: Equatable, Sendable {
  public var backgroundColor: Color?
  public var foregroundColor: Color?
  public var glyph: Character?
  public var spanWidth: Int
  public var spanOffset: Int

  public init(
    backgroundColor: Color?,
    foregroundColor: Color? = nil,
    glyph: Character? = nil,
    spanWidth: Int = 1,
    spanOffset: Int = 0
  ) {
    self.backgroundColor = backgroundColor
    self.foregroundColor = foregroundColor
    self.glyph = glyph
    self.spanWidth = spanWidth
    self.spanOffset = spanOffset
  }
}

/// Raster-time metadata for precomposing an image with a captured backdrop.
public struct RasterImageCompositing: Equatable, Sendable {
  public var blendMode: BlendMode
  public var destinationBackdrop: RasterImageBackdrop
  public var sourceBackdrop: RasterImageBackdrop?
  public var cellPixelSize: PixelSize
  public var backdropSignature: UInt64

  public init(
    blendMode: BlendMode,
    destinationBackdrop: RasterImageBackdrop,
    sourceBackdrop: RasterImageBackdrop? = nil,
    cellPixelSize: PixelSize,
    backdropSignature: UInt64
  ) {
    self.blendMode = blendMode
    self.destinationBackdrop = destinationBackdrop
    self.sourceBackdrop = sourceBackdrop
    self.cellPixelSize = cellPixelSize
    self.backdropSignature = backdropSignature
  }
}

/// A raster-time image placement that the host can present natively.
public struct RasterImageAttachment: Equatable, Sendable {
  /// The full logical destination rect in terminal cells before viewport clipping.
  public var identity: Identity
  public var bounds: CellRect
  /// The portion of ``bounds`` currently visible after ancestor clipping.
  public var visibleBounds: CellRect
  /// The portion of ``visibleBounds`` not covered by cell content painted
  /// after the image, or `nil` when nothing above the image intersects it.
  /// Rasterization derives this from the paint-order sidecar. Layered hosts
  /// composite that order directly and ignore this; hosts whose graphics
  /// cannot stack under later text (kitty placements, the fallback overlay
  /// stamp) draw ``effectiveVisibleBounds`` instead. A zero-size value means
  /// the image is fully covered and must not be drawn.
  package var unoccludedVisibleBounds: CellRect?
  public var source: ImageSource
  public var resolvedReference: ImageAssetReference?
  public var pixelSize: PixelSize?
  public var cellPixelSize: PixelSize?
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode
  /// Effective placement opacity after multiplying the authored ancestor
  /// chain. The value is normalized to `0...1` at this host boundary.
  public var opacity: Double {
    didSet { opacity = Self.normalizedOpacity(opacity) }
  }
  public var compositing: RasterImageCompositing?

  public init(
    identity: Identity,
    bounds: CellRect,
    visibleBounds: CellRect? = nil,
    source: ImageSource,
    resolvedReference: ImageAssetReference? = nil,
    pixelSize: PixelSize? = nil,
    cellPixelSize: PixelSize? = nil,
    isResizable: Bool = false,
    scalingMode: ImageScalingMode = .stretch,
    opacity: Double = 1,
    compositing: RasterImageCompositing? = nil
  ) {
    self.identity = identity
    self.bounds = bounds
    self.visibleBounds = visibleBounds ?? bounds
    self.unoccludedVisibleBounds = nil
    self.source = source
    self.resolvedReference = resolvedReference
    self.pixelSize = pixelSize
    self.cellPixelSize = cellPixelSize
    self.isResizable = isResizable
    self.scalingMode = scalingMode
    self.opacity = Self.normalizedOpacity(opacity)
    self.compositing = compositing
  }

  private static func normalizedOpacity(_ value: Double) -> Double {
    guard !value.isNaN else { return 1 }
    return min(1, max(0, value))
  }

  /// The rect a non-layering host should draw: ``visibleBounds`` minus any
  /// occlusion trim recorded by rasterization.
  package var effectiveVisibleBounds: CellRect {
    unoccludedVisibleBounds ?? visibleBounds
  }
}
