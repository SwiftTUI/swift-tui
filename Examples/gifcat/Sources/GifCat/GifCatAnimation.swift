import Foundation
import GIF

public struct GifCatAnimationFrame: Equatable, Hashable, Sendable {
  public var bytes: [UInt8]
  public var delayMilliseconds: Int

  public init(
    bytes: [UInt8],
    delayMilliseconds: Int
  ) {
    self.bytes = bytes
    self.delayMilliseconds = max(20, delayMilliseconds)
  }
}

public struct GifCatAnimation: Equatable, Hashable, Sendable {
  public var frames: [GifCatAnimationFrame]

  public init(frames: [GifCatAnimationFrame]) {
    precondition(!frames.isEmpty, "GifCatAnimation requires at least one frame")
    self.frames = frames
  }

  public static func load(contentsOf path: String) throws -> GifCatAnimation {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try load(data: [UInt8](data))
  }

  public static func load(data: [UInt8]) throws -> GifCatAnimation {
    var source = ByteSource(bytes: data)
    let image = try GIF.Image.decompress(stream: &source)
    let frames = try image.frames.indices.map { index in
      let pixels = image.composited(frameIndex: index, as: GIF.RGBA<UInt8>.self)
      let delay = normalizedDelayMilliseconds(
        centiseconds: image.frames[index].delayCentiseconds
      )
      return GifCatAnimationFrame(
        bytes: try encodedSingleFrameGIF(
          pixels: pixels,
          size: image.size,
          delayCentiseconds: image.frames[index].delayCentiseconds
        ),
        delayMilliseconds: delay
      )
    }
    return GifCatAnimation(frames: frames)
  }
}

private struct ByteSource: GIF.BytestreamSource {
  var bytes: [UInt8]
  var offset = 0

  mutating func read(count: Int) -> [UInt8]? {
    guard offset < bytes.count else { return nil }
    let end = min(offset + count, bytes.count)
    let chunk = Array(bytes[offset..<end])
    offset = end
    return chunk
  }
}

private struct RGBKey: Equatable, Hashable {
  var red: UInt8
  var green: UInt8
  var blue: UInt8

  init(_ pixel: GIF.RGBA<UInt8>) {
    red = pixel.r
    green = pixel.g
    blue = pixel.b
  }

  var tuple: (r: UInt8, g: UInt8, b: UInt8) {
    (r: red, g: green, b: blue)
  }
}

private func normalizedDelayMilliseconds(centiseconds: Int) -> Int {
  guard centiseconds > 0 else {
    return 100
  }
  return max(20, centiseconds * 10)
}

private func encodedSingleFrameGIF(
  pixels: [GIF.RGBA<UInt8>],
  size: (x: Int, y: Int),
  delayCentiseconds: Int
) throws -> [UInt8] {
  var palette: [(r: UInt8, g: UInt8, b: UInt8)] = [(r: 0, g: 0, b: 0)]
  var colorIndices: [RGBKey: UInt8] = [:]
  var indices: [UInt8] = []
  indices.reserveCapacity(pixels.count)

  for pixel in pixels {
    guard pixel.a > 0 else {
      indices.append(0)
      continue
    }

    let color = RGBKey(pixel)
    if let index = colorIndices[color] {
      indices.append(index)
      continue
    }

    if palette.count < 256 {
      let index = UInt8(palette.count)
      palette.append(color.tuple)
      colorIndices[color] = index
      indices.append(index)
    } else {
      indices.append(nearestPaletteIndex(to: color, in: palette))
    }
  }

  return try GIF.Encoder.encode(
    GIF.IndexedImage(
      size: size,
      globalColorTable: palette,
      backgroundIndex: 0,
      loopCount: 1,
      frames: [
        GIF.IndexedFrame(
          width: size.x,
          height: size.y,
          indices: indices,
          transparentIndex: 0,
          delayCentiseconds: delayCentiseconds,
          disposal: .background
        )
      ]
    )
  )
}

private func nearestPaletteIndex(
  to color: RGBKey,
  in palette: [(r: UInt8, g: UInt8, b: UInt8)]
) -> UInt8 {
  var bestIndex = 1
  var bestDistance = Int.max
  for index in 1..<palette.count {
    let candidate = palette[index]
    let redDelta = Int(color.red) - Int(candidate.r)
    let greenDelta = Int(color.green) - Int(candidate.g)
    let blueDelta = Int(color.blue) - Int(candidate.b)
    let distance = redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta
    if distance < bestDistance {
      bestDistance = distance
      bestIndex = index
    }
  }
  return UInt8(bestIndex)
}
