import SwiftTUIPTYPrimitives
import Testing

@testable import SwiftTUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite(.serialized)
struct ScenePtyTests {
  @Test("Allocates a pty pair with valid file descriptors")
  func allocatesScenePty() async throws {
    try await withScenePty { pty in
      #expect(await pty.pair.rawMasterFD >= 0)
      #expect(pty.slavePath.hasPrefix("/dev/"))
    }
  }

  @Test("Close invalidates the master fd")
  func closeInvalidatesMasterFD() async throws {
    let pty = try ScenePty()
    await pty.close()
    #expect(await pty.pair.rawMasterFD == -1)
    #expect(await pty.hasAttachedClient() == false)
  }

  @Test("Multiple allocations produce distinct fds")
  func multipleAllocationsDistinct() async throws {
    try await withScenePtyPair { pty1, pty2 in
      #expect(await pty1.pair.rawMasterFD != pty2.pair.rawMasterFD)
      #expect(pty1.slavePath != pty2.slavePath)
    }
  }

  @Test("Attached client detection tracks slave open and close")
  func attachedClientDetection() async throws {
    try await withScenePty { pty in
      #expect(await waitForScenePty(pty, attached: false))

      let slaveFD = sceneOpen(pty.slavePath, O_RDWR | O_NOCTTY)
      #expect(slaveFD >= 0)
      #expect(await waitForScenePty(pty, attached: true))

      sceneClose(slaveFD)
      #expect(await waitForScenePty(pty, attached: false))
    }
  }

  #if canImport(Darwin)
    @Test("Master fd suppresses SIGPIPE on Darwin")
    func masterSuppressesSigPipeOnDarwin() async throws {
      try await withScenePty { pty in
        let fd = await pty.pair.rawMasterFD
        #expect(fcntl(fd, F_GETNOSIGPIPE) == 1)
      }
    }
  #endif
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

private func withScenePtyPair<R>(
  _ body: (ScenePty, ScenePty) async throws -> R
) async throws -> R {
  let pty1 = try ScenePty()
  do {
    let pty2 = try ScenePty()
    do {
      let result = try await body(pty1, pty2)
      await pty2.close()
      await pty1.close()
      return result
    } catch {
      await pty2.close()
      await pty1.close()
      throw error
    }
  } catch {
    await pty1.close()
    throw error
  }
}
