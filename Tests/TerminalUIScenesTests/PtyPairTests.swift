import Testing

@testable import TerminalUIScenes

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct PtyPairTests {
  @Test("Allocates a pty pair with valid file descriptors")
  func allocatesPtyPair() throws {
    let pty = try PtyPair()
    #expect(pty.masterFD >= 0)
    #expect(pty.slavePath.hasPrefix("/dev/"))
    pty.close()
  }

  @Test("Close invalidates the master fd")
  func closeInvalidatesMasterFD() throws {
    let pty = try PtyPair()
    pty.close()
    #expect(pty.masterFD == -1)
    #expect(!pty.hasAttachedClient())
  }

  @Test("Multiple allocations produce distinct fds")
  func multipleAllocationsDistinct() throws {
    let pty1 = try PtyPair()
    let pty2 = try PtyPair()
    #expect(pty1.masterFD != pty2.masterFD)
    #expect(pty1.slavePath != pty2.slavePath)
    pty1.close()
    pty2.close()
  }

  @Test("Attached client detection tracks slave open and close")
  func attachedClientDetection() throws {
    let pty = try PtyPair()
    #expect(!pty.hasAttachedClient())

    let slaveFD = sceneOpen(pty.slavePath, O_RDWR | O_NOCTTY)
    #expect(slaveFD >= 0)
    #expect(pty.hasAttachedClient())

    sceneClose(slaveFD)
    #expect(!pty.hasAttachedClient())
    pty.close()
  }
}
