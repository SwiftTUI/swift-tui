import Dispatch
import Foundation
import Synchronization

/// The in-tree loopback HTTP + WebSocket host behind `WebHostRunner`.
///
/// This replaced the third-party-backed server: the four routes and the
/// handshake below are the entire surface the browser bundle needs, and
/// internalizing them removed the package's last external networking
/// dependency. Blocking socket calls run on dedicated `Thread`s only — a
/// blocked cooperative-pool worker can starve the whole runtime on narrow
/// machines — and Swift concurrency is bridged exclusively through
/// `AsyncStream` and the scene channel actor.
package struct WebHostLoopbackServer: WebHostServer {
  package static let maxMessageBytes = WebHostWebSocketWire.maxPayloadBytes

  package init() {}

  package func start(
    configuration: WebHostConfig,
    token: WebHostToken,
    scene: WebHostSceneDescriptor
  ) async throws -> WebHostServerSession {
    var lastError: (any Error)?
    for port in configuration.candidatePorts {
      do {
        return try start(
          configuration: configuration,
          requestedPort: port,
          token: token,
          scene: scene
        )
      } catch {
        lastError = error
        if configuration.candidatePorts.count == 1 {
          throw error
        }
      }
    }
    throw lastError ?? WebHostServerError.unableToDetermineListeningPort
  }

  private func start(
    configuration: WebHostConfig,
    requestedPort: Int,
    token: WebHostToken,
    scene: WebHostSceneDescriptor
  ) throws -> WebHostServerSession {
    let requestedPort = try UInt16(webHostPort: requestedPort)
    let listenerFD = WebHostPOSIXSocket.createTCPSocket()
    guard listenerFD >= 0 else {
      throw WebHostServerError.listenerSetupFailed(code: errno)
    }
    let bound = WebHostPOSIXSocket.bindAndListen(
      listenerFD,
      bind: configuration.bind,
      port: requestedPort
    )
    guard bound.success else {
      WebHostPOSIXSocket.close(listenerFD)
      if bound.invalidAddress {
        throw WebHostServerError.unsupportedBindAddress(configuration.bind)
      }
      throw WebHostServerError.listenerSetupFailed(code: bound.failureErrno)
    }
    guard let port = WebHostPOSIXSocket.boundPort(listenerFD) else {
      WebHostPOSIXSocket.close(listenerFD)
      throw WebHostServerError.unableToDetermineListeningPort
    }

    let channel = WebHostSceneChannel()
    let routes = WebHostRouteTable(
      bind: configuration.bind,
      token: token,
      scene: scene,
      port: port,
      maxMessageBytes: Self.maxMessageBytes
    )
    let coordinator = WebHostConnectionCoordinator(
      listenerFD: listenerFD,
      routes: routes,
      channel: channel
    )
    coordinator.startAccepting()

    return WebHostServerSession(
      baseURL: sessionURL(scheme: "http", bind: configuration.bind, port: port, path: "/"),
      webSocketURL: sessionURL(
        scheme: "ws",
        bind: configuration.bind,
        port: port,
        path: "/ws/scene/\(scene.id)",
        token: token
      ),
      token: token,
      channel: channel,
      stopHandler: {
        await coordinator.stop()
      }
    )
  }
}

/// Owns the listener descriptor, the accept thread, and the live connections.
final class WebHostConnectionCoordinator: Sendable {
  private struct State {
    var running = true
    var connections: [ObjectIdentifier: WebHostLoopbackConnection] = [:]
    var acceptThreadExited = false
    var acceptExitWaiter: CheckedContinuation<Void, Never>?
  }

  private let listenerFD: Int32
  private let routes: WebHostRouteTable
  private let channel: WebHostSceneChannel
  private let state = Mutex(State())

  init(
    listenerFD: Int32,
    routes: WebHostRouteTable,
    channel: WebHostSceneChannel
  ) {
    self.listenerFD = listenerFD
    self.routes = routes
    self.channel = channel
  }

  func startAccepting() {
    Thread.detachNewThread { [self] in
      acceptLoop()
    }
  }

  /// Idempotent. Wakes the accept thread, tears down every connection, and
  /// returns once the accept thread has closed the listener — so a caller
  /// that stops one server and starts another on the same fixed port cannot
  /// race the old listener.
  func stop() async {
    let connections = state.withLock { state in
      state.running = false
      let connections = Array(state.connections.values)
      state.connections.removeAll(keepingCapacity: false)
      return connections
    }
    for connection in connections {
      connection.terminate()
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let alreadyExited = state.withLock { state in
        if state.acceptThreadExited {
          return true
        }
        state.acceptExitWaiter = continuation
        return false
      }
      if alreadyExited {
        continuation.resume()
      }
    }
  }

