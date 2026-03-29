// MARK: - SceneInfo

/// Describes a scene that can be attached to.
struct SceneInfo: Sendable {
  let id: String
  let title: String?
  let ptyPath: String?
  let isAttached: Bool
}

#if !canImport(WASILibc)
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  // MARK: - Codable conformance (stdlib Encodable/Decodable — no Foundation import needed)

  extension SceneInfo: Codable {
    enum CodingKeys: String, CodingKey {
      case id
      case title
      case ptyPath
      case isAttached
    }
  }

  // MARK: - Manual JSON encoding (no Foundation)

  extension SceneInfo {
    /// Produces a compact JSON object string — no Foundation required.
    func jsonString() -> String {
      var fields: [String] = []
      fields.append("\"id\":\(jsonStringLiteral(id))")
      if let title {
        fields.append("\"title\":\(jsonStringLiteral(title))")
      } else {
        fields.append("\"title\":null")
      }
      if let ptyPath {
        fields.append("\"ptyPath\":\(jsonStringLiteral(ptyPath))")
      } else {
        fields.append("\"ptyPath\":null")
      }
      fields.append("\"isAttached\":\(isAttached ? "true" : "false")")
      return "{\(fields.joined(separator: ","))}"
    }

    private func jsonStringLiteral(_ s: String) -> String {
      var out = "\""
      for ch in s.unicodeScalars {
        switch ch.value {
        case 0x22: out += "\\\""  // "
        case 0x5C: out += "\\\\"  // \
        case 0x08: out += "\\b"
        case 0x0C: out += "\\f"
        case 0x0A: out += "\\n"
        case 0x0D: out += "\\r"
        case 0x09: out += "\\t"
        default: out.unicodeScalars.append(ch)
        }
      }
      out += "\""
      return out
    }
  }

  // MARK: - SocketProtocolError

  enum SocketProtocolError: Error, Sendable {
    case unknownCommand(String)
    case missingSceneID
    case encodingFailed(String)
  }

  // MARK: - SocketRequest

  enum SocketRequest: Equatable, Sendable {
    case list
    case attach(sceneID: String)

    static func parse(_ raw: String) throws(SocketProtocolError) -> SocketRequest {
      let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
      if line == "LIST" {
        return .list
      }
      if line.hasPrefix("ATTACH ") {
        let sceneID = String(line.dropFirst("ATTACH ".count))
        if sceneID.isEmpty { throw .missingSceneID }
        return .attach(sceneID: sceneID)
      }
      let command =
        line.split(separator: " " as Character, maxSplits: 1).first.map(String.init) ?? line
      throw .unknownCommand(command)
    }
  }

  // MARK: - SocketResponse

  enum SocketResponse: Sendable {
    case sceneList([SceneInfo])
    case attachOK(ptyPath: String)
    case error(String)

    func encode() throws(SocketProtocolError) -> String {
      switch self {
      case .sceneList(let scenes):
        let items = scenes.map { $0.jsonString() }.joined(separator: ",")
        let json = "[\(items)]"
        return "OK \(json)\n"
      case .attachOK(let ptyPath):
        return "OK \(ptyPath)\n"
      case .error(let message):
        return "ERR \(message)\n"
      }
    }
  }

  enum SceneDiscoveryServerError: Error, CustomStringConvertible, Sendable {
    case failedToCreateSocket(errno: Int32)
    case identifierAlreadyInUse(path: String)
    case failedToBind(path: String, errno: Int32)
    case failedToListen(errno: Int32)

    var description: String {
      switch self {
      case .failedToCreateSocket(let errno):
        "Failed to create discovery socket: \(String(cString: strerror(errno)))"
      case .identifierAlreadyInUse(let path):
        "A running instance is already using discovery socket \(path)."
      case .failedToBind(let path, let errno):
        "Failed to bind discovery socket \(path): \(String(cString: strerror(errno)))"
      case .failedToListen(let errno):
        "Failed to listen on discovery socket: \(String(cString: strerror(errno)))"
      }
    }
  }

  // MARK: - SceneDiscoveryServer

  /// Unix domain socket server that advertises scenes for attachment.
  ///
  /// The server listens at `/tmp/terminalui/<appName>/<identifier>.sock`.
  /// Clients send `LIST\n` or `ATTACH <sceneID>\n`.
  final class SceneDiscoveryServer: Sendable {
    let socketPath: String

    private let sceneProvider: @Sendable () -> [SceneInfo]
    private let attachHandler: @Sendable (String) -> SocketResponse

    init(
      appName: String,
      identifier: String,
      sceneProvider: @escaping @Sendable () -> [SceneInfo],
      attachHandler: @escaping @Sendable (String) -> SocketResponse
    ) {
      let dir = "/tmp/terminalui/\(appName)"
      self.socketPath = "\(dir)/\(identifier).sock"
      self.sceneProvider = sceneProvider
      self.attachHandler = attachHandler
    }

    /// Starts the server: creates the socket directory, binds, listens, and accepts in a loop.
    /// Returns when cancelled or throws on unrecoverable startup error.
    func run() async throws {
      // Create directory structure recursively (pure stdlib — no Foundation)
      let parts = socketPath.split(separator: "/" as Character, omittingEmptySubsequences: true)
      let dirParts = parts.dropLast()
      mkdirRecursive(components: Array(dirParts).map(String.init))

      if pathExists(socketPath) {
        if isSocketLive(socketPath) {
          throw SceneDiscoveryServerError.identifierAlreadyInUse(path: socketPath)
        }
        _ = Darwin.unlink(socketPath)
      }

      let serverFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard serverFD >= 0 else {
        throw SceneDiscoveryServerError.failedToCreateSocket(errno: errno)
      }

      var shouldCleanupSocketPath = false
      defer {
        Darwin.close(serverFD)
        if shouldCleanupSocketPath {
          _ = Darwin.unlink(socketPath)
        }
      }

      // Bind
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

      let bindResult = withUnsafePointer(to: &addr) {
        Darwin.bind(
          serverFD,
          UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self),
          socklen_t(MemoryLayout<sockaddr_un>.size))
      }
      guard bindResult == 0 else {
        if errno == EADDRINUSE {
          throw SceneDiscoveryServerError.identifierAlreadyInUse(path: socketPath)
        }
        throw SceneDiscoveryServerError.failedToBind(path: socketPath, errno: errno)
      }
      shouldCleanupSocketPath = true

      guard Darwin.listen(serverFD, 5) == 0 else {
        throw SceneDiscoveryServerError.failedToListen(errno: errno)
      }

      // Set server socket to non-blocking so accept() doesn't block the cooperative thread pool.
      let flags = fcntl(serverFD, F_GETFL)
      _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

      // Accept loop — poll with a timeout so we check for cancellation periodically.
      while !Task.isCancelled {
        var pfd = pollfd(fd: serverFD, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, 200)  // 200 ms timeout
        guard ready > 0 else {
          await Task.yield()
          continue
        }

        let clientFD = Darwin.accept(serverFD, nil, nil)
        guard clientFD >= 0 else {
          if errno == EAGAIN || errno == EWOULDBLOCK { continue }
          break
        }
        let provider = sceneProvider
        let handler = attachHandler
        Task.detached {
          await SceneDiscoveryServer.handleClient(
            fd: clientFD, sceneProvider: provider, attachHandler: handler)
        }
      }
    }

    /// Creates each directory component in `components` (absolute path, leading "/" implied).
    private func mkdirRecursive(components: [String]) {
      var current = ""
      for component in components {
        current += "/\(component)"
        _ = mkdir(current, 0o755)
      }
    }

    private func pathExists(_ path: String) -> Bool {
      path.withCString { Darwin.access($0, F_OK) == 0 }
    }

    private func isSocketLive(_ path: String) -> Bool {
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

    @Sendable
    private static func handleClient(
      fd: Int32,
      sceneProvider: @escaping @Sendable () -> [SceneInfo],
      attachHandler: @escaping @Sendable (String) -> SocketResponse
    ) async {
      defer { Darwin.close(fd) }

      var buffer = [UInt8](repeating: 0, count: 4096)
      let bytesRead = Darwin.read(fd, &buffer, buffer.count)
      guard bytesRead > 0 else { return }
      let raw = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)

      let response: SocketResponse
      do {
        let request = try SocketRequest.parse(raw)
        switch request {
        case .list:
          response = .sceneList(sceneProvider())
        case .attach(let sceneID):
          response = attachHandler(sceneID)
        }
      } catch {
        response = .error(String(describing: error))
      }

      let encoded: String
      do {
        encoded = try response.encode()
      } catch {
        encoded = "ERR \(error)\n"
      }

      encoded.withCString { cstr in
        _ = Darwin.write(fd, cstr, strlen(cstr))
      }
    }
  }
#endif
