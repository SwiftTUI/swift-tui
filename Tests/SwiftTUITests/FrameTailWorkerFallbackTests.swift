import Foundation
import Synchronization
import Testing

@testable import SwiftTUIRuntime

struct FrameTailWorkerFallbackTests {
  @Test("Layout worker runs the operation exactly once regardless of platform")
  func workerRunsOperationOnce() async {
    let box = FrameTailLayoutWorkerBox()
    let count = Mutex(0)

    let result = await box.async {
      count.withLock { value in
        value += 1
      }
      return 42
    }

    #expect(result == 42)
    #expect(count.withLock { $0 } == 1)
  }

  @Test("Immediate fallback scheduler runs the operation exactly once")
  func immediateFallbackRunsOperationOnce() async {
    let box = FrameTailLayoutWorkerBox(scheduling: .immediate)
    let count = Mutex(0)

    let result = await box.async {
      count.withLock { value in
        value += 1
      }
      return 43
    }

    #expect(result == 43)
    #expect(count.withLock { $0 } == 1)
  }

  @Test("No-Dispatch fallback shares the test-exercised immediate scheduler")
  func noDispatchFallbackSharesImmediateScheduler() throws {
    let root = try repositoryRoot()
    let source = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift"
      ),
      encoding: .utf8
    )

    #expect(source.contains("private struct ImmediateFrameTailLayoutWorker"))
    #expect(source.contains("case immediate(ImmediateFrameTailLayoutWorker)"))
    #expect(!source.contains("#else\n  private final class FrameTailLayoutWorker"))
  }
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw FrameTailWorkerFallbackSourceError.missingPackageRoot
}

private enum FrameTailWorkerFallbackSourceError: Error {
  case missingPackageRoot
}
