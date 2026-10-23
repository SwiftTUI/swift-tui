#if canImport(Darwin)
  import Darwin
  import SwiftTUIPlatformIO
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import CRT
#endif

#if canImport(Darwin)
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int,
    nonBlocking: Bool = false
  ) -> Int {
    unsafe DarwinOutput.write(fileDescriptor, buffer, count, nonBlocking: nonBlocking)
  }

  func terminalPlatformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }

  func terminalPlatformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Darwin.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Glibc)
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    terminalWriteSuppressingSIGPIPE {
      unsafe Glibc.write(fileDescriptor, buffer, count)
    }
  }

  func terminalPlatformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }

  func terminalPlatformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Glibc.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(Android)
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    terminalWriteSuppressingSIGPIPE {
      unsafe Android.write(fileDescriptor, buffer, count)
    }
  }

  func terminalPlatformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.read(fileDescriptor, buffer, count)
  }

  func terminalPlatformPoll(
    _ descriptors: UnsafeMutablePointer<pollfd>?,
    _ count: nfds_t,
    _ timeoutMilliseconds: Int32
  ) -> Int32 {
    unsafe Android.poll(descriptors, count, timeoutMilliseconds)
  }
#elseif canImport(WASILibc)
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.write(fileDescriptor, buffer, count))
  }
#elseif canImport(ucrt)
  // No poll on Windows: readiness comes from WaitForSingleObject inside the
  // WindowsTerminalController record pump, which owns the console handle.
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe _write(fileDescriptor, buffer, UInt32(count)))
  }

  func terminalPlatformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe _read(fileDescriptor, buffer, UInt32(count)))
  }
#endif

#if canImport(Glibc) || canImport(Android)
  /// POSIX write directs SIGPIPE to the calling thread. Block it only for this
  /// synchronous syscall, consume only a newly generated signal on EPIPE, and
  /// restore the caller's mask and errno. No process-wide disposition changes.
  /// https://pubs.opengroup.org/onlinepubs/9699919799/functions/write.html
  private func terminalWriteSuppressingSIGPIPE(_ operation: () -> Int) -> Int {
    var blocked = sigset_t()
    var original = sigset_t()
    var pending = sigset_t()
    _ = unsafe sigemptyset(&blocked)
    _ = unsafe sigaddset(&blocked, SIGPIPE)
    let maskError = unsafe pthread_sigmask(SIG_BLOCK, &blocked, &original)
    guard maskError == 0 else {
      errno = maskError
      return -1
    }
    _ = unsafe sigpending(&pending)
    let wasPending = unsafe sigismember(&pending, SIGPIPE) == 1
    let result = operation()
    let writeError = errno
    if result < 0, writeError == EPIPE, !wasPending {
      var timeout = timespec(tv_sec: 0, tv_nsec: 0)
      while unsafe sigtimedwait(&blocked, nil, &timeout) < 0 && errno == EINTR {}
    }
    _ = unsafe pthread_sigmask(SIG_SETMASK, &original, nil)
    errno = writeError
    return result
  }
#endif
