#if !canImport(WASILibc) && !os(Windows)
  // MARK: - SceneInfo

  /// Describes a scene that can be attached to.
  package struct SceneInfo: Sendable {
    package let id: String
    package let title: String?
    package let ptyPath: String?
    package let isAttached: Bool

    package init(id: String, title: String?, ptyPath: String?, isAttached: Bool) {
      self.id = id
      self.title = title
      self.ptyPath = ptyPath
      self.isAttached = isAttached
    }
  }

  import SwiftTUIPlatformIO
  import SwiftTUIPrimitives

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
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
      JSONStringEncoding.quoted(s)
    }
  }

  // MARK: - SocketProtocolError

  package enum SocketProtocolError: Error, Sendable {
    case unknownCommand(String)
    case missingSceneID
    case encodingFailed(String)
  }

  // MARK: - SocketRequest

  enum SocketRequest: Equatable, Sendable {
    case list
    case companion
    case attach(sceneID: String)

    static func parse(_ raw: String) throws(SocketProtocolError) -> SocketRequest {
      let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
      guard !line.unicodeScalars.contains(where: SocketLineFraming.isControl) else {
        throw .unknownCommand(raw)
      }
      if line == "COMPANION" { return .companion }
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

  package enum SocketResponse: Sendable {
    case companionURL(String)
    case sceneList([SceneInfo])
    case attachOK(ptyPath: String)
    case error(String)

    package func encode() throws(SocketProtocolError) -> String {
      switch self {
      case .companionURL(let url):
        guard !url.unicodeScalars.contains(where: SocketLineFraming.isControl) else {
          throw .encodingFailed("Companion URL contains a control character")
        }
        return "OK \(url)\n"
      case .sceneList(let scenes):
        let items = scenes.map { $0.jsonString() }.joined(separator: ",")
        let json = "[\(items)]"
        return "OK \(json)\n"
      case .attachOK(let ptyPath):
        guard !ptyPath.unicodeScalars.contains(where: SocketLineFraming.isControl) else {
          throw .encodingFailed("PTY path contains a control character")
        }
        return "OK \(ptyPath)\n"
      case .error(let message):
        return "ERR \(SocketLineFraming.escapedMessage(message))\n"
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
        "Failed to create discovery socket: \(unsafe String(cString: strerror(errno)))"
      case .identifierAlreadyInUse(let path):
        "A running instance is already using discovery socket \(path)."
      case .failedToBind(let path, let errno):
        "Failed to bind discovery socket \(path): \(unsafe String(cString: strerror(errno)))"
      case .failedToListen(let errno):
        "Failed to listen on discovery socket: \(unsafe String(cString: strerror(errno)))"
      }
    }
  }

  // MARK: - SceneDiscoveryServer

  /// Unix domain socket server that advertises scenes for attachment.
  ///
  /// The server listens at `/tmp/swifttui/<appName>/<identifier>.sock`.
  /// Clients send `LIST\n` or `ATTACH <sceneID>\n`.
  package final class SceneDiscoveryServer: Sendable {
    package let socketPath: String

    private let sceneProvider: @Sendable () -> [SceneInfo]
    private let companionURL: String?
    private let attachHandler: @Sendable (String) -> SocketResponse

    package init(
      appName: String,
      identifier: String,
      sceneProvider: @escaping @Sendable () -> [SceneInfo],
      companionURL: String? = nil,
      attachHandler: @escaping @Sendable (String) -> SocketResponse
    ) {
      let dir = "/tmp/swifttui/\(appName)"
      self.socketPath = "\(dir)/\(identifier).sock"
      self.companionURL = companionURL
      self.sceneProvider = sceneProvider
      self.attachHandler = attachHandler
    }

    /// Starts the server: creates the socket directory, binds, listens, and accepts in a loop.
    /// Returns when cancelled or throws on unrecoverable startup error.
    ///
    /// - Parameter onReady: invoked exactly once, on the calling task, after the
    ///   listening socket is bound and accepting — i.e. the precise instant a
    ///   client connect would succeed. Lets callers (and tests) `await` server
    ///   readiness directly instead of polling for it.
    package func run(onReady: (@Sendable () -> Void)? = nil) async throws {
      guard var addr = sceneSocketAddress(for: socketPath) else {
        throw SceneDiscoveryServerError.failedToBind(path: socketPath, errno: ENAMETOOLONG)
      }
      // Create directory structure recursively (pure stdlib — no Foundation)
      let parts = socketPath.split(separator: "/" as Character, omittingEmptySubsequences: true)
      let dirParts = parts.dropLast()
      mkdirRecursive(components: Array(dirParts).map(String.init))
      if companionURL != nil {
        // A companion URL contains a bearer token. Discovery may expose it only
        // through a socket in directories owned by this user and not writable
        // by other users. Reject symlinks as well as permissive directories.
        for directory in ["/tmp/swifttui", "/" + dirParts.joined(separator: "/")] {
          var status = stat()
          let result = directory.withCString { unsafe lstat($0, &status) }
          guard result == 0, status.st_uid == geteuid(),
            status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
            status.st_mode & 0o022 == 0
          else { throw SceneDiscoveryServerError.failedToBind(path: directory, errno: EACCES) }
        }
      }

      if pathExists(socketPath) {
        if isSocketLive(socketPath) {
          throw SceneDiscoveryServerError.identifierAlreadyInUse(path: socketPath)
        }
        _ = sceneUnlink(socketPath)
      }

      let serverFD = sceneSocket()
      guard serverFD >= 0 else {
        throw SceneDiscoveryServerError.failedToCreateSocket(errno: errno)
      }

      var shouldCleanupSocketPath = false
      defer {
        sceneClose(serverFD)
        if shouldCleanupSocketPath {
          _ = sceneUnlink(socketPath)
        }
      }

      // Bind
      let bindResult = sceneBind(serverFD, &addr)
      guard bindResult == 0 else {
        if errno == EADDRINUSE {
          throw SceneDiscoveryServerError.identifierAlreadyInUse(path: socketPath)
        }
        throw SceneDiscoveryServerError.failedToBind(path: socketPath, errno: errno)
      }
      shouldCleanupSocketPath = true
      if companionURL != nil {
        let result = socketPath.withCString { unsafe chmod($0, 0o600) }
        guard result == 0 else {
          throw SceneDiscoveryServerError.failedToBind(path: socketPath, errno: errno)
        }
      }

      guard sceneListen(serverFD, 5) == 0 else {
        throw SceneDiscoveryServerError.failedToListen(errno: errno)
      }

      // Set server socket to non-blocking so accept() doesn't block the cooperative thread pool.
      let flags = fcntl(serverFD, F_GETFL)
      _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

      // The socket is now bound and listening: a client connect will succeed
      // from here on. Signal readiness before entering the accept loop.
      onReady?()

      // Accept loop. Probe with a zero timeout and sleep between probes: a
      // blocking `poll` holds a cooperative executor worker for its whole
      // timeout, and that pool is only as wide as the core count. Because every
      // CLI app runs this server, a blocking probe permanently consumed one
      // worker — invisible on a developer machine, but half the pool on a
      // two-core CI runner, where it starved the run loop before first paint.
      // `Task.sleep` suspends instead of blocking, so the worker stays free.
      await withTaskGroup(of: Void.self) { clients in
        var pendingClients = 0
        while !Task.isCancelled {
          // Bound both live connections and completed child-task results.
          if pendingClients == 64 {
            _ = await clients.next()
            pendingClients -= 1
            continue
          }
          var pfd = pollfd(fd: serverFD, events: Int16(POLLIN), revents: 0)
          let ready = unsafe poll(&pfd, 1, 0)
          guard ready > 0 else {
            try? await Task.sleep(for: .milliseconds(20))
            continue
          }
          let clientFD = sceneAccept(serverFD)
          guard clientFD >= 0 else {
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
            break
          }
          let flags = fcntl(clientFD, F_GETFL)
          guard flags >= 0, fcntl(clientFD, F_SETFL, flags | O_NONBLOCK) == 0 else {
            sceneClose(clientFD)
            continue
          }
          pendingClients += 1
          clients.addTask {
            await Self.handleClient(
              fd: clientFD, sceneProvider: self.sceneProvider,
              companionURL: self.companionURL, attachHandler: self.attachHandler)
          }
        }
        clients.cancelAll()
      }
    }

    /// Creates each directory component in `components` (absolute path, leading "/" implied).
    private func mkdirRecursive(components: [String]) {
      var current = ""
      for component in components {
        current += "/\(component)"
        _ = current.withCString { cPath in
          unsafe mkdir(cPath, 0o755)
        }
      }
    }

    private func pathExists(_ path: String) -> Bool {
      sceneAccess(path, F_OK) == 0
    }

    private func isSocketLive(_ path: String) -> Bool {
      let fd = sceneSocket()
      guard fd >= 0 else { return false }
      defer { sceneClose(fd) }

      guard var addr = sceneSocketAddress(for: path) else { return false }

      let result = sceneConnect(fd, &addr)
      return result == 0
    }

    @Sendable
    private static func handleClient(
      fd: Int32,
      sceneProvider: @escaping @Sendable () -> [SceneInfo],
      companionURL: String?,
      attachHandler: @escaping @Sendable (String) -> SocketResponse
    ) async {
      defer { sceneClose(fd) }

      let raw: String
      do {
        guard let line = try await SocketLineFraming.readRequest(fd: fd) else { return }
        raw = line
      } catch {
        await SocketLineFraming.writeResponse("ERR Invalid or incomplete request\n", fd: fd)
        return
      }

      let response: SocketResponse
      do {
        let request = try SocketRequest.parse(raw)
        switch request {
        case .companion:
          response =
            companionURL.map(SocketResponse.companionURL)
            ?? .error("This instance has no browser companion.")
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
        encoded = "ERR \(SocketLineFraming.escapedMessage(String(describing: error)))\n"
      }

      await SocketLineFraming.writeResponse(encoded, fd: fd)
    }
  }
#endif
