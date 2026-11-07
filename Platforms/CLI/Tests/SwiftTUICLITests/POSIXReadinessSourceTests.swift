#if !os(Windows)
  import Dispatch
  import SwiftTUIPlatformIO
  import Synchronization
  import Testing
  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  @Suite("Poll-backed descriptor readiness", .serialized, .timeLimit(.minutes(1)))
  struct POSIXReadinessSourceTests {
    @Test("hangup drains data and cancellation acknowledges descriptor retirement")
    func hangup() async throws {
      // Exercise immediate HUP during registration and retirement repeatedly.
      // The Linux allocator-guard qualification runs the same path under load.
      for _ in 0..<100 {
        var descriptors: [Int32] = [-1, -1]
        try #require(unsafe pipe(&descriptors) == 0)
        let reader = descriptors[0]
        let writer = descriptors[1]
        let source = POSIXReadinessSource(
          fileDescriptor: reader, queue: DispatchQueue(label: "poll-source-test"))
        let received = Mutex<[UInt8]>([])
        source.setEventHandler {
          var bytes: [UInt8] = [0, 0, 0, 0]
          let count = unsafe read(reader, &bytes, bytes.count)
          if count > 0 { received.withLock { $0 += bytes.prefix(count) } }
          if count == 0 { source.cancel() }
        }
        let payload: [UInt8] = [1, 2, 3]
        #expect(unsafe write(writer, payload, payload.count) == payload.count)
        close(writer)
        await withCheckedContinuation { continuation in
          source.setCancelHandler {
            close(reader)
            continuation.resume()
          }
          source.resume()
        }
        #expect(received.withLock { $0 } == payload)
      }
    }

    @Test("cancel retires an idle poll")
    func cancellation() async throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      let reader = descriptors[0]
      let writer = descriptors[1]
      defer { close(writer) }
      let source = POSIXReadinessSource(
        fileDescriptor: reader, queue: DispatchQueue(label: "poll-idle-test"))
      source.setEventHandler { Issue.record("an empty open pipe is not readable") }
      await withCheckedContinuation { continuation in
        source.setCancelHandler {
          close(reader)
          continuation.resume()
        }
        source.resume()
        source.cancel()
      }
    }

    @Test("suspension prevents reads until the matching resume")
    func suspension() async throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      let reader = descriptors[0]
      let writer = descriptors[1]
      defer { close(writer) }
      let queue = DispatchQueue(label: "poll-suspension-test")
      let source = POSIXReadinessSource(fileDescriptor: reader, queue: queue)
      let delivered = Mutex(false)
      source.setEventHandler {
        source.cancel()
        // Cancellation must wait for the event callback to return.
        delivered.withLock { $0 = true }
      }
      source.resume()
      source.suspend()
      queue.sync {}
      var byte: UInt8 = 1
      #expect(unsafe write(writer, &byte, 1) == 1)
      queue.sync {}
      #expect(!delivered.withLock { $0 })
      await withCheckedContinuation { continuation in
        source.setCancelHandler {
          #expect(delivered.withLock { $0 })
          close(reader)
          continuation.resume()
        }
        source.resume()
      }
    }

    @Test("writable sources retire when cancelled while suspended")
    func writableCancellation() async throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      defer { close(descriptors[0]) }
      let writer = descriptors[1]
      let source = POSIXReadinessSource(
        fileDescriptor: writer, writable: true, queue: DispatchQueue(label: "poll-write-test"))
      let delivered = Mutex(false)
      source.setEventHandler {
        delivered.withLock { $0 = true }
        source.suspend()
        source.cancel()
        source.resume()
      }
      await withCheckedContinuation { continuation in
        source.setCancelHandler {
          close(writer)
          continuation.resume()
        }
        source.resume()
      }
      #expect(delivered.withLock { $0 })
    }
  }
#endif
