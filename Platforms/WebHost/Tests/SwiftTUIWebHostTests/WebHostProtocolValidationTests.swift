import Foundation
import Testing

@testable import SwiftTUIWebHost

@Suite struct WebHostProtocolValidationTests {
  @Test func httpDelimitersAreOctetsBesideCombiningScalars() throws {
    let text = "GET /?key=\u{0301}value HTTP/1.1\r\nHost: localhost\r\nX-Value:\u{0301}text\r\n\r\n"
    let head = try #require(WebHostHTTPRequestHead.parse(headBytes: Array(text.utf8)))
    #expect(head.query["key"] == "\u{0301}value")
    #expect(head.headerValue("X-Value") == "\u{0301}text")
  }

  @Test(arguments: [
    "GET / HTTP/1.1\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\r\nHOST: b\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\r\nX: a\u{0000}b\r\n\r\n",
    "GET / HTTP/1.1\r\nHost: a\r\n folded: b\r\n\r\n",
    "GET /#fragment HTTP/1.1\r\nHost: a\r\n\r\n",
    "GET /%zz HTTP/1.1\r\nHost: a\r\n\r\n",
  ]) func invalidRequestHeadsAreRejected(_ request: String) {
    #expect(WebHostHTTPRequestHead.parse(headBytes: Array(request.utf8)) == nil)
  }

  @Test(arguments: [[UInt8(3)], [3, 237], [3, 232, 255]])
  func invalidCloseBodiesAreRejected(_ payload: [UInt8]) {
    var assembler = WebHostWebSocketWire.MessageAssembler(maxMessageBytes: 1024)
    #expect(throws: WebHostWebSocketWire.AssemblyError.invalidClosePayload) {
      try assembler.assemble(.init(fin: true, opcode: .close, payload: payload))
    }
  }

  @Test func longLengthMustAlsoBeMinimal() {
    var decoder = WebHostWebSocketWire.FrameDecoder()
    decoder.append([0x82, 0xff, 0, 0, 0, 0, 0, 0, 0xff, 0xff])
    #expect(throws: WebHostWebSocketWire.DecodeError.nonMinimalPayloadLength) {
      try decoder.nextFrame()
    }
  }

  @Test func wildcardOriginMatchesTheRequestAuthority() {
    let policy = WebHostOriginPolicy(bind: "0.0.0.0")
    #expect(
      policy.allows(
        origin: "http://192.168.1.20:9123", port: 9123,
        requestAuthority: "192.168.1.20:9123"))
    #expect(
      !policy.allows(
        origin: "http://192.168.1.21:9123", port: 9123,
        requestAuthority: "192.168.1.20:9123"))
    #expect(
      !policy.allows(
        origin: "http://evil.example:9123", port: 9123,
        requestAuthority: "192.168.1.20:9123"))
    #expect(!policy.allows(origin: "http://user@localhost:9123", port: 9123))
  }
}