  private func acceptLoop() {
    while state.withLock({ $0.running }) {
      switch WebHostPOSIXSocket.poll(
        listenerFD, events: Int16(POLLIN), timeoutMilliseconds: 100)
      {
      case .timedOut:
        continue
      case .failed, .invalidDescriptor:
        break
      case .ready:
        let connectionFD = WebHostPOSIXSocket.accept(listenerFD)
        guard connectionFD >= 0 else {
          continue
        }
        WebHostPOSIXSocket.configureNoSignalPipe(connectionFD)
        register(connectionFD: connectionFD)
        continue
      }
      break
    }

    WebHostPOSIXSocket.close(listenerFD)
    let waiter = state.withLock { state in
      state.acceptThreadExited = true
      let waiter = state.acceptExitWaiter
      state.acceptExitWaiter = nil
      return waiter
    }
    waiter?.resume()
  }

  private func register(
    connectionFD: Int32
  ) {
    let connection = WebHostLoopbackConnection(
      fd: connectionFD,
      routes: routes,
      channel: channel,
      onClose: { [weak self] connection in
        self?.state.withLock { state in
          state.connections[ObjectIdentifier(connection)] = nil
        }
      }
    )
    let accepted = state.withLock { state in
      guard state.running else {
        return false
      }
      state.connections[ObjectIdentifier(connection)] = connection
      return true
    }
    guard accepted else {
      // Raced a stop: the sweep already ran, so this descriptor is ours to
      // retire before any thread starts.
      WebHostPOSIXSocket.close(connectionFD)
      return
    }
    connection.start()
  }
}

/// One accepted socket: a reader thread that parses and dispatches, a writer
/// thread that drains the outbox, and — for WebSocket sessions — a bridge
/// task that speaks to the scene channel actor.
final class WebHostLoopbackConnection: Sendable {
  private struct State {
    var outbox: [[UInt8]] = []
    var outboxFinished = false
    var readerDone = false
    var writerDone = false
    var terminated = false
    var closed = false
  }

  private let fd: Int32
  private let routes: WebHostRouteTable
  private let channel: WebHostSceneChannel
  private let onClose: @Sendable (WebHostLoopbackConnection) -> Void
  private let state = Mutex(State())
  private let outboxSignal = DispatchSemaphore(value: 0)

  private static let headByteLimit = 64 * 1024
  private static let headReadTimeoutMilliseconds: Int32 = 10_000
  private static let writePollTimeoutMilliseconds: Int32 = 5_000
  private static let drainTimeoutMilliseconds: Int32 = 2_000

  init(
    fd: Int32,
    routes: WebHostRouteTable,
    channel: WebHostSceneChannel,
    onClose: @escaping @Sendable (WebHostLoopbackConnection) -> Void
  ) {
    self.fd = fd
    self.routes = routes
    self.channel = channel
    self.onClose = onClose
  }

  func start() {
    Thread.detachNewThread { [self] in
      readLoop()
    }
    Thread.detachNewThread { [self] in
      writeLoop()
    }
  }

  /// Safe from any thread, idempotent: wakes both IO threads by shutting the
  /// socket down in both directions. The descriptor itself closes only after
  /// both threads have finished with it.
  func terminate() {
    let shouldShutdown = state.withLock { state in
      guard !state.terminated else {
        return false
      }
      state.terminated = true
      return true
    }
    if shouldShutdown {
      WebHostPOSIXSocket.shutdownBoth(fd)
      outboxSignal.signal()
    }
  }

  // MARK: - Writer

  private func enqueue(
    _ bytes: [UInt8]
  ) {
    let accepted = state.withLock { state in
      guard !state.outboxFinished, !state.terminated else {
        return false
      }
      state.outbox.append(bytes)
      return true
    }
    if accepted {
      outboxSignal.signal()
    }
  }

  private func finishWrites() {
    state.withLock { state in
      state.outboxFinished = true
    }
    outboxSignal.signal()
  }

