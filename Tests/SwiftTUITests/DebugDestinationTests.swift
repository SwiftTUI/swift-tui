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
  struct DebugDestinationTests {
    @Test("two live terminals, duplicate descriptors, and redirected pipes")
    func twoTerminals() throws {
      var a: Int32 = -1
      var app: Int32 = -1
      var b: Int32 = -1
      var viewer: Int32 = -1
      try #require(unsafe openpty(&a, &app, nil, nil, nil) == 0)
      try #require(unsafe openpty(&b, &viewer, nil, nil, nil) == 0)
      let alias = dup(app)
      defer { for fd in [a, app, b, viewer, alias] { _ = close(fd) } }
      DiagnosticScreenOwnership.acquire(app)
      defer { DiagnosticScreenOwnership.release(app) }
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: alias))
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: viewer))
      let issue = RuntimeIssue(severity: .warning, code: "test.twoTTY", message: "live")
      RuntimeIssueSink.standardError(to: viewer).report(issue)
      #expect(readAvailable(b).contains("test.twoTTY"), "visible before app teardown")
      #expect(readAvailable(a).isEmpty, "presentation terminal is uncorrupted")
      DiagnosticScreenOwnership.acquire(viewer)
      #expect(!DiagnosticScreenOwnership.allowsDiagnosticWrite(to: viewer))
      DiagnosticScreenOwnership.release(viewer)
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: viewer))
      RuntimeIssueSink.standardError(to: alias).report(issue)
      #expect(DeferredRuntimeIssueBuffer.drain().contains { $0.contains("test.twoTTY") })
      #expect(readAvailable(a).isEmpty)
      var pipes: [Int32] = [-1, -1]
      try #require(unsafe pipe(&pipes) == 0)
      defer { for fd in pipes { _ = close(fd) } }
      #expect(DiagnosticScreenOwnership.allowsDiagnosticWrite(to: pipes[1]))
      RuntimeIssueSink.standardError(to: pipes[1]).report(issue)
      #expect(readAvailable(pipes[0]).contains("test.twoTTY"))
    }

    @Test("bundle precedence and failed file fallback preserve live stderr")
    func bundleAndFailure() throws {
      let dir = NSTemporaryDirectory() + "debug-destination-" + UUID().uuidString
      defer {
        DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
        try? FileManager.default.removeItem(atPath: dir)
      }
      var pipes: [Int32] = [-1, -1]
      try #require(unsafe pipe(&pipes) == 0)
      defer { for fd in pipes { _ = close(fd) } }
      DebugLogRouter.installDefaultDebugDirectory(dir)
      let record = BodyChangeRecord(typeName: "Counter", kind: "view", causes: [.init("identity")])
      BodyChangeOutput.emitPortable(record, format: .text, descriptor: pipes[1])
      BodyChangeOutput.emitPortable(record, format: .json, descriptor: pipes[1])
      #expect(readAvailable(pipes[0]).isEmpty)
      #expect(
        try String(contentsOfFile: dir + "/changes.log", encoding: .utf8) == record.formatted(.text)
      )
      #expect(
        try String(contentsOfFile: dir + "/changes.jsonl", encoding: .utf8)
          == record.formatted(.json))
      #expect(
        DebugLogRouter.emit(
          "fallback\n", toFileAt: dir,
          fallback: .safeStandardError, standardErrorDescriptor: pipes[1]))
      #expect(readAvailable(pipes[0]) == "fallback\n")
    }

    @Test("unsafe output is counted once, and closed/full pipes never hang or signal")
    func failures() throws {
      var pipes: [Int32] = [-1, -1]
      try #require(unsafe pipe(&pipes) == 0)
      defer { _ = close(pipes[1]) }
      let record = BodyChangeRecord(typeName: "Counter", kind: "view", causes: [.init("identity")])
      DiagnosticScreenOwnership.acquire()
      BodyChangeOutput.emitPortable(record, format: .json, descriptor: pipes[1])
      BodyChangeOutput.flushSuppressed(to: pipes[1])
      #expect(readAvailable(pipes[0]).isEmpty)
      DiagnosticScreenOwnership.release()
      BodyChangeOutput.flushSuppressed(to: pipes[1])
      #expect(readAvailable(pipes[0]).contains("1 record(s) suppressed"))
      BodyChangeOutput.flushSuppressed(to: pipes[1])
      #expect(readAvailable(pipes[0]).isEmpty)
      let originalFlags = fcntl(pipes[1], F_GETFL)
      let began = ContinuousClock.now
      #expect(
        !DebugLogRouter.writeDiagnostic(String(repeating: "x", count: 1_048_576), to: pipes[1]))
      #expect(ContinuousClock.now - began < .seconds(1))
      #expect(fcntl(pipes[1], F_GETFL) == originalFlags)
      _ = close(pipes[0])
      #expect(!DebugLogRouter.writeDiagnostic("closed\n", to: pipes[1]))
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
