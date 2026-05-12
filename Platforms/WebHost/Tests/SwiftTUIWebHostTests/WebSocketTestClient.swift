import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

final class WebSocketTestClient {
  private var fileDescriptor: Int32
  private var bufferedBytes: [UInt8]

  private init(fileDescriptor: Int32, bufferedBytes: [UInt8]) {
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

  func close() {
    guard fileDescriptor >= 0 else { return }
    socketClose(fileDescriptor)
    fileDescriptor = -1
  }

  private static func openSocket(to url: URL) throws -> Int32 {
    guard let host = url.host,
      let port = url.port
    else {
      throw WebSocketTestClientError.invalidURL
    }

    let fd = socket(AF_INET, webSocketStreamType, 0)
    guard fd >= 0 else {
      throw WebSocketTestClientError.posix(errno)
    }

    var address = sockaddr_in()
    #if canImport(Darwin)
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)

    guard
      unsafe host.withCString({ unsafe socketInetPton(AF_INET, $0, &address.sin_addr) })
        == 1
    else {
      socketClose(fd)
      throw WebSocketTestClientError.invalidURL
    }

    let result = unsafe withUnsafePointer(to: &address) { pointer in
      unsafe socketConnect(
        fd,
        unsafe UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        socklen_t(MemoryLayout<sockaddr_in>.size)
      )
    }
    guard result == 0 else {
      let failureErrno = errno
      socketClose(fd)
      throw WebSocketTestClientError.posix(failureErrno)
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
    let statusLine =
      try responseText
      .components(separatedBy: "\r\n")
      .first
      .requireValue(or: WebSocketTestClientError.invalidHTTPResponse)
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
      var buffer = [UInt8](repeating: 0, count: 4096)
      let readCount = unsafe buffer.withUnsafeMutableBufferPointer { storage in
        unsafe recv(fileDescriptor, storage.baseAddress, storage.count, 0)
      }
      if readCount > 0 {
        bufferedBytes.append(contentsOf: buffer.prefix(Int(readCount)))
        continue
      }
      if readCount == 0 {
        throw WebSocketTestClientError.connectionClosed
      }
      if errno == EINTR {
        continue
      }
      throw WebSocketTestClientError.posix(errno)
    }

    let result = Array(bufferedBytes.prefix(count))
    bufferedBytes.removeFirst(count)
    return result
  }

  private func writeAll(_ bytes: [UInt8]) throws {
    var offset = 0
    while offset < bytes.count {
      let written = unsafe bytes.withUnsafeBufferPointer { storage in
        unsafe send(
          fileDescriptor,
          storage.baseAddress! + offset,
          bytes.count - offset,
          webSocketNoSignalFlag
        )
      }
      if written > 0 {
        offset += written
        continue
      }
      if errno == EINTR {
        continue
      }
      throw WebSocketTestClientError.posix(errno)
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
  case posix(Int32)
  case unexpectedStatus(Int)
  case unsupportedLength
  case unsupportedOpcode(UInt8)

  var description: String {
    switch self {
    case .connectionClosed:
      "WebSocket connection closed"
    case .invalidHTTPResponse:
      "Invalid HTTP upgrade response"
    case .invalidURL:
      "Invalid WebSocket URL"
    case .posix(let code):
      "POSIX error \(code)"
    case .unexpectedStatus(let status):
      "Unexpected HTTP status \(status)"
    case .unsupportedLength:
      "Unsupported WebSocket frame length"
    case .unsupportedOpcode(let opcode):
      "Unsupported WebSocket opcode \(opcode)"
    }
  }
}

private func webSocketRequestPath(for url: URL) -> String {
  var path = url.path.isEmpty ? "/" : url.path
  if let query = url.query(percentEncoded: true), !query.isEmpty {
    path += "?\(query)"
  }
  return path
}

extension Optional {
  fileprivate func requireValue(or error: any Error) throws -> Wrapped {
    guard let value = self else { throw error }
    return value
  }
}

#if canImport(Darwin)
  private let webSocketStreamType = SOCK_STREAM
  private let webSocketNoSignalFlag: Int32 = 0

  private func socketClose(_ fd: Int32) {
    Darwin.close(fd)
  }

  private func socketConnect(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Darwin.connect(fd, address, length)
  }

  private func socketInetPton(
    _ family: Int32,
    _ source: UnsafePointer<CChar>?,
    _ destination: UnsafeMutableRawPointer?
  ) -> Int32 {
    unsafe Darwin.inet_pton(family, source, destination)
  }
#elseif canImport(Glibc)
  private let webSocketStreamType = Int32(SOCK_STREAM.rawValue)
  private let webSocketNoSignalFlag: Int32 = Int32(MSG_NOSIGNAL)

  private func socketClose(_ fd: Int32) {
    Glibc.close(fd)
  }

  private func socketConnect(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Glibc.connect(fd, address, length)
  }

  private func socketInetPton(
    _ family: Int32,
    _ source: UnsafePointer<CChar>?,
    _ destination: UnsafeMutableRawPointer?
  ) -> Int32 {
    unsafe Glibc.inet_pton(family, source, destination)
  }
#endif
