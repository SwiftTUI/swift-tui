#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(ucrt)
  import CRT
#endif

#if os(Windows)
  import WinSDK
#endif

/// Opens an anonymous pipe with the platform's spelling: POSIX `pipe(2)`, or
/// the Windows CRT `_pipe` in binary mode with a pipe-buffer-sized reserve
/// (Windows plan, Stage 6 item 3). `descriptors` receives `[read, write]`;
/// returns 0 on success, matching `pipe(2)`.
///
/// `nonblockingRead` marks the read end `O_NONBLOCK` on POSIX — the shape
/// the dispatch-source reader arm needs. Windows CRT pipes have no
/// nonblocking mode (and the Windows polling reader never needs one), so
/// the flag is a no-op there; suites that depend on nonblocking semantics
/// at runtime are POSIX-gated separately.
@_spi(Testing) public func openTestPipe(
  _ descriptors: inout [Int32],
  nonblockingRead: Bool = false
) -> Int32 {
  #if os(Windows)
    unsafe _pipe(&descriptors, 4096, _O_BINARY)
  #else
    let result = unsafe pipe(&descriptors)
    guard result == 0 else { return result }
    if nonblockingRead {
      let flags = fcntl(descriptors[0], F_GETFL)
      guard flags >= 0, fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) >= 0 else {
        return -1
      }
    }
    return 0
  #endif
}

/// Sleeps the calling thread, spelled per platform: POSIX `usleep`, or the
/// Windows `Sleep` millisecond API (rounded up so a nonzero request never
/// becomes a zero-length yield).
@_spi(Testing) public func testSleep(microseconds: UInt32) {
  #if os(Windows)
    Sleep(max(1, (microseconds &+ 999) / 1000))
  #else
    _ = usleep(microseconds)
  #endif
}
