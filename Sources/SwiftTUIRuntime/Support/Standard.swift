import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("Unsupported platform: this implementation needs POSIX open/write/close.")
#endif

// Path-based file I/O is not exposed on WASI: the WASI capability model
// makes `open(path, ...)` a no-go, and the wasm SDK explicitly marks
// `O_CREAT` as unavailable. `Standard.File`, `FileOpenError`, and the
// supporting helpers below are therefore compiled out on WASI; the
// stdout/stderr surfaces (`Standard.Out` / `Standard.Error`) stay
// available because writing to fds 1 and 2 works fine.
#if !canImport(WASILibc)
  public enum FileOpenError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
    case failed(path: String, errno: CInt)

    public var description: String {
      switch self {
      case .failed(let path, let errno):
        return "Failed to open '\(path)' (errno: \(errno))"
      }
    }
  }
#endif

@inline(__always)
private func systemWrite(
  _ fd: CInt,
  _ buffer: UnsafeRawPointer,
  _ count: Int
) -> Int {
  #if canImport(Darwin)
    unsafe Darwin.write(fd, buffer, count)
  #elseif canImport(Glibc)
    unsafe Glibc.write(fd, buffer, count)
  #elseif canImport(Android)
    unsafe Android.write(fd, buffer, count)
  #elseif canImport(Musl)
    unsafe Musl.write(fd, buffer, count)
  #elseif canImport(WASILibc)
    Int(unsafe WASILibc.write(fd, buffer, count))
  #endif
}

#if !canImport(WASILibc)
  @inline(__always)
  private func systemOpen(
    _ path: UnsafePointer<CChar>,
    _ flags: CInt,
    _ mode: mode_t
  ) -> CInt {
    #if canImport(Darwin)
      unsafe Darwin.open(path, flags, mode)
    #elseif canImport(Glibc)
      unsafe Glibc.open(path, flags, mode)
    #elseif canImport(Android)
      unsafe Android.open(path, flags, mode)
    #elseif canImport(Musl)
      unsafe Musl.open(path, flags, mode)
    #endif
  }

  @inline(__always)
  private func systemClose(_ fd: CInt) -> CInt {
    #if canImport(Darwin)
      Darwin.close(fd)
    #elseif canImport(Glibc)
      Glibc.close(fd)
    #elseif canImport(Android)
      Android.close(fd)
    #elseif canImport(Musl)
      Musl.close(fd)
    #endif
  }
#endif

@inline(__always)
private func currentErrno() -> CInt {
  errno
}

@inline(__always)
private func interruptedErrno() -> CInt {
  CInt(EINTR)
}

#if !canImport(WASILibc)
  @inline(__always)
  private func appendOpenFlags(create: Bool) -> CInt {
    var flags = CInt(O_WRONLY | O_APPEND)

    if create {
      flags |= CInt(O_CREAT)
    }

    return flags
  }
#endif

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

    public func dump<T>(file: String = #file, line: UInt = #line, _ value: T) {
      var text = "\(file):\(line)\n"
      Swift.dump(value, to: &text)
      write(text)
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
    public func dump<T>(file: String = #file, line: UInt = #line, _ value: T) {
      var text = "\(file):\(line)\n"
      Swift.dump(value, to: &text)
      write(text)
    }
  }

  // `Standard.File` opens an arbitrary path for appending. WASI's
  // capability model makes path-based open() a no-op (`O_CREAT` is marked
  // unavailable in the WASI SDK headers), so this type is compiled out
  // on wasm. Consumers that need scoped file output on WASI must drive
  // the WASI preopened-directory APIs directly.
  #if !canImport(WASILibc)
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
        // mode_t is platform-typed (UInt16 on Darwin, UInt32 on Linux) and
        // imported as `internal` under InternalImportsByDefault, so it
        // can't appear in a public signature. Take a UInt16 publicly and
        // cast at the call site — both target widths accept it.
        let fd = unsafe path.withCString { pathPointer in
          unsafe systemOpen(
            pathPointer,
            appendOpenFlags(create: create),
            mode_t(permissions)
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
      public func dump<T>(file: String = #file, line: UInt = #line, _ value: T) {
        var text = "\(file):\(line)\n"
        Swift.dump(value, to: &text)
        write(text)
      }

      deinit {
        _ = systemClose(descriptor)
      }
    }
  #endif
}
