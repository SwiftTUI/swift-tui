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
  var variantID: String?
  var mode: TerminalImageRenderMode
  var outputSize: PixelSize
  var paletteSize: Int
}

extension TerminalImageVariantKey: Hashable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.reference == rhs.reference
      && lhs.variantID == rhs.variantID
      && lhs.mode == rhs.mode
      && lhs.outputSize.width == rhs.outputSize.width
      && lhs.outputSize.height == rhs.outputSize.height
      && lhs.paletteSize == rhs.paletteSize
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(reference)
    hasher.combine(variantID)
    hasher.combine(mode)
    hasher.combine(outputSize.width)
    hasher.combine(outputSize.height)
    hasher.combine(paletteSize)
  }
}

/// Cap policy for ``TerminalImageRenderer``'s per-kind payload caches. Mirrors
/// ``ImageBlendCompositorCachePolicy``: the renderer's kitty/sixel/fallback
/// caches, keyed by ``TerminalImageVariantKey``, would otherwise gain one entry
/// per distinct image variant for the life of the host and never release it, so
/// each kind is bounded by an entry count and an approximate-byte budget,
/// evicting least-recently-used entries first.
package struct TerminalImageRendererCachePolicy: Sendable, Equatable {
  package static let `default` = TerminalImageRendererCachePolicy(
    maxEntriesPerKind: 256,
    maxApproxBytesPerKind: 16 * 1024 * 1024
  )

  package var maxEntriesPerKind: Int
  package var maxApproxBytesPerKind: Int

  package init(
    maxEntriesPerKind: Int,
    maxApproxBytesPerKind: Int
  ) {
    self.maxEntriesPerKind = max(1, maxEntriesPerKind)
    self.maxApproxBytesPerKind = max(0, maxApproxBytesPerKind)
  }
}

/// A single-kind LRU + byte-budget cache keyed by ``TerminalImageVariantKey``.
/// Each entry remembers the approximate byte cost supplied at store time plus
/// the access generation it was last touched on;
/// ``store(_:approxBytes:for:policy:)`` evicts the lowest-generation entries
/// (never the key just written) until the kind is back within `policy`. A
/// stateless mirror of the eviction logic already proven in
/// ``ImageBlendCompositor``.
private struct BoundedVariantCache<Value> {
  private struct Entry {
    var value: Value
    var approxBytes: Int
    var lastAccessGeneration: Int
  }

  private var entries: [TerminalImageVariantKey: Entry] = [:]
  private var accessGeneration = 0
  private(set) var evictionCount = 0

  var count: Int {
    entries.count
  }

  var approxBytes: Int {
    entries.values.reduce(0) { $0 + $1.approxBytes }
  }

  mutating func lookup(
    _ key: TerminalImageVariantKey
  ) -> Value? {
    guard var entry = entries[key] else {
      return nil
    }
    accessGeneration += 1
    entry.lastAccessGeneration = accessGeneration
    entries[key] = entry
    return entry.value
  }

  mutating func store(
    _ value: Value,
    approxBytes: Int,
    for key: TerminalImageVariantKey,
    policy: TerminalImageRendererCachePolicy
  ) {
    accessGeneration += 1
    entries[key] = Entry(
      value: value,
      approxBytes: max(0, approxBytes),
      lastAccessGeneration: accessGeneration
    )
    evictIfNeeded(policy: policy, protecting: key)
  }

  private mutating func evictIfNeeded(
    policy: TerminalImageRendererCachePolicy,
    protecting protectedKey: TerminalImageVariantKey
  ) {
    while violates(policy), let key = oldestEvictableKey(protecting: protectedKey) {
      entries.removeValue(forKey: key)
      evictionCount += 1
    }
  }

  private func violates(
    _ policy: TerminalImageRendererCachePolicy
  ) -> Bool {
    entries.count > policy.maxEntriesPerKind
      || approxBytes > policy.maxApproxBytesPerKind
  }

  private func oldestEvictableKey(
    protecting protectedKey: TerminalImageVariantKey
  ) -> TerminalImageVariantKey? {
    entries
      .filter { key, _ in key != protectedKey }
      .min { lhs, rhs in
        lhs.value.lastAccessGeneration < rhs.value.lastAccessGeneration
      }?
      .key
  }
}

