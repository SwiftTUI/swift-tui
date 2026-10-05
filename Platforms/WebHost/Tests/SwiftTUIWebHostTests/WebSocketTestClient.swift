import Foundation

@testable import SwiftTUIWebHost

final class WebSocketTestClient {
  private var fileDescriptor: WebHostSocketDescriptor
  private var bufferedBytes: [UInt8]

  private init(fileDescriptor: WebHostSocketDescriptor, bufferedBytes: [UInt8]) {
    self.fileDescriptor = fileDescriptor
    self.bufferedBytes = bufferedBytes
  }

  deinit {
    close()
  }

  static func connect(
    to url: URL,
    headers: [(String, String)] = []
  ) throws -> WebSocketTestClient {
    let fileDescriptor = try openSocket(to: url)
    let client = WebSocketTestClient(fileDescriptor: fileDescriptor, bufferedBytes: [])

    do {
      try client.writeHandshake(to: url, headers: headers)
      let response = try client.readHTTPResponse()
      guard response.statusCode == 101 else {
        throw WebSocketTestClientError.unexpectedStatus(response.statusCode)
      }
      return client
    } catch {
      client.close()
      throw error
    }
  }

  static func requestUpgradeStatus(
    to url: URL,
    headers: [(String, String)] = []
  ) throws -> Int {
    let fileDescriptor = try openSocket(to: url)
    let client = WebSocketTestClient(fileDescriptor: fileDescriptor, bufferedBytes: [])
    defer { client.close() }

    try client.writeHandshake(to: url, headers: headers)
    return try client.readHTTPResponse().statusCode
  }

  func receiveMessage() throws -> Data {
    let first = try readByte()
    let second = try readByte()
    let opcode = first & 0x0f
    guard opcode == 0x1 || opcode == 0x2 else {
      throw WebSocketTestClientError.unsupportedOpcode(opcode)
    }

    var length = Int(second & 0x7f)
    if length == 126 {
      let bytes = try readBytes(count: 2)
      length = (Int(bytes[0]) << 8) | Int(bytes[1])
    } else if length == 127 {
      throw WebSocketTestClientError.unsupportedLength
    }

    return Data(try readBytes(count: length))
  }

