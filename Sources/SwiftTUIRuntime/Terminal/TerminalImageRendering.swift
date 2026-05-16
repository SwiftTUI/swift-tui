import SwiftTUICore

private enum TerminalImageRenderMode: String, Hashable, Sendable {
  case kitty
  case sixel
  case fallbackTrueColor
  case fallbackANSI256
  case fallbackANSI16
  case fallbackASCII
}

private struct TerminalImageVariantKey: Sendable {
  var reference: ImageAssetReference
  var mode: TerminalImageRenderMode
  var outputSize: PixelSize
  var paletteSize: Int
}

extension TerminalImageVariantKey: Hashable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.reference == rhs.reference
      && lhs.mode == rhs.mode
      && lhs.outputSize.width == rhs.outputSize.width
      && lhs.outputSize.height == rhs.outputSize.height
      && lhs.paletteSize == rhs.paletteSize
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(reference)
    hasher.combine(mode)
    hasher.combine(outputSize.width)
    hasher.combine(outputSize.height)
    hasher.combine(paletteSize)
  }
}

private struct RasterImageOverlay: Sendable {
  var size: CellSize
  var cells: [[RasterCell]]
}

/// Container format for a Kitty graphics payload. Maps directly onto
/// the protocol's `f=` key plus the supplemental `s=`/`v=` pixel-size
/// keys required for raw pixel buffers.
///
/// Kitty's `f=` only knows three values: 100 (PNG), 32 (RGBA), 24 (RGB).
/// JPEG isn't decodable by the terminal, so we serialize its already-decoded
/// pixels as RGBA and ship those instead.
private enum KittyPayloadFormat: Sendable, Equatable {
  case png
  case rgba(pixelSize: PixelSize)

  /// Numeric value emitted as `f=` in the kitty control data.
  var formatKey: Int {
    switch self {
    case .png: return 100
    case .rgba: return 32
    }
  }
}

private struct KittyPayload: Sendable {
  /// Base64-encoded image payload.
  var encodedData: String
  /// Container format the payload is shipped in.
  var format: KittyPayloadFormat
}

private struct KittySourceRect: Sendable, Equatable {
  var x: Int
  var y: Int
  var width: Int
  var height: Int
}

private struct KittyPlacement: Sendable, Equatable {
  var origin: CellPoint
  var cellColumns: Int
  var cellRows: Int
  var sourceRect: KittySourceRect?
}

final class TerminalImageRenderer: Sendable {
  private struct Storage {
    var kittyPayloads: [TerminalImageVariantKey: KittyPayload] = [:]
    var sixelPayloads: [TerminalImageVariantKey: String] = [:]
    var fallbackOverlays: [TerminalImageVariantKey: RasterImageOverlay] = [:]
  }

  private let repository: ImageAssetRepository
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  init(
    repository: ImageAssetRepository
  ) {
    self.repository = repository
  }

  func preparedSurface(
    for surface: RasterSurface,
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities
  ) -> RasterSurface {
    guard !surface.imageAttachments.isEmpty else {
      return surface
    }

    // When a graphics protocol (Kitty, Sixel) is active, the image is
    // rendered via escape sequences AFTER the text cells are written.
    // Both protocols paint the image *on top of* the cells in their
    // rectangle — Kitty as an explicit graphics layer above text,
    // Sixel as direct pixel writes — so the cell content does not need
    // to be erased. Crucially, transparent pixels in a Kitty image
    // reveal whatever color was already written to that cell. If we
    // clear the cell style here, those transparent pixels show the
    // terminal's default background instead of the immediate container
    // background (e.g. the dark gray of a card behind the image), which
    // is the bug behind "kitty image transparency shows the wrong
    // color". Sixel images replace pixels in their footprint, so this
    // pass-through is at worst a no-op for sixel.
    if graphicsCapabilities.preferredProtocol != nil {
      return surface
    }

    var prepared = surface
    prepared.cells = normalizedCells(
      prepared.cells,
      size: prepared.size
    )

    for attachment in prepared.imageAttachments {
      guard
        let overlay = fallbackOverlay(
          for: attachment,
          capabilityProfile: capabilityProfile
        )
      else {
        continue
      }
      apply(
        overlay: overlay,
        for: attachment.bounds,
        clippedTo: attachment.visibleBounds,
        to: &prepared.cells,
        surfaceSize: prepared.size
      )
    }

    return prepared
  }

