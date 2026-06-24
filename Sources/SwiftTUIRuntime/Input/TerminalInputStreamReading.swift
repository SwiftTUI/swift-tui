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
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Darwin.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Glibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Glibc.read(fileDescriptor, buffer, count)
  }
#elseif canImport(Android)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    unsafe Android.read(fileDescriptor, buffer, count)
  }
#elseif canImport(WASILibc)
  private func platformRead(
    _ fileDescriptor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ count: Int
  ) -> Int {
    Int(unsafe WASILibc.read(fileDescriptor, buffer, count))
  }
#endif

package enum TerminalInputReadResult: Equatable, Sendable {
  case bytes([UInt8])
  case wouldBlock
  case endOfFile
  case failure(errno: Int32)
}

package struct TerminalInputDrainResult: Equatable, Sendable {
  package var bytes: [UInt8]
  package var shouldFinish: Bool
  package var failureErrno: Int32?

  package init(
    bytes: [UInt8],
    shouldFinish: Bool,
    failureErrno: Int32? = nil
  ) {
    self.bytes = bytes
    self.shouldFinish = shouldFinish
    self.failureErrno = failureErrno
  }
}

package func readTerminalInputChunk(
  from fileDescriptor: Int32,
  maxBytes: Int
) -> TerminalInputReadResult {
  var bytesRead = 0
  let buffer = unsafe [UInt8](unsafeUninitializedCapacity: maxBytes) { buf, count in
    bytesRead = unsafe platformRead(fileDescriptor, buf.baseAddress, maxBytes)
    count = bytesRead > 0 ? bytesRead : 0
  }

  if bytesRead > 0 {
    return .bytes(buffer)
  }

  if bytesRead == 0 {
    return .endOfFile
  }

  if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
    return .wouldBlock
  }

  return .failure(errno: errno)
}

package func drainAvailableTerminalInput(
  from fileDescriptor: Int32,
  maxBytesPerRead: Int
) -> TerminalInputDrainResult {
  var input: [UInt8] = []

  while true {
    switch readTerminalInputChunk(
      from: fileDescriptor,
      maxBytes: maxBytesPerRead
    ) {
    case .bytes(let bytes):
      input.append(contentsOf: bytes)
    case .wouldBlock:
      return TerminalInputDrainResult(
        bytes: input,
        shouldFinish: false
      )
    case .endOfFile:
      return TerminalInputDrainResult(
        bytes: input,
        shouldFinish: true
      )
    case .failure(let failureErrno):
      return TerminalInputDrainResult(
        bytes: input,
        shouldFinish: true,
        failureErrno: failureErrno
      )
    }
  }
}
