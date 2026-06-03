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
      #expect(await waitForScenePty(pty, attached: false))
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

private func waitForScenePty(
  _ pty: ScenePty,
  attached expected: Bool,
  timeout: Duration = .milliseconds(250)
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)

  repeat {
    if await pty.hasAttachedClient() == expected {
      return true
    }
    try? await Task.sleep(for: .milliseconds(5))
  } while clock.now < deadline

  return await pty.hasAttachedClient() == expected
}
