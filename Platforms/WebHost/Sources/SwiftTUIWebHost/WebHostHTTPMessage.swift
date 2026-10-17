import Foundation

/// A parsed HTTP/1.1 request head: the request line plus headers, without any
/// body. The loopback server answers `GET`s and WebSocket upgrades only, and
/// closes the connection after every plain response, so the head is all it
/// ever reads.
struct WebHostHTTPRequestHead: Equatable, Sendable {
  var method: String
  var version: String = "HTTP/1.1"
  var path: String
  var query: [String: String]
  var headers: [(name: String, value: String)]

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.method == rhs.method && lhs.version == rhs.version && lhs.path == rhs.path
      && lhs.query == rhs.query
      && lhs.headers.elementsEqual(rhs.headers, by: ==)
  }

  func headerValue(
    _ name: String
  ) -> String? {
    headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  func headerValues(_ name: String) -> [String] {
    headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
  }

  func containsHeaderToken(_ name: String, token: String) -> Bool {
    headerValues(name).flatMap { $0.split(separator: ",") }.contains {
      $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        .caseInsensitiveCompare(token) == .orderedSame
    }
  }

  var hasDuplicateSingletonHeaders: Bool {
    ["Host", "Origin", "Sec-WebSocket-Key", "Sec-WebSocket-Version"].contains {
      headerValues($0).count > 1
    }
  }

  private static func isTokenByte(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
      || "!#$%&'*+-.^_`|~".utf8.contains(byte)
  }

  /// Parses one request head from the bytes up to (and including) the blank
  /// line. Returns `nil` for anything malformed; the caller answers with 400.
  static func parse(
    headBytes: [UInt8]
  ) -> WebHostHTTPRequestHead? {
    // Delimiters are wire octets. Unicode grapheme segmentation must never
    // hide an ASCII colon, space or line boundary beside a combining scalar.
    guard headBytes.suffix(4).elementsEqual([13, 10, 13, 10]) else { return nil }
    let rawLines = headBytes.split(separator: 10, omittingEmptySubsequences: false)
    guard rawLines.last?.isEmpty == true,
      rawLines.dropLast().allSatisfy({ $0.last == 13 })
    else { return nil }
    let lines = rawLines.dropLast().map { $0.dropLast() }
    guard let requestLine = lines.first else { return nil }
    let parts = requestLine.split(separator: 32, omittingEmptySubsequences: false)
    guard parts.count == 3, !parts[0].isEmpty, parts[0].allSatisfy(isTokenByte),
      parts[1].first == 47, parts[1].allSatisfy({ $0 > 32 && $0 != 127 && $0 != 35 }),
      parts[2].elementsEqual("HTTP/1.1".utf8) || parts[2].elementsEqual("HTTP/1.0".utf8)
    else { return nil }

    func decoded(_ bytes: ArraySlice<UInt8>) -> String? {
      String(bytes: bytes, encoding: .utf8)?.removingPercentEncoding
    }
    let target = parts[1].split(separator: 63, maxSplits: 1, omittingEmptySubsequences: false)
    guard let path = decoded(target[0]) else { return nil }
    var query: [String: String] = [:]
    if target.count == 2 {
      for pair in target[1].split(separator: 38) {
        let fields = pair.split(separator: 61, maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = decoded(fields[0]),
          let value = fields.count == 2 ? decoded(fields[1]) : ""
        else { return nil }
        query[key] = value
      }
    }

    var headers: [(name: String, value: String)] = []
    for line in lines.dropFirst().dropLast() {
      guard let colon = line.firstIndex(of: 58) else { return nil }
      let name = line[..<colon]
      var value = line[line.index(after: colon)...]
      guard !name.isEmpty, name.allSatisfy(isTokenByte),
        value.allSatisfy({ $0 == 9 || ($0 >= 32 && $0 != 127) })
      else { return nil }
      while value.first == 32 || value.first == 9 { value = value.dropFirst() }
      while value.last == 32 || value.last == 9 { value = value.dropLast() }
      // Field values may contain opaque obs-text octets; protocol-specific
      // consumers still validate their own ASCII/base64 grammar.
      guard
        let field = String(bytes: value, encoding: .utf8)
          ?? String(bytes: value, encoding: .isoLatin1)
      else { return nil }
      headers.append((String(decoding: name, as: UTF8.self), field))
    }
    let result = WebHostHTTPRequestHead(
      method: String(decoding: parts[0], as: UTF8.self),
      version: String(decoding: parts[2], as: UTF8.self), path: path, query: query, headers: headers
    )
    guard !result.hasDuplicateSingletonHeaders else { return nil }
    if result.version == "HTTP/1.1", result.headerValue("Host")?.isEmpty != false { return nil }
    return result
  }

}

/// A response the loopback server writes and then closes the connection —
/// except for `101`, which hands the socket over to the WebSocket session.
struct WebHostHTTPResponse: Equatable, Sendable {
  var status: Int
  var reason: String
  var headers: [(name: String, value: String)]
  var body: [UInt8]

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.status == rhs.status && lhs.reason == rhs.reason && lhs.body == rhs.body
      && lhs.headers.elementsEqual(rhs.headers, by: ==)
  }

  init(
    status: Int,
    reason: String,
    headers: [(name: String, value: String)] = [],
    body: [UInt8] = []
  ) {
    self.status = status
    self.reason = reason
    self.headers = headers
    self.body = body
  }

  static func ok(
    body: [UInt8],
    contentType: String
  ) -> WebHostHTTPResponse {
    WebHostHTTPResponse(
      status: 200,
      reason: "OK",
      headers: [("Content-Type", contentType)],
      body: body
    )
  }

  static func forbidden() -> WebHostHTTPResponse {
    WebHostHTTPResponse(
      status: 403,
      reason: "Forbidden",
      headers: [("Content-Type", "text/plain; charset=utf-8")],
      body: Array("Forbidden\n".utf8)
    )
  }

  static func notFound() -> WebHostHTTPResponse {
    WebHostHTTPResponse(
      status: 404,
      reason: "Not Found",
      headers: [("Content-Type", "text/plain; charset=utf-8")],
      body: Array("Not Found\n".utf8)
    )
  }

  static func badRequest() -> WebHostHTTPResponse {
    WebHostHTTPResponse(
      status: 400,
      reason: "Bad Request",
      headers: [("Content-Type", "text/plain; charset=utf-8")],
      body: Array("Bad Request\n".utf8)
    )
  }

  /// Serialized wire form. Plain responses always carry `Connection: close` —
  /// one request per connection keeps the server free of keep-alive timers and
  /// pipelining; on loopback the reconnect cost is negligible. `101` carries
  /// its own `Connection: Upgrade` header instead, and no length.
  func serialized() -> [UInt8] {
    var head = "HTTP/1.1 \(status) \(reason)\r\n"
    for header in headers {
      head += "\(header.name): \(header.value)\r\n"
    }
    if status != 101 {
      head += "Content-Length: \(body.count)\r\n"
      head += "Connection: close\r\n"
    }
    head += "\r\n"
    return Array(head.utf8) + body
  }
}
