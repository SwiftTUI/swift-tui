import Foundation
import Testing

@testable import SwiftTUIWebHost

@Suite(.serialized)
struct AdversarialSetAWebProtocolBoundaryTests {
  @Test func setA976CloseReasonTruncationPreservesUTF8ScalarBoundaries() throws {
    // Hypothesis: byte-prefix truncation cuts a multibyte close reason into invalid UTF-8.
    let reason = String(repeating: "x", count: 122) + "雪"
    let encoded = WebHostWebSocketWire.encodeClose(code: 1000, reason: reason)
    #expect(encoded.count <= 127)
    #expect(Array(encoded[2..<4]) == [3, 232])
    do {
      #expect(String(bytes: encoded.dropFirst(4), encoding: .utf8) != nil)
    }
  }

  @Test func setA977ExtendedFrameLengthsMustUseTheirMinimalRepresentation() {
    // Hypothesis: a short payload using the extended-length field bypasses RFC 6455's canonical framing check.
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append([0x82, 0xFE, 0, 1, 0, 0, 0, 0, 65])
    do {
      #expect(throws: (any Error).self) { try decoder.nextFrame() }
    }
  }

  @Test func setA978OneByteClosePayloadIsRejectedBeforeNormalCloseClassification() throws {
    // Hypothesis: close frames skip payload validation, accepting half of the mandatory two-byte status code.
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append(masked(opcode: 8, payload: [3]))
    var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)
    do {
      #expect(throws: (any Error).self) {
        if let frame = try decoder.nextFrame() { _ = try assembler.assemble(frame) }
      }
    }
  }

  @Test func setA979RequestVersionMustBeAnHTTPVersionNotAnArbitraryPrefix() {
    // Hypothesis: prefix-only HTTP version validation accepts an invalid request line as routable input.
    do {
      #expect(parse("GET / HTTP/1.garbage\r\nHost: localhost\r\n\r\n") == nil)
    }
    #expect(parse("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n") != nil)
  }

  @Test func setA980WhitespaceBeforeAHeaderColonRejectsTheWholeRequest() {
    // Hypothesis: forbidden field-name whitespace is stored as an ignorable alternate name instead of rejecting the request.
    do {
      #expect(parse("GET / HTTP/1.1\r\nHost : localhost\r\n\r\n") == nil)
    }
    #expect(parse("GET / HTTP/1.1\r\nHost:\tlocalhost\r\n\r\n") != nil)
  }

  @Test func setA981AnOmittedOriginPortMeansTheSchemeDefaultNotAnyPort() {
    // Hypothesis: URL.port == nil bypasses the listener-port check instead of resolving the scheme's default port.
    let policy = WebHostOriginPolicy(bind: "127.0.0.1")
    #expect(policy.allows(origin: "http://localhost", port: 80))
    #expect(policy.allows(origin: "https://localhost", port: 443))
    #expect(policy.allows(origin: "http://localhost:9123", port: 9123))
    #expect(!policy.allows(origin: "http://localhost:80", port: 9123))
    do {
      #expect(!policy.allows(origin: "http://localhost", port: 9123))
    }
  }

  @Test func setA982UpgradeHeadersMatchWholeProtocolTokens() {
    // Hypothesis: substring membership accepts non-protocol tokens containing websocket/upgrade.
    var head = upgradeHead()
    for (index, invalid) in [(0, "notwebsocket"), (1, "notupgrade")] {
      var malformed = head
      malformed.headers[index].value = invalid
      do {
        #expect(status(routes().route(malformed)) == 400)
      }
    }
    head.headers[0].value = "WebSocket"
    head.headers[1].value = "keep-alive, Upgrade"
    #expect(status(routes().route(head)) == 101)
  }

  @Test func setA983WebSocketNonceMustDecodeToSixteenBytes() {
    // Hypothesis: any nonempty nonce is accepted without validating the RFC handshake key's Base64 shape and decoded length.
    var head = upgradeHead()
    head.headers[3].value = "not-base64"
    do {
      #expect(status(routes().route(head)) == 400)
    }
  }

  @Test func setA984DuplicateSingletonHandshakeHeadersCannotHideAConflict() {
    // Hypothesis: first-header lookup silently accepts conflicting duplicate Sec-WebSocket-Version fields.
    var head = upgradeHead()
    head.headers.append(("sec-websocket-version", "12"))
    do {
      #expect(status(routes().route(head)) == 400)
    }
  }

  @Test func setA985QueryDecodingSeparatesBeforeUnescapingAndDecodesOnlyOnce() throws {
    // Hypothesis: decoding before pair splitting or twice changes escaped separators and literal percent text into new fields.
    let head = try #require(
      parse("GET /%252F?token=a%26b%3Dc&plus=x+y&literal=%2520 HTTP/1.1\r\nHost: localhost\r\n\r\n")
    )
    #expect(head.path == "/%2F")
    #expect(head.query == ["token": "a&b=c", "plus": "x+y", "literal": "%20"])
  }

  @Test func setA986ExplicitWrongQueryTokenCannotFallBackToAValidCookie() {
    // Hypothesis: failed explicit credentials fall through to cookie credentials and authorize an unintended URL.
    var head = upgradeHead()
    head.query["token"] = "wrong"
    head.headers.append(("Cookie", "SwiftTUIWebHostToken=secret"))
    #expect(status(routes().route(head)) == 403)
  }

  @Test func setA987CookieTokenNameMatchingIsExactAndCaseSensitive() {
    // Hypothesis: cookie scanning treats a similarly named or lowercased cookie as the authorization token.
    var head = upgradeHead()
    head.query = [:]
    head.headers.append(("Cookie", "xSwiftTUIWebHostToken=secret; swifttuiwebhosttoken=secret"))
    #expect(status(routes().route(head)) == 403)
    head.headers.append(("Unused", "secret"))
    head.headers.removeAll { $0.name == "Cookie" }
    head.headers.append(("Cookie", "other=a=b; SwiftTUIWebHostToken=secret"))
    #expect(status(routes().route(head)) == 101)
  }

  @Test func setA988ResponseLengthCountsBodyBytesIncludingNULAndEmoji() throws {
    // Hypothesis: content length measures characters or C-string termination instead of the exact wire body.
    let body = Array("雪\u{0000}👩‍💻".utf8)
    let bytes = WebHostHTTPResponse.ok(body: body, contentType: "text/plain").serialized()
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(text.contains("Content-Length: \(body.count)\r\n"))
    #expect(Array(bytes.suffix(body.count)) == body)
  }

  @Test func setA989FragmentedUTF8MaySplitAScalarAcrossAnInterleavedPing() throws {
    // Hypothesis: text validation runs per fragment and rejects a valid scalar completed after a control frame.
    var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 8)
    let first = try assembler.assemble(.init(fin: false, opcode: .text, payload: [0xE9]))
    let ping = try assembler.assemble(.init(fin: true, opcode: .ping, payload: [0xFF]))
    let last = try assembler.assemble(
      .init(fin: true, opcode: .continuation, payload: [0x9B, 0xAA]))
    #expect(first == nil)
    #expect(ping == .ping(payload: [0xFF]))
    #expect(last == .message(.text("雪")))
  }

  @Test func setA990BinaryFragmentsNeverUseTheTextUTF8Validator() throws {
    // Hypothesis: continuation classification loses the original binary opcode and attempts text decoding.
    var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 4)
    _ = try assembler.assemble(.init(fin: false, opcode: .binary, payload: [0xFF]))
    let result = try assembler.assemble(
      .init(fin: true, opcode: .continuation, payload: [0xFE, 0]))
    #expect(result == .message(.data([0xFF, 0xFE, 0])))
  }

  @Test func setA991HighBitExtendedLengthFailsWithoutIntegerOverflow() {
    // Hypothesis: an unsigned 64-bit wire length overflows signed host arithmetic before the header is refused.
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append([0x82, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 1])
    #expect(throws: WebHostWebSocketWire.DecodeError.payloadTooLarge(declared: Int.max)) {
      try decoder.nextFrame()
    }
  }

  @Test func setA992ControlPayloadLimitIsEnforcedWithoutWaitingForItsBody() {
    // Hypothesis: an oversized control frame waits for its declared payload before rejecting an invalid header.
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append([0x89, 0xFE, 0, 126])
    #expect(throws: WebHostWebSocketWire.DecodeError.oversizedControlFrame) {
      try decoder.nextFrame()
    }
  }

  @Test func setA993AdjacentClientFramesRestartTheirIndependentMaskPhase() throws {
    // Hypothesis: a decoder carries the first frame's payload offset into the next mask cycle.
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append(
      masked(payload: [1, 2, 3]) + masked(payload: [9, 8, 7, 6, 5], mask: [7, 8, 9, 10]))
    let a = try decoder.nextFrame()
    let b = try decoder.nextFrame()
    let end = try decoder.nextFrame()
    #expect(a?.payload == [1, 2, 3])
    #expect(b?.payload == [9, 8, 7, 6, 5])
    #expect(end == nil)
  }

  @Test func setA994CompactionPreservesAPartiallyReceivedFollowingFrame() throws {
    // Hypothesis: discarding consumed bytes on append also discards the unconsumed next-frame prefix.
    let second = masked(payload: [8, 9, 10])
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append(masked(payload: [1]) + Array(second.prefix(5)))
    let first = try decoder.nextFrame()
    let partial = try decoder.nextFrame()
    decoder.append(second.dropFirst(5))
    let completed = try decoder.nextFrame()
    #expect(first?.payload == [1])
    #expect(partial == nil)
    #expect(completed?.payload == [8, 9, 10])
  }

  @Test func setA995MessageBudgetCountsUTF8BytesAcrossFragments() throws {
    // Hypothesis: text-message admission counts decoded graphemes and admits a three-byte scalar to a two-byte budget.
    var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 2)
    _ = try assembler.assemble(.init(fin: false, opcode: .text, payload: [0xE9]))
    #expect(throws: WebHostWebSocketWire.AssemblyError.messageTooLarge(limit: 2)) {
      try assembler.assemble(.init(fin: true, opcode: .continuation, payload: [0x9B, 0xAA]))
    }
  }

  @Test func setA996FinishingIngressDrainsAdmittedRecordsBeforeEndOfStream() async {
    // Hypothesis: finishing a queue discards already admitted reliable controls or permits post-finish arrivals.
    let queue = WebHostIngressQueue<Int>()
    #expect(queue.offer(1, bytes: 3))
    #expect(queue.offer(2, bytes: 4))
    queue.finish()
    #expect(!queue.offer(3, bytes: 1))
    var iterator = queue.stream().makeAsyncIterator()
    #expect(await iterator.next() == 1)
    #expect(await iterator.next() == 2)
    #expect(await iterator.next() == nil)
    #expect(queue.snapshot.bytes == 0)
  }

  @Test func setA997DiscardingBufferedIngressReclaimsBytesButKeepsAdmissionOpen() async {
    // Hypothesis: buffer retirement leaves stale byte debt or incorrectly finishes the reusable queue.
    let queue = WebHostIngressQueue<Int>()
    #expect(queue.offer(1, bytes: WebHostIngressQueue<Int>.byteLimit))
    queue.discardBuffered()
    #expect(queue.offer(2, bytes: WebHostIngressQueue<Int>.byteLimit))
    queue.finish()
    var iterator = queue.stream().makeAsyncIterator()
    #expect(await iterator.next() == 2)
    #expect(queue.snapshot.highWaterBytes == WebHostIngressQueue<Int>.byteLimit)
  }

  @Test func setA998ConcurrentIngressAdmissionPreservesEveryAcceptedRecord() async {
    // Hypothesis: concurrent offers overwrite queue entries or lose byte accounting despite fitting the admission budget.
    let queue = WebHostIngressQueue<Int>()
    let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
      for i in 0..<100 { group.addTask { queue.offer(i, bytes: 1) } }
      var count = 0
      for await item in group { if item { count += 1 } }
      return count
    }
    queue.finish()
    var values: [Int] = []
    for await value in queue.stream() { values.append(value) }
    #expect(accepted == 100)
    #expect(values.sorted() == Array(0..<100))
    #expect(queue.snapshot.records == 0)
    #expect(queue.snapshot.bytes == 0)
  }

  @Test func setA999RefusedOutboundAdmissionCannotConsumeARecordSlot() {
    // Hypothesis: an over-budget send mutates accounting before returning false, preventing a later small send.
    var budget = WebHostOutboundBudget()
    let first = budget.admit(10)
    let refused = budget.admit(WebHostOutboundBudget.byteLimit)
    let next = budget.admit(1)
    #expect(first && !refused && next)
    #expect(budget.records == 2)
    #expect(budget.bytes == 11)
    budget.release(10)
    budget.release(1)
    #expect(budget.records == 0 && budget.bytes == 0)
  }

  @Test func setA1000OriginAdmissionDoesNotTrustHostSuffixesOrOpaqueOrigins() {
    // Hypothesis: host allow-list comparison uses substring matching or treats an opaque null origin as missing.
    let policy = WebHostOriginPolicy(bind: "127.0.0.1", allowMissingOrigin: false)
    #expect(!policy.allows(origin: "http://localhost.evil.example:9123", port: 9123))
    #expect(!policy.allows(origin: "null", port: 9123))
    #expect(!policy.allows(origin: nil, port: 9123))
    #expect(policy.allows(origin: "http://LOCALHOST:9123", port: 9123))
  }

  private func parse(_ text: String) -> WebHostHTTPRequestHead? {
    WebHostHTTPRequestHead.parse(headBytes: Array(text.utf8))
  }
  private func routes() -> WebHostRouteTable {
    .init(
      bind: "127.0.0.1", token: .init(rawValue: "secret"),
      scenes: [.init(id: "main", title: nil, isDefault: true)], port: 9123, maxMessageBytes: 1024)
  }
  private func upgradeHead() -> WebHostHTTPRequestHead {
    .init(
      method: "GET", path: "/ws/scene/main", query: ["token": "secret"],
      headers: [
        ("Upgrade", "websocket"), ("Connection", "Upgrade"), ("Sec-WebSocket-Version", "13"),
        ("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ=="), ("Host", "localhost:9123"),
      ])
  }
  private func status(_ request: WebHostRouteTable.RoutedRequest) -> Int {
    switch request {
    case .plain(let response), .webSocketUpgrade(let response, _): return response.status
    }
  }
  private func masked(opcode: UInt8 = 2, payload: [UInt8], mask: [UInt8] = [1, 2, 3, 4]) -> [UInt8]
  {
    [0x80 | opcode, 0x80 | UInt8(payload.count)] + mask
      + payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
  }
}
