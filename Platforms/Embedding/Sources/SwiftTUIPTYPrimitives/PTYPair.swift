public import SwiftTUICore

#if canImport(Darwin)
  import Darwin
  @unsafe @preconcurrency import Dispatch
#elseif canImport(Glibc)
  import Glibc
  @unsafe @preconcurrency import Dispatch
#endif

public actor PTYPair {
  public let slavePath: String

  private var masterFD: Int32
  private var retainedSlaveFD: Int32
  private var readSource: (any DispatchSourceRead)?
  private var readContinuation: AsyncStream<[UInt8]>.Continuation?
  private var didStartReading = false

  public init(handles: PTYHandles, retainSlaveFD: Bool) {
    masterFD = handles.masterFD
    slavePath = handles.slavePath
    retainedSlaveFD = retainSlaveFD ? handles.slaveFD : -1
    if !retainSlaveFD {
      closeFD(handles.slaveFD)
    }
    Self.setNonblocking(handles.masterFD)
  }

  public var rawMasterFD: Int32 {
    masterFD
  }

  public func releaseSlaveFD() -> Int32 {
    let fd = retainedSlaveFD
    retainedSlaveFD = -1
    return fd
  }

  public func releaseAndCloseSlaveFD() {
    if retainedSlaveFD >= 0 {
      closeFD(retainedSlaveFD)
      retainedSlaveFD = -1
    }
  }

  public func resize(_ size: CellSize) throws(PTYError) {
    guard masterFD >= 0 else {
      throw .notStarted
    }

    try ptyResize(masterFD: masterFD, cols: size.width, rows: size.height)
  }

  public func write(_ bytes: [UInt8]) throws(PTYError) {
    guard masterFD >= 0 else {
      throw .notStarted
    }

    var offset = 0
    while offset < bytes.count {
      let written = unsafe bytes.withUnsafeBufferPointer { buffer -> Int in
        guard let baseAddress = buffer.baseAddress else {
          return 0
        }

        return unsafe ptyWriteOnce(masterFD, baseAddress + offset, bytes.count - offset)
      }

      if written > 0 {
        offset += written
        continue
      }

      let failureErrno = errno
      if failureErrno == EINTR {
        continue
      }

      if failureErrno == EAGAIN || failureErrno == EWOULDBLOCK {
        guard Self.waitUntilWritable(masterFD) else {
          throw .writeFailed(errno: errno)
        }
        continue
      }

      throw .writeFailed(errno: failureErrno)
    }
  }

  public func read() -> AsyncStream<[UInt8]> {
    AsyncStream { continuation in
      Task {
        await self.startReading(continuation: continuation)
      }
    }
  }

  public func close() {
    finishReading()

    if masterFD >= 0 {
      closeFD(masterFD)
      masterFD = -1
    }

    if retainedSlaveFD >= 0 {
      closeFD(retainedSlaveFD)
      retainedSlaveFD = -1
    }
  }

  private func startReading(continuation: AsyncStream<[UInt8]>.Continuation) async {
    guard !didStartReading, masterFD >= 0 else {
      continuation.finish()
      return
    }

    didStartReading = true
    readContinuation = continuation

    let source = DispatchSource.makeReadSource(
      fileDescriptor: masterFD,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler { [weak self] in
      guard let self else {
        return
      }

      Task {
        await self.drainAvailable()
      }
    }
    source.setCancelHandler {}
    continuation.onTermination = { @Sendable [weak self] _ in
      guard let self else {
        return
      }

      Task {
        await self.stopReading()
      }
    }

    readSource = source
    source.resume()
  }

  private func stopReading() {
    readSource?.cancel()
    readSource = nil
    readContinuation = nil
  }

  private func finishReading() {
    readSource?.cancel()
    readSource = nil
    readContinuation?.finish()
    readContinuation = nil
  }

  private func drainAvailable() {
    guard masterFD >= 0 else {
      finishReading()
      return
    }

    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let readCount = unsafe buffer.withUnsafeMutableBufferPointer { storage -> Int in
        guard let baseAddress = storage.baseAddress else {
          return 0
        }

        return unsafe ptyReadOnce(masterFD, baseAddress, storage.count)
      }

      if readCount > 0 {
        readContinuation?.yield(Array(buffer.prefix(Int(readCount))))
        continue
      }

      if readCount == 0 {
        finishReading()
        return
      }

      let failureErrno = errno
      if failureErrno == EINTR {
        continue
      }

      if failureErrno == EAGAIN || failureErrno == EWOULDBLOCK {
        return
      }

      finishReading()
      return
    }
  }

  private static func setNonblocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL, 0)
    guard flags >= 0 else {
      return
    }

    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
  }

  private static func waitUntilWritable(_ fd: Int32) -> Bool {
    var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    while true {
      let result = unsafe poll(&descriptor, 1, 100)
      if result > 0 {
        return (descriptor.revents & Int16(POLLOUT)) != 0
      }

      if result == 0 {
        return true
      }

      if errno != EINTR {
        return false
      }
    }
  }
}

private func ptyWriteOnce(
  _ fd: Int32,
  _ pointer: UnsafePointer<UInt8>,
  _ count: Int
) -> Int {
  unsafe write(fd, pointer, count)
}

private func ptyReadOnce(
  _ fd: Int32,
  _ pointer: UnsafeMutablePointer<UInt8>,
  _ count: Int
) -> Int {
  unsafe read(fd, pointer, count)
}
