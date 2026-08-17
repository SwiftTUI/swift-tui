// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  import SwiftTUIPTYPrimitives
  import SwiftTUIRuntime
  import Testing

  @testable import SwiftTUITerminal

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @Suite("ChildProcessPty", .serialized)
  struct ChildProcessPtyTests {
    @Test("spawn a child process and read its output through the shared pair")
    func spawnEcho() async throws {
      let pty = ChildProcessPty(
        executable: "/bin/sh",
        arguments: ["-c", "printf 'hello\\n'; sleep 0.2"],
        environment: nil,
        workingDirectory: nil,
        initialSize: CellSize(width: 80, height: 24)
      )
      try await pty.start()
      var collected: [UInt8] = []
      let deadline = ContinuousClock.now.advanced(by: .seconds(2))
      for await chunk in await pty.pair.read() {
        collected.append(contentsOf: chunk)
        if collected.contains(UInt8(ascii: "\n")) { break }
        if ContinuousClock.now > deadline { break }
      }
      #expect(String(decoding: collected, as: UTF8.self).contains("hello"))
      let exit = await pty.waitForExit()
      #expect(exit == .exited(code: 0))
    }

    @Test("resize forwards through PTYPair to the child")
    func resize() async throws {
      let pty = ChildProcessPty(
        executable: "/bin/cat",
        arguments: [],
        environment: nil,
        workingDirectory: nil,
        initialSize: CellSize(width: 10, height: 5)
      )
      try await pty.start()
      try await pty.pair.resize(CellSize(width: 100, height: 30))
      try await pty.pair.write(Array("\u{04}".utf8))
      let exit = await pty.waitForExit()
      #expect(exit == .exited(code: 0))
    }

    @Test("sendSignal terminates the child")
    func sendSignal() async throws {
      let pty = ChildProcessPty(
        executable: "/bin/sleep",
        arguments: ["10"],
        environment: nil,
        workingDirectory: nil,
        initialSize: CellSize(width: 80, height: 24)
      )
      try await pty.start()
      try await pty.sendSignal(SIGTERM)
      let exit = await pty.waitForExit()
      #expect(exit == .signalled(signal: SIGTERM))
    }

    @Test("a signal requested before start is delivered after pid installation")
    func requestSignalBeforeStart() async throws {
      let pty = ChildProcessPty(
        executable: "/bin/sleep",
        arguments: ["10"],
        environment: nil,
        workingDirectory: nil,
        initialSize: CellSize(width: 80, height: 24)
      )

      await pty.requestSignal(SIGTERM)
      try await pty.start()

      let exit = await pty.waitForExit()
      #expect(exit == .signalled(signal: SIGTERM))
    }
  }

#endif
