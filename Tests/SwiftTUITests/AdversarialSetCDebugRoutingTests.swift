import Foundation
import Testing

@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
  @MainActor
  @Suite(.serialized)
  struct AdversarialSetCDebugRoutingTests {
    @Test func setC171OwnedTTYAllowsPipeRefusesClosed() throws {
      var controller: Int32 = -1
      var app: Int32 = -1
      try #require(unsafe openpty(&controller, &app, nil, nil, nil) == 0)
      defer { for fd in [controller, app] { _ = close(fd) } }
      DiagnosticScreenOwnership.acquire(app)
      defer { DiagnosticScreenOwnership.release(app) }
      var pipes: [Int32] = [-1, -1]
      try #require(unsafe pipe(&pipes) == 0)
      defer { for fd in pipes { _ = close(fd) } }
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: pipes[1]))
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: -1))
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: app))
    }

    @Test func setC172NonTerminalOwnerSilencesPipes() throws {
      var owner: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      defer { for fd in owner { _ = close(fd) } }
      var redirected: [Int32] = [-1, -1]
      try #require(unsafe pipe(&redirected) == 0)
      defer { for fd in redirected { _ = close(fd) } }
      try #require(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: redirected[1]))
      DiagnosticScreenOwnership.acquire(owner[1])
      defer { DiagnosticScreenOwnership.release(owner[1]) }
      let allowed = DiagnosticScreenOwnership.allowsDiagnosticWrite(to: redirected[1])
      let issue = RuntimeIssue(severity: .warning, code: "setC172.pipeOwner", message: "redirected")
      RuntimeIssueSink.standardError(to: redirected[1]).report(issue)
      let received = readAvailable(redirected[0])
      // STUI-1210: a pipe owner is not a terminal to protect (STUI-1089 contract).
      #expect(allowed)
      #expect(received.contains("setC172.pipeOwner"), "\(received)")
    }

    // FW3-A neighbors (STUI-1210): a pipe-owned presentation admits every
    // other non-terminal destination, but not its own stream, not a terminal
    // (the pipe may feed one), not a closed descriptor, and not anything while
    // an owner of unknown kind is active.
    @Test func wave3a10PipeOwnerAllowsRedirectedFile() throws {
      var owner: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      defer { for fd in owner { _ = close(fd) } }
      let path = NSTemporaryDirectory() + "wave3a10-" + UUID().uuidString + ".log"
      let file = path.withCString { unsafe open($0, O_RDWR | O_CREAT | O_TRUNC, 0o600) }
      try #require(file >= 0)
      defer {
        _ = close(file)
        _ = path.withCString { unsafe unlink($0) }
      }
      DiagnosticScreenOwnership.acquire(owner[1])
      defer { DiagnosticScreenOwnership.release(owner[1]) }
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: file))
    }

    @Test func wave3a11PipeOwnerRefusesItsOwnStream() throws {
      var owner: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      let alias = dup(owner[1])
      defer { for fd in owner + [alias] { _ = close(fd) } }
      try #require(alias >= 0)
      DiagnosticScreenOwnership.acquire(owner[1])
      defer { DiagnosticScreenOwnership.release(owner[1]) }
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: owner[1]))
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: alias))
    }

    @Test func wave3a12PipeOwnerRefusesTerminalsAndInvalidDescriptors() throws {
      var owner: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      var controller: Int32 = -1
      var viewer: Int32 = -1
      try #require(unsafe openpty(&controller, &viewer, nil, nil, nil) == 0)
      defer { for fd in owner + [controller, viewer] { _ = close(fd) } }
      DiagnosticScreenOwnership.acquire(owner[1])
      defer { DiagnosticScreenOwnership.release(owner[1]) }
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: viewer))
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: -1))
    }

    @Test func wave3a13UnknownOwnerStillSilencesRedirectedPipe() throws {
      var owner: [Int32] = [-1, -1]
      try #require(unsafe pipe(&owner) == 0)
      var redirected: [Int32] = [-1, -1]
      try #require(unsafe pipe(&redirected) == 0)
      defer { for fd in owner + redirected { _ = close(fd) } }
      DiagnosticScreenOwnership.acquire(owner[1])
      defer { DiagnosticScreenOwnership.release(owner[1]) }
      DiagnosticScreenOwnership.acquire()
      defer { DiagnosticScreenOwnership.release() }
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: redirected[1]))
    }

    @Test func setC173BalancedOwnershipCounts() throws {
      var controller: Int32 = -1
      var app: Int32 = -1
      try #require(unsafe openpty(&controller, &app, nil, nil, nil) == 0)
      let alias = dup(app)
      defer { for fd in [controller, app, alias] { _ = close(fd) } }
      DiagnosticScreenOwnership.acquire(app)
      DiagnosticScreenOwnership.acquire(app)
      DiagnosticScreenOwnership.release(app)
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: alias))
      DiagnosticScreenOwnership.release(app)
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: alias))
    }

    @Test func setC174EmptyOverrideIgnored() {
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
      #expect(DebugLogRouter.resolvedFilePath(override: "", bundleFileName: "x.log") == nil)
      #expect(
        DebugLogRouter.resolvedFilePath(override: "/tmp/setC174.log", bundleFileName: "x.log")
          == "/tmp/setC174.log")
    }

    @Test func setC175InstalledDirectoryNormalizedAndSticky() {
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
      defer { DebugLogRouter.resetInstalledDefaultDirectoryForTesting() }
      let directory = NSTemporaryDirectory() + "setC175-" + UUID().uuidString
      #expect(DebugLogRouter.installDefaultDebugDirectory(directory + "///") == directory)
      #expect(DebugLogRouter.installDefaultDebugDirectory(directory + "-other") == directory)
      #expect(DebugLogRouter.activeDebugDirectory() == directory)
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
      #expect(DebugLogRouter.activeDebugDirectory() == nil)
    }

    @Test func setC176SafeEmitToReaderlessFifoFallsBack() throws {
      let path = NSTemporaryDirectory() + "setC176-" + UUID().uuidString + ".fifo"
      try #require(path.withCString { unsafe mkfifo($0, 0o644) } == 0)
      defer { _ = path.withCString { unsafe unlink($0) } }
      var fallback: [Int32] = [-1, -1]
      try #require(unsafe pipe(&fallback) == 0)
      defer { for fd in fallback { _ = close(fd) } }
      let clock = ContinuousClock()
      let start = clock.now
      let delivered = DebugLogRouter.emit(
        "setC176 fifo fallback\n", toFileAt: path, fallback: .safeStandardError,
        standardErrorDescriptor: fallback[1])
      let elapsed = clock.now - start
      #expect(delivered)
      #expect(elapsed < .seconds(1), "\(elapsed)")
      #expect(readAvailable(fallback[0]).contains("setC176 fifo fallback"))
    }

    private func readAvailable(_ descriptor: Int32) -> String {
      let flags = fcntl(descriptor, F_GETFL)
      _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
      defer { _ = fcntl(descriptor, F_SETFL, flags) }
      var bytes = [UInt8](repeating: 0, count: 16_384)
      let count = bytes.withUnsafeMutableBytes { unsafe read(descriptor, $0.baseAddress, $0.count) }
      return count > 0 ? String(decoding: bytes.prefix(count), as: UTF8.self) : ""
    }
  }
#endif
