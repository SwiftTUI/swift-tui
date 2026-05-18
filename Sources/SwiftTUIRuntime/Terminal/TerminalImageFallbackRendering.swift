import SwiftTUICore

struct RasterImageOverlay: Sendable {
  var size: CellSize
  var cells: [[RasterCell]]
}

func fallbackRenderMode(
  for capabilityProfile: TerminalCapabilityProfile
) -> TerminalImageRenderMode {
  if capabilityProfile.glyphLevel == .unicode {
    switch capabilityProfile.colorLevel {
    case .trueColor:
      return .fallbackTrueColor
    case .ansi256:
      return .fallbackANSI256
    case .ansi16:
      return .fallbackANSI16
    case .none:
      break
    }
  }
  return .fallbackASCII
}

func fallbackOutputSize(
  for mode: TerminalImageRenderMode,
  cellSize: CellSize
) -> PixelSize {
  switch mode {
  case .fallbackASCII:
    .init(
      width: cellSize.width,
      height: cellSize.height
    )
  case .fallbackANSI16, .fallbackANSI256, .fallbackTrueColor:
    .init(
      width: cellSize.width,
      height: cellSize.height * 2
    )
  case .kitty, .sixel:
    .zero
  }
}

func fallbackPaletteSize(
  for mode: TerminalImageRenderMode
) -> Int {
  switch mode {
  case .fallbackANSI16:
    16
  case .fallbackANSI256:
    256
  default:
    0
  }
}

func makeFallbackOverlay(
  for image: DecodedImage,
  cellSize: CellSize,
  mode: TerminalImageRenderMode
) -> RasterImageOverlay? {
  switch mode {
  case .fallbackTrueColor:
    directColorOverlay(
      for: image,
      cellSize: cellSize
    )
  case .fallbackANSI256:
    indexedColorOverlay(
      for: image,
      cellSize: cellSize,
      palette: ansi256Palette()
    )
  case .fallbackANSI16:
    indexedColorOverlay(
      for: image,
      cellSize: cellSize,
      palette: ansi16Palette()
    )
  case .fallbackASCII:
    asciiOverlay(
      for: image,
      cellSize: cellSize
    )
  case .kitty, .sixel:
    nil
  }
}

private func directColorOverlay(
  for image: DecodedImage,
  cellSize: CellSize
) -> RasterImageOverlay? {
  guard cellSize.width > 0, cellSize.height > 0 else {
    return nil
  }

  let samples = scaledPixels(
    from: image,
    outputSize: .init(width: cellSize.width, height: cellSize.height * 2)
  )
  return halfBlockOverlay(
    colors: samples.map { $0.map(\.color) },
    cellSize: cellSize
  )
}

private func indexedColorOverlay(
  for image: DecodedImage,
  cellSize: CellSize,
  palette: [Color]
) -> RasterImageOverlay? {
  guard cellSize.width > 0, cellSize.height > 0, !palette.isEmpty else {
    return nil
  }

  let sampleSize = PixelSize(
    width: cellSize.width,
    height: cellSize.height * 2
  )
  let samples = scaledPixels(
    from: image,
    outputSize: sampleSize
  )
  let indices = floydSteinbergQuantizedIndices(
    pixels: samples,
    size: sampleSize,
    palette: palette
  )
  let colors = indices.map { index in
    index.map { palette[$0] }
  }
  return halfBlockOverlay(
    colors: colors,
    cellSize: cellSize
  )
}

private func asciiOverlay(
  for image: DecodedImage,
  cellSize: CellSize
) -> RasterImageOverlay? {
  guard cellSize.width > 0, cellSize.height > 0 else {
    return nil
  }

  let samples = scaledPixels(
    from: image,
    outputSize: .init(width: cellSize.width, height: cellSize.height)
  )
  let ramp = Array(" .:-=+*#%@")
  var rows: [[RasterCell]] = Array(
    repeating: Array(repeating: .empty, count: cellSize.width),
    count: cellSize.height
  )

  for y in 0..<cellSize.height {
    for x in 0..<cellSize.width {
      let index = (y * cellSize.width) + x
      guard let pixel = samples[index] else {
        continue
      }

      let luminance = (2126 * pixel.red) + (7152 * pixel.green) + (722 * pixel.blue)
      let normalized = Double(luminance) / Double(10_000 * 255)
      let rampIndex = min(
        ramp.count - 1,
        max(0, Int((normalized * Double(ramp.count - 1)).rounded()))
      )
      rows[y][x] = .init(character: ramp[rampIndex])
    }
  }

  return .init(
    size: cellSize,
    cells: rows
  )
}

private func halfBlockOverlay(
  colors: [Color?],
  cellSize: CellSize
) -> RasterImageOverlay? {
  guard
    cellSize.width > 0,
    cellSize.height > 0,
    colors.count == cellSize.width * cellSize.height * 2
  else {
    return nil
  }

  var rows: [[RasterCell]] = Array(
    repeating: Array(repeating: .empty, count: cellSize.width),
    count: cellSize.height
  )

  for y in 0..<cellSize.height {
    for x in 0..<cellSize.width {
      let topIndex = ((y * 2) * cellSize.width) + x
      let bottomIndex = (((y * 2) + 1) * cellSize.width) + x
      let topColor = colors[topIndex]
      let bottomColor = colors[bottomIndex]
      guard topColor != nil || bottomColor != nil else {
        continue
      }

      let character: Character
      let style: ResolvedTextStyle

      switch (topColor, bottomColor) {
      case (let top?, let bottom?):
        character = "▀"
        style = .init(
          foregroundColor: top,
          backgroundColor: bottom
        )
      case (let top?, nil):
        character = "▀"
        style = .init(foregroundColor: top)
      case (nil, let bottom?):
        character = "▄"
        style = .init(foregroundColor: bottom)
      case (nil, nil):
        continue
      }

      rows[y][x] = .init(
        character: character,
        style: style
      )
    }
  }

  return .init(
    size: cellSize,
    cells: rows
  )
}

private func ansi16Palette() -> [Color] {
  (0...15).compactMap { TerminalAppearance.defaultPalette[$0] }
}

private func ansi256Palette() -> [Color] {
  var palette = ansi16Palette()
  let cubeComponents: [Double] = [0, 95, 135, 175, 215, 255].map { $0 / 255.0 }

  for red in cubeComponents {
    for green in cubeComponents {
      for blue in cubeComponents {
        palette.append(
          .init(
            red: red,
            green: green,
            blue: blue
          )
        )
      }
    }
  }

  for index in 0..<24 {
    let component = Double(8 + (index * 10)) / 255.0
    palette.append(
      .init(
        red: component,
        green: component,
        blue: component
      )
    )
  }

  return palette
}