  private func writeLoop() {
    while true {
      outboxSignal.wait()
      while true {
        let (item, finished, terminated) = state.withLock { state in
          (
            state.outbox.isEmpty ? nil : state.outbox.removeFirst(),
            state.outboxFinished,
            state.terminated
          )
        }
        if terminated {
          writerExit()
          return
        }
        guard let item else {
          if finished {
            WebHostPOSIXSocket.shutdownWrites(fd)
            writerExit()
            return
          }
          break
        }
        guard
          WebHostPOSIXSocket.sendAll(
            fd, item, pollTimeoutMilliseconds: Self.writePollTimeoutMilliseconds)
        else {
          terminate()
          writerExit()
          return
        }
      }
    }
  }

  private func writerExit() {
    let closeNow = state.withLock { state in
      state.writerDone = true
      return state.readerDone && !state.closed
    }
    if closeNow {
      closeDescriptor()
    }
  }

  // MARK: - Reader

  private func readLoop() {
    defer { readerExit() }

    guard let headBytes = readRequestHead() else {
      finishWrites()
      return
    }
    guard let head = WebHostHTTPRequestHead.parse(headBytes: headBytes) else {
      enqueue(WebHostHTTPResponse.badRequest().serialized())
      finishWrites()
      drainIncoming()
      return
    }

    switch routes.route(head) {
    case .plain(let response):
      enqueue(response.serialized())
      finishWrites()
      drainIncoming()
    case .webSocketUpgrade(let acceptResponse):
      enqueue(acceptResponse.serialized())
      runWebSocketSession()
      drainIncoming()
    }
  }

  private func readerExit() {
    let closeNow = state.withLock { state in
      state.readerDone = true
      return state.writerDone && !state.closed
    }
    if closeNow {
      closeDescriptor()
    }
  }

  private func closeDescriptor() {
    let shouldClose = state.withLock { state in
      guard !state.closed else {
        return false
      }
      state.closed = true
      return true
    }
    guard shouldClose else {
      return
    }
    WebHostPOSIXSocket.close(fd)
    onClose(self)
  }

