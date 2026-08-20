import Foundation
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// Units for the screen-aware `.standardError` runtime-issue sink: while a
/// terminal host owns an alternate-screen session, issues must not write to
/// fd 2 (the same tty as the owned screen) — they route to the debug bundle's
/// `runtime-issues.log` when one is armed, and otherwise into a bounded
/// deferral buffer the CLI runner flushes after teardown.
@MainActor
@Suite("Runtime issue screen-aware routing", .serialized)
struct RuntimeIssueScreenRoutingTests {
  private func resetProcessState() {
    while TerminalScreenOwnership.isScreenOwned {
      TerminalScreenOwnership.release()
    }
    _ = DeferredRuntimeIssueBuffer.drain()
    DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
  }

  private func makeIssue(code: String) -> RuntimeIssue {
    RuntimeIssue(
      severity: .warning,
      code: code,
      message: "screen-routing test issue"
    )
  }

  @Test("ownership latch counts nested sessions and clamps at zero")
  func ownershipLatchCountsAndClamps() {
    resetProcessState()
    defer { resetProcessState() }

    #expect(!TerminalScreenOwnership.isScreenOwned)

    TerminalScreenOwnership.acquire()
    TerminalScreenOwnership.acquire()
    #expect(TerminalScreenOwnership.isScreenOwned)

    TerminalScreenOwnership.release()
    #expect(TerminalScreenOwnership.isScreenOwned)

    TerminalScreenOwnership.release()
    #expect(!TerminalScreenOwnership.isScreenOwned)

    // An unbalanced release must not push the count negative and swallow the
    // next session's acquire.
    TerminalScreenOwnership.release()
    TerminalScreenOwnership.acquire()
    #expect(TerminalScreenOwnership.isScreenOwned)
  }

  @Test("issues defer to the bounded buffer while the screen is owned")
  func ownedScreenDefersIssues() {
    resetProcessState()
    defer { resetProcessState() }

    TerminalScreenOwnership.acquire()
    RuntimeIssueSink.standardError.report(makeIssue(code: "test.deferredIssue"))
    TerminalScreenOwnership.release()

    let deferred = DeferredRuntimeIssueBuffer.drain()
    #expect(deferred.count == 1)
    #expect(deferred.first?.contains("test.deferredIssue") == true)
    #expect(deferred.first?.hasSuffix("\n") == true)

    // Drained means drained: the flush after teardown must be a no-op.
    #expect(DeferredRuntimeIssueBuffer.drain().isEmpty)
    RuntimeIssueSink.flushDeferredStandardErrorIssues()
    #expect(DeferredRuntimeIssueBuffer.drain().isEmpty)
  }

  @Test("issues append to the bundle's runtime-issues.log while the screen is owned")
  func ownedScreenWritesToBundleLog() throws {
    resetProcessState()
    let directory =
      NSTemporaryDirectory()
      + "swifttui-screen-routing-\(ProcessInfo.processInfo.processIdentifier)"
    defer {
      try? FileManager.default.removeItem(atPath: directory)
      resetProcessState()
    }

    DebugLogRouter.installDefaultDebugDirectory(directory)
    TerminalScreenOwnership.acquire()
    RuntimeIssueSink.standardError.report(makeIssue(code: "test.bundledIssue"))
    RuntimeIssueSink.standardError.report(makeIssue(code: "test.bundledIssue.second"))
    TerminalScreenOwnership.release()

    let log = try String(
      contentsOfFile: directory + "/runtime-issues.log", encoding: .utf8
    )
    #expect(log.contains("test.bundledIssue"))
    #expect(log.contains("test.bundledIssue.second"))
    // Bundle-routed issues must not double-report through the deferral path.
    #expect(DeferredRuntimeIssueBuffer.drain().isEmpty)
  }

  @Test("an unowned screen leaves nothing deferred")
  func unownedScreenDefersNothing() {
    resetProcessState()
    defer { resetProcessState() }

    RuntimeIssueSink.standardError.report(makeIssue(code: "test.directIssue"))

    #expect(DeferredRuntimeIssueBuffer.drain().isEmpty)
  }

  @Test("the deferral buffer bounds itself and reports the overflow")
  func deferralBufferBoundsItself() {
    resetProcessState()
    defer { resetProcessState() }

    let overflow = 3
    for index in 0..<(DeferredRuntimeIssueBuffer.capacity + overflow) {
      DeferredRuntimeIssueBuffer.append("issue \(index)\n")
    }

    let drained = DeferredRuntimeIssueBuffer.drain()
    #expect(drained.count == DeferredRuntimeIssueBuffer.capacity + 1)
    #expect(drained.last?.contains("\(overflow) additional issue(s)") == true)
    #expect(DeferredRuntimeIssueBuffer.drain().isEmpty)
  }
}