  func graphicsWriteSteps(
    for surface: RasterSurface,
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities,
    transmittedKittyImages: inout Set<UInt32>
  ) -> [String] {
    graphicsWriteSteps(
      for: surface.imageAttachments,
      capabilityProfile: capabilityProfile,
      graphicsCapabilities: graphicsCapabilities,
      transmittedKittyImages: &transmittedKittyImages
    )
  }

  func graphicsWriteSteps(
    for attachments: [RasterImageAttachment],
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities,
    transmittedKittyImages: inout Set<UInt32>
  ) -> [String] {
    guard
      !attachments.isEmpty,
      let graphicsProtocol = graphicsCapabilities.preferredProtocol
    else {
      return []
    }

    var writeSteps: [String] = []

    for attachment in attachments.sorted(by: compareImageAttachments) {
      guard
        let reference = attachment.resolvedReference,
        let image = repository.decodedImage(for: reference)
      else {
        continue
      }

      switch graphicsProtocol {
      case .kitty:
        guard
          let placement = kittyPlacement(
            for: attachment,
            imagePixelSize: image.pixelSize
          )
        else {
          continue
        }
        let imageID = kittyImageID(reference: reference)
        writeSteps.append(terminalSaveCursorSequence())
        writeSteps.append(terminalCursorSequence(to: placement.origin))

        if transmittedKittyImages.contains(imageID) {
          writeSteps.append(
            kittyPlacementCommand(
              imageID: imageID,
              cellColumns: placement.cellColumns,
              cellRows: placement.cellRows,
              sourceRect: placement.sourceRect
            )
          )
        } else if let payload = kittyPayload(
          for: reference,
          image: image
        ) {
          writeSteps.append(
            contentsOf: kittyTransmitAndPlaceCommands(
              payload: payload,
              imageID: imageID,
              cellColumns: placement.cellColumns,
              cellRows: placement.cellRows,
              sourceRect: placement.sourceRect
            )
          )
          transmittedKittyImages.insert(imageID)
        }

        writeSteps.append(terminalRestoreCursorSequence())

      case .sixel:
        guard
          let payload = sixelPayload(
            for: attachment,
            image: image,
            capabilityProfile: capabilityProfile,
            graphicsCapabilities: graphicsCapabilities
          )
        else {
          continue
        }

        writeSteps.append(terminalSaveCursorSequence())
        writeSteps.append(terminalCursorSequence(to: attachment.visibleBounds.origin))
        writeSteps.append(payload)
        writeSteps.append(terminalRestoreCursorSequence())
      }
    }

    return writeSteps
  }

  private func fallbackOverlay(
    for attachment: RasterImageAttachment,
    capabilityProfile: TerminalCapabilityProfile
  ) -> RasterImageOverlay? {
    guard
      let reference = attachment.resolvedReference,
      let image = repository.decodedImage(for: reference)
    else {
      return nil
    }

    let mode = fallbackRenderMode(for: capabilityProfile)
    let outputSize: PixelSize =
      switch mode {
      case .fallbackASCII:
        .init(
          width: attachment.bounds.size.width,
          height: attachment.bounds.size.height
        )
      case .fallbackANSI16, .fallbackANSI256, .fallbackTrueColor:
        .init(
          width: attachment.bounds.size.width,
          height: attachment.bounds.size.height * 2
        )
      case .kitty, .sixel:
        .zero
      }

    let paletteSize =
      switch mode {
      case .fallbackANSI16:
        16
      case .fallbackANSI256:
        256
      default:
        0
      }

    let key = TerminalImageVariantKey(
      reference: reference,
      mode: mode,
      outputSize: outputSize,
      paletteSize: paletteSize
    )

    if let cached = storage.withLockUnchecked({ $0.fallbackOverlays[key] }) {
      return cached
    }

    let overlay: RasterImageOverlay?
    switch mode {
    case .fallbackTrueColor:
      overlay = directColorOverlay(
        for: image,
        cellSize: attachment.bounds.size
      )
    case .fallbackANSI256:
      overlay = indexedColorOverlay(
        for: image,
        cellSize: attachment.bounds.size,
        palette: ansi256Palette()
      )
    case .fallbackANSI16:
      overlay = indexedColorOverlay(
        for: image,
        cellSize: attachment.bounds.size,
        palette: ansi16Palette()
      )
    case .fallbackASCII:
      overlay = asciiOverlay(
        for: image,
        cellSize: attachment.bounds.size
      )
    case .kitty, .sixel:
      overlay = nil
    }

    if let overlay {
      storage.withLockUnchecked { storage in
        storage.fallbackOverlays[key] = overlay
      }
    }

    return overlay
  }

