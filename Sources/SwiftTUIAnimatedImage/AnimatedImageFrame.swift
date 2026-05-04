/// A fully-composited frame in an animated image sequence.
public struct AnimatedImageFrame: Equatable, Hashable, Sendable {
  public var pixelSize: PixelSize
  public var pixels: [AnimatedImagePixel]

  public init(
    pixelSize: PixelSize,
    pixels: [AnimatedImagePixel]
  ) {
    precondition(
      pixelSize.width > 0 && pixelSize.height > 0,
      "AnimatedImageFrame requires positive pixel dimensions"
    )
    precondition(
      pixels.count == pixelSize.width * pixelSize.height,
      "AnimatedImageFrame pixel count must match width * height"
    )
    self.pixelSize = pixelSize
    self.pixels = pixels
  }

  public init(
    width: Int,
    height: Int,
    pixels: [AnimatedImagePixel]
  ) {
    self.init(
      pixelSize: PixelSize(width: width, height: height),
      pixels: pixels
    )
  }

  /// PNG bytes for rendering this frame through `Image(data:)`.
  public var imageData: [UInt8] {
    AnimatedImagePNGEncoder.encode(frame: self)
  }
}
