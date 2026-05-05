import SwiftTUIPTYPrimitives
import Testing

@testable import SwiftTUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ScenePtyTests {
  @Test("Allocates a pty pair with valid file descriptors")
  func allocatesScenePty() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }

    #expect(await pty.pair.rawMasterFD >= 0)
    #expect(pty.slavePath.hasPrefix("/dev/"))
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
    let pty1 = try ScenePty()
    let pty2 = try ScenePty()
    defer {
      Task {
        await pty1.close()
        await pty2.close()
      }
    }

    #expect(await pty1.pair.rawMasterFD != pty2.pair.rawMasterFD)
    #expect(pty1.slavePath != pty2.slavePath)
  }

  @Test("Attached client detection tracks slave open and close")
  func attachedClientDetection() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }

    #expect(await pty.hasAttachedClient() == false)

    let slaveFD = sceneOpen(pty.slavePath, O_RDWR | O_NOCTTY)
    #expect(slaveFD >= 0)
    #expect(await pty.hasAttachedClient())

    sceneClose(slaveFD)
    #expect(await pty.hasAttachedClient() == false)
  }

  #if canImport(Darwin)
    @Test("Master fd suppresses SIGPIPE on Darwin")
    func masterSuppressesSigPipeOnDarwin() async throws {
      let pty = try ScenePty()
      defer { Task { await pty.close() } }

      let fd = await pty.pair.rawMasterFD
      #expect(fcntl(fd, F_GETNOSIGPIPE) == 1)
    }
  #endif
}
