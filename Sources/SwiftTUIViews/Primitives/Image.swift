@_spi(Testing) public import SwiftTUICore

/// Displays a PNG or JPEG image sourced from an explicit resource path,
/// local file URL, or bytes embedded directly in the binary.
public struct Image: PrimitiveView, ResolvableView {
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

  /// Creates an image from a `file://` URL string. The value is parsed as
  /// a URL (host form and percent-encoding included); for a plain
  /// filesystem path use ``init(path:)``.
  public init(
    fileURLString: String
  ) {
    source = .fileURL(fileURLString)
    isResizable = false
    scalingMode = .stretch
  }

  public init(
    data: [UInt8]
  ) {
    source = .data(data)
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
    let resolver = context.imageAssetResolver
    let resolvedAsset = resolver?(
      source,
      context.environmentValues.imageResourceRoots,
      PixelSize(
        width: context.environmentValues.cellPixelMetrics.width,
        height: context.environmentValues.cellPixelMetrics.height
      )
    )

    var node = resolveLeafNode(
      kindName: "Image",
      intrinsicSize: resolvedAsset?.intrinsicCellSize ?? .zero,
      semanticMetadata: .init(
        accessibilityRole: .image,
        accessibilityVisualContent: .init(kind: "Image")
      ),
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
    // Fail loud: an installed resolver that cannot resolve the source means
    // the image silently measures zero. Absence of a resolver is a
    // renderer-configuration situation, not an authoring error.
    if resolver != nil, resolvedAsset == nil {
      node.preferenceValues.merge(
        RuntimeIssuePreferenceKey.self,
        value: [
          RuntimeIssue(
            severity: .warning,
            code: "image.unresolvedSource",
            message:
              "Image source \(sourceDescription) did not resolve to a decodable asset; the image measures zero.",
            identity: context.identity,
            source: "Image"
          )
        ]
      )
    }
    return [node]
  }

  private var sourceDescription: String {
    switch source {
    case .path(let path):
      "path(\(path))"
    case .fileURL(let urlString):
      "fileURLString(\(urlString))"
    case .data(let bytes):
      "data(\(bytes.count) bytes)"
    }
  }
}
