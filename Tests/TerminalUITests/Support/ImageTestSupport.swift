import PNG

@testable import Core

struct InMemoryPNGDestination: PNG.BytestreamDestination {
  var bytes: [UInt8] = []

  mutating func write(
    _ bytes: [UInt8]
  ) -> Void? {
    self.bytes.append(contentsOf: bytes)
    return ()
  }
}

func makePNGBytes(
  width: Int,
  height: Int,
  pixels: [PNG.RGBA<UInt8>]
) throws -> [UInt8] {
  let image = PNG.Image(
    packing: pixels,
    size: (x: width, y: height),
    layout: .init(format: .rgba8(palette: [], fill: nil))
  )
  var destination = InMemoryPNGDestination()
  try image.compress(stream: &destination, level: 9)
  return destination.bytes
}

func makeRasterImageAttachment(
  pngBytes: [UInt8],
  pixelSize: Size,
  bounds: Rect,
  visibleBounds: Rect? = nil,
  identity: Identity = testIdentity("Root", "Image")
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: identity,
    bounds: bounds,
    visibleBounds: visibleBounds,
    source: .data(pngBytes),
    resolvedReference: .embeddedPNG(pngBytes),
    pixelSize: pixelSize,
    isResizable: false,
    scalingMode: .stretch
  )
}

func rgbaPixel(
  red: UInt8,
  green: UInt8,
  blue: UInt8,
  alpha: UInt8 = 255
) -> PNG.RGBA<UInt8> {
  .init(red, green, blue, alpha)
}
