import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Immutable encoded content owned independently of any image placement.
/// IDs are unique for this owner lifetime and cannot alias a retired owner.
@_spi(Runners) public final class ImageContent: Sendable {
  @_spi(Runners) public let id: String
  @_spi(Runners) public let bytes: [UInt8]
  @_spi(Runners) public let format: String
  /// The existing deterministic wire identifier, computed once at admission.
  @_spi(Runners) public let wireID: String
  package let kittyDigest: UInt32
  package let blendPrimaryDigest: UInt64
  package let blendSecondaryDigest: UInt64

  private static let nextID = Mutex<UInt64>(0)

  fileprivate init(bytes: [UInt8]) {
    self.bytes = bytes
    id = Self.nextID.withLock { next in
      precondition(next < UInt64.max, "Image content identity exhausted")
      next += 1
      return "image-content:\(next)"
    }
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
      format = "jpeg"
    } else if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
      format = "gif"
    } else {
      format = "png"
    }
    func addingCount(to seed: UInt64) -> UInt64 {
      var hash = seed
      var count = UInt64(bytes.count)
      for _ in 0..<8 {
        hash = (hash ^ (count & 255)) &* 0x100_0000_01b3
        count >>= 8
      }
      return hash
    }
    var wire: UInt64 = 0xcbf2_9ce4_8422_2325
    var kitty: UInt32 = 2_166_136_261
    for byte in "embedded:".utf8 { kitty = (kitty ^ UInt32(byte)) &* 16_777_619 }
    var primary = addingCount(to: wire)
    var secondary = addingCount(to: 0x8422_2325_cbf2_9ce4)
    for byte in bytes {
      kitty = (kitty ^ UInt32(byte)) &* 16_777_619
      wire = (wire ^ UInt64(byte)) &* 0x100_0000_01b3
      primary = (primary ^ UInt64(byte)) &* 0x100_0000_01b3
      secondary = (secondary ^ UInt64(byte)) &* 0x100_0000_01b3
    }
    let hex = String(wire, radix: 16)
    wireID = "\(format):\(String(repeating: "0", count: 16 - hex.count))\(hex):\(bytes.count)"
    kittyDigest = kitty
    blendPrimaryDigest = primary
    blendSecondaryDigest = secondary
  }
}

/// A bounded source owner shared by resolution, wire encoding and native hosts.
/// Unchanged sources reuse immutable bytes and identity while admitted. Eviction
/// retires that ownership; acquiring the source again creates a fresh identity.
@_spi(Runners) public final class ImageContentRepository: Sendable {
  @_spi(Runners) public static let shared = ImageContentRepository()

  private struct ByteKey: Hashable, Sendable {
    var bytes: [UInt8]
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
    func hash(into hasher: inout Hasher) {
      hasher.combine(bytes.count)
      // A hash collision always falls through to byte-exact equality. Lookup
      // never hashes the full buffer, including for forced interior collisions.
      for byte in bytes.prefix(64) { hasher.combine(byte) }
      if bytes.count > 64 {
        for byte in bytes.suffix(64) { hasher.combine(byte) }
      }
    }
  }

  private enum Key: Hashable, Sendable {
    case bytes(ByteKey)
    case file(String, ImageFileRevision)
  }

  private struct Cost: BoundedLRUCost {
    var entries: Int
    var bytes: Int
    static let zero = Self(entries: 0, bytes: 0)
    static func + (lhs: Self, rhs: Self) -> Self {
      Self(entries: lhs.entries + rhs.entries, bytes: lhs.bytes + rhs.bytes)
    }
    static func - (lhs: Self, rhs: Self) -> Self {
      Self(entries: lhs.entries - rhs.entries, bytes: lhs.bytes - rhs.bytes)
    }
    func violates(_ policy: Self) -> Bool { entries > policy.entries || bytes > policy.bytes }
  }

