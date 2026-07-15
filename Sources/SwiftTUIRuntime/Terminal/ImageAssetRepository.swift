import SwiftTUICore

#if canImport(SwiftTUIVendorPNG)
  import SwiftTUIVendorPNG
#endif

#if canImport(SwiftTUIVendorJPEG)
  import SwiftTUIVendorJPEG
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#endif

// Internal (not file-private) so the sampled-hash contract below is
// directly testable: forced bucket collisions must stay separable by `==`.
struct ImageLookupKey: Sendable {
  var source: ImageSource
  var resourceRoots: [String]
  var cellPixelSize: PixelSize
}

/// Entry-count + byte cost for the repository's decode/resolution caches.
private struct ImageAssetCacheCost: BoundedLRUCost {
  var entryCount: Int
  var byteCount: Int

  static let zero = ImageAssetCacheCost(entryCount: 0, byteCount: 0)

  static func + (lhs: Self, rhs: Self) -> Self {
    Self(entryCount: lhs.entryCount + rhs.entryCount, byteCount: lhs.byteCount + rhs.byteCount)
  }

  static func - (lhs: Self, rhs: Self) -> Self {
    Self(entryCount: lhs.entryCount - rhs.entryCount, byteCount: lhs.byteCount - rhs.byteCount)
  }

  func violates(_ policy: ImageAssetCachePolicy) -> Bool {
    entryCount > policy.maxEntries || byteCount > policy.maxBytes
  }
}

private struct ImageAssetCachePolicy: Sendable {
  var maxEntries: Int
  var maxBytes: Int
}

extension ImageLookupKey: Hashable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.source == rhs.source
      && lhs.resourceRoots == rhs.resourceRoots
      && lhs.cellPixelSize.width == rhs.cellPixelSize.width
      && lhs.cellPixelSize.height == rhs.cellPixelSize.height
  }

  func hash(into hasher: inout Hasher) {
    switch source {
    case .data(let bytes):
      // Hashing the full payload on every lookup dominates animated-image
      // resolve cost (F153): the repository re-hashes the same PNG bytes per
      // tick even on cache hits. Sample the buffer instead — `==` above
      // stays byte-exact, so same-shaped payloads can only cost a bucket
      // collision, never a wrong hit. (Equal sources sample identically, so
      // the equal-implies-equal-hash contract holds.)
      hasher.combine(0x64617461)  // 'data' — keeps the case discriminated
      hasher.combine(bytes.count)
      let sampleCount = 64
      if bytes.count <= sampleCount * 2 {
        hasher.combine(bytes)
      } else {
        for offset in 0..<sampleCount {
          hasher.combine(bytes[offset])
          hasher.combine(bytes[bytes.count - 1 - offset])
        }
      }
    case .path, .fileURL:
      hasher.combine(source)
    }
    hasher.combine(resourceRoots)
    hasher.combine(cellPixelSize.width)
    hasher.combine(cellPixelSize.height)
  }
}

#if canImport(SwiftTUIVendorPNG)
  private struct InMemoryPNGSource: PNG.BytestreamSource {
    private let buffer: [UInt8]
    private var index = 0

    init(
      _ buffer: [UInt8]
    ) {
      self.buffer = buffer
    }

    mutating func read(
      count: Int
    ) -> [UInt8]? {
      guard count >= 0, index + count <= buffer.count else {
        return nil
      }
      let chunk = Array(buffer[index..<(index + count)])
      index += count
      return chunk
    }
  }
#endif

#if canImport(SwiftTUIVendorJPEG)
  private struct InMemoryJPEGSource: JPEG.BytestreamSource {
    private let buffer: [UInt8]
    private var index = 0

    init(
      _ buffer: [UInt8]
    ) {
      self.buffer = buffer
    }

    mutating func read(
      count: Int
    ) -> [UInt8]? {
      guard count >= 0, index + count <= buffer.count else {
        return nil
      }
      let chunk = Array(buffer[index..<(index + count)])
      index += count
      return chunk
    }
  }
#endif

