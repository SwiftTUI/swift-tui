import SwiftTUITestSupport
import Testing

@Suite("AsyncEvent one-shot signal")
struct AsyncEventTests {
  @Test("wait returns immediately when the event already fired")
  func waitAfterFireReturnsImmediately() async {
    let event = AsyncEvent()
    event.fire()
    await event.wait()
  }

  @Test("fire resumes a waiter that suspended first")
  func fireResumesPendingWaiter() async {
    let event = AsyncEvent()
    let waiterStarted = AsyncEvent()

    let waiter = Task {
      waiterStarted.fire()
      await event.wait()
    }

    await waiterStarted.wait()
    event.fire()
    await waiter.value
  }

  @Test("every waiter observes a single firing")
  func allWaitersObserveFiring() async {
    let event = AsyncEvent()
    let waiters = (0..<8).map { _ in
      Task { await event.wait() }
    }

    event.fire()

    for waiter in waiters {
      await waiter.value
    }
  }

  @Test("fire is idempotent and a later wait still returns")
  func fireIsIdempotent() async {
    let event = AsyncEvent()
    event.fire()
    event.fire()
    await event.wait()
  }
}
