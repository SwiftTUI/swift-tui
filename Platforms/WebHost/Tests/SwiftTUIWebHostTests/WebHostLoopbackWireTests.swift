// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises the
// WebHost server stack, whose modules build empty on Windows
// (whole-file-guarded).
#if !os(Windows)

  import Foundation
  import Testing

  @testable import SwiftTUIWebHost

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  /// Byte-level coverage of the internalized WebSocket wire pieces the retired
  /// third-party server backend used to own: the handshake key, the frame codec,
  /// and fragment assembly.
  struct WebHostWebSocketWireTests {
    @Test("SHA-1 matches the RFC 3174 test vectors")
    func sha1MatchesRFCTestVectors() {
      #expect(
        hex(WebHostSHA1.digest(Array("abc".utf8)))
          == "a9993e364706816aba3e25717850c26c9cd0d89d")
      #expect(
        hex(WebHostSHA1.digest([]))
          == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
      #expect(
        hex(
          WebHostSHA1.digest(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
        )
          == "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    @Test("handshake accept key matches the RFC 6455 sample")
    func handshakeAcceptKeyMatchesRFC6455Sample() {
      #expect(
        WebHostWebSocketWire.acceptKey(forClientKey: "dGhlIHNhbXBsZSBub25jZQ==")
          == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test("frame encoding uses the correct length header for each size class")
    func frameEncodingUsesCorrectLengthHeaders() {
      let small = WebHostWebSocketWire.encodeFrame(opcode: .binary, payload: [1, 2, 3])
      #expect(Array(small.prefix(2)) == [0x82, 3])
      #expect(Array(small.suffix(3)) == [1, 2, 3])

      let medium = WebHostWebSocketWire.encodeFrame(
        opcode: .text, payload: [UInt8](repeating: 7, count: 300))
      #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2C])
      #expect(medium.count == 4 + 300)

      let large = WebHostWebSocketWire.encodeFrame(
        opcode: .binary, payload: [UInt8](repeating: 7, count: 80_000))
      #expect(Array(large.prefix(2)) == [0x82, 127])
      #expect(Array(large[2..<10]) == [0, 0, 0, 0, 0, 1, 0x38, 0x80])
      #expect(large.count == 10 + 80_000)
    }

    @Test("close frames carry the code and cap the reason at 123 bytes")
    func closeFramesCarryCodeAndCapReason() {
      let frame = WebHostWebSocketWire.encodeClose(
        code: 1009, reason: String(repeating: "r", count: 200))
      #expect(frame[0] == 0x88)
      #expect(Int(frame[1]) == 125)
      #expect(Array(frame[2..<4]) == [0x03, 0xF1])
    }

    @Test("decoder unmasks client frames, tolerating split arrivals")
    func decoderUnmasksClientFramesAcrossSplitArrivals() throws {
      let payload = Array("hello wire".utf8)
      let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
      var wire: [UInt8] = [0x82, 0x80 | UInt8(payload.count)]
      wire.append(contentsOf: mask)
      for (index, byte) in payload.enumerated() {
        wire.append(byte ^ mask[index % 4])
      }

      var decoder = WebHostWebSocketWire.FrameDecoder()
      decoder.append(wire.prefix(3))
      #expect(try decoder.nextFrame() == nil)
      decoder.append(wire.dropFirst(3))
      let frame = try #require(try decoder.nextFrame())
      #expect(frame.fin)
      #expect(frame.opcode == .binary)
      #expect(frame.payload == payload)
      #expect(try decoder.nextFrame() == nil)
    }

    @Test("decoder refuses unmasked, reserved-bit, unknown-opcode, and fragmented-control frames")
    func decoderRefusesProtocolViolations() {
      var unmasked = WebHostWebSocketWire.FrameDecoder()
      unmasked.append([0x82, 0x03, 1, 2, 3])
      #expect(throws: WebHostWebSocketWire.DecodeError.unmaskedClientFrame) {
        try unmasked.nextFrame()
      }

      var reserved = WebHostWebSocketWire.FrameDecoder()
      reserved.append([0xC2, 0x80, 0, 0, 0, 0])
      #expect(throws: WebHostWebSocketWire.DecodeError.reservedBitsSet) {
        try reserved.nextFrame()
      }

      var unknown = WebHostWebSocketWire.FrameDecoder()
      unknown.append([0x83, 0x80, 0, 0, 0, 0])
      #expect(throws: WebHostWebSocketWire.DecodeError.unknownOpcode(3)) {
        try unknown.nextFrame()
      }

      var fragmentedPing = WebHostWebSocketWire.FrameDecoder()
      fragmentedPing.append([0x09, 0x80, 0, 0, 0, 0])
      #expect(throws: WebHostWebSocketWire.DecodeError.fragmentedControlFrame) {
        try fragmentedPing.nextFrame()
      }
    }

    @Test("decoder refuses oversized payloads at the header, before buffering")
    func decoderRefusesOversizedPayloadsAtHeader() {
      var decoder = WebHostWebSocketWire.FrameDecoder()
      let declared = UInt64(WebHostWebSocketWire.maxPayloadBytes + 1)
      var header: [UInt8] = [0x82, 0x80 | 127]
      for shift in stride(from: 56, through: 0, by: -8) {
        header.append(UInt8(truncatingIfNeeded: declared >> UInt64(shift)))
      }
      decoder.append(header)
      #expect(
        throws: WebHostWebSocketWire.DecodeError.payloadTooLarge(
          declared: WebHostWebSocketWire.maxPayloadBytes + 1)
      ) {
        try decoder.nextFrame()
      }
    }

    @Test("assembler reunites fragments and lets control frames interleave")
    func assemblerReunitesFragmentsWithInterleavedControlFrames() throws {
      var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)

      #expect(
        try assembler.assemble(
          .init(fin: false, opcode: .text, payload: Array("frag".utf8))) == nil)
      #expect(
        try assembler.assemble(.init(fin: true, opcode: .ping, payload: [9]))
          == .ping(payload: [9]))
      #expect(
        try assembler.assemble(
          .init(fin: false, opcode: .continuation, payload: Array("ment".utf8))) == nil)
      let completed = try assembler.assemble(
        .init(fin: true, opcode: .continuation, payload: Array("ed".utf8)))
      #expect(completed == .message(.text("fragmented")))

      // The assembler must be reusable for the next message on the connection.
      let followUp = try assembler.assemble(.init(fin: true, opcode: .binary, payload: [1, 2]))
      #expect(followUp == .message(.data([1, 2])))
    }

    @Test(
      "assembler refuses orphan continuations, interleaved data starts, and oversized aggregates")
    func assemblerRefusesInvalidSequencesAndOversizedAggregates() throws {
      var orphan = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)
      #expect(throws: WebHostWebSocketWire.AssemblyError.continuationWithoutStart) {
        try orphan.assemble(.init(fin: true, opcode: .continuation, payload: [1]))
      }

      var interleaved = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)
      _ = try interleaved.assemble(.init(fin: false, opcode: .binary, payload: [1]))
      #expect(throws: WebHostWebSocketWire.AssemblyError.newMessageDuringFragmentation) {
        try interleaved.assemble(.init(fin: true, opcode: .binary, payload: [2]))
      }

      var oversized = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 8)
      _ = try oversized.assemble(.init(fin: false, opcode: .binary, payload: [1, 2, 3, 4, 5]))
      #expect(throws: WebHostWebSocketWire.AssemblyError.messageTooLarge(limit: 8)) {
        try oversized.assemble(.init(fin: true, opcode: .continuation, payload: [6, 7, 8, 9]))
      }

      var invalidText = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)
      #expect(throws: WebHostWebSocketWire.AssemblyError.invalidTextEncoding) {
        try invalidText.assemble(.init(fin: true, opcode: .text, payload: [0xFF, 0xFE]))
      }
    }

    private func hex(
      _ bytes: [UInt8]
    ) -> String {
      let digits = Array("0123456789abcdef")
      var result = ""
      for byte in bytes {
        result.append(digits[Int(byte >> 4)])
        result.append(digits[Int(byte & 0x0F)])
      }
      return result
    }
  }

  /// Socket-level protocol coverage of the loopback server itself — the
  /// behaviors the retired server backend provided and the previous suite
  /// could not see.
  struct WebHostLoopbackServerProtocolTests {
    @Test("ping frames are answered with matching pongs")
    func pingFramesAreAnsweredWithMatchingPongs() async throws {
      try await withServer { session in
        let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)
        try webSocket.sendFrame(opcode: 0x9, fin: true, payload: [1, 2, 3])
        let (opcode, payload) = try webSocket.receiveFrame()
        #expect(opcode == 0xA)
        #expect(Array(payload) == [1, 2, 3])
        webSocket.close()
      }
    }

    @Test("fragmented client messages arrive as one channel event")
    func fragmentedClientMessagesArriveAsOneChannelEvent() async throws {
      try await withServer { session in
        var events = session.channel.inboundEvents().makeAsyncIterator()
        let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)

        guard case .connectionOpened = try #require(await events.next()) else {
          Issue.record("expected the attach to open a connection")
          return
        }

        try webSocket.sendFrame(opcode: 0x2, fin: false, payload: Array("frag".utf8))
        try webSocket.sendFrame(opcode: 0x0, fin: false, payload: Array("ment".utf8))
        try webSocket.sendFrame(opcode: 0x0, fin: true, payload: Array("ed".utf8))

        guard case .bytes(_, let bytes) = try #require(await events.next()) else {
          Issue.record("expected the reassembled message as one event")
          return
        }
        #expect(String(decoding: bytes, as: UTF8.self) == "fragmented")
        webSocket.close()
      }
    }

    @Test("a header declaring an oversized payload draws a 1009 close")
    func oversizedPayloadHeaderDrawsCloseWithCode1009() async throws {
      try await withServer { session in
        let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)
        try webSocket.sendFrameHeaderClaiming(
          declaredLength: UInt64(WebHostLoopbackServer.maxMessageBytes) + 1,
          opcode: 0x2
        )
        let (opcode, payload) = try webSocket.receiveFrame()
        #expect(opcode == 0x8)
        #expect(payload.count >= 2)
        #expect((UInt16(payload[0]) << 8) | UInt16(payload[1]) == 1009)
        webSocket.close()
      }
    }

    @Test("a client close is echoed as a close frame with the normal code")
    func clientCloseIsEchoedWithNormalCode() async throws {
      try await withServer { session in
        let webSocket = try WebSocketTestClient.connect(to: session.webSocketURL)
        try webSocket.sendFrame(opcode: 0x8, fin: true, payload: [0x03, 0xE8])
        let (opcode, payload) = try webSocket.receiveFrame()
        #expect(opcode == 0x8)
        #expect(payload.count >= 2)
        #expect((UInt16(payload[0]) << 8) | UInt16(payload[1]) == 1000)
        webSocket.close()
      }
    }

    @Test("an authorized upgrade without the WebSocket headers is a 400")
    func authorizedUpgradeWithoutWebSocketHeadersIsBadRequest() async throws {
      try await withServer { session in
        let (_, response) = try await serverData(from: session.url(path: "/ws/scene/main"))
        #expect(try statusCode(from: response) == 400)
      }
    }

    @Test("unknown static paths are 404 and non-GET methods are refused")
    func unknownPathsAndNonGETMethodsAreRefused() async throws {
      try await withServer { session in
        let (_, missing) = try await serverData(from: session.url(path: "/static/absent.bin"))
        #expect(try statusCode(from: missing) == 404)

        var post = URLRequest(url: session.url(path: "/"))
        post.httpMethod = "POST"
        let (_, postResponse) = try await serverData(for: post)
        #expect(try statusCode(from: postResponse) == 404)
      }
    }
  }

#endif
