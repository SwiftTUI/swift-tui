#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#endif

#if canImport(Darwin)
  func terminalPlatformWrite(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.write(fileDescriptor, buffer, count)
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
    unsafe Glibc.write(fileDescriptor, buffer, count)
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
    unsafe Android.write(fileDescriptor, buffer, count)
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
#endif
