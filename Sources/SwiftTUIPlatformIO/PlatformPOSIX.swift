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
  #endif

  #if canImport(Darwin) || canImport(Android)
    private let sceneSocketStreamType = SOCK_STREAM
  #elseif canImport(Glibc)
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
    unsafe path.withCString { cPath in
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
    unsafe path.withCString { cPath in
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
    let fileDescriptor = unsafe path.withCString { cPath in
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

  @inline(__always)
  package func sceneWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android)
      let sent = unsafe send(fileDescriptor, buffer, count, Int32(MSG_NOSIGNAL))
      if sent >= 0 || errno != ENOTSOCK {
        return sent
      }
    #endif
    return unsafe write(fileDescriptor, buffer, count)
  }

  @inline(__always)
  package func sceneAccess(
    _ path: String,
    _ mode: Int32
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe access(cPath, mode)
    }
  }

  @inline(__always)
  package func sceneSocketAddress(
    for path: String
  ) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
    unsafe withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      unsafe path.withCString { cPath in
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
    unsafe withUnsafePointer(to: &address) { pointer in
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
    unsafe withUnsafePointer(to: &address) { pointer in
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
