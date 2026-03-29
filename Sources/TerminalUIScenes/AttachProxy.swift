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
        "Failed to open pty slave \(path): \(String(cString: strerror(errno)))"
      case .failedToSetRawMode(let errno):
        "Failed to set raw mode: \(String(cString: strerror(errno)))"
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
      let slaveFD = Darwin.open(slavePath, O_RDWR | O_NOCTTY)
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
      guard tcgetattr(STDIN_FILENO, &savedAttrs) == 0 else {
        throw AttachProxyError.failedToSetRawMode(errno: errno)
      }

      var rawAttrs = savedAttrs
      cfmakeraw(&rawAttrs)
      guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &rawAttrs) == 0 else {
        throw AttachProxyError.failedToSetRawMode(errno: errno)
      }

      defer {
        var attrs = savedAttrs
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &attrs)
      }

      // Forward data bidirectionally using poll
      await withTaskGroup(of: Void.self) { group in
        // stdin -> slave
        group.addTask {
          var buffer = [UInt8](repeating: 0, count: 4096)
          while !Task.isCancelled {
            var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 100)
            guard ready > 0 else { continue }

            let n = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if n <= 0 { break }
            _ = buffer.withUnsafeBufferPointer { buf in
              Darwin.write(slaveFD, buf.baseAddress!, n)
            }
          }
        }

        // slave -> stdout
        group.addTask {
          var buffer = [UInt8](repeating: 0, count: 4096)
          while !Task.isCancelled {
            var pfd = pollfd(fd: slaveFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 100)
            guard ready > 0 else { continue }

            let n = Darwin.read(slaveFD, &buffer, buffer.count)
            if n <= 0 { break }
            _ = buffer.withUnsafeBufferPointer { buf in
              Darwin.write(STDOUT_FILENO, buf.baseAddress!, n)
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
      guard ioctl(sourceFD, UInt(TIOCGWINSZ), &ws) == 0 else {
        return
      }
      _ = ioctl(targetFD, UInt(TIOCSWINSZ), &ws)
    }
  }
#endif
