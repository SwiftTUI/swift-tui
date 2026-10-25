// Adversarial set H, pass 1 (F6 platform edges): process and clipboard
// helpers whose behaviour depends on the host platform (setH095–setH100).
// Children are reaped through the subject's own completion hook; nothing
// polls process state.
#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @_spi(Testing) @testable import SwiftTUICore
  @_spi(Runners) @testable import SwiftTUIRuntime
  @testable import SwiftTUIViews

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  #if os(Linux)
    private let setHIsLinux = true
  #else
    private let setHIsLinux = false
  #endif

  @Suite("Adversarial set H: process helpers", .serialized)
  struct AdversarialSetHProcessHelperTests {
    @Test func setH095MissingHelperReturnsFalse() {
      let spawned = spawnDetachedProcess(
        command: "swifttui-f6-missing-helper",
        arguments: ["swifttui-f6-missing-helper", "https://example.invalid/"],
        searchPath: true)
      #expect(!spawned)
      #expect(!openLinkInSystem(LinkDestination("")))
    }

    @Test func setH096DetachedChildIsReaped() async throws {
      let pid: pid_t = await withCheckedContinuation { continuation in
        let spawned = spawnDetachedProcess(
          command: "/usr/bin/true", arguments: ["/usr/bin/true"], searchPath: false
        ) { pid in
          continuation.resume(returning: pid)
        }
        if !spawned {
          continuation.resume(returning: -1)
        }
      }
      try #require(pid > 0)
      var status: Int32 = 0
      let reaped = unsafe waitpid(pid, &status, WNOHANG)
      let failure = errno
      #expect(reaped == -1)
      #expect(failure == ECHILD)
    }

    // macOS reads the pasteboard through pbpaste; that arm is not exercised
    // here so the run never reads the operator's clipboard.
    @Test(.enabled(if: setHIsLinux, "macOS reads the real pasteboard"))
    func setH097ClipboardReadIsNilOffMacOS() {
      #expect(systemClipboardText() == nil)
    }

    @Test func setH098AbsoluteMissingCommandReturnsFalse() {
      let spawned = spawnDetachedProcess(
        command: "/nonexistent/setH098/open", arguments: ["/nonexistent/setH098/open"],
        searchPath: false)
      #expect(!spawned)
    }

    // The runtime's chunk reader sees the platform split that PTYPair
    // documents: EIO on Linux, end of file on Darwin.
    @Test func setH099MasterChunkReadAfterSlaveCloseByPlatform() throws {
      let pty = try SetHPTY()
      defer { pty.closeMaster() }
      pty.closeSlave()
      let chunk = readTerminalInputChunk(from: pty.master, maxBytes: 16)
      let drained = drainAvailableTerminalInput(from: pty.master, maxBytesPerRead: 16)
      #if os(Linux)
        #expect(chunk == .failure(errno: EIO))
        #expect(drained.failureErrno == EIO)
      #else
        #expect(chunk == .endOfFile)
        #expect(drained.failureErrno == nil)
      #endif
      #expect(drained.shouldFinish)
      #expect(drained.bytes.isEmpty)
    }

    @Test func setH100GlyphPreferenceApplication() {
      let unicode = TerminalCapabilityProfile.detectPOSIXTerminal(
        environment: ["LANG": "C.UTF-8", "TERM": "xterm"], isTTY: true)
      #expect(unicode.applying(RuntimeConfiguration(glyphs: .ascii)).glyphLevel == .ascii)
      let ascii = TerminalCapabilityProfile.detectPOSIXTerminal(
        environment: ["LANG": "C", "TERM": "xterm"], isTTY: true)
      #expect(ascii.applying(RuntimeConfiguration(glyphs: .unicode)).glyphLevel == .ascii)
    }
  }
#endif
