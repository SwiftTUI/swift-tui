#if canImport(Darwin)
  import Darwin
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

// POSIX shims for the web-surface transport and image encoder. Widened to
// `package` when they moved from the WASI bridge into the runtime (the
// encoders became shared host infrastructure — convergence proposal
// 2026-07-22-002); the WASI transport keeps consuming them cross-module.

#if canImport(Darwin)
  package func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Darwin.open(pathPointer, O_RDONLY)
    }
  }

  package func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Darwin.close(fileDescriptor)
  }

  package func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }

  package func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.write(fileDescriptor, buffer, count)
  }
#elseif canImport(Android)
  package func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Android.open(pathPointer, Android.O_RDONLY)
    }
  }

  package func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Android.close(fileDescriptor)
  }

  package func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.read(fileDescriptor, buffer, count)
  }

  package func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.write(fileDescriptor, buffer, count)
  }
#elseif canImport(Musl)
  package func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Musl.open(pathPointer, Musl.O_RDONLY)
    }
  }

  package func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Musl.close(fileDescriptor)
  }

  package func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Musl.read(fileDescriptor, buffer, count)
  }

  package func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Musl.write(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  package func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe Glibc.open(pathPointer, Glibc.O_RDONLY)
    }
  }

  package func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    Glibc.close(fileDescriptor)
  }

  package func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }

  package func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.write(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  package func webSurfaceOpenRead(
    _ path: String
  ) -> Int32 {
    unsafe path.withCString { pathPointer in
      unsafe WASILibc.open(pathPointer, WASILibc.O_RDONLY)
    }
  }

  package func webSurfaceClose(
    _ fileDescriptor: Int32
  ) -> Int32 {
    WASILibc.close(fileDescriptor)
  }

  package func webSurfaceRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  }

  package func webSurfaceWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.write(fileDescriptor, buffer, count))
  }
#endif

#if canImport(Darwin) || canImport(Android) || canImport(Musl) || canImport(Glibc) || canImport(WASILibc)
  package let webSurfaceStandardInputFileDescriptor: Int32 = STDIN_FILENO
  package let webSurfaceStandardOutputFileDescriptor: Int32 = STDOUT_FILENO

  package var webSurfaceErrno: Int32 {
    errno
  }

  package func webSurfaceErrnoIsWouldBlock(_ value: Int32) -> Bool {
    value == EAGAIN || value == EWOULDBLOCK
  }
#endif
