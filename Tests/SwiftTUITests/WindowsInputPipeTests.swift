#if os(Windows)
  import CRT
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @testable import SwiftTUIRuntime

  @MainActor
  @Suite(.timeLimit(.minutes(1)))
  struct WindowsInputPipeTests {
    @Test("redirected UTF-8 input reaches both streams and finishes", arguments: [false, true])
    func bytesAndEOF(terminalEvents: Bool) async throws {
      let pipe = try WindowsPipeFixture()
      let reader = InputReader(fileDescriptor: pipe.input)
      try pipe.write("é😀q")
      pipe.finish()
      var keys: [KeyPress] = []
      if terminalEvents {
        for await event in reader.inputEvents() {
          if case .key(let key) = event { keys.append(key) }
        }
      } else {
        for await key in reader.events() { keys.append(key) }
      }
      #expect(
        keys == [KeyPress(.character("é")), KeyPress(.character("😀")), KeyPress(.character("q"))])
    }

    @Test("an idle redirected pipe remains cancellable")
    func idlePipeCancellation() async throws {
      let pipe = try WindowsPipeFixture()
      let reader = InputReader(fileDescriptor: pipe.input)
      let started = AsyncEvent()
      let consumer = Task {
        let stream = reader.inputEvents()
        started.fire()
        for await _ in stream {}
      }
      await started.wait()
      consumer.cancel()
      await consumer.value
    }

    @Test("a suspended pipe reader leaves the external operation's bytes untouched")
    func handoffOwnsInput() async throws {
      let pipe = try WindowsPipeFixture()
      let reader = InputReader(fileDescriptor: pipe.input)
      let stream = reader.events()
      let operation: @MainActor @Sendable () async throws -> Void = {
        try pipe.write("a")
        #expect(readWindowsRedirectedInputChunk(from: pipe.input, maxBytes: 512) == .bytes([0x61]))
      }
      try await reader.withInputSuspended(operation)
      try pipe.write("q")
      pipe.finish()
      var keys: [KeyPress] = []
      for await key in stream { keys.append(key) }
      #expect(keys == [KeyPress(.character("q"))])
    }
  }

  @MainActor
  private final class WindowsPipeFixture {
    let input: Int32
    private var output: Int32

    init() throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(openTestPipe(&descriptors) == 0)
      input = descriptors[0]
      output = descriptors[1]
    }

    func write(_ text: String) throws {
      let bytes = Array(text.utf8)
      let written = unsafe bytes.withUnsafeBufferPointer {
        unsafe _write(output, $0.baseAddress, UInt32($0.count))
      }
      try #require(written == bytes.count)
    }

    func finish() {
      closeTestDescriptor(output)
      output = -1
    }

    deinit {
      closeTestDescriptor(input)
      if output >= 0 { closeTestDescriptor(output) }
    }
  }
#endif
