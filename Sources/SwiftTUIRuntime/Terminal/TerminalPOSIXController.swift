import SwiftTUICore

// Plain (internal) imports on purpose: after the Stage 3 reshape no libc
// type appears in the seam's package-visible surface — that is the point of
// ``TerminalModeSnapshot``.
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(ucrt)
  import CRT
#endif

// Positive host test, not "not WASI": the terminal-control seam compiles
// exactly where a real terminal host exists (Stage 3.5 of the Windows plan).
#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(ucrt)
  package protocol TerminalControlling: Sendable {
    func isATTY(_ fileDescriptor: Int32) -> Bool
    func windowSize(of fileDescriptor: Int32) throws -> CellSize
    func cellPixelSize(of fileDescriptor: Int32) throws -> PixelSize?

    /// Captures the current terminal mode, switches to raw, and returns the
    /// snapshot `restore` consumes. What "raw mode" means is owned by the
    /// platform: on POSIX, `cfmakeraw` plus `VMIN=1`/`VTIME=0` plus
    /// `O_NONBLOCK` on the input descriptor.
    func enterRawMode(input: Int32, output: Int32) throws -> TerminalModeSnapshot
    /// Restores a snapshot captured by `enterRawMode`. Idempotent.
    func restore(_ snapshot: TerminalModeSnapshot, input: Int32, output: Int32) throws

    func write(_ output: String, to fileDescriptor: Int32) throws
    func read(
      from fileDescriptor: Int32,
      maxBytes: Int,
      timeoutMilliseconds: Int
    ) throws -> [UInt8]
  }

  extension TerminalControlling {
    func cellPixelSize(of _: Int32) throws -> PixelSize? {
      nil
    }
  }

  /// Selects the platform's terminal controller. Every construction site goes
  /// through here so the platform difference stays invisible to callers —
  /// direct `POSIXTerminalController()` instantiation would defeat the seam
  /// on Windows.
  package enum PlatformTerminalController {
    package static func make() -> any TerminalControlling {
      #if canImport(ucrt)
        // Arrives with Stage 4 of the Windows plan.
        WindowsTerminalController()
      #else
        POSIXTerminalController()
      #endif
    }
  }
#endif