  /// Reads through the head's terminating blank line, bounded in both bytes
  /// and time so a stalled or hostile client cannot hold the thread.
  private func readRequestHead() -> [UInt8]? {
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 4096)
    while !bytes.suffix(4).elementsEqual([13, 10, 13, 10]) {
      guard bytes.count <= Self.headByteLimit else {
        return nil
      }
      switch WebHostPOSIXSocket.poll(
        fd, events: Int16(POLLIN), timeoutMilliseconds: Self.headReadTimeoutMilliseconds)
      {
      case .ready:
        break
      case .timedOut, .failed, .invalidDescriptor:
        return nil
      }
      let count = WebHostPOSIXSocket.receive(fd, into: &buffer)
      guard count > 0 else {
        return nil
      }
      bytes.append(contentsOf: buffer.prefix(count))
    }
    return bytes
  }

  /// After the write side has finished, give the client a bounded window to
  /// acknowledge and close so the response is not cut off by a reset.
  private func drainIncoming() {
    var buffer = [UInt8](repeating: 0, count: 4096)
    for _ in 0..<8 {
      switch WebHostPOSIXSocket.poll(
        fd, events: Int16(POLLIN), timeoutMilliseconds: Self.drainTimeoutMilliseconds)
      {
      case .ready:
        if WebHostPOSIXSocket.receive(fd, into: &buffer) <= 0 {
          return
        }
      case .timedOut, .failed, .invalidDescriptor:
        return
      }
    }
  }

  // MARK: - WebSocket session

  private func runWebSocketSession() {
    let (clientStream, clientContinuation) = AsyncStream<WebHostSocketMessage>.makeStream()

    // The bridge task owns the channel conversation. It never blocks: writes
    // go through the outbox, and the writer thread does the blocking. It must
    // end *naturally* — when the channel detaches and finishes the output
    // stream — never by cancellation: cancelling it as the reader exits would
    // end the `for await` before the close frame the channel echoes back has
    // been drained, and the client would see a bare FIN instead of the close.
    // Natural termination is guaranteed: the reader's `finish()` on the client
    // stream drives the channel to detach, and detach finishes this output.
    Task { [channel] in
      let output = await channel.attach(client: clientStream)
      for await message in output {
        switch message {
        case .text(let text):
          enqueue(WebHostWebSocketWire.encodeFrame(opcode: .text, payload: Array(text.utf8)))
        case .data(let bytes):
          enqueue(WebHostWebSocketWire.encodeFrame(opcode: .binary, payload: bytes))
        case .close(let code, let reason):
          enqueue(WebHostWebSocketWire.encodeClose(code: code, reason: reason))
        }
      }
      finishWrites()
    }

    var decoder = WebHostWebSocketWire.FrameDecoder()
    var assembler = WebHostWebSocketWire.MessageAssembler(
      maxMessageBytes: routes.maxMessageBytes)
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)

    defer { clientContinuation.finish() }

    while true {
      let count = WebHostPOSIXSocket.receive(fd, into: &buffer)
      guard count > 0 else {
        return
      }
      decoder.append(buffer.prefix(count))

      while true {
        let frame: WebHostWebSocketWire.Frame?
        do {
          frame = try decoder.nextFrame()
        } catch {
          handleWireFailure(decodeError: error, clientContinuation: clientContinuation)
          return
        }
        guard let frame else {
          break
        }

        let event: WebHostWebSocketWire.AssembledEvent?
        do {
          event = try assembler.assemble(frame)
        } catch {
          handleWireFailure(assemblyError: error, clientContinuation: clientContinuation)
          return
        }

        switch event {
        case nil:
          continue
        case .ping(let payload):
          enqueue(WebHostWebSocketWire.encodeFrame(opcode: .pong, payload: payload))
        case .pong:
          continue
        case .closeReceived:
          // The channel echoes the close back out, which is what makes the
          // writer send the closing frame; see `WebHostSceneChannel.receive`.
          clientContinuation.yield(.normalClose)
          return
        case .message(let message):
          clientContinuation.yield(message)
        }
      }
    }
  }

  /// Size violations travel through the channel as a synthesized 1009 close —
  /// the channel echoes it to the wire and detaches, exactly as the previous
  /// server backend behaved. Protocol violations never reach the
  /// channel: the close frame is written directly and the connection ends.
  private func handleWireFailure(
    decodeError: WebHostWebSocketWire.DecodeError? = nil,
    assemblyError: WebHostWebSocketWire.AssemblyError? = nil,
    clientContinuation: AsyncStream<WebHostSocketMessage>.Continuation
  ) {
    let isTooLarge: Bool
    switch (decodeError, assemblyError) {
    case (.payloadTooLarge, _), (_, .messageTooLarge):
      isTooLarge = true
    default:
      isTooLarge = false
    }

    if isTooLarge {
      clientContinuation.yield(
        .close(
          code: 1009,
          reason: "WebHost WebSocket message exceeded \(routes.maxMessageBytes) bytes."
        )
      )
    } else {
      enqueue(WebHostWebSocketWire.encodeClose(code: 1002, reason: "WebSocket protocol error."))
      finishWrites()
    }
  }
}

/// The four routes the browser bundle uses, plus token and origin policy.
/// Pure request-to-response mapping; no IO.
struct WebHostRouteTable: Sendable {
  static let cookieName = "SwiftTUIWebHostToken"

  var bind: String
  var token: WebHostToken
  var scene: WebHostSceneDescriptor
  var port: Int
  var maxMessageBytes: Int

  enum RoutedRequest: Equatable, Sendable {
    case plain(WebHostHTTPResponse)
    case webSocketUpgrade(WebHostHTTPResponse)
  }

  func route(
    _ head: WebHostHTTPRequestHead
  ) -> RoutedRequest {
    guard head.method == "GET" else {
      return .plain(.notFound())
    }

    if head.path == "/ws/scene/\(scene.id)" {
      return webSocketUpgrade(head)
    }

    return .plain(
      authorizedResponse(for: head) {
        switch head.path {
        case "/":
          do {
            return .ok(
              body: Array(try WebHostBrowserBundle.indexHTML(token: token)),
              contentType: "text/html; charset=utf-8"
            )
          } catch {
            return .notFound()
          }
        case "/scene-manifest.json":
          return .ok(
            body: Array(Self.sceneManifest(scene).utf8),
            contentType: "application/json; charset=utf-8"
          )
        default:
          do {
            let resource = try WebHostBrowserBundle.resource(for: head.path)
            return .ok(body: Array(resource.data), contentType: resource.contentType)
          } catch {
            return .notFound()
          }
        }
      }
    )
  }