  private struct Storage {
    var cache = BoundedLRUCache<Key, ImageContent, Cost>()
    var hits = 0
    var misses = 0
    var fileReads = 0
    var fileBytesRead = 0
    var contentBytesHashed = 0
  }
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())
  private let policy: Cost
  private let memoryMetricToken: MemoryMetricRegistry.Token

  @_spi(Runners) public init(maxEntries: Int = 256, maxBytes: Int = 128 * 1024 * 1024) {
    policy = Cost(entries: max(0, maxEntries), bytes: max(0, maxBytes))
    let storage = storage
    memoryMetricToken = MemoryMetricRegistry.shared.register(
      ClosureMemoryMetricProvider {
        storage.withLockUnchecked { state in
          MemoryMetricSnapshot(
            name: "ImageContentRepository.sources", count: state.cache.count,
            approxBytes: state.cache.totalCost.bytes,
            detail: [
              "hits": state.hits, "misses": state.misses, "fileReads": state.fileReads,
              "fileBytesRead": state.fileBytesRead, "contentBytesHashed": state.contentBytesHashed,
            ])
        }
      })
  }

  @_spi(Runners) public func content(for attachment: RasterImageAttachment) -> ImageContent? {
    if let reference = attachment.resolvedReference {
      switch reference {
      case .filePath, .embeddedImage: return content(for: reference)
      case .namedResource: break
      }
    }
    switch attachment.source {
    case .data(let bytes): return content(for: .embeddedImage(bytes))
    case .path(let path): return content(for: .filePath(path))
    case .fileURL(let url): return parseFileURL(url).flatMap { content(for: .filePath($0)) }
    }
  }

  @_spi(Runners) public func content(for reference: ImageAssetReference) -> ImageContent? {
    switch reference {
    case .namedResource: return nil
    case .embeddedImage(let bytes):
      let key = Key.bytes(ByteKey(bytes: bytes))
      if let cached = lookup(key) { return cached }
      return admit(bytes, for: key, keyBytes: bytes.count)
    case .filePath(let path):
      // Platforms without a reliable high-resolution revision use byte-exact
      // lookup after reading. They preserve correctness without claiming the
      // unchanged-file read elimination provided by POSIX revision keys.
      #if os(Windows) || canImport(WASILibc)
        guard let bytes = read(path) else { return nil }
        return content(for: .embeddedImage(bytes))
      #else
        for _ in 0..<2 {
          guard let revision = ImageFileRevision.read(path) else { return nil }
          let key = Key.file(path, revision)
          if let cached = lookup(key) { return cached }
          guard let bytes = read(path) else { return nil }
          guard ImageFileRevision.read(path) == revision else { continue }
          return admit(bytes, for: key, keyBytes: path.utf8.count)
        }
        return nil  // a concurrently replaced source has no stable snapshot yet
      #endif
    }
  }

  @_spi(Runners) public func removeAll() {
    storage.withLockUnchecked { $0.cache.removeAll() }
  }

  package var snapshot:
    (
      entries: Int, bytes: Int, hits: Int, misses: Int, fileReads: Int, fileBytesRead: Int,
      contentBytesHashed: Int
    )
  {
    storage.withLockUnchecked {
      (
        $0.cache.count, $0.cache.totalCost.bytes, $0.hits, $0.misses, $0.fileReads,
        $0.fileBytesRead, $0.contentBytesHashed
      )
    }
  }

  private func lookup(_ key: Key) -> ImageContent? {
    storage.withLockUnchecked {
      if let content = $0.cache.recordAccess(key) {
        $0.hits += 1
        return content
      }
      $0.misses += 1
      return nil
    }
  }

  private func read(_ path: String) -> [UInt8]? {
    guard let bytes = imageContentReadFileBytes(at: path) else { return nil }
    storage.withLockUnchecked {
      $0.fileReads += 1
      $0.fileBytesRead += bytes.count
    }
    return bytes
  }

  private func admit(_ bytes: [UInt8], for key: Key, keyBytes: Int) -> ImageContent {
    let content = ImageContent(bytes: bytes)
    return storage.withLockUnchecked { storage in
      storage.contentBytesHashed += bytes.count
      if let cached = storage.cache.recordAccess(key) { return cached }
      let (retained, overflow) = bytes.count.addingReportingOverflow(keyBytes)
      let (estimated, metadataOverflow) = retained.addingReportingOverflow(256)
      guard !overflow, !metadataOverflow else { return content }
      let cost = Cost(entries: 1, bytes: estimated)
      if !cost.violates(policy) {
        storage.cache.upsert(key, value: content, cost: cost, policy: policy)
      }
      return content
    }
  }
}

private struct ImageFileRevision: Hashable, Sendable {
  var device: UInt64
  var inode: UInt64
  var size: Int64
  var modifiedSeconds: Int64
  var modifiedNanoseconds: Int64
  var changedSeconds: Int64
  var changedNanoseconds: Int64

  #if !os(Windows) && !canImport(WASILibc)
    static func read(_ path: String) -> Self? {
      var info = stat()
      let result = path.withCString { unsafe stat($0, &info) }
      guard result == 0 else { return nil }
      #if canImport(Darwin)
        let modified = info.st_mtimespec
        let changed = info.st_ctimespec
      #else
        let modified = info.st_mtim
        let changed = info.st_ctim
      #endif
      return Self(
        device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino),
        size: Int64(info.st_size),
        modifiedSeconds: Int64(modified.tv_sec), modifiedNanoseconds: Int64(modified.tv_nsec),
        changedSeconds: Int64(changed.tv_sec), changedNanoseconds: Int64(changed.tv_nsec))
    }
  #endif
}
