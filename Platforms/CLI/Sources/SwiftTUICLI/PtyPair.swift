#if !canImport(WASILibc)
  import Synchronization

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  enum PtyError: Error, CustomStringConvertible {
    case allocationFailed(errno: Int32)
    case slavePathUnavailable

    var description: String {
      switch self {
      case .allocationFailed(let errno):
        "Failed to allocate pty: \(unsafe String(cString: strerror(errno)))"
      case .slavePathUnavailable:
        "Could not determine slave pty path"
      }
    }
  }

  final class PtyPair: Sendable {
    private let _masterFD: Mutex<Int32>
    let slavePath: String

    var masterFD: Int32 {
      _masterFD.withLock { $0 }
    }

    func hasAttachedClient() -> Bool {
      let fd = masterFD
      guard fd >= 0 else { return false }

      // PTY masters report a hangup when no slave is attached. That signal is
      // stable across Darwin and Linux, unlike zero-byte writes.
      var descriptor = pollfd(
        fd: fd,
        events: Int16(POLLHUP | POLLOUT),
        revents: 0
      )
      let result = unsafe poll(&descriptor, 1, 0)
      guard result > 0 else { return false }
      return (descriptor.revents & Int16(POLLHUP)) == 0
    }

    init() throws(PtyError) {
      var masterFD: Int32 = -1
      var slaveFD: Int32 = -1

      guard unsafe openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
        throw .allocationFailed(errno: errno)
      }

      sceneConfigureNoSigPipe(masterFD)
      sceneConfigureNoSigPipe(slaveFD)

      // We only need the slave path, not the slave fd — clients open it themselves.
      // Read the path before closing the slave fd.
      guard let slavePath = sceneTTYName(slaveFD) else {
        sceneClose(masterFD)
        sceneClose(slaveFD)
        throw .slavePathUnavailable
      }

      // Close the slave fd — clients will open the slave path themselves.
      sceneClose(slaveFD)

      self._masterFD = Mutex(masterFD)
      self.slavePath = slavePath
    }

    func close() {
      let fd = _masterFD.withLock { fd -> Int32 in
        let current = fd
        fd = -1
        return current
      }
      if fd >= 0 {
        sceneClose(fd)
      }
    }

    deinit {
      let fd = _masterFD.withLock { fd -> Int32 in
        let current = fd
        fd = -1
        return current
      }
      if fd >= 0 {
        sceneClose(fd)
      }
    }
  }
#else
  enum PtyError: Error, CustomStringConvertible {
    case unavailableOnWASI

    var description: String {
      switch self {
      case .unavailableOnWASI:
        "Pseudo-terminals are unavailable when building for WASI."
      }
    }
  }

  final class PtyPair: Sendable {
    let slavePath = ""

    var masterFD: Int32 {
      -1
    }

    func hasAttachedClient() -> Bool {
      false
    }

    init() throws(PtyError) {
      throw .unavailableOnWASI
    }

    func close() {}
  }
#endif