/// Returns `true` if `bytes` begins with the JPEG SOI marker (`FF D8 FF`).
private func isJPEGBytes(_ bytes: [UInt8]) -> Bool {
  bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
}

/// Returns `true` if `bytes` begins with the PNG signature
/// (`89 50 4E 47 0D 0A 1A 0A`).
private func isPNGBytes(_ bytes: [UInt8]) -> Bool {
  bytes.count >= 8
    && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
    && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A
}

final class ImageAssetRepository: Sendable {
  // Both caches live for the process (`sharedImageAssetRepository`), so without a
  // bound a long session that views many distinct images grows them without
  // limit (and leaks across tests sharing the singleton). Cap each by entry
  // count; F52 moved them onto the shared generational-LRU ``BoundedLRUCache``
  // (recency-ordered, O(1) eviction) — the working set of on-screen images is
  // small, so a generous cap bounds memory without measurably hurting hit rate.
  private static let resolutionPolicy = ImageAssetCachePolicy(maxEntries: 512, maxBytes: .max)
  private static let decodedPolicy = ImageAssetCachePolicy(maxEntries: 256, maxBytes: .max)

  private struct Storage {
    var resolutions = BoundedLRUCache<ImageLookupKey, ResolvedImageAsset, ImageAssetCacheCost>()
    var decodedImages = BoundedLRUCache<ImageAssetReference, DecodedImage, ImageAssetCacheCost>()
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  func resolver() -> ImageAssetResolver {
    { [weak self] source, resourceRoots, cellPixelSize in
      self?.resolve(
        source,
        resourceRoots: resourceRoots,
        cellPixelSize: cellPixelSize
      )
    }
  }

  func resolve(
    _ source: ImageSource,
    resourceRoots: [String],
    cellPixelSize: PixelSize
  ) -> ResolvedImageAsset? {
    let lookupKey = ImageLookupKey(
      source: source,
      resourceRoots: resourceRoots,
      cellPixelSize: cellPixelSize
    )

    if let cached = storage.withLockUnchecked({ $0.resolutions.recordAccess(lookupKey) }) {
      return cached
    }

    guard let reference = resolvedReference(for: source, resourceRoots: resourceRoots),
      let image = decodedImage(for: reference)
    else {
      return nil
    }

    let resolved = ResolvedImageAsset(
      reference: reference,
      pixelSize: image.pixelSize,
      intrinsicCellSize: intrinsicCellSize(
        pixelSize: image.pixelSize,
        cellPixelSize: cellPixelSize
      ),
      cellPixelSize: cellPixelSize
    )

    storage.withLockUnchecked { storage in
      storage.resolutions.upsert(
        lookupKey,
        value: resolved,
        cost: ImageAssetCacheCost(entryCount: 1, byteCount: 0),
        policy: Self.resolutionPolicy
      )
    }
    return resolved
  }

  func decodedImage(
    for reference: ImageAssetReference
  ) -> DecodedImage? {
    if let cached = storage.withLockUnchecked({ $0.decodedImages.recordAccess(reference) }) {
      return cached
    }

    guard let decoded = loadDecodedImage(for: reference) else {
      return nil
    }

    let byteCount =
      decoded.encodedBytes.count
      + decoded.pixels.count * MemoryLayout<RGBAImagePixel>.stride
    storage.withLockUnchecked { storage in
      storage.decodedImages.upsert(
        reference,
        value: decoded,
        cost: ImageAssetCacheCost(entryCount: 1, byteCount: byteCount),
        policy: Self.decodedPolicy
      )
    }
    return decoded
  }

  private func resolvedReference(
    for source: ImageSource,
    resourceRoots: [String]
  ) -> ImageAssetReference? {
    switch source {
    case .path(let name):
      if name.hasPrefix("/") {
        return .filePath(name)
      }
      for root in resourceRoots {
        let candidate = joinedPath(root: root, component: name)
        if fileExists(at: candidate) {
          return .filePath(candidate)
        }
      }
      return nil
    case .fileURL(let value):
      return parseFileURL(value).map(ImageAssetReference.filePath)
    case .data(let bytes):
      return .embeddedImage(bytes)
    }
  }

