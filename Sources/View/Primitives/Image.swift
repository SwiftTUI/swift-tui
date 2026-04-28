public import Core
@_spi(Testing) import Core

/// Displays a PNG, JPEG, or GIF image sourced from an explicit resource
/// path, local file URL, or bytes embedded directly in the binary.
public struct Image: View, ResolvableView {
  public var source: ImageSource
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode

  public init(
    path: String
  ) {
    source = .path(path)
    isResizable = false
    scalingMode = .stretch
  }

  public init(
    fileURL: String
  ) {
    source = .fileURL(fileURL)
    isResizable = false
    scalingMode = .stretch
  }

  public init(
    pngData: [UInt8]
  ) {
    source = .pngData(pngData)
    isResizable = false
    scalingMode = .stretch
  }

  /// Convenience initializer for JPEG bytes. Routes through the same backing
  /// storage as ``init(pngData:)`` — the decoder dispatches on magic bytes,
  /// so either constructor accepts either format.
  public init(
    jpegData: [UInt8]
  ) {
    source = .pngData(jpegData)
    isResizable = false
    scalingMode = .stretch
  }

  /// Convenience initializer for GIF bytes. Routes through the same
  /// backing storage as ``init(pngData:)`` — the decoder dispatches on
  /// magic bytes, so any constructor accepts any supported format. Only
  /// the first frame of an animated GIF is rendered.
  public init(
    gifData: [UInt8]
  ) {
    source = .pngData(gifData)
    isResizable = false
    scalingMode = .stretch
  }

  public func resizable() -> Image {
    var copy = self
    copy.isResizable = true
    copy.scalingMode = .stretch
    return copy
  }

  public func scaledToFit() -> Image {
    var copy = self
    copy.isResizable = true
    copy.scalingMode = .fit
    return copy
  }

  public func scaledToFill() -> Image {
    var copy = self
    copy.isResizable = true
    copy.scalingMode = .fill
    return copy
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let resolvedAsset = context.imageAssetResolver?(
      source,
      context.environmentValues.imageResourceRoots,
      Size(
        width: context.environmentValues.cellPixelMetrics.width,
        height: context.environmentValues.cellPixelMetrics.height
      )
    )

    return [
      resolveLeafNode(
        kindName: "Image",
        intrinsicSize: resolvedAsset?.intrinsicCellSize ?? .zero,
        drawPayload: .image(
          .init(
            source: source,
            resolvedAsset: resolvedAsset,
            isResizable: isResizable,
            scalingMode: scalingMode
          )
        ),
        in: context
      )
    ]
  }
}
