// Adversarial set B, pass 4: the loopback WebHost server, its browser bundle,
// token and origin gates, outbound budgets, input decoding and shutdown
// (331–340).
//
// The server answers four token-gated routes from a bundle inventory, allows
// socket origins from a fixed host list, bounds every outbound boundary at
// 32 records and 4 MiB, decodes RS-framed input records into runtime events,
// and tears every socket down on stop. These probes request dotfiles and
// case variants the inventory omits, ask for the media types of files a
// shipped bundle carries, look for cache headers on the token-bearing index,
// open a socket from the LAN address a 0.0.0.0 bind advertises, send one
// record at the wire's own size ceiling, push a key's modifier field past
// the defined bits, pin token precedence and scene routing, and stop the
// session while a socket write is stuck.
import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUIWebHost

@MainActor
@Suite("Adversarial set B: WebHost", .serialized, .timeLimit(.minutes(1)))
struct AdversarialSetBWebHostTests {
  // A custom bundle's dotfiles are excluded from the asset inventory but are
  // still served by path.
  @Test func setB331DotfilesOutsideTheInventoryAreStillServed() throws {
    let bundle = try SetBBundleDirectory()
    defer { bundle.remove() }
    try bundle.write("index.html", "<script src=\"./app.js\"></script>")
    try bundle.write("app.js", "app")
    try bundle.write(".env", "SECRET=1")
    try bundle.write(".vite/manifest.json", "{}")
    let resources = WebHostBrowserBundle(directory: bundle.root.path)
    let inventory = try resources.assetPaths()
    #expect(inventory == ["app.js", "index.html"], "\(inventory)")
    #expect(throws: WebHostBrowserBundleError.self) {
      try resources.resource(for: "/.vite/../../outside.txt")
    }
    do {
      #expect(throws: WebHostBrowserBundleError.self) { try resources.resource(for: "/.env") }
      #expect(throws: WebHostBrowserBundleError.self) {
        try resources.resource(for: "/.vite/manifest.json")
      }
    }
    let routed = setBRoutes(bundle: resources).route(
      setBHead("/.env", query: ["token": setBToken.rawValue]))
    do {
      #expect(setBPlainResponse(routed)?.status == 404, "\(routed)")
    }
  }

  // On a case-insensitive volume a case variant of an asset path is served
  // although the inventory names the asset exactly once.
  @Test func setB332CaseVariantsOfAssetPathsAreServedOnCaseInsensitiveVolumes() throws {
    let bundle = try SetBBundleDirectory()
    defer { bundle.remove() }
    try bundle.write("index.html", "<p>index</p>")
    try bundle.write("app.js", "app")
    let resources = WebHostBrowserBundle(directory: bundle.root.path)
    #expect(try resources.assetPaths() == ["app.js", "index.html"])
    #expect(try resources.resource(for: "/app.js").path == "app.js")
    do {
      #expect(throws: WebHostBrowserBundleError.self) { try resources.resource(for: "/APP.JS") }
      #expect(throws: WebHostBrowserBundleError.self) {
        try resources.resource(for: "/Index.html")
      }
    }
  }

  // Files a shipped bundle contains get a recognizable media type: plain
  // text, classic web fonts, modern images and icons.
  @Test func setB333CommonBundleFileTypesGetARecognizableMediaType() {
    let bundle = WebHostBrowserBundle.bundled
    #expect(bundle.contentType(for: "BUNDLE.JS") == "application/javascript; charset=utf-8")
    #expect(bundle.contentType(for: "chunk.mjs") == "application/javascript; charset=utf-8")
    #expect(bundle.contentType(for: "photo.JPEG") == "image/jpeg")
    #expect(bundle.contentType(for: "app.wasm") == "application/wasm")
    #expect(bundle.contentType(for: "LICENSE") == "application/octet-stream")
    do {
      #expect(bundle.contentType(for: "LICENSE.txt").hasPrefix("text/plain"))
      #expect(bundle.contentType(for: "fonts/mono.woff") == "font/woff")
      #expect(bundle.contentType(for: "fonts/mono.ttf") == "font/ttf")
      #expect(bundle.contentType(for: "hero.webp") == "image/webp")
      #expect(bundle.contentType(for: "favicon.ico").hasPrefix("image/"))
    }
  }

  // The index response embeds the bearer token in its asset URLs, so it must
  // not be cacheable.
  @Test func setB334TokenBearingIndexResponseIsNotCacheable() throws {
    let routed = setBRoutes().route(setBHead("/", query: ["token": setBToken.rawValue]))
    let response = try #require(setBPlainResponse(routed))
    #expect(response.status == 200)
    #expect(
      String(decoding: response.body, as: UTF8.self).contains("?token=\(setBToken.rawValue)"))
    let cookie = try #require(setBHeader("Set-Cookie", in: response))
    #expect(cookie.contains("HttpOnly"), "\(cookie)")
    #expect(cookie.contains("SameSite=Strict"), "\(cookie)")
    #expect(cookie.contains("Path=/"), "\(cookie)")
    let wire = String(decoding: response.serialized(), as: UTF8.self)
    #expect(wire.contains("\r\nContent-Length: \(response.body.count)\r\n"))
    #expect(wire.contains("\r\nConnection: close\r\n"))
    do {
      #expect(setBHeader("Cache-Control", in: response)?.contains("no-store") == true)
    }
  }

  // A 0.0.0.0 bind advertises network reachability, so a page served to a
  // LAN address must be allowed to open its socket from that origin.
  @Test func setB335NetworkBindAcceptsTheOriginItAdvertises() {
    let loopback = WebHostOriginPolicy(bind: "127.0.0.1")
    #expect(loopback.allows(origin: "http://127.0.0.1:9123", port: 9123))
    #expect(loopback.allows(origin: "https://LOCALHOST:9123", port: 9123))
    #expect(!loopback.allows(origin: "http://127.0.0.1:9124", port: 9123))
    #expect(!loopback.allows(origin: "null", port: 9123))
    #expect(!loopback.allows(origin: "ftp://127.0.0.1:9123", port: 9123))
    #expect(loopback.allows(origin: "", port: 9123))
    let network = WebHostOriginPolicy(bind: "0.0.0.0")
    #expect(network.allows(origin: "http://localhost:9123", port: 9123))
    do {
      #expect(network.allows(origin: "http://192.168.1.20:9123", port: 9123))
    }
  }

  // A record at the wire's own ceiling (recordBytes plus the terminating LF)
  // is admitted by the outbound budget instead of closing the connection.
  @Test func setB336RecordAtTheWireCeilingIsAdmittedByTheOutboundBudget() async throws {
    #expect(WebHostOutboundBudget.byteLimit == HostWireBudget.recordBytes + 1)
    let channel = WebHostSceneChannel()
    let disconnected = SetBFlag()
    let client = AsyncStream<WebHostSocketMessage>.makeStream()
    let (output, connectionToken) = await channel.attachSocket(client: client.stream) {
      disconnected.set()
    }
    let token = try #require(connectionToken)
    await channel.applyCapabilities(token: token, reanchor: {}, requestRefresh: {})
    var iterator = output.makeAsyncIterator()
    // Payloads are compared by size: a failed `#expect` renders both operands
    // into the issue record, and describing a 4 MiB array costs seconds.
    let exact = [UInt8](repeating: 0x41, count: HostWireBudget.recordBytes)
    let exactSend = Task { try await channel.send(exact, connectionToken: token) }
    let admitted = await iterator.next()
    #expect(setBDataCount(admitted) == exact.count, "\(setBSummary(admitted))")
    await channel.completeOutput(token: token, byteCount: exact.count, succeeded: true)
    try await exactSend.value
    #expect(!disconnected.isSet)
    let ceiling = [UInt8](repeating: 0x42, count: HostWireBudget.recordBytes + 1)
    let ceilingSend = Task { try await channel.send(ceiling, connectionToken: token) }
    let delivered = await iterator.next()
    await channel.completeOutput(token: token, byteCount: ceiling.count, succeeded: true)
    do {
      #expect(setBDataCount(delivered) == ceiling.count, "\(setBSummary(delivered))")
      #expect(!disconnected.isSet)
      try await ceilingSend.value
    }
    await channel.shutdown()
    client.continuation.finish()
    withExtendedLifetime(output) {}
  }

  // A modifier field past the defined bits is masked or dropped, not clamped
  // into undefined flags.
  @Test func setB337ModifierFieldsPastTheDefinedBitsAreNotClampedIntoUndefinedFlags() async {
    let client = await SetBReaderClient.attached()
    await client.feed(
      "\u{001E}key:character:A:-1\n\u{001E}key:character:A:7\n\u{001E}key:F1:0\n"
        + "\u{001E}key:f1:0\n\u{001E}key:f25:0\n\u{001E}key:character:A:256\n")
    let events = await client.collect()
    let presses = events.compactMap { event -> KeyPress? in
      if case .key(let press) = event { return press }
      return nil
    }
    #expect(presses.count == 4, "\(events)")
    #expect(presses.first == KeyPress(.character("A"), modifiers: []))
    #expect(
      presses.dropFirst().first == KeyPress(.character("A"), modifiers: [.shift, .alt, .ctrl]))
    #expect(presses.dropFirst(2).first == KeyPress(.functionKey(1)))
    let clamped = presses.last
    #expect(clamped?.key == .character("A"))
    do {
      #expect((clamped?.modifiers.rawValue ?? 0) & ~0b111 == 0, "\(String(describing: clamped))")
    }
    await client.shutdown()
  }

  // A wrong or empty query token refuses even when a valid cookie rides along,
  // a valid cookie alone authorizes without a new Set-Cookie, and token
  // comparison is exact in case and length.
  @Test func setB338QueryTokenTakesPrecedenceOverTheCookieAndComparesExactly() throws {
    let routes = setBRoutes()
    let token = setBToken.rawValue
    let cookieName = WebHostRouteTable.cookieName
    let cookie = (name: "Cookie", value: "theme=dark; \(cookieName)=\(token)")
    func status(
      _ path: String, query: [String: String] = [:],
      headers: [(name: String, value: String)] = []
    ) -> Int? {
      setBPlainResponse(routes.route(setBHead(path, query: query, headers: headers)))?.status
    }
    let viaCookie = try #require(setBPlainResponse(routes.route(setBHead("/", headers: [cookie]))))
    #expect(viaCookie.status == 200)
    #expect(setBHeader("Set-Cookie", in: viaCookie) == nil)
    #expect(status("/", query: ["token": "wrong"], headers: [cookie]) == 403)
    #expect(status("/", query: ["token": ""], headers: [cookie]) == 403)
    #expect(status("/", query: ["token": token.uppercased()]) == 403)
    #expect(status("/", query: ["token": token + "x"]) == 403)
    #expect(status("/", query: ["token": String(token.dropLast())]) == 403)
    #expect(status("/", query: ["TOKEN": token]) == 403)
    #expect(status("/", headers: [("Cookie", "\(cookieName)=\"\(token)\"")]) == 403)
    #expect(status("/", headers: [("Cookie", "\(cookieName.lowercased())=\(token)")]) == 403)
    let missing = try #require(
      setBPlainResponse(routes.route(setBHead("/missing.js", query: ["token": token]))))
    #expect(missing.status == 404)
    #expect(setBHeader("Set-Cookie", in: missing) != nil)
  }

  // Scene ids and titles survive the manifest and the socket route: hostile
  // titles are escaped, exactly one scene is default, ids with "/" and "?"
  // route, and an empty or duplicate scene set is refused before binding.
  @Test func setB339SceneManifestAndRoutesKeepIdentityExactly() async throws {
    let title = "q\"\\\n\u{2028}\t\u{01}é"
    let scenes: [WebHostSceneDescriptor] = [
      .init(id: "a/b", title: title, isDefault: true),
      .init(id: "x?y", title: nil, isDefault: true),
    ]
    let manifest = try setBJSON(WebHostRouteTable.sceneManifest(scenes))
    #expect(manifest["defaultSceneId"] as? String == "a/b")
    let entries = try #require(manifest["scenes"] as? [[String: Any]])
    #expect(entries.map { $0["id"] as? String } == ["a/b", "x?y"])
    #expect(entries.first?["title"] as? String == title)
    #expect(entries.map { $0["isDefault"] as? Bool } == [true, false])
    let noDefault = try setBJSON(
      WebHostRouteTable.sceneManifest([.init(id: "only", isDefault: false)]))
    #expect(noDefault["defaultSceneId"] as? String == "only")
    let routes = setBRoutes(scenes: scenes)
    let upgrade: [(name: String, value: String)] = [
      ("Host", "127.0.0.1:8787"),
      ("Upgrade", "websocket"), ("Connection", "Upgrade"), ("Sec-WebSocket-Version", "13"),
      ("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ=="),
    ]
    for id in ["a/b", "x?y"] {
      let routed = routes.route(
        setBHead("/ws/scene/\(id)", query: ["token": setBToken.rawValue], headers: upgrade))
      guard case .webSocketUpgrade(let response, let sceneID) = routed else {
        Issue.record("expected an upgrade for scene \(id), got \(routed)")
        continue
      }
      #expect(sceneID == id)
      #expect(response.status == 101)
    }
    await #expect(throws: WebHostServerError.invalidScenes) {
      try await WebHostLoopbackServer().start(
        configuration: .init(port: 0), token: setBToken, scenes: [])
    }
    let duplicates: [WebHostSceneDescriptor] = [.init(id: "dup"), .init(id: "dup")]
    await #expect(throws: WebHostServerError.invalidScenes) {
      try await WebHostLoopbackServer().start(
        configuration: .init(port: 0), token: setBToken, scenes: duplicates)
    }
  }

  // Stopping the session while a socket write is stuck returns promptly,
  // settles the pending send, and releases the listener.
  @Test func setB340StopWhileASocketWriteIsStuckIsBoundedAndReleasesTheListener() async throws {
    try await withServer { session in
      let probe = SetBIngressProbe()
      await session.channel.observeIngress { probe.record($0) }
      let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)
      defer { webSocket.close() }
      await probe.wait { $0?.currentToken != nil }
      let payload = [UInt8](repeating: 0x5A, count: 3 << 20)
      // Detached: a main-actor task could not run while the header read below
      // blocks this thread.
      let sending = Task.detached { try await session.channel.send(payload) }
      // The frame is in flight once its header reaches the client. The test
      // client refuses the 8-byte length form right after reading those two
      // bytes and never reads the payload, so the server's writer stays stuck.
      do {
        _ = try webSocket.receiveFrame()
        Issue.record("expected the 3 MiB frame header to be refused by the test client")
      } catch {
        #expect("\(error)".contains("Unsupported WebSocket frame length"), "\(error)")
      }
      #expect(await session.channel.yieldedOutputRecordCount() == 1)
      let start = ContinuousClock.now
      await session.stop()
      #expect(start.duration(to: .now) < .milliseconds(900))
      switch await sending.result {
      case .success:
        break
      case .failure(let error):
        #expect(error as? WebHostByteSinkError == .sendDidNotComplete, "\(error)")
      }
      #expect(await session.channel.consumeObservations().phase == .terminal)
      await #expect(throws: Never.self) { try await session.channel.send([1]) }
      await #expect(throws: (any Error).self) {
        _ = try await serverData(from: session.url(path: "/"))
      }
    }
  }
}

