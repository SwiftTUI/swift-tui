public import Core

/// A decorative tiled pattern that can be used as a lightweight background layer.
public struct TileBackground: View, ResolvableView {
  public var width: Int
  public var height: Int
  public var tiles: [String]
  public var style: AnyShapeStyle
  public var opacity: Double

  public init<S: ShapeStyle>(
    width: Int,
    height: Int,
    tiles: [String] = ["░▒", "▒░"],
    style: S,
    opacity: Double = 0.18
  ) {
    self.width = width
    self.height = height
    self.tiles = tiles.isEmpty ? [" "] : tiles
    self.style = AnyShapeStyle(style)
    self.opacity = opacity
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<height) { row in
        Text(tiledLine(for: row))
          .foregroundStyle(style)
          .drawMetadata(.init(opacity: opacity))
          .lineLimit(1)
          .frame(width: width, alignment: .leading)
      }
    }
    .frame(width: width, height: height, alignment: .topLeading)
    .resolveElements(in: context)
  }

  private func tiledLine(
    for row: Int
  ) -> String {
    let seed = tiles[row % tiles.count]
    let repeated = String(
      repeating: seed,
      count: max(1, width / max(1, seed.count) + 2)
    )
    return paddedLine(repeated, width: width)
  }
}

private func paddedLine(
  _ content: String,
  width: Int
) -> String {
  guard width > 0 else {
    return ""
  }

  let truncated = String(content.prefix(width))
  let remaining = max(0, width - truncated.count)
  return truncated + String(repeating: " ", count: remaining)
}
