import Core

/// Displays a PNG image sourced from an explicit resource path, local file URL,
/// or bytes embedded directly in the binary.
public struct Image: View, ResolvableView {
  public var source: ImageSource
  public var isResizable: Bool
  public var scalingMode: ImageScalingMode

  public init(
    _ name: String
  ) {
    source = .named(name)
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
      context.environmentValues.terminalCellPixelSize
    )

    return [
      parallelResolveLeaf(
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
