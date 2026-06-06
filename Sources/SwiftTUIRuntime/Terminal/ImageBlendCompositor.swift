import SwiftTUICore

package struct BlendedImageEncodedPayload: Equatable, Sendable {
  package var id: String
  package var bytes: [UInt8]
  package var pixelSize: PixelSize

  package init(
    id: String,
    bytes: [UInt8],
    pixelSize: PixelSize
  ) {
    self.id = id
    self.bytes = bytes
    self.pixelSize = pixelSize
  }
}

struct BlendedImageVariant: Sendable {
  var id: String
  var image: DecodedImage
  var attachment: RasterImageAttachment
}

package struct ImageBlendCompositorCachePolicy: Sendable, Equatable {
  package static let `default` = ImageBlendCompositorCachePolicy(
    maxEntries: 256,
    maxDecodedPixels: 4 * 1024 * 1024,
    maxEncodedBytes: 16 * 1024 * 1024
  )

  package var maxEntries: Int
  package var maxDecodedPixels: Int
  package var maxEncodedBytes: Int

  package init(
    maxEntries: Int,
    maxDecodedPixels: Int,
    maxEncodedBytes: Int
  ) {
    self.maxEntries = max(1, maxEntries)
    self.maxDecodedPixels = max(0, maxDecodedPixels)
    self.maxEncodedBytes = max(0, maxEncodedBytes)
  }
}

package struct ImageBlendCompositorCacheSnapshot: Sendable, Equatable {
  package var entryCount: Int
  package var decodedPixelBytes: Int
  package var encodedBytes: Int
  package var retainedMetadataBytes: Int
  package var accessGeneration: Int
  package var evictionCount: Int
  package var decodedHits: Int
  package var decodedMisses: Int
  package var encodedHits: Int
  package var encodedMisses: Int

  package var totalApproxBytes: Int {
    decodedPixelBytes + encodedBytes + retainedMetadataBytes
  }
}