final class TerminalImageRenderer: Sendable {
  private struct Storage {
    var kittyPayloads = BoundedVariantCache<KittyPayload>()
    var sixelPayloads = BoundedVariantCache<String>()
    var fallbackOverlays = BoundedVariantCache<RasterImageOverlay>()
  }

  private let repository: ImageAssetRepository
  private let blendCompositor: ImageBlendCompositor
  private let cachePolicy: TerminalImageRendererCachePolicy
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())
  // A TerminalImageRenderer is created per host, so a *permanent* metric
  // registration made `providerCount` (itself the documented leak signal) climb
  // per host. Hold the token instead, so the provider deregisters when this
  // renderer is released.
  private let metricToken: MemoryMetricRegistry.Token

  init(
    repository: ImageAssetRepository,
    blendCompositorCachePolicy: ImageBlendCompositorCachePolicy = .default,
    payloadCachePolicy: TerminalImageRendererCachePolicy = .default
  ) {
    self.repository = repository
    blendCompositor = ImageBlendCompositor(
      repository: repository,
      cachePolicy: blendCompositorCachePolicy
    )
    cachePolicy = payloadCachePolicy
    // Capture the storage lock (already initialized) rather than `self`, so the
    // provider does not form a self-capturing closure during init (and the
    // registry holds no strong reference back to this renderer).
    let storage = storage
    metricToken = MemoryMetricRegistry.shared.register(
      ClosureMemoryMetricProvider {
        storage.withLockUnchecked { storage in
          MemoryMetricSnapshot(
            name: "TerminalImageRenderer.payloads",
            count: storage.kittyPayloads.count + storage.sixelPayloads.count
              + storage.fallbackOverlays.count,
            approxBytes: storage.kittyPayloads.approxBytes
              + storage.sixelPayloads.approxBytes
              + storage.fallbackOverlays.approxBytes,
            detail: [
              "kitty": storage.kittyPayloads.count,
              "sixel": storage.sixelPayloads.count,
              "fallback": storage.fallbackOverlays.count,
              "evictions": storage.kittyPayloads.evictionCount
                + storage.sixelPayloads.evictionCount
                + storage.fallbackOverlays.evictionCount,
            ]
          )
        }
      }
    )
  }

  package func imageBlendCacheSnapshot() -> ImageBlendCompositorCacheSnapshot {
    blendCompositor.cacheSnapshot()
  }

  func occupancy() -> (kitty: Int, sixel: Int, fallback: Int, approxBytes: Int) {
    storage.withLockUnchecked { storage in
      (
        storage.kittyPayloads.count,
        storage.sixelPayloads.count,
        storage.fallbackOverlays.count,
        storage.kittyPayloads.approxBytes
          + storage.sixelPayloads.approxBytes
          + storage.fallbackOverlays.approxBytes
      )
    }
  }

  func preparedSurface(
    for surface: RasterSurface,
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities,
    fallbackBackground: Color
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
      let presentation = presentationVariant(
        for: attachment,
        fallbackBackground: fallbackBackground
      )
      let displayAttachment = presentation?.attachment ?? attachment
      guard
        let overlay = fallbackOverlay(
          for: displayAttachment,
          sourceReference: attachment.resolvedReference,
          variant: presentation,
          capabilityProfile: capabilityProfile
        )
      else {
        continue
      }
      apply(
        overlay: overlay,
        for: displayAttachment.bounds,
        clippedTo: displayAttachment.visibleBounds,
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
    fallbackBackground: Color,
    transmittedKittyImages: inout Set<UInt32>
  ) -> [String] {
    graphicsWriteSteps(
      for: surface.imageAttachments,
      capabilityProfile: capabilityProfile,
      graphicsCapabilities: graphicsCapabilities,
      fallbackBackground: fallbackBackground,
      transmittedKittyImages: &transmittedKittyImages
    )
  }

  func graphicsWriteSteps(
    for attachments: [RasterImageAttachment],
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities,
    fallbackBackground: Color,
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
        let sourceImage = repository.decodedImage(for: reference)
      else {
        continue
      }

      switch graphicsProtocol {
      case .kitty:
        let presentation = presentationVariant(
          for: attachment,
          fallbackBackground: fallbackBackground
        )
        let displayAttachment = presentation?.attachment ?? attachment
        let image = presentation?.image ?? sourceImage
        guard
          let placement = kittyPlacement(
            for: displayAttachment,
            imagePixelSize: image.pixelSize
          )
        else {
          continue
        }
        let imageID =
          if let presentation {
            stableIdentifier(from: Array(presentation.id.utf8))
          } else {
            kittyImageID(reference: reference)
          }
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
          variantID: presentation?.id,
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
        let outputSize = sixelOutputSize(
          for: attachment.visibleBounds,
          graphicsCapabilities: graphicsCapabilities
        )
        let presentation = presentationVariant(
          for: attachment,
          outputSize: outputSize,
          fallbackBackground: fallbackBackground
        )
        let displayAttachment = presentation?.attachment ?? attachment
        let image = presentation?.image ?? sourceImage
        guard
          let payload = sixelPayload(
            for: displayAttachment,
            sourceReference: reference,
            variantID: presentation?.id,
            image: image,
            capabilityProfile: capabilityProfile,
            graphicsCapabilities: graphicsCapabilities
          )
        else {
          continue
        }

        writeSteps.append(terminalSaveCursorSequence())
        writeSteps.append(terminalCursorSequence(to: displayAttachment.visibleBounds.origin))
        writeSteps.append(payload)
        writeSteps.append(terminalRestoreCursorSequence())
      }
    }

    return writeSteps
  }

  private func fallbackOverlay(
    for attachment: RasterImageAttachment,
    sourceReference: ImageAssetReference?,
    variant: BlendedImageVariant?,
    capabilityProfile: TerminalCapabilityProfile
  ) -> RasterImageOverlay? {
    guard let reference = sourceReference else {
      return nil
    }

    let image: DecodedImage
    if let variant {
      image = variant.image
    } else {
      guard let sourceImage = repository.decodedImage(for: reference) else {
        return nil
      }
      image = sourceImage
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
      variantID: variant?.id,
      mode: mode,
      outputSize: outputSize,
      paletteSize: paletteSize
    )

    if let cached = storage.withLockUnchecked({ $0.fallbackOverlays.lookup(key) }) {
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
      storage.fallbackOverlays.store(
        overlay,
        approxBytes: overlay.size.width * overlay.size.height,
        for: key,
        policy: cachePolicy
      )
    }
    return overlay
  }

  private func kittyPayload(
    for reference: ImageAssetReference,
    variantID: String?,
    image: DecodedImage
  ) -> KittyPayload? {
    guard !image.encodedBytes.isEmpty else {
      return nil
    }

    let key = TerminalImageVariantKey(
      reference: reference,
      variantID: variantID,
      mode: .kitty,
      outputSize: image.pixelSize,
      paletteSize: 0
    )

    if let cached = storage.withLockUnchecked({ $0.kittyPayloads.lookup(key) }) {
      return cached
    }

    guard let payload = makeKittyPayload(for: image) else {
      return nil
    }

    storage.withLockUnchecked { storage in
      storage.kittyPayloads.store(
        payload,
        approxBytes: payload.encodedData.utf8.count,
        for: key,
        policy: cachePolicy
      )
    }
    return payload
  }

  private func sixelPayload(
    for attachment: RasterImageAttachment,
    sourceReference: ImageAssetReference,
    variantID: String?,
    image: DecodedImage,
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities
  ) -> String? {
    let pixelSize = sixelOutputSize(
      for: attachment.visibleBounds,
      graphicsCapabilities: graphicsCapabilities
    )
    let paletteBudget = sixelPaletteBudget(
      capabilityProfile: capabilityProfile,
      graphicsCapabilities: graphicsCapabilities
    )
    let key = TerminalImageVariantKey(
      reference: sourceReference,
      variantID: variantID,
      mode: .sixel,
      outputSize: pixelSize,
      paletteSize: paletteBudget
    )

    if let cached = storage.withLockUnchecked({ $0.sixelPayloads.lookup(key) }) {
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
      storage.sixelPayloads.store(
        payload,
        approxBytes: payload.utf8.count,
        for: key,
        policy: cachePolicy
      )
    }
    return payload
  }

  private func presentationVariant(
    for attachment: RasterImageAttachment,
    outputSize: PixelSize? = nil,
    fallbackBackground: Color
  ) -> BlendedImageVariant? {
    guard attachment.compositing != nil else {
      return nil
    }
    return blendCompositor.decodedVariant(
      for: attachment,
      outputSize: outputSize,
      fallbackBackground: fallbackBackground
    )
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
