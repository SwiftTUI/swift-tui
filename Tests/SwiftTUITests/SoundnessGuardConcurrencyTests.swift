@_spi(Testing) import SwiftTUITestSupport
import Testing

@Suite(.serialized)
struct SoundnessGuardConcurrencyTests {
  @Test("peer soundness scopes queue instead of overlapping counter windows")
  func peerScopesAreProcessExclusive() async {
    let gate = SoundnessCounterScopeGate()
    await gate.acquire()

    let contenderStarted = AsyncEvent()
    let contenderAcquired = AsyncEvent()
    let contender = Task {
      contenderStarted.fire()
      await gate.acquire()
      contenderAcquired.fire()
      await gate.release()
    }

    await contenderStarted.wait()
    await gate.waitUntilWaitingCount(atLeast: 1)
    #expect(
      await gate.waitingCount == 1,
      "a peer scope must queue while the process-global counter window is held"
    )

    await gate.release()
    await contenderAcquired.wait()
    await contender.value
    #expect(await gate.waitingCount == 0)
  }
}