  private func kittyPayload(
    for reference: ImageAssetReference,
    image: DecodedImage
  ) -> KittyPayload? {
    guard !image.encodedBytes.isEmpty else {
      return nil
    }

    let key = TerminalImageVariantKey(
      reference: reference,
      mode: .kitty,
      outputSize: image.pixelSize,
      paletteSize: 0
    )

    if let cached = storage.withLockUnchecked({ $0.kittyPayloads[key] }) {
      return cached
    }

    let payload: KittyPayload
    switch image.encodedFormat {
    case .png:
      // Ship the PNG bytes as `f=100`. Kitty decodes and scales them
      // natively — smaller on the wire than RGBA and avoids any
      // software-scaling artifacts on our side.
      payload = KittyPayload(
        encodedData: base64Encoded(image.encodedBytes),
        format: .png
      )
    case .jpeg:
      // Kitty has no JPEG decoder. Serialize the already-decoded pixels
      // as raw RGBA and let kitty ingest them via `f=32` with explicit
      // pixel-size keys (`s=`, `v=`).
      payload = KittyPayload(
        encodedData: base64Encoded(rgbaBytes(from: image.pixels)),
        format: .rgba(pixelSize: image.pixelSize)
      )
    }

    storage.withLockUnchecked { storage in
      storage.kittyPayloads[key] = payload
    }
    return payload
  }

  /// Forwards to the free `rgbaBytes(from:)` packer so animation
  /// transmits and first-frame transmits share one implementation.
  private func rgbaBytes(from pixels: [RGBAImagePixel]) -> [UInt8] {
    SwiftTUI_rgbaBytes(from: pixels)
  }

  private func sixelPayload(
    for attachment: RasterImageAttachment,
    image: DecodedImage,
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities
  ) -> String? {
    guard let reference = attachment.resolvedReference else {
      return nil
    }

    let cellPixelSize = graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)
    let pixelSize = PixelSize(
      width: max(1, attachment.visibleBounds.size.width * max(1, cellPixelSize.width)),
      height: max(1, attachment.visibleBounds.size.height * max(1, cellPixelSize.height))
    )
    let paletteBudget = sixelPaletteBudget(
      capabilityProfile: capabilityProfile,
      graphicsCapabilities: graphicsCapabilities
    )
    let key = TerminalImageVariantKey(
      reference: reference,
      mode: .sixel,
      outputSize: pixelSize,
      paletteSize: paletteBudget
    )

    if let cached = storage.withLockUnchecked({ $0.sixelPayloads[key] }) {
      return cached
    }

    let scaledPixels = scaledPixels(
      from: image,
      outputSize: pixelSize
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
      size: pixelSize,
      palette: palette
    )

    let payload = sixelCommand(
      indices: indices,
      palette: palette,
      size: pixelSize
    )

    storage.withLockUnchecked { storage in
      storage.sixelPayloads[key] = payload
    }
    return payload
  }
}