  func sendBinary(_ data: Data) throws {
    let bytes = Array(data)
    guard bytes.count < 126 else {
      throw WebSocketTestClientError.unsupportedLength
    }

    let mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]
    var frame: [UInt8] = [0x82, 0x80 | UInt8(bytes.count)]
    frame.append(contentsOf: mask)
    for (index, byte) in bytes.enumerated() {
      frame.append(byte ^ mask[index % mask.count])
    }
    try writeAll(frame)
  }

  /// One masked frame with explicit fin/opcode, for protocol-level tests
  /// (fragmentation, ping, close). Payloads stay under the 126 length path.
  func sendFrame(
    opcode: UInt8,
    fin: Bool,
    payload: [UInt8]
  ) throws {
    guard payload.count < 126 else {
      throw WebSocketTestClientError.unsupportedLength
    }

    let mask: [UInt8] = [0x9A, 0xBC, 0xDE, 0xF0]
    var frame: [UInt8] = [(fin ? 0x80 : 0x00) | opcode, 0x80 | UInt8(payload.count)]
    frame.append(contentsOf: mask)
    for (index, byte) in payload.enumerated() {
      frame.append(byte ^ mask[index % mask.count])
    }
    try writeAll(frame)
  }

  /// A masked frame header *claiming* `declaredLength` bytes of payload while
  /// sending none — lets a test exercise the server's header-time size refusal
  /// without shipping the oversized payload.
  func sendFrameHeaderClaiming(
    declaredLength: UInt64,
    opcode: UInt8
  ) throws {
    var frame: [UInt8] = [0x80 | opcode, 0x80 | 127]
    for shift in stride(from: 56, through: 0, by: -8) {
      frame.append(UInt8(truncatingIfNeeded: declaredLength >> UInt64(shift)))
    }
    frame.append(contentsOf: [0x9A, 0xBC, 0xDE, 0xF0])
    try writeAll(frame)
  }

  /// Reads one frame of any opcode. `receiveMessage()` remains the
  /// data-frame-only strict variant existing tests use.
  func receiveFrame() throws -> (opcode: UInt8, payload: Data) {
    let first = try readByte()
    let second = try readByte()
    let opcode = first & 0x0f

    var length = Int(second & 0x7f)
    if length == 126 {
      let bytes = try readBytes(count: 2)
      length = (Int(bytes[0]) << 8) | Int(bytes[1])
    } else if length == 127 {
      throw WebSocketTestClientError.unsupportedLength
    }

    return (opcode, Data(try readBytes(count: length)))
  }

  func close() {
    guard WebHostSocket.isValid(fileDescriptor) else { return }
    WebHostSocket.close(fileDescriptor)
    fileDescriptor = WebHostSocket.invalidDescriptor
  }

  private static func openSocket(to url: URL) throws -> WebHostSocketDescriptor {
    guard let host = url.host,
      let port = url.port
    else {
      throw WebSocketTestClientError.invalidURL
    }

    let fd = WebHostSocket.createTCPSocket()
    guard WebHostSocket.isValid(fd) else {
      throw WebSocketTestClientError.socket(WebHostSocket.lastError)
    }
    guard WebHostSocket.connect(fd, host: host, port: UInt16(port)) else {
      let code = WebHostSocket.lastError
      WebHostSocket.close(fd)
      throw WebSocketTestClientError.socket(code)
    }

    return fd
  }

  private func writeHandshake(
    to url: URL,
    headers: [(String, String)]
  ) throws {
    let path = webSocketRequestPath(for: url)
    let host = url.host ?? "127.0.0.1"
    let port = url.port.map { ":\($0)" } ?? ""
    var lines = [
      "GET \(path) HTTP/1.1",
      "Host: \(host)\(port)",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
      "Sec-WebSocket-Version: 13",
    ]
    lines.append(contentsOf: headers.map { "\($0.0): \($0.1)" })
    lines.append("")
    lines.append("")
    try writeAll(Array(lines.joined(separator: "\r\n").utf8))
  }

  private func readHTTPResponse() throws -> HTTPUpgradeResponse {
    var bytes: [UInt8] = []
    while Array(bytes.suffix(4)) != [13, 10, 13, 10] {
      bytes.append(try readByte())
    }

    let responseText = String(decoding: bytes, as: UTF8.self)
    guard let statusLine = responseText.components(separatedBy: "\r\n").first else {
      throw WebSocketTestClientError.invalidHTTPResponse
    }
    let parts = statusLine.split(separator: " ")
    guard parts.count >= 2, let statusCode = Int(parts[1]) else {
      throw WebSocketTestClientError.invalidHTTPResponse
    }
    return HTTPUpgradeResponse(statusCode: statusCode)
  }

  private func readByte() throws -> UInt8 {
    try readBytes(count: 1)[0]
  }

  private func readBytes(count: Int) throws -> [UInt8] {
    while bufferedBytes.count < count {
      try waitUntilReady(
        WebHostSocket.readEvents,
        timeoutError: .readTimedOut(webSocketIOTimeoutMilliseconds)
      )

      var buffer = [UInt8](repeating: 0, count: 4096)
      let readCount = WebHostSocket.receive(fileDescriptor, into: &buffer)
      if readCount > 0 {
        bufferedBytes.append(contentsOf: buffer.prefix(Int(readCount)))
        continue
      }
      if readCount == 0 {
        throw WebSocketTestClientError.connectionClosed
      }
      throw WebSocketTestClientError.socket(WebHostSocket.lastError)
    }

    let result = Array(bufferedBytes.prefix(count))
    bufferedBytes.removeFirst(count)
    return result
  }

  private func writeAll(_ bytes: [UInt8]) throws {
    guard
      WebHostSocket.sendAll(
        fileDescriptor, bytes, pollTimeoutMilliseconds: webSocketIOTimeoutMilliseconds)
    else {
      throw WebSocketTestClientError.writeTimedOut(webSocketIOTimeoutMilliseconds)
    }
  }

  private func waitUntilReady(
    _ event: Int16,
    timeoutError: WebSocketTestClientError
  ) throws {
    switch WebHostSocket.poll(
      fileDescriptor, events: event, timeoutMilliseconds: webSocketIOTimeoutMilliseconds)
    {
    case .ready: return
    case .timedOut: throw timeoutError
    case .failed(let code): throw WebSocketTestClientError.socket(code)
    case .invalidDescriptor: throw WebSocketTestClientError.connectionClosed
    }
  }
}

private struct HTTPUpgradeResponse {
  var statusCode: Int
}

private enum WebSocketTestClientError: Error, CustomStringConvertible {
  case connectionClosed
  case invalidHTTPResponse
  case invalidURL
  case socket(Int32)
  case readTimedOut(Int32)
  case unexpectedStatus(Int)
  case unsupportedLength
  case unsupportedOpcode(UInt8)
  case writeTimedOut(Int32)

  var description: String {
    switch self {
    case .connectionClosed:
      "WebSocket connection closed"
    case .invalidHTTPResponse:
      "Invalid HTTP upgrade response"
    case .invalidURL:
      "Invalid WebSocket URL"
    case .socket(let code):
      "Socket error \(code)"
    case .readTimedOut(let timeoutMilliseconds):
      "WebSocket read timed out after \(timeoutMilliseconds) ms"
    case .unexpectedStatus(let status):
      "Unexpected HTTP status \(status)"
    case .unsupportedLength:
      "Unsupported WebSocket frame length"
    case .unsupportedOpcode(let opcode):
      "Unsupported WebSocket opcode \(opcode)"
    case .writeTimedOut(let timeoutMilliseconds):
      "WebSocket write timed out after \(timeoutMilliseconds) ms"
    }
  }
}

private let webSocketIOTimeoutMilliseconds: Int32 = 5_000

private func webSocketRequestPath(for url: URL) -> String {
  var path = url.path.isEmpty ? "/" : url.path
  if let query = url.query(percentEncoded: true), !query.isEmpty {
    path += "?\(query)"
  }
  return path
}