package final class ImageBlendCompositor: Sendable {
  private struct PresentationAttachment: Sendable {
    var identity: Identity
    var bounds: CellRect
    var visibleBounds: CellRect
    var pixelSize: PixelSize
    var cellPixelSize: PixelSize?
    var isResizable: Bool
    var scalingMode: ImageScalingMode

    var rasterAttachment: RasterImageAttachment {
      RasterImageAttachment(
        identity: identity,
        bounds: bounds,
        visibleBounds: visibleBounds,
        source: .data([]),
        resolvedReference: nil,
        pixelSize: pixelSize,
        cellPixelSize: cellPixelSize,
        isResizable: isResizable,
        scalingMode: scalingMode,
        compositing: nil
      )
    }

    var retainedByteEstimate: Int {
      let identityBytes = identity.components.reduce(0) { total, component in
        total + component.utf8.count
      }
      return identityBytes + (MemoryLayout<Int>.stride * 12) + 2
    }
  }

  private struct CacheEntry: Sendable {
    var id: String
    var pixelSize: PixelSize
    var encodedBytes: [UInt8]
    var decodedImage: DecodedImage?
    var presentationAttachment: PresentationAttachment
    var lastAccessGeneration: Int

    var decodedPixelCount: Int {
      decodedImage?.pixels.count ?? 0
    }

    var decodedPixelBytes: Int {
      decodedPixelCount * MemoryLayout<RGBAImagePixel>.stride
    }

    var encodedByteCount: Int {
      encodedBytes.count
    }

    var retainedMetadataBytes: Int {
      id.utf8.count
        + presentationAttachment.retainedByteEstimate
        + (MemoryLayout<Int>.stride * 4)
    }

    var encodedPayload: BlendedImageEncodedPayload {
      BlendedImageEncodedPayload(id: id, bytes: encodedBytes, pixelSize: pixelSize)
    }

    var decodedVariant: BlendedImageVariant? {
      guard let decodedImage else {
        return nil
      }
      return BlendedImageVariant(
        id: id,
        image: decodedImage,
        attachment: presentationAttachment.rasterAttachment
      )
    }
  }

  private struct Storage {
    var entries: [ImageBlendCacheKey: CacheEntry] = [:]
    var accessGeneration = 0
    var evictionCount = 0
    var decodedHits = 0
    var decodedMisses = 0
    var encodedHits = 0
    var encodedMisses = 0

    mutating func decodedLookup(
      for key: ImageBlendCacheKey
    ) -> (variant: BlendedImageVariant?, encodedBytes: [UInt8]?) {
      if var entry = entries[key] {
        if let variant = entry.decodedVariant {
          accessGeneration += 1
          entry.lastAccessGeneration = accessGeneration
          entries[key] = entry
          decodedHits += 1
          return (variant, entry.encodedBytes)
        }

        decodedMisses += 1
        return (nil, entry.encodedBytes)
      }

      decodedMisses += 1
      return (nil, nil)
    }

    mutating func encodedLookup(
      for key: ImageBlendCacheKey
    ) -> BlendedImageEncodedPayload? {
      guard var entry = entries[key] else {
        encodedMisses += 1
        return nil
      }

      accessGeneration += 1
      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      encodedHits += 1
      return entry.encodedPayload
    }

    mutating func storeDecodedVariant(
      _ variant: BlendedImageVariant,
      for key: ImageBlendCacheKey,
      presentationAttachment: PresentationAttachment,
      policy: ImageBlendCompositorCachePolicy
    ) {
      accessGeneration += 1
      var entry = entries[key]
        ?? CacheEntry(
          id: variant.id,
          pixelSize: variant.image.pixelSize,
          encodedBytes: variant.image.encodedBytes,
          decodedImage: nil,
          presentationAttachment: presentationAttachment,
          lastAccessGeneration: accessGeneration
        )
      entry.id = variant.id
      entry.pixelSize = variant.image.pixelSize
      entry.encodedBytes = variant.image.encodedBytes
      entry.decodedImage = variant.image
      entry.presentationAttachment = presentationAttachment
      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      evictIfNeeded(policy: policy, protecting: key)
    }

    mutating func storeEncodedPayload(
      _ payload: BlendedImageEncodedPayload,
      presentationAttachment: PresentationAttachment,
      for key: ImageBlendCacheKey,
      policy: ImageBlendCompositorCachePolicy
    ) {
      accessGeneration += 1
      var entry = entries[key]
        ?? CacheEntry(
          id: payload.id,
          pixelSize: payload.pixelSize,
          encodedBytes: payload.bytes,
          decodedImage: nil,
          presentationAttachment: presentationAttachment,
          lastAccessGeneration: accessGeneration
        )
      entry.id = payload.id
      entry.pixelSize = payload.pixelSize
      entry.encodedBytes = payload.bytes
      entry.presentationAttachment = presentationAttachment
      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      evictIfNeeded(policy: policy, protecting: key)
    }

    func snapshot() -> ImageBlendCompositorCacheSnapshot {
      var decodedPixelBytes = 0
      var encodedBytes = 0
      var retainedMetadataBytes = 0
      for (key, entry) in entries {
        decodedPixelBytes += entry.decodedPixelBytes
        encodedBytes += entry.encodedByteCount
        retainedMetadataBytes += key.retainedByteEstimate + entry.retainedMetadataBytes
      }
      return ImageBlendCompositorCacheSnapshot(
        entryCount: entries.count,
        decodedPixelBytes: decodedPixelBytes,
        encodedBytes: encodedBytes,
        retainedMetadataBytes: retainedMetadataBytes,
        accessGeneration: accessGeneration,
        evictionCount: evictionCount,
        decodedHits: decodedHits,
        decodedMisses: decodedMisses,
        encodedHits: encodedHits,
        encodedMisses: encodedMisses
      )
    }

    private mutating func evictIfNeeded(
      policy: ImageBlendCompositorCachePolicy,
      protecting protectedKey: ImageBlendCacheKey
    ) {
      while violates(policy), let key = oldestEvictableKey(protecting: protectedKey) {
        entries.removeValue(forKey: key)
        evictionCount += 1
      }
    }

    private func violates(
      _ policy: ImageBlendCompositorCachePolicy
    ) -> Bool {
      let snapshot = snapshot()
      return snapshot.entryCount > policy.maxEntries
        || decodedPixelCount > policy.maxDecodedPixels
        || snapshot.encodedBytes + snapshot.retainedMetadataBytes > policy.maxEncodedBytes
    }

    private var decodedPixelCount: Int {
      entries.values.reduce(0) { $0 + $1.decodedPixelCount }
    }

    private func oldestEvictableKey(
      protecting protectedKey: ImageBlendCacheKey
    ) -> ImageBlendCacheKey? {
      entries
        .filter { key, _ in key != protectedKey }
        .min { lhs, rhs in
          lhs.value.lastAccessGeneration < rhs.value.lastAccessGeneration
        }?
        .key
    }
  }

  private let repository: ImageAssetRepository
  private let cachePolicy: ImageBlendCompositorCachePolicy
  private let storage: OSAllocatedUnfairLock<Storage>
  private let memoryMetricToken: MemoryMetricRegistry.Token

  package convenience init() {
    self.init(repository: ImageAssetRepository())
  }

  package convenience init(
    cachePolicy: ImageBlendCompositorCachePolicy
  ) {
    self.init(repository: ImageAssetRepository(), cachePolicy: cachePolicy)
  }

  init(
    repository: ImageAssetRepository,
    cachePolicy: ImageBlendCompositorCachePolicy = .default
  ) {
    let storage = OSAllocatedUnfairLock(uncheckedState: Storage())
    self.repository = repository
    self.cachePolicy = cachePolicy
    self.storage = storage
    memoryMetricToken = MemoryMetricRegistry.shared.register(
      ClosureMemoryMetricProvider {
        let snapshot = storage.withLockUnchecked { $0.snapshot() }
        return MemoryMetricSnapshot(
          name: "ImageBlendCompositor.variants",
          count: snapshot.entryCount,
          approxBytes: snapshot.totalApproxBytes,
          detail: [
            "accessGeneration": snapshot.accessGeneration,
            "decodedPixelBytes": snapshot.decodedPixelBytes,
            "encodedBytes": snapshot.encodedBytes,
            "retainedMetadataBytes": snapshot.retainedMetadataBytes,
            "evictions": snapshot.evictionCount,
            "decodedHits": snapshot.decodedHits,
            "decodedMisses": snapshot.decodedMisses,
            "encodedHits": snapshot.encodedHits,
            "encodedMisses": snapshot.encodedMisses,
          ]
        )
      }
    )
  }

  package func cacheSnapshot() -> ImageBlendCompositorCacheSnapshot {
    storage.withLockUnchecked { $0.snapshot() }
  }

  func decodedVariant(
    for attachment: RasterImageAttachment,
    outputSize requestedOutputSize: PixelSize? = nil,
    fallbackBackground: Color
  ) -> BlendedImageVariant? {
    guard
      let reference = imageReference(for: attachment),
      let compositing = attachment.compositing,
      !attachment.visibleBounds.isEmpty
    else {
      return nil
    }

    let outputSize = requestedOutputSize ?? blendedOutputSize(for: attachment, compositing: compositing)
    guard outputSize.width > 0, outputSize.height > 0 else {
      return nil
    }

    let key = ImageBlendCacheKey(
      source: sourceCacheKey(for: reference),
      bounds: attachment.bounds,
      visibleBounds: attachment.visibleBounds,
      outputSize: outputSize,
      scalingMode: attachment.scalingMode,
      blendMode: compositing.blendMode,
      cellPixelSize: compositing.cellPixelSize,
      backdropSignature: compositing.backdropSignature,
      fallbackBackground: fallbackBackground
    )
    let lookup = storage.withLockUnchecked { $0.decodedLookup(for: key) }
    if let cached = lookup.variant {
      return cached
    }

    guard let sourceImage = repository.decodedImage(for: reference) else {
      return nil
    }

    let pixels = blendedPixels(
      sourceImage: sourceImage,
      attachment: attachment,
      compositing: compositing,
      outputSize: outputSize,
      fallbackBackground: fallbackBackground
    )
    guard pixels.count == outputSize.width * outputSize.height else {
      return nil
    }

    let id = blendedImageID(for: key)
    let encodedBytes = lookup.encodedBytes
      ?? ImageBlendPNGEncoder.encode(pixels: pixels, pixelSize: outputSize)
    let presentationAttachment = imageBlendPresentationAttachment(
      from: attachment,
      outputSize: outputSize
    )

    let variant = BlendedImageVariant(
      id: id,
      image: DecodedImage(
        encodedBytes: encodedBytes,
        encodedFormat: .png,
        pixelSize: outputSize,
        pixels: pixels
      ),
      attachment: presentationAttachment.rasterAttachment
    )

    storage.withLockUnchecked { storage in
      storage.storeDecodedVariant(
        variant,
        for: key,
        presentationAttachment: presentationAttachment,
        policy: cachePolicy
      )
    }
    return variant
  }

  package func encodedPNGPayload(
    for attachment: RasterImageAttachment,
    fallbackBackground: Color
  ) -> BlendedImageEncodedPayload? {
    guard
      let reference = imageReference(for: attachment),
      let compositing = attachment.compositing,
      !attachment.visibleBounds.isEmpty
    else {
      return nil
    }

    let outputSize = blendedOutputSize(for: attachment, compositing: compositing)
    let key = ImageBlendCacheKey(
      source: sourceCacheKey(for: reference),
      bounds: attachment.bounds,
      visibleBounds: attachment.visibleBounds,
      outputSize: outputSize,
      scalingMode: attachment.scalingMode,
      blendMode: compositing.blendMode,
      cellPixelSize: compositing.cellPixelSize,
      backdropSignature: compositing.backdropSignature,
      fallbackBackground: fallbackBackground
    )
    if let cached = storage.withLockUnchecked({ $0.encodedLookup(for: key) }) {
      return cached
    }

    guard let sourceImage = repository.decodedImage(for: reference) else {
      return nil
    }

    let pixels = blendedPixels(
      sourceImage: sourceImage,
      attachment: attachment,
      compositing: compositing,
      outputSize: outputSize,
      fallbackBackground: fallbackBackground
    )
    guard pixels.count == outputSize.width * outputSize.height else {
      return nil
    }

    let payload = BlendedImageEncodedPayload(
      id: blendedImageID(for: key),
      bytes: ImageBlendPNGEncoder.encode(pixels: pixels, pixelSize: outputSize),
      pixelSize: outputSize
    )
    let presentationAttachment = imageBlendPresentationAttachment(
      from: attachment,
      outputSize: outputSize
    )
    storage.withLockUnchecked { storage in
      storage.storeEncodedPayload(
        payload,
        presentationAttachment: presentationAttachment,
        for: key,
        policy: cachePolicy
      )
    }
    return payload
  }

  private func imageBlendPresentationAttachment(
    from attachment: RasterImageAttachment,
    outputSize: PixelSize
  ) -> PresentationAttachment {
    PresentationAttachment(
      identity: attachment.identity,
      bounds: attachment.visibleBounds,
      visibleBounds: attachment.visibleBounds,
      pixelSize: outputSize,
      cellPixelSize: attachment.cellPixelSize,
      isResizable: attachment.isResizable,
      scalingMode: attachment.scalingMode
    )
  }

  private func blendedPixels(
    sourceImage: DecodedImage,
    attachment: RasterImageAttachment,
    compositing: RasterImageCompositing,
    outputSize: PixelSize,
    fallbackBackground: Color
  ) -> [RGBAImagePixel] {
    let bounds = attachment.bounds
    let visibleBounds = attachment.visibleBounds
    let cellPixelSize = compositing.cellPixelSize
    let logicalOutputSize = PixelSize(
      width: max(1, bounds.size.width * max(1, cellPixelSize.width)),
      height: max(1, bounds.size.height * max(1, cellPixelSize.height))
    )
    let visibleLogicalPixelSize = PixelSize(
      width: max(1, visibleBounds.size.width * max(1, cellPixelSize.width)),
      height: max(1, visibleBounds.size.height * max(1, cellPixelSize.height))
    )
    let hiddenLeftPixels = max(0, visibleBounds.origin.x - bounds.origin.x) * max(
      1,
      cellPixelSize.width
    )
    let hiddenTopPixels = max(0, visibleBounds.origin.y - bounds.origin.y) * max(
      1,
      cellPixelSize.height
    )
    let cellPixelWidth = max(1, cellPixelSize.width)
    let cellPixelHeight = max(1, cellPixelSize.height)

    var pixels: [RGBAImagePixel] = []
    pixels.reserveCapacity(outputSize.width * outputSize.height)

    for y in 0..<outputSize.height {
      let visiblePixelY = proportionalPixelSample(
        destinationIndex: y,
        destinationCount: outputSize.height,
        sourceCount: visibleLogicalPixelSize.height
      )
      let logicalY = min(logicalOutputSize.height - 1, hiddenTopPixels + visiblePixelY)
      let sourceY = proportionalPixelSample(
        destinationIndex: logicalY,
        destinationCount: logicalOutputSize.height,
        sourceCount: sourceImage.pixelSize.height
      )
      let backdropCellY = min(visibleBounds.size.height - 1, visiblePixelY / cellPixelHeight)
      let backdropPixelY = visiblePixelY % cellPixelHeight

      for x in 0..<outputSize.width {
        let visiblePixelX = proportionalPixelSample(
          destinationIndex: x,
          destinationCount: outputSize.width,
          sourceCount: visibleLogicalPixelSize.width
        )
        let logicalX = min(logicalOutputSize.width - 1, hiddenLeftPixels + visiblePixelX)
        let sourceX = proportionalPixelSample(
          destinationIndex: logicalX,
          destinationCount: logicalOutputSize.width,
          sourceCount: sourceImage.pixelSize.width
        )
        let backdropCellX = min(visibleBounds.size.width - 1, visiblePixelX / cellPixelWidth)
        let backdropPixelX = visiblePixelX % cellPixelWidth

        let source = color(
          from: sourceImage.pixels[(sourceY * sourceImage.pixelSize.width) + sourceX]
        )
        let destination = backdropPixelColor(
          compositing.destinationBackdrop,
          relativeX: backdropCellX,
          relativeY: backdropCellY,
          pixelX: backdropPixelX,
          pixelY: backdropPixelY,
          cellPixelSize: PixelSize(width: cellPixelWidth, height: cellPixelHeight),
          fallbackBackground: fallbackBackground
        )
        if let sourceBackdrop = compositing.sourceBackdrop {
          let groupBackdrop = backdropPixelColor(
            sourceBackdrop,
            relativeX: backdropCellX,
            relativeY: backdropCellY,
            pixelX: backdropPixelX,
            pixelY: backdropPixelY,
            cellPixelSize: PixelSize(width: cellPixelWidth, height: cellPixelHeight),
            fallbackBackground: fallbackBackground
          )
          let flattenedSource = source.composited(over: groupBackdrop)
          pixels.append(
            pixel(
              from: flattenedSource.composited(
                over: destination,
                mode: compositing.blendMode
              )
            )
          )
        } else {
          pixels.append(
            pixel(
              from: source.composited(
                over: destination,
                mode: compositing.blendMode
              )
            )
          )
        }
      }
    }

    return pixels
  }

  private func imageReference(
    for attachment: RasterImageAttachment
  ) -> ImageAssetReference? {
    if let reference = attachment.resolvedReference {
      return reference
    }
    if case .data(let bytes) = attachment.source {
      return .embeddedImage(bytes)
    }
    return nil
  }

  private func blendedOutputSize(
    for attachment: RasterImageAttachment,
    compositing: RasterImageCompositing
  ) -> PixelSize {
    PixelSize(
      width: max(1, attachment.visibleBounds.size.width * max(1, compositing.cellPixelSize.width)),
      height: max(1, attachment.visibleBounds.size.height * max(1, compositing.cellPixelSize.height))
    )
  }

  private func backdropPixelColor(
    _ backdrop: RasterImageBackdrop,
    relativeX: Int,
    relativeY: Int,
    pixelX: Int,
    pixelY: Int,
    cellPixelSize: PixelSize,
    fallbackBackground: Color
  ) -> Color {
    guard backdrop.bounds.size.width > 0, backdrop.bounds.size.height > 0 else {
      return fallbackBackground
    }

    let x = max(0, min(backdrop.bounds.size.width - 1, relativeX))
    let y = max(0, min(backdrop.bounds.size.height - 1, relativeY))
    let index = y * backdrop.bounds.size.width + x
    guard index >= 0, index < backdrop.cells.count else {
      return fallbackBackground
    }
    let cell = backdrop.cells[index]
    let background = cell.backgroundColor ?? fallbackBackground
    guard
      let foreground = cell.foregroundColor,
      coverage(
        rasterBackdropCoverage(for: cell.glyph, spanWidth: cell.spanWidth),
        containsPixelX: pixelX,
        y: pixelY,
        spanWidth: cell.spanWidth,
        spanOffset: cell.spanOffset,
        cellPixelSize: cellPixelSize
      )
    else {
      return background
    }
    return foreground.composited(over: background)
  }

  private func coverage(
    _ coverage: RasterBackdropCoverage,
    containsPixelX pixelX: Int,
    y pixelY: Int,
    spanWidth: Int,
    spanOffset: Int,
    cellPixelSize: PixelSize
  ) -> Bool {
    let width = max(1, cellPixelSize.width)
    let height = max(1, cellPixelSize.height)
    let x = max(0, min(width - 1, pixelX))
    let y = max(0, min(height - 1, pixelY))

    switch coverage {
    case .none:
      return false
    case .full:
      return true
    case .quadrant(let mask):
      let column = min(1, (x * 2) / width)
      let row = min(1, (y * 2) / height)
      let bit: UInt8 = switch (row, column) {
      case (0, 0): 0b0001
      case (0, 1): 0b0010
      case (1, 0): 0b0100
      default: 0b1000
      }
      return (mask & bit) != 0
    case .braille(let mask):
      let column = min(1, (x * 2) / width)
      let row = min(3, (y * 4) / height)
      let bitIndex: UInt8 = switch (column, row) {
      case (0, 0): 0
      case (0, 1): 1
      case (0, 2): 2
      case (1, 0): 3
      case (1, 1): 4
      case (1, 2): 5
      case (0, 3): 6
      default: 7
      }
      return (mask & (UInt8(1) << bitIndex)) != 0
    case .textApproximation:
      let textSpanWidth = max(1, spanWidth)
      let clampedOffset = max(0, min(textSpanWidth - 1, spanOffset))
      let expandedWidth = width * textSpanWidth
      let expandedX = (clampedOffset * width) + x
      let horizontalInset = expandedWidth > 2 ? max(1, expandedWidth / 4) : 0
      let verticalInset = height > 2 ? max(1, height / 5) : 0
      return expandedX >= horizontalInset
        && expandedX <= expandedWidth - 1 - horizontalInset
        && y >= verticalInset
        && y <= height - 1 - verticalInset
    }
  }

  private func color(
    from pixel: RGBAImagePixel
  ) -> Color {
    Color(
      red: Double(pixel.red) / 255.0,
      green: Double(pixel.green) / 255.0,
      blue: Double(pixel.blue) / 255.0,
      alpha: Double(pixel.alpha) / 255.0
    )
  }

  private func pixel(
    from color: Color
  ) -> RGBAImagePixel {
    let converted = color.converted(to: .sRGB, gamutMapping: .clip)
    return RGBAImagePixel(
      red: byte(from: converted.red),
      green: byte(from: converted.green),
      blue: byte(from: converted.blue),
      alpha: byte(from: converted.alpha)
    )
  }

  private func byte(
    from component: Double
  ) -> Int {
    Int((max(0.0, min(1.0, component)) * 255.0).rounded())
  }
}

