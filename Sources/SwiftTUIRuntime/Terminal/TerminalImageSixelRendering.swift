import SwiftTUICore

func sixelOutputSize(
  for visibleBounds: CellRect,
  graphicsCapabilities: TerminalGraphicsCapabilities
) -> PixelSize {
  let cellPixelSize = graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)
  return PixelSize(
    width: max(1, visibleBounds.size.width * max(1, cellPixelSize.width)),
    height: max(1, visibleBounds.size.height * max(1, cellPixelSize.height))
  )
}

func sixelPaletteBudget(
  capabilityProfile: TerminalCapabilityProfile,
  graphicsCapabilities: TerminalGraphicsCapabilities
) -> Int {
  let requestedBudget: Int =
    switch capabilityProfile.colorLevel {
    case .ansi16, .none:
      16
    case .ansi256:
      256
    case .trueColor:
      256
    }

  if let sixelColorRegisters = graphicsCapabilities.sixelColorRegisters {
    return max(2, min(requestedBudget, sixelColorRegisters))
  }
  return requestedBudget
}

func makeSixelPayload(
  for image: DecodedImage,
  outputSize: PixelSize,
  paletteBudget: Int
) -> String? {
  let scaledPixels = scaledPixels(
    from: image,
    outputSize: outputSize
  )
  let palette = adaptivePalette(
    from: scaledPixels,
    maxColors: paletteBudget
  )
  guard !palette.isEmpty else {
    return nil
  }

  let indices = floydSteinbergQuantizedIndices(
    pixels: scaledPixels,
    size: outputSize,
    palette: palette
  )

  return sixelCommand(
    indices: indices,
    palette: palette,
    size: outputSize
  )
}

private func sixelCommand(
  indices: [Int?],
  palette: [Color],
  size: PixelSize
) -> String {
  var result = "\u{001B}P0;1;0q"
  result += "\"1;1;\(size.width);\(size.height)"

  let usedIndices = Set(indices.compactMap { $0 }).sorted()
  for index in usedIndices {
    let color = palette[index]
    result +=
      "#\(index);2;\(sixelPercent(color.red));\(sixelPercent(color.green));\(sixelPercent(color.blue))"
  }

  for bandStart in stride(from: 0, to: size.height, by: 6) {
    let usedBandIndices = usedIndices.filter { paletteIndex in
      bandHasColor(
        indices: indices,
        paletteIndex: paletteIndex,
        bandStart: bandStart,
        size: size
      )
    }

    if usedBandIndices.isEmpty {
      if bandStart + 6 < size.height {
        result += "-"
      }
      continue
    }

    for index in usedBandIndices.indices {
      let paletteIndex = usedBandIndices[index]
      result += "#\(paletteIndex)"
      result += encodedSixelLine(
        indices: indices,
        paletteIndex: paletteIndex,
        bandStart: bandStart,
        size: size
      )
      if index + 1 < usedBandIndices.count {
        result += "$"
      }
    }

    if bandStart + 6 < size.height {
      result += "-"
    }
  }

  result += "\u{001B}\\"
  return result
}

private func bandHasColor(
  indices: [Int?],
  paletteIndex: Int,
  bandStart: Int,
  size: PixelSize
) -> Bool {
  for y in bandStart..<min(size.height, bandStart + 6) {
    for x in 0..<size.width {
      if indices[(y * size.width) + x] == paletteIndex {
        return true
      }
    }
  }
  return false
}

private func encodedSixelLine(
  indices: [Int?],
  paletteIndex: Int,
  bandStart: Int,
  size: PixelSize
) -> String {
  var result = ""
  var currentScalar: UnicodeScalar?
  var runLength = 0

  func flushRun() {
    guard let currentScalar else {
      return
    }
    if runLength >= 4 {
      result += "!\(runLength)\(Character(currentScalar))"
    } else {
      for _ in 0..<runLength {
        result.append(Character(currentScalar))
      }
    }
    runLength = 0
  }

  for x in 0..<size.width {
    var value = 0
    for bit in 0..<6 {
      let y = bandStart + bit
      guard y < size.height else {
        continue
      }
      if indices[(y * size.width) + x] == paletteIndex {
        value |= (1 << bit)
      }
    }

    let scalar = UnicodeScalar(63 + value) ?? "?"
    if scalar == currentScalar {
      runLength += 1
    } else {
      flushRun()
      currentScalar = scalar
      runLength = 1
    }
  }

  flushRun()
  return result
}

private func sixelPercent(
  _ component: Double
) -> Int {
  Int((component * 100).rounded())
}

private func adaptivePalette(
  from pixels: [RGBAImagePixel?],
  maxColors: Int
) -> [Color] {
  guard maxColors > 0 else {
    return []
  }

  struct Bucket {
    var count = 0
    var red = 0.0
    var green = 0.0
    var blue = 0.0
  }

  var buckets: [Int: Bucket] = [:]

  for pixel in pixels {
    guard let pixel else {
      continue
    }

    let bucketKey =
      ((pixel.red / 16) << 8)
      | ((pixel.green / 16) << 4)
      | (pixel.blue / 16)
    var bucket = buckets[bucketKey] ?? Bucket()
    bucket.count += 1
    bucket.red += Double(pixel.red) / 255.0
    bucket.green += Double(pixel.green) / 255.0
    bucket.blue += Double(pixel.blue) / 255.0
    buckets[bucketKey] = bucket
  }

  let palette = buckets.values
    .sorted { lhs, rhs in
      lhs.count > rhs.count
    }
    .prefix(maxColors)
    .map { bucket in
      let divisor = Double(max(1, bucket.count))
      return Color(
        red: bucket.red / divisor,
        green: bucket.green / divisor,
        blue: bucket.blue / divisor
      )
    }

  if palette.isEmpty {
    return [.black]
  }
  return palette
}
