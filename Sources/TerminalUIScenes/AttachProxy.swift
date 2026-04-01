#if !canImport(WASILibc)

  import UnixSignals

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  enum AttachProxyError: Error, CustomStringConvertible {
    case failedToOpenSlave(path: String, errno: Int32)
    case failedToSetRawMode(errno: Int32)

    var description: String {
      switch self {
      case .failedToOpenSlave(let path, let errno):
        "Failed to open pty slave \(path): \(unsafe String(cString: strerror(errno)))"
      case .failedToSetRawMode(let errno):
        "Failed to set raw mode: \(unsafe String(cString: strerror(errno)))"
      }
    }
  }

  enum AttachProxy {
    /// Proxy the current terminal's stdio to a pty slave.
    ///
    /// This puts the current terminal into raw mode, forwards stdin to the slave,
    /// forwards slave output to stdout, and relays SIGWINCH.
    /// Returns when the slave closes or the task is cancelled.
    static func run(slavePath: String) async throws {
      let slaveFD = unsafe Darwin.open(slavePath, O_RDWR | O_NOCTTY)
      guard slaveFD >= 0 else {
        throw AttachProxyError.failedToOpenSlave(
          path: slavePath,
          errno: errno
        )
      }
      defer { Darwin.close(slaveFD) }

      // Set the slave's window size to match the current terminal
      syncWindowSize(from: STDOUT_FILENO, to: slaveFD)

      // Save current terminal attributes and enter raw mode
      var savedAttrs = termios()
      guard unsafe tcgetattr(STDIN_FILENO, &savedAttrs) == 0 else {
        throw AttachProxyError.failedToSetRawMode(errno: errno)
      }

      var rawAttrs = savedAttrs
      unsafe cfmakeraw(&rawAttrs)
      guard unsafe tcsetattr(STDIN_FILENO, TCSAFLUSH, &rawAttrs) == 0 else {
        throw AttachProxyError.failedToSetRawMode(errno: errno)
      }

      defer {
        var attrs = savedAttrs
        unsafe tcsetattr(STDIN_FILENO, TCSAFLUSH, &attrs)
      }

      // Forward data bidirectionally using poll
      await withTaskGroup(of: Void.self) { group in
        // stdin -> slave
        group.addTask {
          var buffer = [UInt8](repeating: 0, count: 4096)
          while !Task.isCancelled {
            var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = unsafe poll(&pfd, 1, 100)
            guard ready > 0 else { continue }

            let n = unsafe Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if n <= 0 { break }
            _ = unsafe buffer.withUnsafeBufferPointer { buf in
              unsafe Darwin.write(slaveFD, buf.baseAddress!, n)
            }
          }
        }

        // slave -> stdout
        group.addTask {
          var buffer = [UInt8](repeating: 0, count: 4096)
          while !Task.isCancelled {
            var pfd = pollfd(fd: slaveFD, events: Int16(POLLIN), revents: 0)
            let ready = unsafe poll(&pfd, 1, 100)
            guard ready > 0 else { continue }

            let n = unsafe Darwin.read(slaveFD, &buffer, buffer.count)
            if n <= 0 { break }
            _ = unsafe buffer.withUnsafeBufferPointer { buf in
              unsafe Darwin.write(STDOUT_FILENO, buf.baseAddress!, n)
            }
          }
        }

        // SIGWINCH -> sync window size
        group.addTask {
          let signals = UnixSignalsSequence.stream(for: [.sigwinch])
          for await _ in signals {
            syncWindowSize(from: STDOUT_FILENO, to: slaveFD)
          }
        }

        // Wait for any task to finish (slave closed or stdin closed)
        // then cancel the rest
        await group.next()
        group.cancelAll()
      }
    }

    private static func syncWindowSize(
      from sourceFD: Int32,
      to targetFD: Int32
    ) {
      var ws = winsize()
      guard unsafe ioctl(sourceFD, UInt(TIOCGWINSZ), &ws) == 0 else {
        return
      }
      _ = unsafe ioctl(targetFD, UInt(TIOCSWINSZ), &ws)
    }
  }
#endif