private struct ImageBlendCacheKey: Hashable, Sendable {
  var source: ImageBlendSourceCacheKey
  var bounds: CellRect
  var visibleBounds: CellRect
  var outputSize: PixelSize
  var scalingMode: ImageScalingMode
  var blendMode: BlendMode
  var cellPixelSize: PixelSize
  var backdropSignature: UInt64
  var fallbackBackground: Color

  var retainedByteEstimate: Int {
    source.retainedByteEstimate
      + fallbackBackground.profile.name.utf8.count
      + (MemoryLayout<Int>.stride * 14)
      + (MemoryLayout<UInt64>.stride * 5)
  }
}

private enum ImageBlendSourceCacheKey: Hashable, Sendable {
  case namedResource(String)
  case filePath(String)
  case embeddedImage(byteCount: Int, digest: UInt64, secondaryDigest: UInt64)

  var retainedByteEstimate: Int {
    switch self {
    case .namedResource(let name):
      name.utf8.count
    case .filePath(let path):
      path.utf8.count
    case .embeddedImage:
      MemoryLayout<Int>.stride + (MemoryLayout<UInt64>.stride * 2)
    }
  }
}

private func sourceCacheKey(
  for reference: ImageAssetReference
) -> ImageBlendSourceCacheKey {
  switch reference {
  case .namedResource(let name):
    .namedResource(name)
  case .filePath(let path):
    .filePath(path)
  case .embeddedImage(let bytes):
    .embeddedImage(
      byteCount: bytes.count,
      digest: stableDigest(for: bytes, seed: 0xcbf2_9ce4_8422_2325),
      secondaryDigest: stableDigest(for: bytes, seed: 0x8422_2325_cbf2_9ce4)
    )
  }
}

