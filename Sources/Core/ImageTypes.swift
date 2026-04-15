/// A high-level image source used by the public view surface.
public enum ImageSource: Equatable, Hashable, Sendable {
  case named(String)
  case fileURL(String)
  case pngData([UInt8])
}

/// A normalized image reference used by the renderer and host runtime.
public enum ImageAssetReference: Equatable, Hashable, Sendable {
  case namedResource(String)
  case filePath(String)
  case embeddedPNG([UInt8])
}

/// Layout behavior used when an image participates in resizable measurement.
public enum ImageScalingMode: String, Equatable, Sendable {
  case stretch
  case fit
  case fill
}

/// Image metadata resolved before layout and presentation.
public struct ResolvedImageAsset: Equatable, Sendable {
  public var reference: ImageAssetReference
  public var pixelSize: Size
  public var intrinsicCellSize: Size
  /// Pixel dimensions of a single terminal cell at the time of resolution.
  /// Carried here so the layout engine can reconcile pixel-space aspect
  /// ratios (source image) with cell-space frames (parent proposals) when
  /// measuring `.scaledToFit()` / `.scaledToFill()` images.
  public var cellPixelSize: Size

  public init(
    reference: ImageAssetReference,
    pixelSize: Size,
    intrinsicCellSize: Size,
    cellPixelSize: Size
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
  }

  public var intrinsicCellSize: Size {
    resolvedAsset?.intrinsicCellSize ?? .zero
  }
}

/// A raster-time image placement that the host may present natively.
public struct RasterImageAttachment: Equatable, Sendable {
  /// The full logical destination rect in terminal cells before viewport clipping.
  public var identity: Identity
  public var bounds: Rect
  /// The portion of ``bounds`` currently visible after ancestor clipping.
  public var visibleBounds: Rect
  public var source: ImageSource
  public var resolvedReference: ImageAssetReference?
  public var pixelSize: Size?
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode

  public init(
    identity: Identity,
    bounds: Rect,
    visibleBounds: Rect? = nil,
    source: ImageSource,
    resolvedReference: ImageAssetReference? = nil,
    pixelSize: Size? = nil,
    isResizable: Bool = false,
    scalingMode: ImageScalingMode = .stretch
  ) {
    self.identity = identity
    self.bounds = bounds
    self.visibleBounds = visibleBounds ?? bounds
    self.source = source
    self.resolvedReference = resolvedReference
    self.pixelSize = pixelSize
    self.isResizable = isResizable
    self.scalingMode = scalingMode
  }
}
