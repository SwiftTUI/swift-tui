import SwiftTUIPTYPrimitives
import Testing

@testable import SwiftTUICLI

@Suite("ScenePty characterization", .serialized)
struct ScenePtyCharacterizationTests {
  @Test("init opens a usable master fd and slave path")
  func initOpensUsableFds() async throws {
    try await withScenePty { pty in
      let fd = await pty.pair.rawMasterFD
      #expect(fd >= 0)
      #expect(!pty.slavePath.isEmpty)
      #expect(pty.slavePath.hasPrefix("/dev/"))
    }
  }

  @Test("hasAttachedClient returns false when no client has opened the slave")
  func hasAttachedClientFalseInitially() async throws {
    try await withScenePty { pty in
      #expect(await pty.hasAttachedClient() == false)
    }
  }
}

private func withScenePty<R>(
  _ body: (ScenePty) async throws -> R
) async throws -> R {
  let pty = try ScenePty()
  do {
    let result = try await body(pty)
    await pty.close()
    return result
  } catch {
    await pty.close()
    throw error
  }
}
