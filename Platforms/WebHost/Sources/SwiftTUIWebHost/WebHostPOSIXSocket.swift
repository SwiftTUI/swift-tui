#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Blocking POSIX socket primitives for the loopback WebHost server.
///
/// Every function here is a thin, `unsafe`-annotated wrapper over one libc
/// call, in the same style as `TerminalPOSIXController`. All blocking calls
/// are made from dedicated `Thread`s only — never from a Swift concurrency
/// executor, where a blocked worker can pin the whole cooperative pool on
/// narrow machines.
enum WebHostPOSIXSocket {
  enum PollOutcome: Equatable {
    case ready
    case timedOut
    case failed(errno: Int32)
    case invalidDescriptor
  }

  static func createTCPSocket() -> Int32 {
    #if canImport(Darwin)
      let fd = socket(AF_INET, SOCK_STREAM, 0)
    #else
      let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    #endif
    guard fd >= 0 else {
      return fd
    }
    var enable: Int32 = 1
    _ = unsafe withUnsafePointer(to: &enable) { pointer in
      unsafe setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, pointer, socklen_t(MemoryLayout<Int32>.size))
    }
    configureNoSignalPipe(fd)
    return fd
  }

  /// Writes to a socket whose peer already closed raise `SIGPIPE` by default,
  /// which would kill the host process outright. Darwin suppresses it per
  /// descriptor; Linux suppresses it per `send` call via `MSG_NOSIGNAL`.
  static func configureNoSignalPipe(
    _ fd: Int32
  ) {
    #if canImport(Darwin)
      var enable: Int32 = 1
      _ = unsafe withUnsafePointer(to: &enable) { pointer in
        unsafe setsockopt(
          fd, SOL_SOCKET, SO_NOSIGPIPE, pointer, socklen_t(MemoryLayout<Int32>.size))
      }
    #endif
  }

  /// Binds and listens on `bind`:`port`. Returns `nil` on failure with the
  /// captured `errno`; throws nothing so callers own error shaping.
  static func bindAndListen(
    _ fd: Int32,
    bind bindAddress: String,
    port: UInt16
  ) -> (success: Bool, failureErrno: Int32, invalidAddress: Bool) {
    var address = sockaddr_in()
    #if canImport(Darwin)
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port.bigEndian)

    let converted = unsafe bindAddress.withCString { pointer in
      unsafe inet_pton(AF_INET, pointer, &address.sin_addr)
    }
    guard converted == 1 else {
      return (false, 0, true)
    }

    let bound = unsafe withUnsafePointer(to: &address) { pointer in
      unsafe systemBind(
        fd,
        unsafe UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        socklen_t(MemoryLayout<sockaddr_in>.size)
      )
    }
    guard bound == 0 else {
      return (false, errno, false)
    }
    guard listen(fd, 16) == 0 else {
      return (false, errno, false)
    }
    return (true, 0, false)
  }

  static func boundPort(
    _ fd: Int32
  ) -> Int? {
    var address = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = unsafe withUnsafeMutablePointer(to: &address) { pointer in
      unsafe getsockname(
        fd,
        unsafe UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        &length
      )
    }
    guard result == 0 else {
      return nil
    }
    return Int(UInt16(bigEndian: address.sin_port))
  }

  static func poll(
    _ fd: Int32,
    events: Int16,
    timeoutMilliseconds: Int32
  ) -> PollOutcome {
    while true {
      var descriptor = pollfd(fd: fd, events: events, revents: 0)
      let ready = unsafe systemPoll(&descriptor, 1, timeoutMilliseconds)
      if ready > 0 {
        if descriptor.revents & Int16(POLLNVAL) != 0 {
          return .invalidDescriptor
        }
        return .ready
      }
      if ready == 0 {
        return .timedOut
      }
      if errno == EINTR {
        continue
      }
      return .failed(errno: errno)
    }
  }

  static func accept(
    _ fd: Int32
  ) -> Int32 {
    systemAccept(fd, nil, nil)
  }

  /// One blocking `recv`. Returns read count; `0` means orderly shutdown, and
  /// `-1` a failure other than `EINTR` (which retries internally).
  static func receive(
    _ fd: Int32,
    into buffer: inout [UInt8]
  ) -> Int {
    while true {
      let readCount = unsafe buffer.withUnsafeMutableBufferPointer { storage in
        unsafe recv(fd, storage.baseAddress, storage.count, 0)
      }
      if readCount >= 0 {
        return readCount
      }
      if errno == EINTR {
        continue
      }
      return -1
    }
  }

  /// Writes the full buffer, waiting for writability with a bounded poll per
  /// chunk so a stalled peer cannot hold the writer thread forever.
  static func sendAll(
    _ fd: Int32,
    _ bytes: [UInt8],
    pollTimeoutMilliseconds: Int32
  ) -> Bool {
    var offset = 0
    while offset < bytes.count {
      switch poll(fd, events: Int16(POLLOUT), timeoutMilliseconds: pollTimeoutMilliseconds) {
      case .ready:
        break
      case .timedOut, .failed, .invalidDescriptor:
        return false
      }

      let written = unsafe bytes.withUnsafeBufferPointer { storage in
        unsafe send(fd, storage.baseAddress! + offset, bytes.count - offset, noSignalSendFlags)
      }
      if written > 0 {
        offset += written
        continue
      }
      if written < 0, errno == EINTR {
        continue
      }
      return false
    }
    return true
  }

  static func shutdownBoth(
    _ fd: Int32
  ) {
    #if canImport(Darwin)
      _ = shutdown(fd, SHUT_RDWR)
    #else
      _ = shutdown(fd, Int32(SHUT_RDWR))
    #endif
  }

  static func shutdownWrites(
    _ fd: Int32
  ) {
    #if canImport(Darwin)
      _ = shutdown(fd, SHUT_WR)
    #else
      _ = shutdown(fd, Int32(SHUT_WR))
    #endif
  }

  static func close(
    _ fd: Int32
  ) {
    _ = systemClose(fd)
  }
}

