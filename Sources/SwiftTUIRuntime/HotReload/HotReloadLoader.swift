#if DEBUG && (os(macOS) || os(Linux))
  import SwiftTUICore
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  package struct HotReloadLoadError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
  }

  /// Same-user development images only. No loaded image is ever unloaded: Swift
  /// metadata and runtime caches can outlive every visible root instance.
  @MainActor
  package final class HotReloadLoader {
    package let spoolPath: String
    private let directory: Int32
    private let toolchain: UInt64
    private var imageCount = 0
    private var pendingSequence: UInt64 = 0
    private var lastSequence: UInt64 = 0
    private var expectedGeneration: UInt64?
    private var announcedReady = false
    package var loadedImageCount: Int { imageCount }
    package let replayTypeAliases: [String: String]

    package init(spoolPath: String, expectedToolchain: UInt64? = nil, logicalModule: String? = nil) throws {
      if let logicalModule {
        replayTypeAliases = Dictionary(uniqueKeysWithValues: (1...HotReloadABI.maximumImages).map {
          ("\(logicalModule)_SwiftTUIReload_\($0)", logicalModule)
        })
      } else {
        replayTypeAliases = [:]
      }
      guard spoolPath.hasPrefix("/"), !spoolPath.utf8.contains(0) else {
        throw HotReloadLoadError("Reload spool must be an absolute path")
      }
      let fd = unsafe spoolPath.withCString { unsafe open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
      guard fd >= 0 else { throw HotReloadLoadError("Cannot open reload spool") }
      var info = stat()
      guard unsafe fstat(fd, &info) == 0, info.st_uid == getuid(),
        info.st_mode & 0o777 == 0o700
      else {
        _ = close(fd)
        throw HotReloadLoadError("Reload spool must be owned by this user with mode 0700")
      }
      self.spoolPath = spoolPath
      directory = fd
      if let expectedToolchain {
        toolchain = expectedToolchain
      } else {
        do {
          guard let process = unsafe dlopen(nil, RTLD_NOW),
            try unsafe Self.scalar("swifttui_hot_reload_abi", in: process) == HotReloadABI.version
          else {
            throw HotReloadLoadError("Host was not built with the matching swifttui-dev contract")
          }
          toolchain = try unsafe Self.scalar("swifttui_hot_reload_toolchain", in: process)
        } catch {
          _ = close(fd)
          throw error
        }
      }
    }

    deinit { _ = close(directory) }

    /// Consumes the atomically published manifest, then validates the image's
    /// scalar entries before calling its Swift-object-producing root export.
    package func loadPending() throws -> HotReloadGeneration? {
      var info = stat()
      guard unsafe fstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
        throw HotReloadLoadError("Reload spool permissions changed; restart swifttui-dev")
      }
      let manifest = unsafe "pending".withCString {
        unsafe openat(directory, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
      }
      if manifest < 0, errno == ENOENT { return nil }
      guard manifest >= 0 else { throw HotReloadLoadError("Cannot open pending reload manifest") }
      defer {
        _ = close(manifest)
        _ = unsafe "pending".withCString { unsafe unlinkat(directory, $0, 0) }
      }
      let text = try readSmallFile(manifest, maximumBytes: 4096)
      let fields = text.split(separator: "\n", omittingEmptySubsequences: false)
      guard fields.count == 4, fields[0] == "SwiftTUIReload1", fields[3].isEmpty,
        let sequence = UInt64(fields[1]), sequence > lastSequence,
        fields[2] == Substring(Self.imageName(sequence))
      else { throw HotReloadLoadError("Invalid or stale reload manifest") }
      pendingSequence = sequence
      lastSequence = sequence
      let name = String(fields[2])
      defer { _ = unsafe name.withCString { unsafe unlinkat(directory, $0, 0) } }
      guard imageCount < HotReloadABI.maximumImages else {
        throw HotReloadLoadError("100 image limit reached; restart swifttui-dev")
      }
      let imageFD = unsafe name.withCString {
        unsafe openat(directory, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
      }
      guard imageFD >= 0 else { throw HotReloadLoadError("Cannot open reload image") }
      defer { _ = close(imageFD) }
      try validateFile(imageFD, maximumBytes: 256 * 1024 * 1024)
      #if os(macOS)
        let flags = RTLD_NOW | RTLD_LOCAL | RTLD_FIRST
      #else
        let flags = RTLD_NOW | RTLD_LOCAL
      #endif
      guard let handle = unsafe (spoolPath + "/" + name).withCString({ unsafe dlopen($0, flags) }) else {
        let detail = unsafe dlerror().map { unsafe String(cString: $0) } ?? "unknown loader error"
        throw HotReloadLoadError("Cannot load image: \(detail)")
      }
      // The outstanding dlopen reference itself pins the image. Deliberately
      // discard its handle after use, so no teardown path can unload it.
      imageCount += 1
      guard try unsafe Self.scalar("swifttui_hot_reload_abi", in: handle) == HotReloadABI.version,
        try unsafe Self.scalar("swifttui_hot_reload_toolchain", in: handle) == toolchain
      else { throw HotReloadLoadError("ABI or toolchain mismatch; restart swifttui-dev") }
      guard let symbol = unsafe "swifttui_hot_reload_root".withCString({ unsafe dlsym(handle, $0) }) else {
        throw HotReloadLoadError("Image is missing swifttui_hot_reload_root")
      }
      let factory = unsafe unsafeBitCast(symbol, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)
      guard let payload = unsafe factory() else { throw HotReloadLoadError("Root export returned nil") }
      return unsafe Unmanaged<HotReloadGeneration>.fromOpaque(payload).takeRetainedValue()
    }

    package func installed(generation: UInt64) { expectedGeneration = generation }

    package func didCommit(session: HotReloadSession?) {
      guard let session, session.generationRoot != nil, !session.awaitingCommit else { return }
      if !announcedReady {
        announcedReady = true
        writeStatus("ready\t\(getpid())\t\(HotReloadABI.version)\t\(toolchain)")
      }
      if expectedGeneration == session.generation {
        writeStatus("committed\t\(pendingSequence)\t\(session.lastReport.count)\t\(imageCount)")
        expectedGeneration = nil
      }
    }

    package func report(_ error: any Error) {
      expectedGeneration = nil
      let detail = String(describing: error).map { $0 == "\n" || $0 == "\r" || $0 == "\t" ? " " : $0 }
      writeStatus("error\t\(pendingSequence)\t\(String(detail))")
    }

    package static func imageName(_ sequence: UInt64) -> String {
      #if os(macOS)
        "generation-\(sequence).dylib"
      #else
        "generation-\(sequence).so"
      #endif
    }

    private static func scalar(_ name: String, in handle: UnsafeMutableRawPointer) throws -> UInt64 {
      guard let symbol = unsafe name.withCString({ unsafe dlsym(handle, $0) }) else {
        throw HotReloadLoadError("Image is missing \(name)")
      }
      let read = unsafe unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)
      return read()
    }

    private func validateFile(_ fd: Int32, maximumBytes: Int) throws {
      var info = stat()
      guard unsafe fstat(fd, &info) == 0, info.st_uid == getuid(),
        info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0,
        info.st_size > 0, info.st_size <= maximumBytes
      else { throw HotReloadLoadError("Reload file must be a bounded, regular same-user file") }
    }

    private func readSmallFile(_ fd: Int32, maximumBytes: Int) throws -> String {
      try validateFile(fd, maximumBytes: maximumBytes)
      var bytes = [UInt8](repeating: 0, count: maximumBytes + 1)
      var count = 0
      while count < bytes.count {
        let amount = unsafe bytes.withUnsafeMutableBytes {
          unsafe read(fd, $0.baseAddress!.advanced(by: count), $0.count - count)
        }
        if amount < 0, errno == EINTR { continue }
        guard amount >= 0 else { throw HotReloadLoadError("Cannot read reload manifest") }
        if amount == 0 { break }
        count += amount
      }
      guard count > 0, count <= maximumBytes,
        let value = String(validating: bytes.prefix(count), as: UTF8.self)
      else { throw HotReloadLoadError("Invalid reload manifest encoding or size") }
      return value
    }

    private func writeStatus(_ value: String) {
      _ = unsafe "status.tmp".withCString { unsafe unlinkat(directory, $0, 0) }
      let fd = unsafe "status.tmp".withCString {
        unsafe openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      }
      guard fd >= 0 else { return }
      defer { _ = close(fd) }
      var bytes = Array((value + "\n").utf8)
      var count = 0
      while count < bytes.count {
        let amount = unsafe bytes.withUnsafeMutableBytes {
          unsafe write(fd, $0.baseAddress!.advanced(by: count), $0.count - count)
        }
        if amount < 0, errno == EINTR { continue }
        guard amount > 0 else { return }
        count += amount
      }
      _ = unsafe "status.tmp".withCString { old in
        unsafe "status".withCString { unsafe renameat(directory, old, directory, $0) }
      }
    }
  }
#endif
