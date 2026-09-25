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

/// `FailOnSoundnessViolationGrowth` is recursive, so swift-testing copies it
/// onto every suite nested in a guarded suite. The no-argument `.serialized`
/// is not copied (it serializes descendants through its scope instead), so a
/// nested suite sees the inherited guard without a `ParallelizationTrait` of
/// its own. Its preparation must accept that rather than trap the whole plan.
@Suite(.serialized, FailOnSoundnessViolationGrowth())
struct SoundnessGuardNestedSuiteTests {
  @Suite
  struct AttributedNestedSuite {
    @Test("a nested @Suite runs under the guard inherited from its containing suite")
    func attributedNestedSuiteInheritsGuard() throws {
      let test = try #require(Test.current)
      #expect(test.traits.contains { $0 is FailOnSoundnessViolationGrowth })
    }
  }

  struct ImplicitNestedSuite {
    @Test("a nested type holding tests runs under the guard inherited from its containing suite")
    func implicitNestedSuiteInheritsGuard() throws {
      let test = try #require(Test.current)
      #expect(test.traits.contains { $0 is FailOnSoundnessViolationGrowth })
    }
  }
}
