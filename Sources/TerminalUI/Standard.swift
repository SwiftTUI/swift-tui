import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#else
  #error("Unsupported platform: this implementation needs POSIX open/write/close.")
#endif

public enum FileOpenError: Swift.Error, Sendable, CustomStringConvertible {
  case failed(path: String, errno: CInt)

  public var description: String {
    switch self {
    case .failed(let path, let errno):
      return "Failed to open '\(path)' (errno: \(errno))"
    }
  }
}

@inline(__always)
private func systemWrite(
  _ fd: CInt,
  _ buffer: UnsafeRawPointer,
  _ count: Int
) -> Int {
  #if canImport(Darwin)
    unsafe Darwin.write(fd, buffer, count)
  #elseif canImport(Glibc)
    Glibc.write(fd, buffer, count)
  #elseif canImport(Musl)
    Musl.write(fd, buffer, count)
  #endif
}

@inline(__always)
private func systemOpen(
  _ path: UnsafePointer<CChar>,
  _ flags: CInt,
  _ mode: mode_t
) -> CInt {
  #if canImport(Darwin)
    unsafe Darwin.open(path, flags, mode)
  #elseif canImport(Glibc)
    Glibc.open(path, flags, mode)
  #elseif canImport(Musl)
    Musl.open(path, flags, mode)
  #endif
}

@inline(__always)
private func systemClose(_ fd: CInt) -> CInt {
  #if canImport(Darwin)
    Darwin.close(fd)
  #elseif canImport(Glibc)
    Glibc.close(fd)
  #elseif canImport(Musl)
    Musl.close(fd)
  #endif
}

@inline(__always)
private func currentErrno() -> CInt {
  errno
}

@inline(__always)
private func interruptedErrno() -> CInt {
  CInt(EINTR)
}

@inline(__always)
private func appendOpenFlags(create: Bool) -> CInt {
  var flags = CInt(O_WRONLY | O_APPEND)

  if create {
    flags |= CInt(O_CREAT)
  }

  return flags
}

@discardableResult
private func writeAll(
  to fd: CInt,
  bytes: UnsafeBufferPointer<UInt8>
) -> CInt? {
  guard let baseAddress = bytes.baseAddress, !bytes.isEmpty else {
    return nil
  }

  var offset = 0

  while offset < bytes.count {
    let result = unsafe systemWrite(
      fd,
      UnsafeRawPointer(baseAddress.advanced(by: offset)),
      bytes.count - offset
    )

    if result > 0 {
      offset += result
    } else if result == -1, currentErrno() == interruptedErrno() {
      continue
    } else {
      return currentErrno()
    }
  }

  return nil
}

@discardableResult
private func writeAll(to fd: CInt, string: String) -> CInt? {
  var string = string

  return string.withUTF8 { bytes in
    unsafe writeAll(to: fd, bytes: bytes)
  }
}

public enum Standard {
  /// A `TextOutputStream` to standard error.
  ///
  /// Writes are locked to prevent interleaved output from multiple writers
  /// in this process.
  public struct Error: TextOutputStream, Sendable {
    private static let lock = Mutex(())

    public init() {}

    public func write(_ string: String) {
      Self.lock.withLock { _ -> Void in
        _ = writeAll(to: 2, string: string)
      }
    }
  }

  /// A `TextOutputStream` to standard output.
  ///
  /// Writes are locked to prevent interleaved output from multiple writers
  /// in this process.
  public struct Out: TextOutputStream, Sendable {
    private static let lock = Mutex(())

    public init() {}

    public func write(_ string: String) {
      Self.lock.withLock { _ -> Void in
        _ = writeAll(to: 1, string: string)
      }
    }
  }
}

public final class File: TextOutputStream, Sendable {
  private let descriptor: CInt
  private let lock = Mutex(())

  /// Opens `path` for appending.
  ///
  /// `create: false` more closely matches `FileHandle(forUpdating:)`,
  /// because the file must already exist.
  ///
  /// Use `create: true` if you want the file to be created when missing.
  public init(
    path: String,
    create: Bool = false,
    permissions: UInt16 = 0o666
  ) throws {
    let fd = unsafe path.withCString { pathPointer in
      unsafe systemOpen(
        pathPointer,
        appendOpenFlags(create: create),
        permissions
      )
    }

    guard fd >= 0 else {
      throw FileOpenError.failed(path: path, errno: currentErrno())
    }

    self.descriptor = fd
  }

  public func write(_ string: String) {
    lock.withLock { _ -> Void in
      _ = writeAll(to: descriptor, string: string)
    }
  }

  deinit {
    _ = systemClose(descriptor)
  }
}
