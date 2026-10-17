#if !canImport(WASILibc) && !os(Windows)
  import SwiftTUIPlatformIO

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  /// One request and one response per connection. Socket reads and writes may
  /// split at any byte; only LF completes a record. Limits include that LF.
  enum SocketLineFraming {
    static let requestLimit = 4096
    static let responseLimit = 4 * 1024 * 1024

    enum Failure: Error { case incomplete, oversized, invalidUTF8 }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
      scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
        || scalar.value == 0x2028 || scalar.value == 0x2029
    }

    static func escapedMessage(_ message: String) -> String {
      message.unicodeScalars.map { scalar in
        isControl(scalar) ? "\\u{" + String(scalar.value, radix: 16) + "}" : String(scalar)
      }.joined()
    }

    static func readRequest(fd: Int32) async throws -> String? {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      var received: [UInt8] = []
      var buffer = [UInt8](repeating: 0, count: requestLimit)
      while !Task.isCancelled && ContinuousClock.now < deadline {
        let count = unsafe sceneRead(fd, &buffer, min(buffer.count, requestLimit - received.count))
        if count > 0 {
          let chunk = buffer.prefix(count)
          if let newline = chunk.firstIndex(of: 10) {
            received.append(contentsOf: chunk[...newline])
            guard let line = String(validating: received, as: UTF8.self) else {
              throw Failure.invalidUTF8
            }
            return line
          }
          received.append(contentsOf: chunk)
          guard received.count < requestLimit else { throw Failure.oversized }
        } else if count == 0 {
          if received.isEmpty { return nil }  // A liveness probe has no request.
          throw Failure.incomplete
        } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
          throw Failure.incomplete
        } else {
          try await Task.sleep(for: .milliseconds(5))
        }
      }
      throw Failure.incomplete
    }

    static func writeResponse(_ response: String, fd: Int32) async {
      let bytes = Array(
        (response.utf8.count <= responseLimit ? response : "ERR Response exceeds limit\n").utf8)
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      var offset = 0
      while offset < bytes.count && !Task.isCancelled && ContinuousClock.now < deadline {
        let written = bytes.withUnsafeBytes { buffer in
          unsafe sceneWrite(fd, buffer.baseAddress?.advanced(by: offset), bytes.count - offset)
        }
        if written > 0 {
          offset += written
        } else if written < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
          try? await Task.sleep(for: .milliseconds(5))
        } else {
          return
        }
      }
    }
  }
#endif
