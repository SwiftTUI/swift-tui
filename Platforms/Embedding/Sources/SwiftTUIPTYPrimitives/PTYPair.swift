// PTY plumbing is POSIX-only; dependency edges exclude Windows.
#if !os(Windows)
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
    // The unfolding stream has no implicit buffer. At most 64 KiB waits here,
    // plus one <=4 KiB chunk owned by the consumer. Kernel buffers are separate.
    static let readBufferLimit = 65_536
    private struct ReadChunk {
      let bytes: [UInt8]
      let readTime: UInt64
    }
    private var readQueue: [ReadChunk] = []
    private(set) var queuedReadBytes = 0
    private var readWaiter: CheckedContinuation<[UInt8]?, Never>?
    private var readingFinished = false
    private var childExited = false
    private var readGeneration: UInt64 = 0
    private let trace = PTYReadTrace()
    private var readQueueObserver: (@Sendable (Int) -> Void)?

    func observeReadQueue(_ observer: @escaping @Sendable (Int) -> Void) {
      readQueueObserver = observer
      observer(queuedReadBytes)
    }
    private var didStartReading = false
    private struct PendingWrite {
      let id: UInt64
      let bytes: [UInt8]
      var offset = 0
      let continuation: CheckedContinuation<Result<Void, PTYError>, Never>
    }
    private var pendingWrites: [PendingWrite] = []
    private var nextWriteID: UInt64 = 0
    private var writeSource: (any DispatchSourceWrite)?
    private var writeGeneration: UInt64 = 0

    deinit {
      readSource?.cancel()
      writeSource?.cancel()
      readWaiter?.resume(returning: nil)
      closeFD(masterFD)
      closeFD(retainedSlaveFD)
    }

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

    /// Writes are serialized in admission order. Cancellation returns ECANCELED;
    /// bytes already accepted by the kernel remain delivered, and the unwritten
    /// suffix is discarded. Closing fails all pending writes with notStarted.
    public func write(_ bytes: [UInt8]) async throws(PTYError) {
      trace?.record("writeStart", slave: slavePath, bytes: bytes.count)
      let id = nextWriteID
      nextWriteID &+= 1
      let result: Result<Void, PTYError> = await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          guard !Task.isCancelled else {
            continuation.resume(returning: .failure(.writeFailed(errno: ECANCELED)))
            return
          }
          guard masterFD >= 0 else {
            continuation.resume(returning: .failure(.notStarted))
            return
          }
          pendingWrites.append(PendingWrite(id: id, bytes: bytes, continuation: continuation))
          pendingWriteObserver?(pendingWrites.count)
          if pendingWrites.count == 1 { drainWrites() }
        }
      } onCancel: {
        Task { await self.cancelWrite(id) }
      }
      trace?.record("writeEnd", slave: slavePath, bytes: bytes.count)
      try result.get()
    }

    var pendingWriteCount: Int { pendingWrites.count }
    private var pendingWriteObserver: (@Sendable (Int) -> Void)?
    func observePendingWrites(_ observer: @escaping @Sendable (Int) -> Void) {
      pendingWriteObserver = observer
      observer(pendingWrites.count)
    }

    private func cancelWrite(_ id: UInt64) {
      guard let index = pendingWrites.firstIndex(where: { $0.id == id }) else { return }
      pendingWrites.remove(at: index).continuation.resume(
        returning: .failure(.writeFailed(errno: ECANCELED)))
      if index == 0 {
        cancelWriteSource()
        drainWrites()
      }
    }

    private func cancelWriteSource() {
      writeGeneration &+= 1
      writeSource?.cancel()
      writeSource = nil
    }

    private func drainWrites() {
      guard masterFD >= 0, writeSource == nil else { return }
      var turnBytes = 0
      while !pendingWrites.isEmpty {
        let request = pendingWrites[0]
        if request.offset == request.bytes.count {
          pendingWrites.removeFirst().continuation.resume(returning: .success(()))
          continue
        }
        // Bound one actor turn even when a peer drains continuously.
        if turnBytes >= 65_536 {
          Task {
            await Task.yield()
            self.drainWrites()
          }
          return
        }
        let written = request.bytes.withUnsafeBufferPointer { buffer in
          unsafe ptyWriteOnce(
            masterFD, buffer.baseAddress! + request.offset,
            min(65_536 - turnBytes, request.bytes.count - request.offset))
        }
        if written > 0 {
          pendingWrites[0].offset += written
          turnBytes += written
          continue
        }
        let failure = errno
        if written < 0 && failure == EINTR { continue }
        if written < 0 && (failure == EAGAIN || failure == EWOULDBLOCK) {
          waitForWritable()
          return
        }
        pendingWrites.removeFirst().continuation.resume(
          returning: .failure(.writeFailed(errno: written == 0 ? EIO : failure)))
      }
    }

    private func waitForWritable() {
      // The source owns a duplicate until its cancel handler runs. Closing the
      // actor's descriptor cannot make a delayed dispatch callback watch a
      // recycled descriptor. Callbacks only notify the actor; they never write.
      let fd = fcntl(masterFD, F_DUPFD_CLOEXEC, 0)
      guard fd >= 0 else {
        let failure = PTYError.writeFailed(errno: errno)
        let writes = pendingWrites
        pendingWrites.removeAll()
        for request in writes { request.continuation.resume(returning: .failure(failure)) }
        return
      }
      writeGeneration &+= 1
      let generation = writeGeneration
      let source = DispatchSource.makeWriteSource(
        fileDescriptor: fd,
        queue: DispatchQueue.global(qos: .userInitiated))
      source.setEventHandler { [weak self] in
        source.cancel()
        Task { await self?.becameWritable(generation) }
      }
      source.setCancelHandler { closeFD(fd) }
      writeSource = source
      source.resume()
    }

    private func becameWritable(_ generation: UInt64) {
      guard generation == writeGeneration else { return }
      cancelWriteSource()
      drainWrites()
    }

    /// A single-consumer, lossless stream. Stop requesting chunks to apply
    /// backpressure to the child. Cancellation ends reading; call close() to
    /// release descriptors when abandoning a pair.
    public func read() -> AsyncStream<[UInt8]> {
      guard !didStartReading else {
        return AsyncStream { $0.finish() }
      }
      didStartReading = true
      startReading()
      return AsyncStream(unfolding: { await self.nextChunk() })
    }

    private func nextChunk() async -> [UInt8]? {
      await withTaskCancellationHandler {
        guard !Task.isCancelled else {
          cancelReading()
          return nil
        }
        if !readQueue.isEmpty {
          let chunk = readQueue.removeFirst()
          queuedReadBytes -= chunk.bytes.count
          recordRead("dequeue", count: chunk.bytes.count, readTime: chunk.readTime)
          readQueueObserver?(queuedReadBytes)
          // A full queue has no armed source. Consumption restarts the reader.
          startReading()
          return chunk.bytes
        }
        guard !readingFinished else { return nil }
        return await withCheckedContinuation { continuation in
          precondition(readWaiter == nil, "PTYPair.read() supports one consumer")
          readWaiter = continuation
          startReading()
        }
      } onCancel: {
        Task { await self.cancelReading() }
      }
    }

    /// Darwin can discard unread output when the last slave closes. A full
    /// queue therefore defers that close until consumption reaches EAGAIN.
    /// Process exit notification itself must never wait for a consumer.
    func finishChildOutput() {
      childExited = true
      if readingFinished {
        releaseAndCloseSlaveFD()
      } else {
        cancelReadSource()
        drainAvailable()
      }
    }

    public func close() {
      finishReading()
      cancelWriteSource()
      let writes = pendingWrites
      pendingWrites.removeAll()
      for request in writes { request.continuation.resume(returning: .failure(.notStarted)) }

      if masterFD >= 0 {
        closeFD(masterFD)
        masterFD = -1
      }

      if retainedSlaveFD >= 0 {
        closeFD(retainedSlaveFD)
        retainedSlaveFD = -1
      }
    }

    func startReading() {
      guard !readingFinished, readSource == nil, queuedReadBytes < Self.readBufferLimit else {
        return
      }
      drainAvailable()
    }

    private func waitForReadable() {
      guard readSource == nil, !readingFinished else { return }
      let fd = fcntl(masterFD, F_DUPFD_CLOEXEC, 0)
      guard fd >= 0 else {
        close()
        return
      }
      readGeneration &+= 1
      let generation = readGeneration
      let source = DispatchSource.makeReadSource(
        fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
      // One callback per arm: a readable full PTY cannot enqueue unbounded
      // actor tasks while the consumer is stalled.
      source.setEventHandler { [weak self] in
        source.cancel()
        Task { await self?.becameReadable(generation) }
      }
      source.setCancelHandler { closeFD(fd) }
      readSource = source
      source.resume()
    }

    private func becameReadable(_ generation: UInt64) {
      guard generation == readGeneration else { return }
      cancelReadSource()
      drainAvailable()
    }

    private func cancelReadSource() {
      readGeneration &+= 1
      readSource?.cancel()
      readSource = nil
    }

    private func cancelReading() {
      finishReading()
      readQueue.removeAll()
      queuedReadBytes = 0
      readQueueObserver?(0)
      if childExited { releaseAndCloseSlaveFD() }
    }

    private func finishReading() {
      readingFinished = true
      cancelReadSource()
      let waiter = readWaiter
      readWaiter = nil
      waiter?.resume(returning: nil)
    }

    private func recordRead(_ event: String, count: Int, readTime: UInt64 = 0) {
      guard let trace else { return }
      let now = DispatchTime.now().uptimeNanoseconds
      trace.record(
        event, time: now, slave: slavePath, bytes: count, queued: queuedReadBytes,
        oldest: readQueue.first.map { now - $0.readTime } ?? 0,
        residence: readTime == 0 ? 0 : now - readTime)
    }

    private func drainAvailable() {
      guard !readingFinished else { return }
      guard masterFD >= 0 else {
        finishReading()
        return
      }
      var buffer = [UInt8](repeating: 0, count: 4096)
      // Strict byte budget, including a short read at the remaining boundary.
      while queuedReadBytes < Self.readBufferLimit {
        let budget = min(buffer.count, Self.readBufferLimit - queuedReadBytes)
        let readCount = buffer.withUnsafeMutableBufferPointer { storage in
          unsafe ptyReadOnce(masterFD, storage.baseAddress!, budget)
        }
        if readCount > 0 {
          let chunk = ReadChunk(
            bytes: Array(buffer.prefix(readCount)),
            readTime: trace == nil ? 0 : DispatchTime.now().uptimeNanoseconds)
          recordRead("read", count: readCount)
          if let waiter = readWaiter {
            readWaiter = nil
            recordRead("dequeue", count: readCount, readTime: chunk.readTime)
            waiter.resume(returning: chunk.bytes)
          } else {
            readQueue.append(chunk)
            queuedReadBytes += readCount
            recordRead("enqueue", count: readCount)
            readQueueObserver?(queuedReadBytes)
          }
          continue
        }
        if readCount == 0 {
          close()
          return
        }
        let failureErrno = errno
        if failureErrno == EINTR { continue }
        if failureErrno == EAGAIN || failureErrno == EWOULDBLOCK {
          if childExited && retainedSlaveFD >= 0 {
            releaseAndCloseSlaveFD()
            // Recheck EOF (or a descendant's output) after the retained close.
            continue
          }
          waitForReadable()
          return
        }
        // Linux reports EIO when the last slave closes.
        close()
        return
      }
      recordRead("full", count: 0)
    }

    private static func setNonblocking(_ fd: Int32) {
      let flags = fcntl(fd, F_GETFL, 0)
      guard flags >= 0 else {
        return
      }

      _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
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
#endif