private func stableDigest(
  for bytes: [UInt8],
  seed: UInt64
) -> UInt64 {
  var hasher = ImageBlendStableHasher(seed: seed)
  hasher.combine(bytes.count)
  for byte in bytes {
    hasher.combine(byte)
  }
  return hasher.value
}

private func proportionalPixelSample(
  destinationIndex: Int,
  destinationCount: Int,
  sourceCount: Int
) -> Int {
  guard destinationCount > 0, sourceCount > 0 else {
    return 0
  }
  return min(
    sourceCount - 1,
    Int(
      (Double((destinationIndex * 2) + 1) * Double(sourceCount))
        / Double(destinationCount * 2)
    )
  )
}

private func blendedImageID(
  for key: ImageBlendCacheKey
) -> String {
  var hasher = ImageBlendStableHasher()
  hasher.combine("swift-tui-blended-image-v1")
  hasher.combine(key.source)
  hasher.combine(key.bounds)
  hasher.combine(key.visibleBounds)
  hasher.combine(key.outputSize.width)
  hasher.combine(key.outputSize.height)
  hasher.combine(key.scalingMode.rawValue)
  hasher.combine(key.blendMode.rawValue)
  hasher.combine(key.cellPixelSize.width)
  hasher.combine(key.cellPixelSize.height)
  hasher.combine(key.backdropSignature)
  hasher.combine(key.fallbackBackground)
  return "blend:png:\(hexString(hasher.value))"
}

