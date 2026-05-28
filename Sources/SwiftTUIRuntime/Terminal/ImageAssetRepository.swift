import SwiftTUICore

#if canImport(PNG)
  import PNG
#endif

#if canImport(JPEG)
  import JPEG
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

private struct ImageLookupKey: Sendable {
  var source: ImageSource
  var resourceRoots: [String]
  var cellPixelSize: PixelSize
}

extension ImageLookupKey: Hashable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.source == rhs.source
      && lhs.resourceRoots == rhs.resourceRoots
      && lhs.cellPixelSize.width == rhs.cellPixelSize.width
      && lhs.cellPixelSize.height == rhs.cellPixelSize.height
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(source)
    hasher.combine(resourceRoots)
    hasher.combine(cellPixelSize.width)
    hasher.combine(cellPixelSize.height)
  }
}

#if canImport(PNG)
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

#if canImport(JPEG)
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
  private struct Storage {
    var resolutions: [ImageLookupKey: ResolvedImageAsset] = [:]
    var decodedImages: [ImageAssetReference: DecodedImage] = [:]
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

    if let cached = storage.withLockUnchecked({ $0.resolutions[lookupKey] }) {
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
      storage.resolutions[lookupKey] = resolved
    }
    return resolved
  }

  func decodedImage(
    for reference: ImageAssetReference
  ) -> DecodedImage? {
    if let cached = storage.withLockUnchecked({ $0.decodedImages[reference] }) {
      return cached
    }

    guard let decoded = loadDecodedImage(for: reference) else {
      return nil
    }

    storage.withLockUnchecked { storage in
      storage.decodedImages[reference] = decoded
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
      #if canImport(JPEG)
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
      #if canImport(PNG)
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
      let approxBytes = storage.decodedImages.values.reduce(0) { total, image in
        total + image.encodedBytes.count
          + image.pixels.count * MemoryLayout<RGBAImagePixel>.stride
      }
      return (storage.resolutions.count, storage.decodedImages.count, approxBytes)
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