private let setBToken = WebHostToken(rawValue: "setb-token")

private func setBRoutes(
  bundle: WebHostBrowserBundle = .bundled,
  scenes: [WebHostSceneDescriptor] = [.init(id: "main")]
) -> WebHostRouteTable {
  WebHostRouteTable(
    bind: "127.0.0.1", token: setBToken, scenes: scenes, port: 9123, maxMessageBytes: 1024,
    browserBundle: bundle)
}

private func setBHead(
  _ path: String, query: [String: String] = [:], headers: [(name: String, value: String)] = []
) -> WebHostHTTPRequestHead {
  WebHostHTTPRequestHead(method: "GET", path: path, query: query, headers: headers)
}

private func setBPlainResponse(_ routed: WebHostRouteTable.RoutedRequest) -> WebHostHTTPResponse? {
  if case .plain(let response) = routed { return response }
  return nil
}

private func setBHeader(_ name: String, in response: WebHostHTTPResponse) -> String? {
  response.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
}

private func setBJSON(_ text: String) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func setBDataCount(_ message: WebHostSocketMessage?) -> Int? {
  if case .data(let bytes) = message { return bytes.count }
  return nil
}

private func setBSummary(_ message: WebHostSocketMessage?) -> String {
  switch message {
  case .data(let bytes):
    return "data(\(bytes.count) bytes)"
  case .text(let text):
    return "text(\(text.utf8.count) bytes)"
  case .close(let code, let reason):
    return "close(\(code), \(reason))"
  case nil:
    return "nil"
  }
}

