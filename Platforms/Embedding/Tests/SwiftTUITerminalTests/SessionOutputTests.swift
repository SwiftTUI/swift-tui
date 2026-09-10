#if !os(Windows)
  import Foundation
  import SwiftTUIRuntime
  import Testing

  @testable import SwiftTUITerminal

  @Suite("Terminal process output", .serialized)
  struct SessionOutputTests {
    @Test("cat drains a large file and retains its final output", .timeLimit(.minutes(1)))
    func catRetainsLargeFileTail() async throws {
      let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("terminal-session-output-\(UUID().uuidString).txt")
      defer { try? FileManager.default.removeItem(at: file) }
      let contents =
        "\u{001B}]2;terminal-output-start\u{0007}"
        + String(repeating: String(repeating: "x", count: 79) + "\n", count: 13_108)
        + "\u{001B}]2;terminal-output-end\u{0007}terminal-output-tail"
      try contents.write(to: file, atomically: true, encoding: .utf8)
      let session = TerminalProcessSession(
        command: "/bin/cat", arguments: [file.path],
        initialSize: CellSize(width: 80, height: 24)
      )
      let events = session.events()
      try await session.start()
      var titles: [String] = []
      for await event in events {
        if case .titleChanged(let title) = event { titles.append(title) }
      }
      #expect(await session.currentLifecycle() == .exited(reason: .normal(code: 0)))
      #expect(titles == ["terminal-output-start", "terminal-output-end"])
      let snapshot = await session.snapshot()
      let text = snapshot.cells.map { String($0.map(\.character)) }.joined(separator: "\n")
      #expect(text.contains("terminal-output-tail"))
    }
  }
#endif