  private func loadDecodedImage(
    for reference: ImageAssetReference
  ) -> DecodedImage? {
    let bytes: [UInt8]
    switch reference {
    case .namedResource:
      return nil
    case .filePath(let path):
      guard let read = readFileBytes(at: path) else {
        return nil
      }
      bytes = read
    case .embeddedImage(let read):
      // Despite the case name, this carries any supported image format.
      bytes = read
    }

    return decodeImageBytes(bytes)
  }

  /// Decodes a raster image from its bytes, dispatching by magic bytes
  /// between PNG (89 50 4E 47…) and JPEG (FF D8 FF…). Returns `nil` if
  /// the bytes are neither format, or the matching decoder fails.
  private func decodeImageBytes(_ bytes: [UInt8]) -> DecodedImage? {
    if isJPEGBytes(bytes) {
      #if canImport(SwiftTUIVendorJPEG)
        var source = InMemoryJPEGSource(bytes)
        guard let image = try? JPEG.Image.decompress(stream: &source) else {
          return nil
        }
        let pixels = image.unpack(as: JPEG.RGBA<UInt8>.self).map(RGBAImagePixel.init)
        return DecodedImage(
          encodedBytes: bytes,
          encodedFormat: .jpeg,
          pixelSize: .init(width: image.size.x, height: image.size.y),
          pixels: pixels
        )
      #else
        return nil
      #endif
    }
    if isPNGBytes(bytes) {
      #if canImport(SwiftTUIVendorPNG)
        var source = InMemoryPNGSource(bytes)
        guard let image = try? PNG.Image.decompress(stream: &source) else {
          return nil
        }
        let pixels = image.unpack(as: PNG.RGBA<UInt8>.self).map(RGBAImagePixel.init)
        return DecodedImage(
          encodedBytes: bytes,
          encodedFormat: .png,
          pixelSize: .init(width: image.size.x, height: image.size.y),
          pixels: pixels
        )
      #else
        return nil
      #endif
    }
    return nil
  }

  func occupancy() -> (resolutionCount: Int, decodedCount: Int, approxBytes: Int) {
    storage.withLockUnchecked { storage in
      (
        storage.resolutions.count,
        storage.decodedImages.count,
        storage.decodedImages.totalCost.byteCount
      )
    }
  }

