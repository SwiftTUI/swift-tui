#if os(Windows)
  import WinSDK

  typealias WebHostSocketDescriptor = SOCKET

  /// Winsock counterpart of the dedicated-thread POSIX transport. SOCKET is
  /// pointer-sized; it must never pass through a CRT file descriptor or Int32.
  enum WebHostSocket {
    enum PollOutcome: Equatable {
      case ready
      case timedOut
      case failed(errno: Int32)
      case invalidDescriptor
    }

    static let invalidDescriptor = SOCKET.max
    static let readEvents = Int16(POLLRDNORM)
    static let writeEvents = Int16(POLLWRNORM)
    static var lastError: Int32 { WSAGetLastError() }
    static func isValid(_ fd: SOCKET) -> Bool { fd != invalidDescriptor }

    // Each owned socket retains one Winsock reference. Accepted sockets retain
    // their own reference, so stopping the listener cannot invalidate them.
    private static func retainWinsock() -> Bool {
      var data = unsafe WSADATA()
      let result = unsafe WSAStartup(0x0202, &data)
      guard result == 0 else {
        WSASetLastError(result)
        return false
      }
      return true
    }

    static func createTCPSocket() -> SOCKET {
      guard retainWinsock() else { return invalidDescriptor }
      let fd = WinSDK.socket(AF_INET, SOCK_STREAM, Int32(IPPROTO_TCP.rawValue))
      guard isValid(fd) else {
        let code = lastError
        _ = WSACleanup()
        WSASetLastError(code)
        return invalidDescriptor
      }
      // Unlike POSIX SO_REUSEADDR, Windows reuse can let a second process take
      // an occupied endpoint. Reserve this listener exclusively instead.
      var enabled: Int32 = 1
      let result = withUnsafePointer(to: &enabled) { pointer in
        unsafe setsockopt(
          fd, SOL_SOCKET, ~Int32(SO_REUSEADDR),
          UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self),
          Int32(MemoryLayout<Int32>.size))
      }
      guard result == 0 else {
        let code = lastError
        close(fd)
        WSASetLastError(code)
        return invalidDescriptor
      }
      return fd
    }

    static func configureNoSignalPipe(_ fd: SOCKET) {}

    private static func address(_ host: String, port: UInt16) -> SOCKADDR_IN? {
      var address = SOCKADDR_IN()
      address.sin_family = ADDRESS_FAMILY(AF_INET)
      address.sin_port = port.bigEndian
      guard host.withCString({ unsafe inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
        return nil
      }
      return address
    }

    static func bindAndListen(_ fd: SOCKET, bind host: String, port: UInt16)
      -> (success: Bool, failureErrno: Int32, invalidAddress: Bool)
    {
      guard var address = address(host, port: port) else { return (false, 0, true) }
      let result = withUnsafePointer(to: &address) { pointer in
        unsafe WinSDK.bind(
          fd, UnsafeRawPointer(pointer).assumingMemoryBound(to: SOCKADDR.self),
          Int32(MemoryLayout<SOCKADDR_IN>.size))
      }
      guard result == 0, listen(fd, 16) == 0 else { return (false, lastError, false) }
      return (true, 0, false)
    }

    static func connect(_ fd: SOCKET, host: String, port: UInt16) -> Bool {
      guard var address = address(host, port: port) else { return false }
      return withUnsafePointer(to: &address) { pointer in
        unsafe WinSDK.connect(
          fd, UnsafeRawPointer(pointer).assumingMemoryBound(to: SOCKADDR.self),
          Int32(MemoryLayout<SOCKADDR_IN>.size)) == 0
      }
    }

    static func boundPort(_ fd: SOCKET) -> Int? {
      var address = SOCKADDR_IN()
      var length = Int32(MemoryLayout<SOCKADDR_IN>.size)
      let result = withUnsafeMutablePointer(to: &address) { pointer in
        unsafe getsockname(
          fd, UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: SOCKADDR.self), &length)
      }
      return result == 0 ? Int(UInt16(bigEndian: address.sin_port)) : nil
    }

    static func poll(_ fd: SOCKET, events: Int16, timeoutMilliseconds: Int32) -> PollOutcome {
      while true {
        var descriptor = WSAPOLLFD(fd: fd, events: events, revents: 0)
        let ready = unsafe WSAPoll(&descriptor, 1, timeoutMilliseconds)
        if ready > 0 {
          return descriptor.revents & Int16(POLLNVAL) != 0 ? .invalidDescriptor : .ready
        }
        if ready == 0 { return .timedOut }
        if lastError == WSAEINTR { continue }
        return .failed(errno: lastError)
      }
    }

    static func accept(_ fd: SOCKET) -> SOCKET {
      let client = WinSDK.accept(fd, nil, nil)
      guard isValid(client) else { return invalidDescriptor }
      guard retainWinsock() else {
        _ = closesocket(client)
        return invalidDescriptor
      }
      return client
    }

    static func receive(_ fd: SOCKET, into buffer: inout [UInt8]) -> Int {
      while true {
        let count = buffer.withUnsafeMutableBytes { bytes in
          unsafe recv(
            fd, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(bytes.count), 0)
        }
        if count >= 0 { return Int(count) }
        if lastError != WSAEINTR { return -1 }
      }
    }

    static func sendAll(_ fd: SOCKET, _ bytes: [UInt8], pollTimeoutMilliseconds: Int32) -> Bool {
      var offset = 0
      while offset < bytes.count {
        guard poll(fd, events: writeEvents, timeoutMilliseconds: pollTimeoutMilliseconds) == .ready
        else { return false }
        let written = bytes.withUnsafeBytes { storage in
          unsafe send(
            fd, (storage.baseAddress! + offset).assumingMemoryBound(to: CChar.self),
            Int32(min(bytes.count - offset, Int(Int32.max))), 0)
        }
        if written > 0 {
          offset += Int(written)
          continue
        }
        if written < 0, lastError == WSAEINTR { continue }
        return false
      }
      return true
    }

    static func shutdownBoth(_ fd: SOCKET) { _ = shutdown(fd, SD_BOTH) }
    static func shutdownWrites(_ fd: SOCKET) { _ = shutdown(fd, SD_SEND) }
    static func close(_ fd: SOCKET) {
      guard isValid(fd) else { return }
      _ = closesocket(fd)
      _ = WSACleanup()
    }
  }
#endif
