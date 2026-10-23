#if canImport(Darwin)
  import Darwin
  import Synchronization

  /// Synchronous output that preserves a borrowed descriptor's policy.
  /// The owner must keep the descriptor open and coordinate other flag setters.
  /// Pipe suppression is shared with aliases only for one nonblocking syscall.
  package enum DarwinOutput {
    private static let descriptorLock = Mutex<Void>(())

    private enum WriteAttempt {
      case completed(count: Int, error: Int32)
      case waitForOutput
    }

    package static func write(
      _ descriptor: Int32,
      _ buffer: UnsafeRawPointer?,
      _ count: Int,
      nonBlocking: Bool = false
    ) -> Int {
      var information = stat()
      guard unsafe fstat(descriptor, &information) == 0 else { return -1 }
      let kind = information.st_mode & mode_t(S_IFMT)
      if kind == mode_t(S_IFSOCK) {
        // Socket options cannot be changed after shutdown. Per-send suppression
        // also leaves other users of the socket's open description untouched.
        var flags = MSG_NOSIGNAL
        if nonBlocking { flags |= MSG_DONTWAIT }
        return unsafe send(descriptor, buffer, count, flags)
      }

      let isPipe = kind == mode_t(S_IFIFO)
      let isTerminal = kind == mode_t(S_IFCHR) && isatty(descriptor) == 1
      guard isPipe || isTerminal else {
        // O_NONBLOCK cannot bound ordinary file I/O. Do not serialize it with
        // terminal output or change a policy that this write does not need.
        return unsafe Darwin.write(descriptor, buffer, count)
      }

      while true {
        let attempt = descriptorLock.withLock { _ in
          unsafe writeNonBlocking(
            descriptor, buffer, count, suppressSIGPIPE: isPipe, nonBlocking: nonBlocking)
        }
        switch attempt {
        case .completed(let count, let error):
          errno = error
          return count
        case .waitForOutput:
          break
        }

        // Never wait for an output peer while holding the shared descriptor
        // lock. Blocking hosts retain their blocking write contract; budgeted
        // callers request nonblocking attempts and own their deadline/retry.
        var readiness = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard unsafe poll(&readiness, 1, -1) >= 0 else { return -1 }
      }
    }

    private static func writeNonBlocking(
      _ descriptor: Int32,
      _ buffer: UnsafeRawPointer?,
      _ count: Int,
      suppressSIGPIPE: Bool,
      nonBlocking: Bool
    ) -> WriteAttempt {
      let flags = fcntl(descriptor, F_GETFL)
      guard flags >= 0 else { return .completed(count: -1, error: errno) }
      var noSIGPIPE: Int32 = 0
      if suppressSIGPIPE { noSIGPIPE = fcntl(descriptor, F_GETNOSIGPIPE) }
      guard noSIGPIPE >= 0 else { return .completed(count: -1, error: errno) }
      guard fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
        return .completed(count: -1, error: errno)
      }
      if suppressSIGPIPE, fcntl(descriptor, F_SETNOSIGPIPE, 1) < 0 {
        let setupError = errno
        let restoreError = restore(descriptor, command: F_SETFL, value: flags)
        return .completed(count: -1, error: restoreError == 0 ? setupError : restoreError)
      }

      let written = unsafe Darwin.write(descriptor, buffer, count)
      let writeError = errno
      var policyError: Int32 = 0
      if suppressSIGPIPE {
        policyError = restore(descriptor, command: F_SETNOSIGPIPE, value: noSIGPIPE)
      }
      let flagsError = restore(descriptor, command: F_SETFL, value: flags)
      if policyError != 0 { return .completed(count: -1, error: policyError) }
      if flagsError != 0 { return .completed(count: -1, error: flagsError) }
      let wouldBlock = writeError == EAGAIN || writeError == EWOULDBLOCK
      let wasNonBlocking = flags & O_NONBLOCK != 0
      if written < 0, wouldBlock, !nonBlocking, !wasNonBlocking {
        return .waitForOutput
      }
      return .completed(count: written, error: writeError)
    }

    private static func restore(_ descriptor: Int32, command: Int32, value: Int32) -> Int32 {
      while fcntl(descriptor, command, value) < 0 {
        if errno != EINTR { return errno }
      }
      return 0
    }
  }
#endif
