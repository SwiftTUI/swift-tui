#if !canImport(WASILibc)
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  // MARK: - SocketClientError

  enum SocketClientError: Error, Sendable {
    case noRunningInstances
    case instanceNotFound(String)
    case unexpectedResponse(String)
    case connectionFailed(Int32)
    case sendFailed(Int32)
    case readFailed(Int32)
  }

  // MARK: - InstanceInfo

  /// Describes a running TerminalUIScenes app instance discovered via socket files.
  struct InstanceInfo: Sendable {
    let identifier: String
    let socketPath: String
    let pid: Int?
    let name: String?
  }

  // MARK: - SocketClient

  enum SocketClient {
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
    static func discoverInstances(appName: String) -> [InstanceInfo] {
      let dir = "/tmp/terminalui/\(appName)"
      guard let dp = Darwin.opendir(dir) else { return [] }
      defer { Darwin.closedir(dp) }

      var instances: [DiscoveredInstance] = []
      while let entry = Darwin.readdir(dp) {
        let entryName = withUnsafePointer(to: entry.pointee.d_name) { ptr in
          String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
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
        } else {
          // Remove stale socket
          _ = Darwin.unlink(socketPath)
        }
      }
      return
        instances
        .sorted { $0.sortKey < $1.sortKey }
        .map(\.info)
    }

    /// Selects a specific instance by selector strategy.
    static func selectInstance(appName: String, selector: InstanceSelector)
      throws(SocketClientError)
      -> InstanceInfo
    {
      let instances = discoverInstances(appName: appName)
      guard !instances.isEmpty else { throw .noRunningInstances }

      switch selector {
      case .mostRecent:
        guard let instance = instances.last else { throw .noRunningInstances }
        return instance
      case .pid(let pid):
        let pidString = String(pid)
        guard let instance = instances.first(where: { $0.identifier == pidString }) else {
          throw .instanceNotFound("pid:\(pid)")
        }
        return instance
      case .name(let name):
        guard let instance = instances.first(where: { $0.identifier == name || $0.name == name })
        else {
          throw .instanceNotFound(name)
        }
        return instance
      }
    }

    /// Connects to a socket, sends a request line, reads the response.
    static func sendRequest(socketPath: String, request: String) throws(SocketClientError) -> String
    {
      let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard fd >= 0 else { throw .connectionFailed(errno) }
      defer { Darwin.close(fd) }

      var addr = sockaddr_un()
      addr.sun_family = sa_family_t(AF_UNIX)
      let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
      withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        socketPath.withCString { cstr in
          _ = Darwin.strncpy(
            UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
            cstr,
            sunPathSize - 1
          )
        }
      }

      let connectResult = withUnsafePointer(to: &addr) {
        Darwin.connect(
          fd,
          UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self),
          socklen_t(MemoryLayout<sockaddr_un>.size))
      }
      guard connectResult == 0 else { throw .connectionFailed(errno) }

      // Send request
      let sent = request.withCString { ptr in
        Darwin.write(fd, ptr, strlen(ptr))
      }
      guard sent > 0 else { throw .sendFailed(errno) }

      // Read response (up to 64 KB)
      var buffer = [UInt8](repeating: 0, count: 65536)
      let bytesRead = Darwin.read(fd, &buffer, 65536)
      guard bytesRead > 0 else { throw .readFailed(errno) }
      return String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
    }

    // MARK: - Private helpers

    private static func isSocketLive(_ path: String) -> Bool {
      let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard fd >= 0 else { return false }
      defer { Darwin.close(fd) }

      var addr = sockaddr_un()
      addr.sun_family = sa_family_t(AF_UNIX)
      let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
      withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { cstr in
          _ = Darwin.strncpy(
            UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
            cstr,
            sunPathSize - 1
          )
        }
      }

      let result = withUnsafePointer(to: &addr) {
        Darwin.connect(
          fd,
          UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self),
          socklen_t(MemoryLayout<sockaddr_un>.size))
      }
      return result == 0
    }

    private static func sortKey(for path: String, identifier: String) -> InstanceSortKey {
      var fileStatus = stat()
      let result = path.withCString {
        lstat($0, &fileStatus)
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
      #elseif canImport(Glibc)
        return InstanceSortKey(
          seconds: Int64(fileStatus.st_mtim.tv_sec),
          nanoseconds: Int64(fileStatus.st_mtim.tv_nsec),
          identifier: identifier
        )
      #endif
    }
  }
#endif
