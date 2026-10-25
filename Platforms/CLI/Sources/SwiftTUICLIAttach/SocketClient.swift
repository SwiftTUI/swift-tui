#if !canImport(WASILibc) && !os(Windows)
  import SwiftTUIPlatformIO

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  // MARK: - SocketClientError

  package enum SocketClientError: Error, Sendable {
    case noRunningInstances
    case instanceNotFound(String)
    case unexpectedResponse(String)
    case connectionFailed(Int32)
    case sendFailed(Int32)
    case sendTimedOut
    case readFailed(Int32)
    case readTimedOut
  }

  // MARK: - InstanceInfo

  /// Describes a running SwiftTUI CLI app instance discovered via socket files.
  package struct InstanceInfo: Sendable {
    package let identifier: String
    package let socketPath: String
    package let pid: Int?
    package let name: String?
  }

  // MARK: - SocketClient

  package enum SocketClient {
    private struct DiscoveredInstance {
      let info: InstanceInfo
      let sortKey: InstanceSortKey
    }

    private struct InstanceSortKey: Comparable {
      let seconds: Int64
      let nanoseconds: Int64
      let identifier: String

      static func < (lhs: InstanceSortKey, rhs: InstanceSortKey) -> Bool {
        if lhs.seconds != rhs.seconds {
          return lhs.seconds < rhs.seconds
        }
        if lhs.nanoseconds != rhs.nanoseconds {
          return lhs.nanoseconds < rhs.nanoseconds
        }
        return lhs.identifier < rhs.identifier
      }
    }

    /// Scans the socket directory for live instances, removes stale sockets.
    package static func discoverInstances(appName: String) -> [InstanceInfo] {
      let dir = "/tmp/swifttui/\(appName)"
      guard let dp = unsafe sceneOpenDirectory(dir) else { return [] }
      defer { unsafe sceneCloseDirectory(dp) }

      var instances: [DiscoveredInstance] = []
      while let entry = unsafe sceneReadDirectory(dp) {
        let entryName = unsafe withUnsafePointer(to: entry.pointee.d_name) { ptr in
          unsafe String(
            cString: unsafe UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
          )
        }
        guard entryName.hasSuffix(".sock") else { continue }
        let identifier = String(entryName.dropLast(5))  // strip ".sock"
        let socketPath = "\(dir)/\(entryName)"

        // Check liveness by attempting a quick connection
        if isSocketLive(socketPath) {
          let pid = Int32(identifier)
          let instanceName: String? = pid == nil ? identifier : nil
          instances.append(
            DiscoveredInstance(
              info: InstanceInfo(
                identifier: identifier,
                socketPath: socketPath,
                pid: pid.map(Int.init),
                name: instanceName
              ),
              sortKey: sortKey(for: socketPath, identifier: identifier)
            )
          )
        } else if isSocketEntry(socketPath) {
          // Remove stale socket; any other entry with the suffix is not ours.
          _ = sceneUnlink(socketPath)
        }
      }
      return
        instances
        .sorted { $0.sortKey < $1.sortKey }
        .map(\.info)
    }

    /// Connects to a socket, sends a request line, reads the response.
    package static func sendRequest(
      socketPath: String,
      request: String,
      timeoutMilliseconds: Int32 = 500
    ) throws(SocketClientError) -> String {
      let fd = sceneSocket()
      guard fd >= 0 else { throw .connectionFailed(errno) }
      defer { sceneClose(fd) }

      guard var addr = sceneSocketAddress(for: socketPath) else {
        throw .connectionFailed(ENAMETOOLONG)
      }

      let bytes = Array(request.utf8)
      guard bytes.count <= SocketLineFraming.requestLimit else { throw .sendFailed(EMSGSIZE) }
      let flags = fcntl(fd, F_GETFL)
      guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
        throw .connectionFailed(errno)
      }
      let deadline = ContinuousClock.now.advanced(by: .milliseconds(max(0, timeoutMilliseconds)))
      if sceneConnect(fd, &addr) != 0 {
        guard errno == EINPROGRESS else { throw .connectionFailed(errno) }
        guard waitFor(fd: fd, events: Int16(POLLOUT), until: deadline) > 0 else {
          throw .connectionFailed(ETIMEDOUT)
        }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard unsafe getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
          throw .connectionFailed(errno)
        }
        guard socketError == 0 else { throw .connectionFailed(socketError) }
      }

      var offset = 0
      while offset < bytes.count {
        let ready = waitFor(fd: fd, events: Int16(POLLOUT), until: deadline)
        guard ready > 0 else {
          if ready == 0 { throw .sendTimedOut }
          throw .sendFailed(errno)
        }
        let sent = bytes.withUnsafeBytes { buffer in
          unsafe sceneWrite(fd, buffer.baseAddress?.advanced(by: offset), bytes.count - offset)
        }
        if sent < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
        guard sent > 0 else { throw .sendFailed(errno) }
        offset += sent
      }

      var received: [UInt8] = []
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let ready = waitFor(fd: fd, events: Int16(POLLIN), until: deadline)
        guard ready > 0 else {
          if ready == 0 { throw .readTimedOut }
          throw .readFailed(errno)
        }
        let bytesRead = unsafe sceneRead(fd, &buffer, buffer.count)
        if bytesRead < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
        guard bytesRead >= 0 else { throw .readFailed(errno) }
        guard bytesRead > 0 else {
          throw .unexpectedResponse(String(decoding: received, as: UTF8.self))
        }
        let chunk = buffer.prefix(bytesRead)
        let lineBytes = chunk.firstIndex(of: 10).map { chunk[...$0] } ?? chunk
        guard received.count + lineBytes.count <= SocketLineFraming.responseLimit else {
          throw .unexpectedResponse("Response exceeds limit")
        }
        received.append(contentsOf: lineBytes)
        if received.last == 10 {
          guard let line = String(validating: received, as: UTF8.self) else {
            throw .unexpectedResponse("Response is not UTF-8")
          }
          return line
        }
      }
    }

    /// A single deadline covers connection, every write, and every read; a
    /// slow peer cannot restart the timeout by delivering another byte.
    private static func waitFor(
      fd: Int32, events: Int16, until deadline: ContinuousClock.Instant
    ) -> Int32 {
      while true {
        let now = ContinuousClock.now
        guard now < deadline else { return 0 }
        let remaining = now.duration(to: deadline).components
        let milliseconds = Int32(
          min(
            Int64(Int32.max),
            remaining.seconds * 1000 + remaining.attoseconds / 1_000_000_000_000_000 + 1))
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let result = unsafe poll(&descriptor, 1, milliseconds)
        if result < 0 && errno == EINTR { continue }
        return result
      }
    }

    // MARK: - Private helpers

    private static func isSocketLive(_ path: String) -> Bool {
      let fd = sceneSocket()
      guard fd >= 0 else { return false }
      defer { sceneClose(fd) }

      guard var addr = sceneSocketAddress(for: path) else { return false }

      let result = sceneConnect(fd, &addr)
      return result == 0
    }

    /// Whether the directory entry itself is a socket; `lstat(2)` does not
    /// follow a symbolic link, so a link named `*.sock` is never removed.
    private static func isSocketEntry(_ path: String) -> Bool {
      var fileStatus = stat()
      let result = path.withCString { cPath in
        unsafe lstat(cPath, &fileStatus)
      }
      return result == 0 && fileStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK)
    }

    private static func sortKey(for path: String, identifier: String) -> InstanceSortKey {
      var fileStatus = stat()
      let result = path.withCString { cPath in
        unsafe lstat(cPath, &fileStatus)
      }
      guard result == 0 else {
        return InstanceSortKey(seconds: 0, nanoseconds: 0, identifier: identifier)
      }

      #if canImport(Darwin)
        return InstanceSortKey(
          seconds: Int64(fileStatus.st_mtimespec.tv_sec),
          nanoseconds: Int64(fileStatus.st_mtimespec.tv_nsec),
          identifier: identifier
        )
      #else
        return InstanceSortKey(
          seconds: Int64(fileStatus.st_mtim.tv_sec),
          nanoseconds: Int64(fileStatus.st_mtim.tv_nsec),
          identifier: identifier
        )
      #endif
    }
  }
#endif
