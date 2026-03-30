import Synchronization
import Testing

@testable import TerminalUI

@Suite
struct StreamingTerminalHostTests {
  @Test("streaming terminal host writes terminal control sequences to its output handler")
  func streamingTerminalHostWritesToOutputHandler() throws {
    let writes = Mutex<[String]>([])
    let host = StreamingTerminalHost(
      surfaceSize: .init(width: 10, height: 4),
      outputHandler: { output in
        writes.withLock { capturedWrites in
          capturedWrites.append(output)
        }
      }
    )

    try host.enableRawMode()
    try host.write("Hello")
    host.updateSurfaceSize(.init(width: 12, height: 6))
    let updatedAppearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    host.updateAppearance(updatedAppearance)
    try host.disableRawMode()

    let output = writes.withLock { $0.joined() }

    #expect(output.contains("\u{001B}[?1049h"))
    #expect(output.contains("\u{001B}[?1049l"))
    #expect(output.contains("Hello"))
    #expect(host.surfaceSize == .init(width: 12, height: 6))
    #expect(host.appearance == updatedAppearance)
  }
}
