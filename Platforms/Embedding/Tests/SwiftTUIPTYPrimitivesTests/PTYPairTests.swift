// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  import SwiftTUI
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  import Dispatch
  import Synchronization

  @testable import SwiftTUIPTYPrimitives

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @Suite("PTYPair", .serialized)
  struct PTYPairTests {
    @Test("init from handles exposes masterFD and slavePath")
    func initFromHandles() async throws {
      try await withPTYPair(retainSlaveFD: false) { handles, pair in
        #expect(await pair.rawMasterFD >= 0)
        #expect(await pair.slavePath == handles.slavePath)
      }
    }

    @Test("write to master is readable on the slave")
    func writeMasterReadSlave() async throws {
      try await withPTYPair(retainSlaveFD: true) { handles, pair in
        try await pair.write(Array("hello\n".utf8))

        var buffer = [UInt8](repeating: 0, count: 16)
        let n = buffer.withUnsafeMutableBufferPointer { buf in
          unsafe read(handles.slaveFD, buf.baseAddress, buf.count)
        }
        #expect(n >= 5)
        let received = Array(buffer.prefix(Int(n)))
        #expect(received.starts(with: Array("hello".utf8)))
      }
    }

    @Test("resize updates the kernel winsize")
    func resize() async throws {
      try await withPTYPair(retainSlaveFD: true) { handles, pair in
        try await pair.resize(CellSize(width: 132, height: 50))

        var ws = winsize()
        _ = unsafe ioctl(handles.masterFD, UInt(TIOCGWINSZ), &ws)
        #expect(ws.ws_col == 132)
        #expect(ws.ws_row == 50)
      }
    }

    @Test("saturated writes cancel and close without a reader", arguments: [false, true])
    func saturatedWrite(cancel: Bool) async throws {
      let completed = Mutex(false)
      DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        precondition(completed.withLock { $0 }, "PTY cancellation/close watchdog expired")
      }
      defer { completed.withLock { $0 = true } }
      try await withPTYPair(retainSlaveFD: true) { handles, pair in
        try makeRaw(handles.slaveFD)
        let writer = Task { try await pair.write([UInt8](repeating: 0x61, count: 4 * 1024 * 1024)) }
        await pendingWrites(pair, atLeast: 1)
        if cancel { writer.cancel() } else { await pair.close() }
        let result = await writer.result
        switch result {
        case .success: Issue.record("A saturated write unexpectedly completed")
        case .failure(let error):
          #expect((error as? PTYError) == (cancel ? .writeFailed(errno: ECANCELED) : .notStarted))
        }
        #expect(await pair.pendingWriteCount == 0)
      }
    }

    @Test("partial writes remain ordered across readiness suspensions")
    func partialWriteOrdering() async throws {
      let completed = Mutex(false)
      DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
        precondition(completed.withLock { $0 }, "PTY ordering watchdog expired")
      }
      defer { completed.withLock { $0 = true } }
      try await withPTYPair(retainSlaveFD: true) { handles, pair in
        try makeRaw(handles.slaveFD)
        _ = fcntl(handles.slaveFD, F_SETFL, O_NONBLOCK)
        let first = [UInt8](repeating: 0x61, count: 128 * 1024)
        let second = [UInt8](repeating: 0x62, count: 128 * 1024)
        let a = Task { try await pair.write(first) }
        await pendingWrites(pair, atLeast: 1)
        let b = Task { try await pair.write(second) }
        await pendingWrites(pair, atLeast: 2)
        var received: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.count < first.count + second.count {
          let n = unsafe read(handles.slaveFD, &buffer, buffer.count)
          if n > 0 {
            received.append(contentsOf: buffer.prefix(n))
          } else {
            await readable(handles.slaveFD)
          }
        }
        try await a.value
        try await b.value
        #expect(received == first + second)
      }
    }

    @Test("close and cancellation race without resuming or writing twice")
    func closeCancelRace() async throws {
      for _ in 0..<32 {
        try await withPTYPair(retainSlaveFD: true) { handles, pair in
          try makeRaw(handles.slaveFD)
          let writer = Task { try await pair.write([UInt8](repeating: 1, count: 128 * 1024)) }
          await pendingWrites(pair, atLeast: 1)
          let closer = Task { await pair.close() }
          writer.cancel()
          await closer.value
          #expect(await pair.rawMasterFD == -1)
          #expect(await pair.pendingWriteCount == 0)
          if case .success = await writer.result { Issue.record("saturated write completed") }
        }
      }
    }

    @Test("a child whose exec fails releases its PTY")
    func failedChildExec() async throws {
      let child = ChildProcessPty(
        executable: "/nonexistent/swifttui-reliability-test",
        initialSize: .init(width: 80, height: 24))
      try await child.start()
      let pair = try #require(await child.pair)
      let exit = await child.waitForExit()
      #expect(exit == .exited(code: 127))
      #expect(await pair.rawMasterFD == -1)
    }

    @Test("last-owner cleanup preserves transferred and reused descriptors")
    func finalOwnerCleanup() async throws {
      for iteration in 0..<100 {
        let handles = try openPTY()
        var pair: PTYPair? = PTYPair(handles: handles, retainSlaveFD: true)
        let transferred = iteration.isMultiple(of: 2)
        if transferred { #expect(await pair?.releaseSlaveFD() == handles.slaveFD) }
        if iteration.isMultiple(of: 3) { await pair?.close() }
        weak let weakPair = pair
        pair = nil
        #expect(weakPair == nil)
        #expect(fcntl(handles.masterFD, F_GETFD) == -1)
        #expect((fcntl(handles.slaveFD, F_GETFD) >= 0) == transferred)
        if transferred { closeFD(handles.slaveFD) }
      }
      let handles = try openPTY()
      var pair: PTYPair? = PTYPair(handles: handles, retainSlaveFD: true)
      _ = await pair?.read()
      await pair?.close()
      let replacement = unsafe open("/dev/null", O_RDONLY)
      defer { closeFD(replacement) }
      pair = nil
      // A source cancel handler owns a duplicate, never the now-reusable master.
      #expect(fcntl(replacement, F_GETFD) >= 0)
    }

    @Test("openPTY resolves slave paths while other threads open PTYs")
    func concurrentOpenResolvesSlavePaths() async {
      let failures = await withTaskGroup(of: [String].self) { group in
        for _ in 0..<8 {
          group.addTask {
            var failures: [String] = []
            for _ in 0..<50 {
              do throws(PTYError) {
                let handles = try openPTY()
                if !handles.slavePath.hasPrefix("/dev/") {
                  failures.append("unexpected slave path \(handles.slavePath)")
                }
                closeFD(handles.masterFD)
                closeFD(handles.slaveFD)
              } catch {
                failures.append(error.description)
              }
            }
            return failures
          }
        }
        var failures: [String] = []
        for await taskFailures in group {
          failures += taskFailures
        }
        return failures
      }
      #expect(
        failures.isEmpty, "\(failures.count) of 400 opens failed; first: \(failures.first ?? "")")
    }
  }

  private func pendingWrites(_ pair: PTYPair, atLeast target: Int) async {
    let signal = ConditionSignal()
    let count = Mutex(0)
    await pair.observePendingWrites { value in
      count.withLock { $0 = value }
      signal.notify()
    }
    await signal.wait(until: { count.withLock { $0 >= target } })
  }

  private func readable(_ fd: Int32) async {
    await withCheckedContinuation { continuation in
      let source = DispatchSource.makeReadSource(
        fileDescriptor: fd,
        queue: DispatchQueue.global())
      source.setEventHandler { source.cancel() }
      source.setCancelHandler { continuation.resume() }
      source.resume()
    }
  }

  private func makeRaw(_ fd: Int32) throws {
    var attributes = termios()
    #expect(unsafe tcgetattr(fd, &attributes) == 0)
    unsafe cfmakeraw(&attributes)
    #expect(unsafe tcsetattr(fd, TCSANOW, &attributes) == 0)
  }

  private func withPTYPair<R>(
    retainSlaveFD: Bool,
    _ body: (PTYHandles, PTYPair) async throws -> R
  ) async throws -> R {
    let handles = try openPTY()
    let pair = PTYPair(handles: handles, retainSlaveFD: retainSlaveFD)
    do {
      let result = try await body(handles, pair)
      await pair.close()
      return result
    } catch {
      await pair.close()
      throw error
    }
  }

#endif
