// The POSIX arm of the SwiftTUIPlatformIO syscall facade. The Windows arm
// (PlatformWindows.swift) mirrors the path/fd file-I/O subset; the socket
// and directory-enumeration functions are POSIX-only because their sole
// consumers live in the POSIX-only attach subsystem.
#if !canImport(WASILibc) && !canImport(ucrt)
  #if canImport(Darwin)
    package import Darwin
  #elseif canImport(Glibc)
    package import Glibc
  #elseif canImport(Android)
    package import Android
  #elseif canImport(Musl)
    package import Musl
  #endif

  #if canImport(Darwin) || canImport(Android)
    private let sceneSocketStreamType = SOCK_STREAM
  #elseif canImport(Glibc) || canImport(Musl)
    private let sceneSocketStreamType = Int32(SOCK_STREAM.rawValue)
  #endif

  #if canImport(Darwin)
    package typealias SceneDirectoryHandle = UnsafeMutablePointer<DIR>
  #else
    package typealias SceneDirectoryHandle = OpaquePointer
  #endif

  @inline(__always)
  package func sceneConfigureNoSigPipe(
    _ fileDescriptor: Int32
  ) {
    #if canImport(Darwin)
      guard fileDescriptor >= 0 else { return }
      _ = fcntl(fileDescriptor, F_SETNOSIGPIPE, 1)
    #endif
  }

  @inline(__always)
  package func sceneOpenDirectory(
    _ path: String
  ) -> SceneDirectoryHandle? {
    path.withCString { cPath in
      unsafe opendir(cPath)
    }
  }

  @inline(__always)
  package func sceneCloseDirectory(
    _ directory: SceneDirectoryHandle
  ) {
    unsafe closedir(directory)
  }

  @inline(__always)
  package func sceneReadDirectory(
    _ directory: SceneDirectoryHandle
  ) -> UnsafeMutablePointer<dirent>? {
    unsafe readdir(directory)
  }

  @inline(__always)
  package func sceneUnlink(
    _ path: String
  ) -> Int32 {
    path.withCString { cPath in
      unsafe unlink(cPath)
    }
  }

  @inline(__always)
  package func sceneSocket() -> Int32 {
    let fileDescriptor = socket(AF_UNIX, sceneSocketStreamType, 0)
    sceneConfigureNoSigPipe(fileDescriptor)
    return fileDescriptor
  }

  @inline(__always)
  package func sceneOpen(
    _ path: String,
    _ flags: Int32
  ) -> Int32 {
    let fileDescriptor = path.withCString { cPath in
      unsafe open(cPath, flags)
    }
    sceneConfigureNoSigPipe(fileDescriptor)
    return fileDescriptor
  }

  @inline(__always)
  package func sceneClose(
    _ fileDescriptor: Int32
  ) {
    close(fileDescriptor)
  }

  @inline(__always)
  package func sceneRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe read(fileDescriptor, buffer, count)
  }

  /// A closed peer fails the write with EPIPE instead of raising SIGPIPE.
  /// Sockets use `MSG_NOSIGNAL`. Darwin relies on the `F_SETNOSIGPIPE` that
  /// the facade installs when it opens, accepts or configures a descriptor;
  /// the other POSIX arms block SIGPIPE in the calling thread for the
  /// `write(2)` alone (see `sceneWriteSuppressingSIGPIPE`).
  @inline(__always)
  package func sceneWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      let sent = unsafe send(fileDescriptor, buffer, count, Int32(MSG_NOSIGNAL))
      if sent >= 0 || errno != ENOTSOCK {
        return sent
      }
    #endif
    #if canImport(Darwin)
      return unsafe write(fileDescriptor, buffer, count)
    #else
      return sceneWriteSuppressingSIGPIPE {
        unsafe write(fileDescriptor, buffer, count)
      }
    #endif
  }

  #if !canImport(Darwin)
    /// POSIX write(2) sends SIGPIPE to the calling thread on EPIPE. Block it in
    /// this thread for the one syscall, consume only a signal the write itself
    /// generated (one already pending stays pending), and restore the caller's
    /// mask and errno. The process-wide disposition never changes, so other
    /// writers keep default SIGPIPE. Same technique as the runtime's
    /// `terminalWriteSuppressingSIGPIPE` and libpq's `pq_block_sigpipe`.
    /// https://pubs.opengroup.org/onlinepubs/9799919799/functions/write.html
    private func sceneWriteSuppressingSIGPIPE(_ operation: () -> Int) -> Int {
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

  @inline(__always)
  package func sceneAccess(
    _ path: String,
    _ mode: Int32
  ) -> Int32 {
    path.withCString { cPath in
      unsafe access(cPath, mode)
    }
  }

  @inline(__always)
  package func sceneSocketAddress(
    for path: String
  ) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
    guard !path.utf8.contains(0), path.utf8.count < sunPathSize else { return nil }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      path.withCString { cPath in
        _ = unsafe strncpy(
          unsafe UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
          cPath,
          sunPathSize - 1
        )
      }
    }

    return address
  }

  @inline(__always)
  package func sceneBind(
    _ fileDescriptor: Int32,
    _ address: inout sockaddr_un
  ) -> Int32 {
    withUnsafePointer(to: &address) { pointer in
      unsafe bind(
        fileDescriptor,
        unsafe UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        socklen_t(MemoryLayout<sockaddr_un>.size)
      )
    }
  }

  @inline(__always)
  package func sceneConnect(
    _ fileDescriptor: Int32,
    _ address: inout sockaddr_un
  ) -> Int32 {
    withUnsafePointer(to: &address) { pointer in
      unsafe connect(
        fileDescriptor,
        unsafe UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        socklen_t(MemoryLayout<sockaddr_un>.size)
      )
    }
  }

  @inline(__always)
  package func sceneListen(
    _ fileDescriptor: Int32,
    _ backlog: Int32
  ) -> Int32 {
    listen(fileDescriptor, backlog)
  }

  @inline(__always)
  package func sceneAccept(
    _ fileDescriptor: Int32
  ) -> Int32 {
    let clientFileDescriptor = unsafe accept(
      fileDescriptor,
      nil as UnsafeMutablePointer<sockaddr>?,
      nil as UnsafeMutablePointer<socklen_t>?
    )
    sceneConfigureNoSigPipe(clientFileDescriptor)
    return clientFileDescriptor
  }

#endif