#if canImport(Darwin) || canImport(Glibc) || canImport(Android)
  struct POSIXTerminalController: TerminalControlling {
    func isATTY(_ fileDescriptor: Int32) -> Bool {
      isatty(fileDescriptor) == 1
    }

    func enterRawMode(input: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      var currentAttributes = termios()
      guard unsafe tcgetattr(input, &currentAttributes) == 0 else {
        throw TerminalHostError.failedToReadAttributes(errno: errno)
      }

      var rawAttributes = currentAttributes
      unsafe cfmakeraw(&rawAttributes)
      // VMIN = 1, VTIME = 0: the platform-dependent c_cc tuple indices are
      // part of what "raw mode" means here and must not leak to callers.
      rawAttributes.c_cc.16 = 1
      rawAttributes.c_cc.17 = 0

      guard unsafe tcsetattr(input, TCSAFLUSH, &rawAttributes) == 0 else {
        throw TerminalHostError.failedToSetAttributes(errno: errno)
      }

      let currentFileStatusFlags = fcntl(input, F_GETFL)
      guard currentFileStatusFlags >= 0 else {
        let flagsErrno = errno
        _ = unsafe tcsetattr(input, TCSAFLUSH, &currentAttributes)
        throw TerminalHostError.failedToReadFileStatusFlags(errno: flagsErrno)
      }
      guard fcntl(input, F_SETFL, currentFileStatusFlags | Int32(O_NONBLOCK)) >= 0 else {
        let flagsErrno = errno
        _ = unsafe tcsetattr(input, TCSAFLUSH, &currentAttributes)
        throw TerminalHostError.failedToSetFileStatusFlags(errno: flagsErrno)
      }

      return TerminalModeSnapshot(
        attributes: currentAttributes,
        inputFileStatusFlags: currentFileStatusFlags
      )
    }

    func restore(_ snapshot: TerminalModeSnapshot, input: Int32, output _: Int32) throws {
      guard fcntl(input, F_SETFL, snapshot.inputFileStatusFlags) >= 0 else {
        throw TerminalHostError.failedToSetFileStatusFlags(errno: errno)
      }
      var attributes = snapshot.attributes
      guard unsafe tcsetattr(input, TCSAFLUSH, &attributes) == 0 else {
        throw TerminalHostError.failedToSetAttributes(errno: errno)
      }
    }

    func windowSize(of fileDescriptor: Int32) throws -> CellSize {
      var windowSize = winsize()
      guard unsafe ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }

      return CellSize(
        width: max(1, Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_row))
      )
    }

    func cellPixelSize(of fileDescriptor: Int32) throws -> PixelSize? {
      var windowSize = winsize()
      guard unsafe ioctl(fileDescriptor, UInt(TIOCGWINSZ), &windowSize) == 0 else {
        throw TerminalHostError.failedToReadWindowSize(errno: errno)
      }
      guard
        windowSize.ws_col > 0,
        windowSize.ws_row > 0,
        windowSize.ws_xpixel > 0,
        windowSize.ws_ypixel > 0
      else {
        return nil
      }

      return .init(
        width: max(1, Int(windowSize.ws_xpixel) / Int(windowSize.ws_col)),
        height: max(1, Int(windowSize.ws_ypixel) / Int(windowSize.ws_row))
      )
    }

    func write(_ output: String, to fileDescriptor: Int32) throws {
      let bytes = Array(output.utf8)
      let totalBytes = bytes.count

      try unsafe bytes.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
          return
        }

        var bytesWritten = 0
        while bytesWritten < totalBytes {
          let pointer = unsafe baseAddress.advanced(by: bytesWritten)
          let result = unsafe terminalPlatformWrite(
            fileDescriptor,
            pointer,
            totalBytes - bytesWritten
          )

          if result > 0 {
            bytesWritten += result
            continue
          }

          if result == 0 {
            continue
          }

          switch errno {
          case EINTR:
            continue
          case EAGAIN, EWOULDBLOCK:
            try waitUntilWritable(fileDescriptor)
          case EIO, EPIPE:
            // The far end of the terminal has closed: EIO when a PTY master
            // is gone, EPIPE for a socket-backed terminal. That is a clean
            // disconnect, not a failure — stop writing and let the input
            // side (EOF) drive the session's orderly shutdown.
            return
          default:
            throw TerminalHostError.failedToWrite(errno: errno)
          }
        }
      }
    }

    func read(
      from fileDescriptor: Int32,
      maxBytes: Int,
      timeoutMilliseconds: Int
    ) throws -> [UInt8] {
      guard maxBytes > 0 else {
        return []
      }

      var descriptor = pollfd(
        fd: fileDescriptor,
        events: Int16(POLLIN),
        revents: 0
      )
      let ready = unsafe terminalPlatformPoll(
        &descriptor,
        1,
        Int32(timeoutMilliseconds)
      )

      guard ready > 0 else {
        return []
      }

      var buffer = Array(repeating: UInt8(0), count: maxBytes)
      let bytesRead = unsafe terminalPlatformRead(fileDescriptor, &buffer, maxBytes)
      guard bytesRead > 0 else {
        return []
      }

      return Array(buffer.prefix(Int(bytesRead)))
    }
  }

  extension POSIXTerminalController {
    private func waitUntilWritable(
      _ fileDescriptor: Int32
    ) throws {
      var descriptor = pollfd(
        fd: fileDescriptor,
        events: Int16(POLLOUT),
        revents: 0
      )

      while true {
        let ready = unsafe terminalPlatformPoll(&descriptor, 1, -1)
        if ready > 0 {
          return
        }
        if ready == 0 || errno == EINTR {
          continue
        }
        throw TerminalHostError.failedToWrite(errno: errno)
      }
    }
  }
#endif