#if canImport(Darwin)
  private let noSignalSendFlags: Int32 = 0

  private func systemBind(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Darwin.bind(fd, address, length)
  }

  private func systemAccept(
    _ fd: Int32,
    _ address: UnsafeMutablePointer<sockaddr>?,
    _ length: UnsafeMutablePointer<socklen_t>?
  ) -> Int32 {
    unsafe Darwin.accept(fd, address, length)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: UInt32,
    _ timeout: Int32
  ) -> Int32 {
    unsafe Darwin.poll(descriptors, count, timeout)
  }

  private func systemClose(
    _ fd: Int32
  ) -> Int32 {
    Darwin.close(fd)
  }
#elseif canImport(Glibc)
  private let noSignalSendFlags = Int32(MSG_NOSIGNAL)

  private func systemBind(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Glibc.bind(fd, address, length)
  }

  private func systemAccept(
    _ fd: Int32,
    _ address: UnsafeMutablePointer<sockaddr>?,
    _ length: UnsafeMutablePointer<socklen_t>?
  ) -> Int32 {
    unsafe Glibc.accept(fd, address, length)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: UInt32,
    _ timeout: Int32
  ) -> Int32 {
    unsafe Glibc.poll(descriptors, count, timeout)
  }

  private func systemClose(
    _ fd: Int32
  ) -> Int32 {
    Glibc.close(fd)
  }
#elseif canImport(Android)
  private let noSignalSendFlags = Int32(MSG_NOSIGNAL)

  private func systemBind(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Android.bind(fd, address, length)
  }

  private func systemAccept(
    _ fd: Int32,
    _ address: UnsafeMutablePointer<sockaddr>?,
    _ length: UnsafeMutablePointer<socklen_t>?
  ) -> Int32 {
    unsafe Android.accept(fd, address, length)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: UInt32,
    _ timeout: Int32
  ) -> Int32 {
    unsafe Android.poll(descriptors, count, timeout)
  }

  private func systemClose(
    _ fd: Int32
  ) -> Int32 {
    Android.close(fd)
  }
#elseif canImport(Musl)
  private let noSignalSendFlags = Int32(MSG_NOSIGNAL)

  private func systemBind(
    _ fd: Int32,
    _ address: UnsafePointer<sockaddr>,
    _ length: socklen_t
  ) -> Int32 {
    unsafe Musl.bind(fd, address, length)
  }

  private func systemAccept(
    _ fd: Int32,
    _ address: UnsafeMutablePointer<sockaddr>?,
    _ length: UnsafeMutablePointer<socklen_t>?
  ) -> Int32 {
    unsafe Musl.accept(fd, address, length)
  }

  private func systemPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>,
    _ count: UInt32,
    _ timeout: Int32
  ) -> Int32 {
    unsafe Musl.poll(descriptors, count, timeout)
  }

  private func systemClose(
    _ fd: Int32
  ) -> Int32 {
    Musl.close(fd)
  }
#endif
