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

  public init(
    reference: ImageAssetReference,
    pixelSize: Size,
    intrinsicCellSize: Size
  ) {
    self.reference = reference
    self.pixelSize = pixelSize
    self.intrinsicCellSize = intrinsicCellSize
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
  public var identity: Identity
  public var bounds: Rect
  public var source: ImageSource
  public var resolvedReference: ImageAssetReference?
  public var pixelSize: Size?
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode

  public init(
    identity: Identity,
    bounds: Rect,
    source: ImageSource,
    resolvedReference: ImageAssetReference? = nil,
    pixelSize: Size? = nil,
    isResizable: Bool = false,
    scalingMode: ImageScalingMode = .stretch
  ) {
    self.identity = identity
    self.bounds = bounds
    self.source = source
    self.resolvedReference = resolvedReference
    self.pixelSize = pixelSize
    self.isResizable = isResizable
    self.scalingMode = scalingMode
  }
}