private struct ImageBlendStableHasher {
  private(set) var value: UInt64

  init(
    seed: UInt64 = 0xcbf2_9ce4_8422_2325
  ) {
    value = seed
  }

  mutating func combine(
    _ source: ImageBlendSourceCacheKey
  ) {
    switch source {
    case .namedResource(let name):
      combine("named")
      combine(name)
    case .filePath(let path):
      combine("file")
      combine(path)
    case .embeddedImage(let byteCount, let digest, let secondaryDigest):
      combine("embedded")
      combine(byteCount)
      combine(digest)
      combine(secondaryDigest)
    }
  }

  mutating func combine(
    _ rect: CellRect
  ) {
    combine(rect.origin.x)
    combine(rect.origin.y)
    combine(rect.size.width)
    combine(rect.size.height)
  }

  mutating func combine(
    _ color: Color
  ) {
    combine(color.red.bitPattern)
    combine(color.green.bitPattern)
    combine(color.blue.bitPattern)
    combine(color.alpha.bitPattern)
    combine(color.profile.name)
  }

  mutating func combine(
    _ string: String
  ) {
    for byte in string.utf8 {
      combine(byte)
    }
    combine(UInt8(0))
  }

  mutating func combine(
    _ value: Int
  ) {
    combine(UInt64(bitPattern: Int64(value)))
  }

