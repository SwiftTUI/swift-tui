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

    guard let payload = makeKittyPayload(for: image) else {
      return nil
    }

    storage.withLockUnchecked { storage in
      storage.kittyPayloads[key] = payload
    }
    return payload
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

    let pixelSize = sixelOutputSize(
      for: attachment.visibleBounds,
      graphicsCapabilities: graphicsCapabilities
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

    guard
      let payload = makeSixelPayload(
        for: image,
        outputSize: pixelSize,
        paletteBudget: paletteBudget
      )
    else {
      return nil
    }

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