  private func intrinsicCellSize(
    pixelSize: PixelSize,
    cellPixelSize: PixelSize
  ) -> CellSize {
    guard pixelSize.width > 0, pixelSize.height > 0 else {
      return .zero
    }

    let cellWidth = max(1, cellPixelSize.width)
    let cellHeight = max(1, cellPixelSize.height)

    return .init(
      width: max(1, (pixelSize.width + cellWidth - 1) / cellWidth),
      height: max(1, (pixelSize.height + cellHeight - 1) / cellHeight)
    )
  }
}

let sharedImageAssetRepository: ImageAssetRepository = {
  let repo = ImageAssetRepository()
  // Only the shared repository is counted; per-test instances never register,
  // so the occupancy signal tracks the real process-lived decode cache.
  MemoryMetricRegistry.shared.registerPermanent(
    ClosureMemoryMetricProvider { [weak repo] in
      guard let repo else {
        return MemoryMetricSnapshot(name: "ImageAssetRepository.decodedImages", count: 0)
      }
      let occupancy = repo.occupancy()
      return MemoryMetricSnapshot(
        name: "ImageAssetRepository.decodedImages",
        count: occupancy.decodedCount,
        approxBytes: occupancy.approxBytes,
        detail: ["resolutions": occupancy.resolutionCount]
      )
    }
  )
  return repo
}()

private func joinedPath(
  root: String,
  component: String
) -> String {
  guard !root.isEmpty else {
    return component
  }
  if root.hasSuffix("/") {
    return root + component
  }
  return root + "/" + component
}

private func fileExists(
  at path: String
) -> Bool {
  let fileDescriptor = openReadOnlyFile(path)
  guard fileDescriptor >= 0 else {
    return false
  }
  closeFile(fileDescriptor)
  return true
}

private func readFileBytes(
  at path: String
) -> [UInt8]? {
  let fileDescriptor = openReadOnlyFile(path)
  guard fileDescriptor >= 0 else {
    return nil
  }
  defer {
    closeFile(fileDescriptor)
  }

  var bytes: [UInt8] = []
  var buffer = Array(repeating: UInt8(0), count: 4096)

  while true {
    let bytesRead = unsafe readFileChunk(fileDescriptor, &buffer, buffer.count)
    if bytesRead > 0 {
      bytes.append(contentsOf: buffer.prefix(bytesRead))
      continue
    }

    guard bytesRead == 0 else {
      return nil
    }
    return bytes
  }
}

private func parseFileURL(
  _ rawValue: String
) -> String? {
  let prefix = "file://"
  guard rawValue.hasPrefix(prefix) else {
    return nil
  }

  let suffix = String(rawValue.dropFirst(prefix.count))
  let pathComponent: String
  if suffix.hasPrefix("localhost/") {
    pathComponent = "/" + String(suffix.dropFirst("localhost/".count))
  } else if suffix.hasPrefix("/") {
    pathComponent = suffix
  } else {
    return nil
  }

  return percentDecoded(pathComponent)
}

private func percentDecoded(
  _ rawValue: String
) -> String? {
  let scalars = Array(rawValue.unicodeScalars)
  var bytes: [UInt8] = []
  var index = 0

  while index < scalars.count {
    let scalar = scalars[index]
    if scalar == "%" {
      guard index + 2 < scalars.count,
        let high = hexNibble(scalars[index + 1]),
        let low = hexNibble(scalars[index + 2])
      else {
        return nil
      }
      bytes.append((high << 4) | low)
      index += 3
      continue
    }

    if scalar.value <= 0x7F {
      bytes.append(UInt8(scalar.value))
    } else {
      bytes.append(contentsOf: String(scalar).utf8)
    }
    index += 1
  }

  return String(decoding: bytes, as: UTF8.self)
}

private func hexNibble(
  _ scalar: UnicodeScalar
) -> UInt8? {
  switch scalar.value {
  case 48...57:
    return UInt8(scalar.value - 48)
  case 65...70:
    return UInt8(scalar.value - 55)
  case 97...102:
    return UInt8(scalar.value - 87)
  default:
    return nil
  }
}

private func openReadOnlyFile(
  _ path: String
) -> Int32 {
  unsafe path.withCString { cPath in
    #if canImport(Darwin)
      unsafe Darwin.open(cPath, O_RDONLY)
    #elseif canImport(Glibc)
      unsafe Glibc.open(cPath, O_RDONLY)
    #elseif canImport(Android)
      unsafe Android.open(cPath, O_RDONLY)
    #elseif canImport(WASILibc)
      unsafe WASILibc.open(cPath, O_RDONLY)
    #endif
  }
}

private func closeFile(
  _ fileDescriptor: Int32
) {
  #if canImport(Darwin)
    _ = Darwin.close(fileDescriptor)
  #elseif canImport(Glibc)
    _ = Glibc.close(fileDescriptor)
  #elseif canImport(Android)
    _ = Android.close(fileDescriptor)
  #elseif canImport(WASILibc)
    _ = WASILibc.close(fileDescriptor)
  #endif
}

private func readFileChunk(
  _ fileDescriptor: Int32,
  _ buffer: UnsafeMutableRawPointer?,
  _ count: Int
) -> Int {
  #if canImport(Darwin)
    unsafe Darwin.read(fileDescriptor, buffer, count)
  #elseif canImport(Glibc)
    unsafe Glibc.read(fileDescriptor, buffer, count)
  #elseif canImport(Android)
    unsafe Android.read(fileDescriptor, buffer, count)
  #elseif canImport(WASILibc)
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  #endif
}