  mutating func combine(
    _ value: UInt64
  ) {
    var remaining = value
    for _ in 0..<8 {
      combine(UInt8(remaining & 0xFF))
      remaining >>= 8
    }
  }

  mutating func combine(
    _ byte: UInt8
  ) {
    value ^= UInt64(byte)
    value &*= 0x100_0000_01b3
  }
}

private func hexString(
  _ value: UInt64
) -> String {
  var text = String(value, radix: 16, uppercase: false)
  while text.count < 16 {
    text = "0" + text
  }
  return text
}

private enum ImageBlendPNGEncoder {
  static func encode(
    pixels: [RGBAImagePixel],
    pixelSize: PixelSize
  ) -> [UInt8] {
    var raw: [UInt8] = []
    raw.reserveCapacity(pixelSize.height * (1 + pixelSize.width * 4))
    for row in 0..<pixelSize.height {
      raw.append(0)
      for col in 0..<pixelSize.width {
        let pixel = pixels[row * pixelSize.width + col]
        raw.append(UInt8(pixel.red))
        raw.append(UInt8(pixel.green))
        raw.append(UInt8(pixel.blue))
        raw.append(UInt8(pixel.alpha))
      }
    }

    var output: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    output.append(
      contentsOf: pngChunk(
        type: "IHDR",
        data: ihdrData(width: pixelSize.width, height: pixelSize.height)
      )
    )
    output.append(contentsOf: pngChunk(type: "IDAT", data: zlibStream(of: raw)))
    output.append(contentsOf: pngChunk(type: "IEND", data: []))
    return output
  }