private struct SetBBundleDirectory {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SetBWebHost-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func write(_ relativePath: String, _ contents: String) throws {
    let url = root.appendingPathComponent(relativePath, isDirectory: false)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

private final class SetBFlag: Sendable {
  private let state = Mutex(false)

  var isSet: Bool { state.withLock { $0 } }

  func set() {
    state.withLock { $0 = true }
  }
}

// An awaitable view of the channel's ingress observations
// (pattern: WebHostIngressTests.IngressProbe).
private final class SetBIngressProbe: Sendable {
  private let state = Mutex<WebHostSceneChannel.IngressObservation?>(nil)
  private let changes = ConditionSignal()

  func record(_ observation: WebHostSceneChannel.IngressObservation) {
    state.withLock { $0 = observation }
    changes.notify()
  }

  func wait(
    _ predicate: @escaping @Sendable (WebHostSceneChannel.IngressObservation?) -> Bool
  ) async {
    await changes.wait(until: { self.state.withLock { predicate($0) } })
  }
}

private typealias SetBStreamPair<Element: Sendable> = (
  stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation
)

// One attached client on a real channel, stepped through the reader's own
// `process` step so an assertion runs once the record has been applied
// (pattern: WebSocketInputReaderTests.ChannelClient).
private struct SetBReaderClient {
  let channel: WebHostSceneChannel
  let reader: WebSocketInputReader
  let token: UInt64
  private let events: SetBStreamPair<InputEvent>
  private let client: SetBStreamPair<WebHostSocketMessage>
  private let output: AsyncStream<WebHostSocketMessage>

  static func attached() async -> SetBReaderClient {
    let channel = WebHostSceneChannel()
    let client = AsyncStream<WebHostSocketMessage>.makeStream()
    let output = await channel.attach(client: client.stream)
    let token = await channel.currentConnectionToken() ?? 0
    return SetBReaderClient(
      channel: channel, reader: WebSocketInputReader(source: channel), token: token,
      events: AsyncStream<InputEvent>.makeStream(), client: client, output: output)
  }

  func feed(_ text: String) async {
    await reader.process(.bytes(token: token, Array(text.utf8)), yielding: events.continuation)
  }

  func collect() async -> [InputEvent] {
    events.continuation.finish()
    var collected: [InputEvent] = []
    for await event in events.stream {
      collected.append(event)
    }
    return collected
  }

  func shutdown() async {
    await channel.shutdown()
    client.continuation.finish()
    withExtendedLifetime(output) {}
  }
}
