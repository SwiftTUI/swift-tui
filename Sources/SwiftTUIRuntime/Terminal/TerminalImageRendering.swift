import SwiftTUICore

enum TerminalImageRenderMode: String, Hashable, Sendable {
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
    MemoryMetricRegistry.shared.registerPermanent(
      ClosureMemoryMetricProvider { [weak self] in
        guard let self else {
          return MemoryMetricSnapshot(name: "TerminalImageRenderer.payloads", count: 0)
        }
        let occupancy = self.occupancy()
        return MemoryMetricSnapshot(
          name: "TerminalImageRenderer.payloads",
          count: occupancy.kitty + occupancy.sixel + occupancy.fallback,
          approxBytes: occupancy.approxBytes,
          detail: [
            "kitty": occupancy.kitty,
            "sixel": occupancy.sixel,
            "fallback": occupancy.fallback,
          ]
        )
      }
    )
  }

  func occupancy() -> (kitty: Int, sixel: Int, fallback: Int, approxBytes: Int) {
    storage.withLockUnchecked { storage in
      var approxBytes = 0
      for payload in storage.kittyPayloads.values {
        approxBytes += payload.encodedData.utf8.count
      }
      for payload in storage.sixelPayloads.values {
        approxBytes += payload.utf8.count
      }
      for overlay in storage.fallbackOverlays.values {
        approxBytes += overlay.size.width * overlay.size.height
      }
      return (
        storage.kittyPayloads.count,
        storage.sixelPayloads.count,
        storage.fallbackOverlays.count,
        approxBytes
      )
    }
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
    let cellSize = attachment.bounds.size
    let outputSize = fallbackOutputSize(
      for: mode,
      cellSize: cellSize
    )
    let paletteSize = fallbackPaletteSize(for: mode)

    let key = TerminalImageVariantKey(
      reference: reference,
      mode: mode,
      outputSize: outputSize,
      paletteSize: paletteSize
    )

    if let cached = storage.withLockUnchecked({ $0.fallbackOverlays[key] }) {
      return cached
    }

    guard
      let overlay = makeFallbackOverlay(
        for: image,
        cellSize: cellSize,
        mode: mode
      )
    else {
      return nil
    }

    storage.withLockUnchecked { storage in
      storage.fallbackOverlays[key] = overlay
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
