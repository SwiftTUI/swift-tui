#if !os(Windows)
  import Testing

  @testable import SwiftTUIWebHost

  struct WebHostOutboundBudgetTests {
    @Test("outbound admission includes the active record and reclaims exact bytes")
    func recordAndByteLimits() {
      var budget = WebHostOutboundBudget()
      for _ in 0..<WebHostOutboundBudget.recordLimit {
        let admitted = budget.admit(1)
        #expect(admitted)
      }
      let extraRecord = budget.admit(1)
      #expect(!extraRecord)
      #expect(budget.records == 32)
      budget.release(1)
      let exactBytes = budget.admit(WebHostOutboundBudget.byteLimit - 31)
      #expect(exactBytes)
      #expect(budget.bytes == WebHostOutboundBudget.byteLimit)
      let extraByte = budget.admit(1)
      #expect(!extraByte)
      budget.release(WebHostOutboundBudget.byteLimit - 31)
      let oversized = budget.admit(WebHostOutboundBudget.byteLimit - 30)
      #expect(!oversized)
      #expect(budget.records == 31)
      #expect(budget.bytes == 31)
    }

    @Test("detached reliable control bytes are capped without evicting admitted records")
    func detachedByteLimit() async throws {
      let channel = WebHostSceneChannel()
      let record = [UInt8](repeating: 65, count: WebHostOutboundBudget.byteLimit)
      try await channel.send(record)
      await #expect(throws: WebHostByteSinkError.outboundBacklogExceeded) {
        try await channel.send([66])
      }
      let observations = await channel.consumeObservations()
      #expect(observations.detachedNonSurfaceBacklogCount == 1)
      #expect(observations.detachedNonSurfaceBacklogBytes == WebHostOutboundBudget.byteLimit)
      await channel.shutdown()
    }

    @Test("cancelled socket writes detach only their own connection and release waiters")
    func cancelledWrite() async throws {
      let channel = WebHostSceneChannel()
      let client = AsyncStream<WebHostSocketMessage>.makeStream()
      let (output, connectionToken) = await channel.attachSocket(client: client.stream) {}
      let token = try #require(connectionToken)
      let sending = Task { try await channel.send([65], connectionToken: token) }
      var iterator = output.makeAsyncIterator()
      #expect(await iterator.next() == .data([65]))
      sending.cancel()
      await #expect(throws: WebHostByteSinkError.sendDidNotComplete) {
        try await sending.value
      }
      #expect(await channel.currentConnectionToken() == nil)
      #expect(await channel.consumeObservations().sceneInputFinished == false)
      await channel.shutdown()
      client.continuation.finish()
    }
  }
#endif