  private func webSocketUpgrade(
    _ head: WebHostHTTPRequestHead
  ) -> RoutedRequest {
    guard isAuthorized(head) else {
      return .plain(.forbidden())
    }
    let originPolicy = WebHostOriginPolicy(bind: bind)
    guard originPolicy.allows(origin: head.headerValue("Origin"), port: port) else {
      return .plain(.forbidden())
    }

    guard
      head.headerValue("Upgrade")?.lowercased().contains("websocket") == true,
      head.headerValue("Connection")?.lowercased().contains("upgrade") == true,
      head.headerValue("Sec-WebSocket-Version") == "13",
      let clientKey = head.headerValue("Sec-WebSocket-Key"),
      !clientKey.isEmpty
    else {
      return .plain(.badRequest())
    }

    return .webSocketUpgrade(
      WebHostHTTPResponse(
        status: 101,
        reason: "Switching Protocols",
        headers: [
          ("Upgrade", "websocket"),
          ("Connection", "Upgrade"),
          ("Sec-WebSocket-Accept", WebHostWebSocketWire.acceptKey(forClientKey: clientKey)),
        ]
      )
    )
  }

  func isAuthorized(
    _ head: WebHostHTTPRequestHead
  ) -> Bool {
    if let queryToken = head.query["token"] {
      return constantTimeEquals(queryToken, token.rawValue)
    }
    guard let cookie = cookieToken(from: head) else {
      return false
    }
    return constantTimeEquals(cookie, token.rawValue)
  }

  private func authorizedResponse(
    for head: WebHostHTTPRequestHead,
    response: () -> WebHostHTTPResponse
  ) -> WebHostHTTPResponse {
    guard isAuthorized(head) else {
      return .forbidden()
    }
    var response = response()
    if let queryToken = head.query["token"], constantTimeEquals(queryToken, token.rawValue) {
      response.headers.append(
        ("Set-Cookie", "\(Self.cookieName)=\(token.rawValue); Path=/; SameSite=Strict; HttpOnly"))
    }
    return response
  }

  private func cookieToken(
    from head: WebHostHTTPRequestHead
  ) -> String? {
    guard let cookie = head.headerValue("Cookie") else {
      return nil
    }
    for field in cookie.split(separator: ";") {
      let parts = field.split(separator: "=", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      if parts.count == 2, parts[0] == Self.cookieName {
        return parts[1]
      }
    }
    return nil
  }

  static func sceneManifest(
    _ scene: WebHostSceneDescriptor
  ) -> String {
    let title = scene.title.map { ",\"title\":\(jsonString($0))" } ?? ""
    return """
      {"defaultSceneId":\(jsonString(scene.id)),"scenes":[{"id":\(jsonString(scene.id))\(title),"isDefault":true}]}
      """
  }
}

private func constantTimeEquals(
  _ lhs: String,
  _ rhs: String
) -> Bool {
  let lhsBytes = Array(lhs.utf8)
  let rhsBytes = Array(rhs.utf8)
  var difference = UInt8(lhsBytes.count == rhsBytes.count ? 0 : 1)
  let count = max(lhsBytes.count, rhsBytes.count)
  var index = 0
  while index < count {
    let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
    let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
    difference |= lhsByte ^ rhsByte
    index += 1
  }
  return difference == 0
}

private func sessionURL(
  scheme: String,
  bind: String,
  port: Int,
  path: String,
  token: WebHostToken? = nil
) -> URL {
  var components = URLComponents()
  components.scheme = scheme
  components.host = bind == "0.0.0.0" ? "127.0.0.1" : bind
  components.port = port
  components.path = path
  if let token {
    components.queryItems = [
      URLQueryItem(name: "token", value: token.rawValue)
    ]
  }
  return components.url!
}

private func jsonString(
  _ text: String
) -> String {
  var result = "\""
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x22:
      result += "\\\""
    case 0x5C:
      result += "\\\\"
    case 0x08:
      result += "\\b"
    case 0x0C:
      result += "\\f"
    case 0x0A:
      result += "\\n"
    case 0x0D:
      result += "\\r"
    case 0x09:
      result += "\\t"
    case 0x00...0x1F:
      var hex = String(scalar.value, radix: 16, uppercase: true)
      while hex.count < 4 {
        hex = "0" + hex
      }
      result += "\\u\(hex)"
    default:
      result.unicodeScalars.append(scalar)
    }
  }
  result += "\""
  return result
}

extension UInt16 {
  fileprivate init(
    webHostPort port: Int
  ) throws {
    guard port >= 0, port <= Int(UInt16.max) else {
      throw WebHostServerError.unsupportedPort(port)
    }
    self = UInt16(port)
  }
}
