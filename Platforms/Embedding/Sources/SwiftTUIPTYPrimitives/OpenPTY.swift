// PTY plumbing is POSIX-only; dependency edges exclude Windows.
#if !os(Windows)
  import Synchronization

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  public struct PTYHandles: Sendable {
    public let masterFD: Int32
    public let slaveFD: Int32
    public let slavePath: String

    public init(masterFD: Int32, slaveFD: Int32, slavePath: String) {
      self.masterFD = masterFD
      self.slaveFD = slaveFD
      self.slavePath = slavePath
    }
  }

  /// Darwin's `openpty` occasionally fails when two threads allocate at once
  /// (4 of 16,000 calls in an eight-thread harness, with a negative errno), so
  /// this process allocates one PTY at a time.
  private let ptyAllocation = Mutex(())

  public func openPTY() throws(PTYError) -> PTYHandles {
    var masterFD: Int32 = -1
    var slaveFD: Int32 = -1

    let allocationErrno: Int32? = ptyAllocation.withLock { _ in
      unsafe openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 ? nil : errno
    }
    if let allocationErrno {
      throw .allocationFailed(errno: allocationErrno)
    }

    configureNoSigPipe(masterFD)
    configureNoSigPipe(slaveFD)

    guard let slavePath = slavePath(masterFD: masterFD, slaveFD: slaveFD) else {
      closeFD(masterFD)
      closeFD(slaveFD)
      throw .slavePathUnavailable
    }

    return PTYHandles(masterFD: masterFD, slaveFD: slaveFD, slavePath: slavePath)
  }

  public func ptyResize(masterFD: Int32, cols: Int, rows: Int) throws(PTYError) {
    var windowSize = winsize(
      ws_row: UInt16(rows),
      ws_col: UInt16(cols),
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    guard unsafe ioctl(masterFD, UInt(TIOCSWINSZ), &windowSize) == 0 else {
      throw .resizeFailed(errno: errno)
    }
  }

  public func closeFD(_ fd: Int32) {
    if fd >= 0 {
      _ = close(fd)
    }
  }

  private func configureNoSigPipe(_ fd: Int32) {
    #if canImport(Darwin)
      _ = fcntl(fd, F_SETNOSIGPIPE, 1)
    #endif
  }

  /// The slave device path. Darwin's `ttyname_r` is not thread-safe: while
  /// another thread resolves a terminal name it fails with `ERANGE`, which
  /// broke parallel tests that open PTYs. `ptsname_r` on the master asks the
  /// kernel for the same name. Glibc's `ttyname_r` reads `/proc/self/fd` and
  /// is safe.
  private func slavePath(masterFD: Int32, slaveFD: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let result = buffer.withUnsafeMutableBufferPointer { storage in
      guard let baseAddress = storage.baseAddress else {
        return ERANGE
      }

      #if canImport(Darwin)
        return unsafe ptsname_r(masterFD, baseAddress, storage.count)
      #else
        return unsafe ttyname_r(slaveFD, baseAddress, storage.count)
      #endif
    }

    guard result == 0 else {
      return nil
    }

    return buffer.withUnsafeBufferPointer { storage in
      guard let baseAddress = storage.baseAddress else {
        return nil
      }

      let path = unsafe String(cString: baseAddress)
      return path.isEmpty ? nil : path
    }
  }
#endif