  private static func ihdrData(
    width: Int,
    height: Int
  ) -> [UInt8] {
    var data: [UInt8] = []
    data.reserveCapacity(13)
    data.append(contentsOf: bigEndianUInt32(UInt32(width)))
    data.append(contentsOf: bigEndianUInt32(UInt32(height)))
    data.append(8)
    data.append(6)
    data.append(0)
    data.append(0)
    data.append(0)
    return data
  }

  private static func pngChunk(
    type: String,
    data: [UInt8]
  ) -> [UInt8] {
    var output: [UInt8] = []
    output.reserveCapacity(8 + data.count + 4)
    output.append(contentsOf: bigEndianUInt32(UInt32(data.count)))
    let typeBytes = Array(type.utf8)
    output.append(contentsOf: typeBytes)
    output.append(contentsOf: data)
    output.append(contentsOf: bigEndianUInt32(crc32(typeBytes + data)))
    return output
  }

  private static func zlibStream(
    of raw: [UInt8]
  ) -> [UInt8] {
    var output: [UInt8] = [0x78, 0x01]

    let maxBlock = 65_535
    var index = 0
    while index < raw.count {
      let remaining = raw.count - index
      let count = min(remaining, maxBlock)
      let isFinal = index + count == raw.count
      output.append(isFinal ? 0x01 : 0x00)
      let length = UInt16(count)
      output.append(UInt8(length & 0xFF))
      output.append(UInt8((length >> 8) & 0xFF))
      let inverseLength = ~length
      output.append(UInt8(inverseLength & 0xFF))
      output.append(UInt8((inverseLength >> 8) & 0xFF))
      output.append(contentsOf: raw[index..<(index + count)])
      index += count
    }

    if raw.isEmpty {
      output.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
    }

    output.append(contentsOf: bigEndianUInt32(adler32(raw)))
    return output
  }

  private static func bigEndianUInt32(
    _ value: UInt32
  ) -> [UInt8] {
    [
      UInt8((value >> 24) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8(value & 0xFF),
    ]
  }

  private static func crc32(
    _ bytes: [UInt8]
  ) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        let mask = UInt32(0) &- (crc & 1)
        crc = (crc >> 1) ^ (0xEDB8_8320 & mask)
      }
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static func adler32(
    _ bytes: [UInt8]
  ) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    let modulus: UInt32 = 65_521
    for byte in bytes {
      a = (a + UInt32(byte)) % modulus
      b = (b + a) % modulus
    }
    return (b << 16) | a
  }
}
