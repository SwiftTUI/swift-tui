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
}