private func fallbackRenderMode(
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

private func apply(
  overlay: RasterImageOverlay,
  for bounds: CellRect,
  clippedTo visibleBounds: CellRect,
  to cells: inout [[RasterCell]],
  surfaceSize: CellSize
) {
  guard surfaceSize.width > 0, surfaceSize.height > 0 else {
    return
  }

  // Pre-compute the visible cell window. Cells of the overlay falling
  // outside `visibleBounds` belong to a region that an ancestor clipped
  // away (a ScrollView's content rect, or a sibling region — toolbar,
  // safeAreaInset). The kitty path crops the source rect to mirror this;
  // the fallback path historically didn't, so the dithered overlay would
  // overwrite a sibling toolbar cell-for-cell. Skipping clipped cells
  // here gives the fallback path the same clipping behavior.
  let visibleMinX = visibleBounds.origin.x
  let visibleMinY = visibleBounds.origin.y
  let visibleMaxX = visibleBounds.origin.x + visibleBounds.size.width
  let visibleMaxY = visibleBounds.origin.y + visibleBounds.size.height

  for y in 0..<overlay.size.height {
    let targetY = bounds.origin.y + y
    guard targetY >= 0, targetY < surfaceSize.height else {
      continue
    }
    guard targetY >= visibleMinY, targetY < visibleMaxY else {
      continue
    }

    for x in 0..<overlay.size.width {
      let targetX = bounds.origin.x + x
      guard targetX >= 0, targetX < surfaceSize.width else {
        continue
      }
      guard targetX >= visibleMinX, targetX < visibleMaxX else {
        continue
      }

      let cell = overlay.cells[y][x]
      guard imageFallbackCellIsVisible(cell) else {
        continue
      }
      cells[targetY][targetX] = cell
    }
  }
}

private func normalizedCells(
  _ existing: [[RasterCell]],
  size: CellSize
) -> [[RasterCell]] {
  guard size.width > 0, size.height > 0 else {
    return []
  }

  var cells = existing
  if cells.count < size.height {
    cells.append(
      contentsOf: Array(
        repeating: Array(repeating: .empty, count: size.width),
        count: size.height - cells.count
      )
    )
  }

  for index in cells.indices {
    if cells[index].count < size.width {
      cells[index].append(
        contentsOf: Array(
          repeating: .empty,
          count: size.width - cells[index].count
        )
      )
    } else if cells[index].count > size.width {
      cells[index] = Array(cells[index].prefix(size.width))
    }
  }

  if cells.count > size.height {
    cells = Array(cells.prefix(size.height))
  }

  return cells
}

private func imageFallbackCellIsVisible(
  _ cell: RasterCell
) -> Bool {
  cell.character != " " || cell.style != nil
}

private func compareImageAttachments(
  lhs: RasterImageAttachment,
  rhs: RasterImageAttachment
) -> Bool {
  if lhs.visibleBounds.origin.y != rhs.visibleBounds.origin.y {
    return lhs.visibleBounds.origin.y < rhs.visibleBounds.origin.y
  }
  if lhs.visibleBounds.origin.x != rhs.visibleBounds.origin.x {
    return lhs.visibleBounds.origin.x < rhs.visibleBounds.origin.x
  }
  return lhs.identity < rhs.identity
}

private func kittyPlacement(
  for attachment: RasterImageAttachment,
  imagePixelSize: PixelSize
) -> KittyPlacement? {
  let logicalBounds = attachment.bounds
  let visibleBounds = attachment.visibleBounds
  guard logicalBounds.size.width > 0, logicalBounds.size.height > 0,
    visibleBounds.size.width > 0, visibleBounds.size.height > 0
  else {
    return nil
  }

  // Cells of the logical placement that are clipped away by an ancestor
  // (e.g. a ScrollView's content rect, or a sibling toolbar reserving
  // space via safeAreaInset). Both top/left AND bottom/right must be
  // honored: cells written before the kitty stream remain in the buffer,
  // so any kitty rows extending into a sibling region (toolbar, footer)
  // would paint over those cells. Limiting cellRows/cellColumns to the
  // visible rect — and cropping the source pixels proportionally — keeps
  // the on-screen scale identical to the unclipped case while preventing
  // overdraw.
  let hiddenLeft = max(0, visibleBounds.origin.x - logicalBounds.origin.x)
  let hiddenTop = max(0, visibleBounds.origin.y - logicalBounds.origin.y)
  let hiddenRight = max(
    0,
    (logicalBounds.origin.x + logicalBounds.size.width)
      - (visibleBounds.origin.x + visibleBounds.size.width)
  )
  let hiddenBottom = max(
    0,
    (logicalBounds.origin.y + logicalBounds.size.height)
      - (visibleBounds.origin.y + visibleBounds.size.height)
  )

  let placement = KittyPlacement(
    origin: .init(
      x: logicalBounds.origin.x + hiddenLeft,
      y: logicalBounds.origin.y + hiddenTop
    ),
    cellColumns: max(1, logicalBounds.size.width - hiddenLeft - hiddenRight),
    cellRows: max(1, logicalBounds.size.height - hiddenTop - hiddenBottom),
    sourceRect: kittySourceRect(
      hiddenLeftCells: hiddenLeft,
      hiddenTopCells: hiddenTop,
      hiddenRightCells: hiddenRight,
      hiddenBottomCells: hiddenBottom,
      logicalCellSize: logicalBounds.size,
      imagePixelSize: imagePixelSize
    )
  )
  return placement.cellColumns > 0 && placement.cellRows > 0 ? placement : nil
}

private func kittySourceRect(
  hiddenLeftCells: Int,
  hiddenTopCells: Int,
  hiddenRightCells: Int,
  hiddenBottomCells: Int,
  logicalCellSize: CellSize,
  imagePixelSize: PixelSize
) -> KittySourceRect? {
  guard
    hiddenLeftCells > 0 || hiddenTopCells > 0
      || hiddenRightCells > 0 || hiddenBottomCells > 0
  else {
    return nil
  }

  let sourceX = proportionalPixelOffset(
    hiddenCells: hiddenLeftCells,
    totalCells: logicalCellSize.width,
    totalPixels: imagePixelSize.width
  )
  let sourceY = proportionalPixelOffset(
    hiddenCells: hiddenTopCells,
    totalCells: logicalCellSize.height,
    totalPixels: imagePixelSize.height
  )
  let trimRight = proportionalPixelOffset(
    hiddenCells: hiddenRightCells,
    totalCells: logicalCellSize.width,
    totalPixels: imagePixelSize.width
  )
  let trimBottom = proportionalPixelOffset(
    hiddenCells: hiddenBottomCells,
    totalCells: logicalCellSize.height,
    totalPixels: imagePixelSize.height
  )
  return KittySourceRect(
    x: sourceX,
    y: sourceY,
    width: max(1, imagePixelSize.width - sourceX - trimRight),
    height: max(1, imagePixelSize.height - sourceY - trimBottom)
  )
}

private func proportionalPixelOffset(
  hiddenCells: Int,
  totalCells: Int,
  totalPixels: Int
) -> Int {
  guard hiddenCells > 0, totalCells > 0, totalPixels > 0 else {
    return 0
  }
  let numerator = Int64(hiddenCells) * Int64(totalPixels)
  let rounded = (numerator + Int64(totalCells / 2)) / Int64(totalCells)
  return min(totalPixels - 1, max(0, Int(rounded)))
}

private func scaledPixels(
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

private func floydSteinbergQuantizedIndices(
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

private func sixelPaletteBudget(
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

private func kittyTransmitAndPlaceCommands(
  payload: KittyPayload,
  imageID: UInt32,
  cellColumns: Int,
  cellRows: Int,
  sourceRect: KittySourceRect?
) -> [String] {
  // Kitty requires payload chunks no larger than 4096 bytes of base64 data,
  // and every chunk except the last must be a multiple of 4 bytes so the
  // receiver can reassemble base64 boundaries.
  let chunkSize = 4096
  let chunks = stride(from: 0, to: payload.encodedData.count, by: chunkSize).map { index in
    let start = payload.encodedData.index(payload.encodedData.startIndex, offsetBy: index)
    let end =
      payload.encodedData.index(
        start,
        offsetBy: min(chunkSize, payload.encodedData.count - index),
        limitedBy: payload.encodedData.endIndex
      ) ?? payload.encodedData.endIndex
    return String(payload.encodedData[start..<end])
  }

  guard !chunks.isEmpty else {
    return []
  }

  return chunks.enumerated().map { index, chunk in
    let hasMore = index + 1 < chunks.count ? 1 : 0
    if index == 0 {
      // First chunk carries the full control data:
      //   a=T  transmit and display
      //   q=2  suppress all responses (we already probed for support)
      //   t=d  direct transmission (payload is base64 in this escape code)
      //   f    pixel format (100 for PNG, 32 for RGBA, 24 for RGB)
      //   s,v  source-image pixel width/height — required by `f=32`
      //        and `f=24`, ignored for `f=100`
      //   C=1  do not advance the cursor after placement
      //   c,r  display rectangle in terminal cells (Kitty scales to fit)
      //   i    stable image id so we can re-place the image by id later
      //   m    1 if more chunks follow, 0 otherwise
      var controlData =
        "_Ga=T,q=2,t=d,f=\(payload.format.formatKey),C=1,c=\(cellColumns),r=\(cellRows),i=\(imageID)"
      if case .rgba(let pixelSize) = payload.format {
        controlData.append(",s=\(pixelSize.width),v=\(pixelSize.height)")
      }
      // Note: the kitty protocol explicitly says the root-frame gap
      // *must* be set via a follow-up `a=a,r=1,z=...` control message
      // (see Animation in graphics-protocol.rst). `z=` on the initial
      // transmit applies only to additional frames, not frame 1.
      if let sourceRect {
        controlData.append(
          ",x=\(sourceRect.x),y=\(sourceRect.y),w=\(sourceRect.width),h=\(sourceRect.height)"
        )
      }
      controlData.append(",m=\(hasMore)")
      return "\u{001B}\(controlData);\(chunk)\u{001B}\\"
    }
    // Continuation chunks may only carry the `m` (and optionally `q`) key.
    return "\u{001B}_Gm=\(hasMore);\(chunk)\u{001B}\\"
  }
}

/// Flattens an array of decoded RGBA pixels into the row-major byte
/// stream Kitty expects under `f=32` (4 bytes per pixel: R, G, B, A).
private func SwiftTUI_rgbaBytes(from pixels: [RGBAImagePixel]) -> [UInt8] {
  var out = [UInt8]()
  out.reserveCapacity(pixels.count * 4)
  for pixel in pixels {
    out.append(UInt8(pixel.red))
    out.append(UInt8(pixel.green))
    out.append(UInt8(pixel.blue))
    out.append(UInt8(pixel.alpha))
  }
  return out
}

private func kittyPlacementCommand(
  imageID: UInt32,
  cellColumns: Int,
  cellRows: Int,
  sourceRect: KittySourceRect?
) -> String {
  // Re-place a previously transmitted image at the current cursor position
  // using the same cell rectangle. `a=p` does not re-transmit the image data.
  var controlData = "_Ga=p,q=2,C=1,c=\(cellColumns),r=\(cellRows),i=\(imageID)"
  if let sourceRect {
    controlData.append(
      ",x=\(sourceRect.x),y=\(sourceRect.y),w=\(sourceRect.width),h=\(sourceRect.height)"
    )
  }
  return "\u{001B}\(controlData)\u{001B}\\"
}

private func kittyImageID(
  reference: ImageAssetReference
) -> UInt32 {
  stableIdentifier(from: stableBytes(for: reference))
}

private func stableBytes(
  for reference: ImageAssetReference
) -> [UInt8] {
  switch reference {
  case .namedResource(let name):
    Array(("named:\(name)").utf8)
  case .filePath(let path):
    Array(("file:\(path)").utf8)
  case .embeddedImage(let bytes):
    Array("embedded:".utf8) + bytes
  }
}

func stableIdentifier(
  from bytes: [UInt8]
) -> UInt32 {
  var hash: UInt32 = 2_166_136_261
  for byte in bytes {
    hash ^= UInt32(byte)
    hash &*= 16_777_619
  }
  return hash == 0 ? 1 : hash
}

private func terminalSaveCursorSequence() -> String {
  "\u{001B}7"
}

private func terminalRestoreCursorSequence() -> String {
  "\u{001B}8"
}

private func terminalCursorSequence(
  to point: CellPoint
) -> String {
  let row = max(1, point.y + 1)
  let column = max(1, point.x + 1)
  return "\u{001B}[\(row);\(column)H"
}

private func base64Encoded(
  _ bytes: [UInt8]
) -> String {
  let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
  var result = ""
  var index = 0

  while index < bytes.count {
    let first = Int(bytes[index])
    let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
    let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
    let combined = (first << 16) | (second << 8) | third

    result.append(alphabet[(combined >> 18) & 0x3F])
    result.append(alphabet[(combined >> 12) & 0x3F])
    if index + 1 < bytes.count {
      result.append(alphabet[(combined >> 6) & 0x3F])
    } else {
      result.append("=")
    }
    if index + 2 < bytes.count {
      result.append(alphabet[combined & 0x3F])
    } else {
      result.append("=")
    }

    index += 3
  }

  return result
}

private func clampColorComponent(
  _ value: Double
) -> Double {
  max(0.0, min(1.0, value))
}

private func sixelPercent(
  _ component: Double
) -> Int {
  Int((component * 100).rounded())
}
