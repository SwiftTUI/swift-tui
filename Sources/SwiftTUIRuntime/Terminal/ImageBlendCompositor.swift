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
  package var accessGeneration: Int
  package var evictionCount: Int
  package var decodedHits: Int
  package var decodedMisses: Int
  package var encodedHits: Int
  package var encodedMisses: Int

  package var totalApproxBytes: Int {
    decodedPixelBytes + encodedBytes
  }
}

package final class ImageBlendCompositor: Sendable {
  private struct CacheEntry: Sendable {
    var id: String
    var pixelSize: PixelSize
    var encodedBytes: [UInt8]
    var decodedImage: DecodedImage?
    var attachment: RasterImageAttachment
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

    var encodedPayload: BlendedImageEncodedPayload {
      BlendedImageEncodedPayload(id: id, bytes: encodedBytes, pixelSize: pixelSize)
    }

    var decodedVariant: BlendedImageVariant? {
      guard let decodedImage else {
        return nil
      }
      return BlendedImageVariant(id: id, image: decodedImage, attachment: attachment)
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
      accessGeneration += 1
      if var entry = entries[key] {
        entry.lastAccessGeneration = accessGeneration
        entries[key] = entry

        if let variant = entry.decodedVariant {
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
      accessGeneration += 1
      guard var entry = entries[key] else {
        encodedMisses += 1
        return nil
      }

      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      encodedHits += 1
      return entry.encodedPayload
    }

    mutating func storeDecodedVariant(
      _ variant: BlendedImageVariant,
      for key: ImageBlendCacheKey,
      policy: ImageBlendCompositorCachePolicy
    ) {
      accessGeneration += 1
      var entry = entries[key]
        ?? CacheEntry(
          id: variant.id,
          pixelSize: variant.image.pixelSize,
          encodedBytes: variant.image.encodedBytes,
          decodedImage: nil,
          attachment: variant.attachment,
          lastAccessGeneration: accessGeneration
        )
      entry.id = variant.id
      entry.pixelSize = variant.image.pixelSize
      entry.encodedBytes = variant.image.encodedBytes
      entry.decodedImage = variant.image
      entry.attachment = variant.attachment
      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      evictIfNeeded(policy: policy, protecting: key)
    }

    mutating func storeEncodedPayload(
      _ payload: BlendedImageEncodedPayload,
      attachment: RasterImageAttachment,
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
          attachment: attachment,
          lastAccessGeneration: accessGeneration
        )
      entry.id = payload.id
      entry.pixelSize = payload.pixelSize
      entry.encodedBytes = payload.bytes
      entry.attachment = attachment
      entry.lastAccessGeneration = accessGeneration
      entries[key] = entry
      evictIfNeeded(policy: policy, protecting: key)
    }

    func snapshot() -> ImageBlendCompositorCacheSnapshot {
      var decodedPixelBytes = 0
      var encodedBytes = 0
      for entry in entries.values {
        decodedPixelBytes += entry.decodedPixelBytes
        encodedBytes += entry.encodedByteCount
      }
      return ImageBlendCompositorCacheSnapshot(
        entryCount: entries.count,
        decodedPixelBytes: decodedPixelBytes,
        encodedBytes: encodedBytes,
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
        || snapshot.encodedBytes > policy.maxEncodedBytes
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
      reference: reference,
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
    let presentationAttachment = blendedPresentationAttachment(
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
      attachment: presentationAttachment
    )

    storage.withLockUnchecked { storage in
      storage.storeDecodedVariant(variant, for: key, policy: cachePolicy)
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
      reference: reference,
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
    let presentationAttachment = blendedPresentationAttachment(
      from: attachment,
      outputSize: outputSize
    )
    storage.withLockUnchecked { storage in
      storage.storeEncodedPayload(
        payload,
        attachment: presentationAttachment,
        for: key,
        policy: cachePolicy
      )
    }
    return payload
  }

  private func blendedPresentationAttachment(
    from attachment: RasterImageAttachment,
    outputSize: PixelSize
  ) -> RasterImageAttachment {
    var presentationAttachment = attachment
    presentationAttachment.bounds = attachment.visibleBounds
    presentationAttachment.visibleBounds = attachment.visibleBounds
    presentationAttachment.pixelSize = outputSize
    return presentationAttachment
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
      let backdropCellY = proportionalPixelSample(
        destinationIndex: y,
        destinationCount: outputSize.height,
        sourceCount: visibleBounds.size.height
      )

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
        let backdropCellX = proportionalPixelSample(
          destinationIndex: x,
          destinationCount: outputSize.width,
          sourceCount: visibleBounds.size.width
        )

        let source = color(
          from: sourceImage.pixels[(sourceY * sourceImage.pixelSize.width) + sourceX]
        )
        let destination = backdropColor(
          compositing.destinationBackdrop,
          relativeX: backdropCellX,
          relativeY: backdropCellY,
          fallbackBackground: fallbackBackground
        )
        if let sourceBackdrop = compositing.sourceBackdrop {
          let groupBackdrop = backdropColor(
            sourceBackdrop,
            relativeX: backdropCellX,
            relativeY: backdropCellY,
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

  private func backdropColor(
    _ backdrop: RasterImageBackdrop,
    relativeX: Int,
    relativeY: Int,
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
    return backdrop.cells[index].backgroundColor ?? fallbackBackground
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
  var reference: ImageAssetReference
  var bounds: CellRect
  var visibleBounds: CellRect
  var outputSize: PixelSize
  var scalingMode: ImageScalingMode
  var blendMode: BlendMode
  var cellPixelSize: PixelSize
  var backdropSignature: UInt64
  var fallbackBackground: Color
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
  hasher.combine(key.reference)
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
  private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

  mutating func combine(
    _ reference: ImageAssetReference
  ) {
    switch reference {
    case .namedResource(let name):
      combine("named")
      combine(name)
    case .filePath(let path):
      combine("file")
      combine(path)
    case .embeddedImage(let bytes):
      combine("embedded")
      combine(bytes.count)
      for byte in bytes {
        combine(byte)
      }
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

  private mutating func combine(
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
