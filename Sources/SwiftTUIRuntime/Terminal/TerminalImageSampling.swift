import SwiftTUICore

func scaledPixels(
  from image: DecodedImage,
  outputSize: PixelSize
) -> [RGBAImagePixel?] {
  guard
    outputSize.width > 0,
    outputSize.height > 0,
    image.pixelSize.width > 0,
    image.pixelSize.height > 0
  else {
    return []
  }

  var output: [RGBAImagePixel?] = Array(
    repeating: nil,
    count: outputSize.width * outputSize.height
  )

  for y in 0..<outputSize.height {
    let sourceY = min(
      image.pixelSize.height - 1,
      Int(
        (Double((y * 2) + 1) * Double(image.pixelSize.height))
          / Double(outputSize.height * 2)
      )
    )

    for x in 0..<outputSize.width {
      let sourceX = min(
        image.pixelSize.width - 1,
        Int(
          (Double((x * 2) + 1) * Double(image.pixelSize.width))
            / Double(outputSize.width * 2)
        )
      )
      let pixel = image.pixels[(sourceY * image.pixelSize.width) + sourceX]
      if pixel.alpha >= 16 {
        output[(y * outputSize.width) + x] = pixel
      }
    }
  }

  return output
}

/// Nearest-neighbor resample of the decoded pixels to `outputSize`,
/// keeping every pixel (including fully transparent ones) at its
/// sampled alpha. The optional-pixel variant above serves cell-fallback
/// rendering, which drops near-transparent pixels; raw RGBA payloads
/// (kitty `f=32`) must preserve them.
func scaledRGBAPixels(
  from image: DecodedImage,
  outputSize: PixelSize
) -> [RGBAImagePixel] {
  guard
    outputSize.width > 0,
    outputSize.height > 0,
    image.pixelSize.width > 0,
    image.pixelSize.height > 0
  else {
    return []
  }

  var output = [RGBAImagePixel]()
  output.reserveCapacity(outputSize.width * outputSize.height)

  for y in 0..<outputSize.height {
    let sourceY = min(
      image.pixelSize.height - 1,
      Int(
        (Double((y * 2) + 1) * Double(image.pixelSize.height))
          / Double(outputSize.height * 2)
      )
    )

    for x in 0..<outputSize.width {
      let sourceX = min(
        image.pixelSize.width - 1,
        Int(
          (Double((x * 2) + 1) * Double(image.pixelSize.width))
            / Double(outputSize.width * 2)
        )
      )
      output.append(image.pixels[(sourceY * image.pixelSize.width) + sourceX])
    }
  }

  return output
}

func floydSteinbergQuantizedIndices(
  pixels: [RGBAImagePixel?],
  size: PixelSize,
  palette: [Color]
) -> [Int?] {
  guard
    size.width > 0,
    size.height > 0,
    pixels.count == size.width * size.height,
    !palette.isEmpty
  else {
    return []
  }

  var red = pixels.map { Double($0?.red ?? 0) / 255.0 }
  var green = pixels.map { Double($0?.green ?? 0) / 255.0 }
  var blue = pixels.map { Double($0?.blue ?? 0) / 255.0 }
  var quantized: [Int?] = Array(repeating: nil, count: pixels.count)

  for y in 0..<size.height {
    for x in 0..<size.width {
      let index = (y * size.width) + x
      guard pixels[index] != nil else {
        continue
      }

      let current = Color(
        red: clampColorComponent(red[index]),
        green: clampColorComponent(green[index]),
        blue: clampColorComponent(blue[index])
      )
      let paletteIndex = closestPaletteIndex(
        for: current,
        palette: palette
      )
      let target = palette[paletteIndex]
      quantized[index] = paletteIndex

      let errorRed = red[index] - target.red
      let errorGreen = green[index] - target.green
      let errorBlue = blue[index] - target.blue

      diffuseError(
        red: errorRed,
        green: errorGreen,
        blue: errorBlue,
        x: x + 1,
        y: y,
        size: size,
        factor: 7.0 / 16.0,
        redBuffer: &red,
        greenBuffer: &green,
        blueBuffer: &blue,
        pixels: pixels
      )
      diffuseError(
        red: errorRed,
        green: errorGreen,
        blue: errorBlue,
        x: x - 1,
        y: y + 1,
        size: size,
        factor: 3.0 / 16.0,
        redBuffer: &red,
        greenBuffer: &green,
        blueBuffer: &blue,
        pixels: pixels
      )
      diffuseError(
        red: errorRed,
        green: errorGreen,
        blue: errorBlue,
        x: x,
        y: y + 1,
        size: size,
        factor: 5.0 / 16.0,
        redBuffer: &red,
        greenBuffer: &green,
        blueBuffer: &blue,
        pixels: pixels
      )
      diffuseError(
        red: errorRed,
        green: errorGreen,
        blue: errorBlue,
        x: x + 1,
        y: y + 1,
        size: size,
        factor: 1.0 / 16.0,
        redBuffer: &red,
        greenBuffer: &green,
        blueBuffer: &blue,
        pixels: pixels
      )
    }
  }

  return quantized
}

private func diffuseError(
  red errorRed: Double,
  green errorGreen: Double,
  blue errorBlue: Double,
  x: Int,
  y: Int,
  size: PixelSize,
  factor: Double,
  redBuffer: inout [Double],
  greenBuffer: inout [Double],
  blueBuffer: inout [Double],
  pixels: [RGBAImagePixel?]
) {
  guard
    x >= 0,
    y >= 0,
    x < size.width,
    y < size.height
  else {
    return
  }

  let index = (y * size.width) + x
  guard pixels[index] != nil else {
    return
  }

  redBuffer[index] = clampColorComponent(redBuffer[index] + (errorRed * factor))
  greenBuffer[index] = clampColorComponent(greenBuffer[index] + (errorGreen * factor))
  blueBuffer[index] = clampColorComponent(blueBuffer[index] + (errorBlue * factor))
}

private func closestPaletteIndex(
  for color: Color,
  palette: [Color]
) -> Int {
  var bestIndex = 0
  var bestDistance = squaredDistance(
    from: color,
    to: palette[0]
  )

  for index in 1..<palette.count {
    let distance = squaredDistance(
      from: color,
      to: palette[index]
    )
    if distance < bestDistance {
      bestDistance = distance
      bestIndex = index
    }
  }

  return bestIndex
}

private func squaredDistance(
  from lhs: Color,
  to rhs: Color
) -> Double {
  let dr = lhs.red - rhs.red
  let dg = lhs.green - rhs.green
  let db = lhs.blue - rhs.blue
  return (dr * dr) + (dg * dg) + (db * db)
}

private func clampColorComponent(
  _ value: Double
) -> Double {
  max(0.0, min(1.0, value))
}
