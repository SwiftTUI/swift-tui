#if !canImport(WASILibc)
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #endif

  #if canImport(Darwin) || canImport(Android)
    private let sceneSocketStreamType = SOCK_STREAM
  #elseif canImport(Glibc)
    private let sceneSocketStreamType = Int32(SOCK_STREAM.rawValue)
  #endif

  #if canImport(Darwin)
    typealias SceneDirectoryHandle = UnsafeMutablePointer<DIR>
  #else
    typealias SceneDirectoryHandle = OpaquePointer
  #endif

  @inline(__always)
  func sceneOpenDirectory(
    _ path: String
  ) -> SceneDirectoryHandle? {
    unsafe path.withCString { cPath in
      unsafe opendir(cPath)
    }
  }

  @inline(__always)
  func sceneCloseDirectory(
    _ directory: SceneDirectoryHandle
  ) {
    unsafe closedir(directory)
  }

  @inline(__always)
  func sceneReadDirectory(
    _ directory: SceneDirectoryHandle
  ) -> UnsafeMutablePointer<dirent>? {
    unsafe readdir(directory)
  }

  @inline(__always)
  func sceneUnlink(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe unlink(cPath)
    }
  }

  @inline(__always)
  func sceneSocket() -> Int32 {
    socket(AF_UNIX, sceneSocketStreamType, 0)
  }

  @inline(__always)
  func sceneOpen(
    _ path: String,
    _ flags: Int32
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe open(cPath, flags)
    }
  }

  @inline(__always)
  func sceneClose(
    _ fileDescriptor: Int32
  ) {
    close(fileDescriptor)
  }

  @inline(__always)
  func sceneRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe read(fileDescriptor, buffer, count)
  }

  @inline(__always)
  func sceneWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe write(fileDescriptor, buffer, count)
  }

  @inline(__always)
  func sceneAccess(
    _ path: String,
    _ mode: Int32
  ) -> Int32 {
    unsafe path.withCString { cPath in
      unsafe access(cPath, mode)
    }
  }

  @inline(__always)
  func sceneSocketAddress(
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
  func sceneBind(
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
  func sceneConnect(
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
  func sceneListen(
    _ fileDescriptor: Int32,
    _ backlog: Int32
  ) -> Int32 {
    listen(fileDescriptor, backlog)
  }

  @inline(__always)
  func sceneAccept(
    _ fileDescriptor: Int32
  ) -> Int32 {
    unsafe accept(
      fileDescriptor,
      nil as UnsafeMutablePointer<sockaddr>?,
      nil as UnsafeMutablePointer<socklen_t>?
    )
  }

  @inline(__always)
  func sceneTTYName(
    _ fileDescriptor: Int32
  ) -> String? {
    var buffer = [CChar](repeating: 0, count: 1024)
    let result = unsafe ttyname_r(fileDescriptor, &buffer, buffer.count)
    guard result == 0 else {
      return nil
    }
    return String(
      decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
      as: UTF8.self
    )
  }
#endif
