#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Darwin.open(pathPointer, O_RDONLY)
    }
  }

  func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Darwin.close(fileDescriptor)
  }

  func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }

  func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.write(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Glibc.open(pathPointer, Glibc.O_RDONLY)
    }
  }

  func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Glibc.close(fileDescriptor)
  }

  func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }

  func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.write(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe WASILibc.open(pathPointer, WASILibc.O_RDONLY)
    }
  }

  func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    WASILibc.close(fileDescriptor)
  }

  func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  }

  func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.write(fileDescriptor, buffer, count))
  }
#endif

#if canImport(Darwin) || canImport(Glibc) || canImport(WASILibc)
  let webSurfaceStandardInputFileDescriptor: Int32 = STDIN_FILENO
  let webSurfaceStandardOutputFileDescriptor: Int32 = STDOUT_FILENO

  var webSurfaceErrno: Int32 {
    errno
  }

  func webSurfaceErrnoIsWouldBlock(_ value: Int32) -> Bool {
    value == EAGAIN || value == EWOULDBLOCK
  }
#endif
