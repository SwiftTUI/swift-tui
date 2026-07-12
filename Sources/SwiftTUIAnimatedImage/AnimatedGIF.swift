import Foundation
import GIF

/// GIF import and export for finite animated image sequences.
public enum AnimatedGIF {
  public static func decode(
    contentsOf path: String
  ) throws -> AnimatedImageSequence {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try decode(data: [UInt8](data))
  }

  public static func decode(
    data: [UInt8]
  ) throws -> AnimatedImageSequence {
    var source = GIFByteSource(bytes: data)
    let image = try GIF.Image.decompress(stream: &source)
    let frames = image.frames.indices.map { index in
      AnimatedImageFrame(
        width: image.size.x,
        height: image.size.y,
        pixels: image.composited(frameIndex: index, as: GIF.RGBA<UInt8>.self).map(
          AnimatedImagePixel.init
        )
      )
    }
    let delays = image.frames.map { frame in
      UInt64(normalizedGIFDelayMilliseconds(centiseconds: frame.delayCentiseconds))
        * 1_000_000
    }
    return AnimatedImageSequence(frames: frames, delayNanoseconds: delays)
  }

  public static func encode(
    _ sequence: AnimatedImageSequence,
    loopCount: Int = 0
  ) throws -> [UInt8] {
    let reservesTransparency = sequence.frames.contains { frame in
      frame.pixels.contains { $0.alpha == 0 }
    }
    var palette = GIFPalette(reservesTransparency: reservesTransparency)
    let frames = sequence.frames.enumerated().map { index, frame in
      var hasTransparentPixels = false
      let indices = frame.pixels.map { pixel in
        if pixel.alpha == 0 {
          hasTransparentPixels = true
        }
        return palette.index(for: pixel)
      }
      return GIF.IndexedFrame(
        width: frame.pixelSize.width,
        height: frame.pixelSize.height,
        indices: indices,
        transparentIndex: hasTransparentPixels ? 0 : nil,
        delayCentiseconds: delayCentiseconds(
          forNanoseconds: sequence.delayNanoseconds[index]
        ),
        disposal: .previous
      )
    }

    return try GIF.Encoder.encode(
      GIF.IndexedImage(
        size: (
          x: sequence.frames[0].pixelSize.width,
          y: sequence.frames[0].pixelSize.height
        ),
        globalColorTable: palette.colors,
        backgroundIndex: 0,
        loopCount: loopCount,
        frames: frames
      )
    )
  }
}

private struct GIFByteSource: GIF.BytestreamSource {
  var bytes: [UInt8]
  var offset = 0

  mutating func read(
    count: Int
  ) -> [UInt8]? {
    guard count >= 0, offset < bytes.count else {
      return nil
    }
    let end = min(offset + count, bytes.count)
    let chunk = Array(bytes[offset..<end])
    offset = end
    return chunk
  }
}

private struct GIFRGBKey: Equatable, Hashable {
  var red: UInt8
  var green: UInt8
  var blue: UInt8

  init(
    _ pixel: AnimatedImagePixel
  ) {
    red = pixel.red
    green = pixel.green
    blue = pixel.blue
  }

  var tuple: (r: UInt8, g: UInt8, b: UInt8) {
    (r: red, g: green, b: blue)
  }
}

private struct GIFPalette {
  var colors: [(r: UInt8, g: UInt8, b: UInt8)]
  private var colorIndices: [GIFRGBKey: UInt8] = [:]
  private let firstOpaqueIndex: Int

  init(reservesTransparency: Bool) {
    colors = reservesTransparency ? [(r: 0, g: 0, b: 0)] : []
    firstOpaqueIndex = reservesTransparency ? 1 : 0
  }

  mutating func index(
    for pixel: AnimatedImagePixel
  ) -> UInt8 {
    guard pixel.alpha > 0 else {
      return 0
    }

    let color = GIFRGBKey(pixel)
    if let index = colorIndices[color] {
      return index
    }

    if colors.count < 256 {
      let index = UInt8(colors.count)
      colors.append(color.tuple)
      colorIndices[color] = index
      return index
    }

    return nearestPaletteIndex(to: color)
  }

  private func nearestPaletteIndex(
    to color: GIFRGBKey
  ) -> UInt8 {
    var bestIndex = firstOpaqueIndex
    var bestDistance = Int.max
    for index in firstOpaqueIndex..<colors.count {
      let candidate = colors[index]
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
}

extension AnimatedImagePixel {
  init(
    _ pixel: GIF.RGBA<UInt8>
  ) {
    self.init(
      red: pixel.r,
      green: pixel.g,
      blue: pixel.b,
      alpha: pixel.a
    )
  }
}

private func normalizedGIFDelayMilliseconds(
  centiseconds: Int
) -> Int {
  guard centiseconds > 0 else {
    return 100
  }
  return max(20, centiseconds * 10)
}

private func delayCentiseconds(
  forNanoseconds nanoseconds: UInt64
) -> Int {
  let centiseconds = (nanoseconds + 9_999_999) / 10_000_000
  return Int(min(UInt64(UInt16.max), max(1, centiseconds)))
}
