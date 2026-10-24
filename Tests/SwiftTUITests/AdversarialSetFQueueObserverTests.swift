import Synchronization
import Testing

@testable import SwiftTUIRuntime

@Suite("set F queued-job observer reentry")
struct AdversarialSetFQueueObserverTests {
  @Test(arguments: Array(41...50))
  func observerBoundary(id: Int) {
    let token = FrameTailJobCancellationToken()
    let trace = Mutex<[String]>([])
    switch id {
    case 41:
      token.onRelease {
        trace.withLock { $0.append(token.currentState.rawValue) }
        token.markCompleted()
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["started"])
      #expect(token.currentState == .completed)
    case 42:
      token.onRelease {
        trace.withLock { $0.append(token.currentState.rawValue) }
        token.markCompleted()
      }
      #expect(token.cancelBeforeStart())
      #expect(trace.withLock { $0 } == ["cancelled_before_start"])
      #expect(token.currentState == .cancelledBeforeStart)
    case 43:
      token.onRelease {
        trace.withLock { $0.append("outer") }
        token.onRelease { trace.withLock { $0.append("inner") } }
        trace.withLock { $0.append("returned") }
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["outer", "inner", "returned"])
    case 44:
      token.onRelease {
        trace.withLock { $0.append("outer") }
        token.onRelease { trace.withLock { $0.append("inner") } }
        trace.withLock { $0.append("returned") }
      }
      #expect(token.cancelBeforeStart())
      #expect(trace.withLock { $0 } == ["outer", "inner", "returned"])
    case 45:
      token.onRelease {
        trace.withLock { $0.append(String(token.markStarted())) }
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["true"])
      #expect(token.currentState == .started)
    case 46:
      token.onRelease {
        trace.withLock { $0.append(String(token.markStarted())) }
      }
      #expect(token.cancelBeforeStart())
      #expect(trace.withLock { $0 } == ["false"])
      #expect(token.currentState == .cancelledBeforeStart)
    case 47:
      token.onRelease {
        trace.withLock { $0.append(String(token.cancelBeforeStart())) }
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["false"])
      #expect(token.currentState == .started)
    case 48:
      token.onRelease {
        trace.withLock { $0.append(String(token.cancelBeforeStart())) }
      }
      #expect(token.cancelBeforeStart())
      #expect(trace.withLock { $0 } == ["false"])
      #expect(token.currentState == .cancelledBeforeStart)
    case 49:
      let next = FrameTailJobCancellationToken()
      token.onRelease {
        trace.withLock { $0.append("first") }
        _ = next.markStarted()
      }
      next.onRelease {
        trace.withLock { $0.append("second") }
        token.markCompleted()
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["first", "second"])
      #expect(token.currentState == .completed)
      #expect(next.currentState == .started)
    default:
      let next = FrameTailJobCancellationToken()
      token.onRelease {
        trace.withLock { $0.append("first") }
        _ = next.cancelBeforeStart()
      }
      next.onRelease {
        trace.withLock { $0.append("second") }
        trace.withLock { $0.append(String(token.cancelBeforeStart())) }
      }
      #expect(token.markStarted())
      #expect(trace.withLock { $0 } == ["first", "second", "false"])
      #expect(token.currentState == .started)
      #expect(next.currentState == .cancelledBeforeStart)
    }
  }
}
