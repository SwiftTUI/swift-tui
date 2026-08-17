// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  import Foundation

  /// A parsed HTTP/1.1 request head: the request line plus headers, without any
  /// body. The loopback server answers `GET`s and WebSocket upgrades only, and
  /// closes the connection after every plain response, so the head is all it
  /// ever reads.
  struct WebHostHTTPRequestHead: Equatable, Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [(name: String, value: String)]

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.method == rhs.method && lhs.path == rhs.path && lhs.query == rhs.query
        && lhs.headers.elementsEqual(rhs.headers, by: ==)
    }

    func headerValue(
      _ name: String
    ) -> String? {
      headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Parses one request head from the bytes up to (and including) the blank
    /// line. Returns `nil` for anything malformed; the caller answers with 400.
    static func parse(
      headBytes: [UInt8]
    ) -> WebHostHTTPRequestHead? {
      let text = String(decoding: headBytes, as: UTF8.self)
      var lines = text.components(separatedBy: "\r\n")
      guard !lines.isEmpty else {
        return nil
      }
      let requestLine = lines.removeFirst()
      let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
      guard requestParts.count == 3, !requestParts[0].isEmpty,
        requestParts[2].hasPrefix("HTTP/1.")
      else {
        return nil
      }

      let target = String(requestParts[1])
      var path = target
      var query: [String: String] = [:]
      if let separatorIndex = target.firstIndex(of: "?") {
        path = String(target[..<separatorIndex])
        let queryText = String(target[target.index(after: separatorIndex)...])
        for pair in queryText.split(separator: "&") {
          let keyValue = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
          guard let key = String(keyValue[0]).removingPercentEncoding else {
            continue
          }
          let value =
            keyValue.count == 2
            ? (String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1]))
            : ""
          query[key] = value
        }
      }
      guard let decodedPath = path.removingPercentEncoding else {
        return nil
      }

      var headers: [(name: String, value: String)] = []
      for line in lines {
        if line.isEmpty {
          break
        }
        guard let colonIndex = line.firstIndex(of: ":") else {
          return nil
        }
        let name = String(line[..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])
          .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
          return nil
        }
        headers.append((name, value))
      }

      return WebHostHTTPRequestHead(
        method: String(requestParts[0]),
        path: decodedPath,
        query: query,
        headers: headers
      )
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
#endif
