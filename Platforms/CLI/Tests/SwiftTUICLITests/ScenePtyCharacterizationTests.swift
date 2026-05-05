import SwiftTUIPTYPrimitives
import Testing

@testable import SwiftTUICLI

@Suite("ScenePty characterization")
struct ScenePtyCharacterizationTests {
  @Test("init opens a usable master fd and slave path")
  func initOpensUsableFds() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }

    let fd = await pty.pair.rawMasterFD
    #expect(fd >= 0)
    #expect(!pty.slavePath.isEmpty)
    #expect(pty.slavePath.hasPrefix("/dev/"))
  }

  @Test("hasAttachedClient returns false when no client has opened the slave")
  func hasAttachedClientFalseInitially() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }

    let attached = await pty.hasAttachedClient()
    #expect(attached == false)
  }
}
