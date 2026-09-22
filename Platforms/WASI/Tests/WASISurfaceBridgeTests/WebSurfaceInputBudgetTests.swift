@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite struct WebSurfaceInputBudgetTests {
  @Test func unterminatedInputIsDiscardedThroughNewlineAndRecovers() {
    var parser = WebSurfaceInputParser()
    _ = parser.feed([0x1E])
    let chunk = [UInt8](repeating: 120, count: 8192)
    for _ in 0..<1024 {
      let result = parser.feed(chunk)
      #expect(result.events.isEmpty && result.controlMessages.isEmpty)
      #expect(parser.bufferedCommandBytes.count < HostWireBudget.recordBytes)
    }
    let result = parser.feed(Array("\u{1E}resize:100:20\n\u{1E}resize:80:24\n".utf8))
    #expect(result.controlMessages.count == 1)
    #expect(result.events.isEmpty)
    #expect(parser.bufferedCommandBytes.isEmpty)
  }

  @Test func oversizedResizeNeverReachesRasterAllocation() {
    var parser = WebSurfaceInputParser()
    for command in ["resize:1025:1", "resize:257:256", "resize:9223372036854775807:2"] {
      #expect(parser.feed(Array("\u{1E}\(command)\n".utf8)).controlMessages.isEmpty)
    }
    #expect(parser.feed(Array("\u{1E}resize:256:256\n".utf8)).controlMessages.count == 1)
  }
}
