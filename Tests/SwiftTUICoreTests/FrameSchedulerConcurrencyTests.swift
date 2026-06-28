import Testing

@testable import SwiftTUICore

/// Concurrency-safety regression for `FrameScheduler`.
///
/// The scheduler's coalescing state is mutated by `request*` from any thread and
/// drained by the main-actor run loop via `consumeReadyFrame`. It used to be
/// lock-free and safe only "by convention" (every caller on the main actor),
/// which raced the run loop when an off-main caller — notably the Observation
/// `onChange` bridge firing from a background mutation — broke that convention.
/// These tests hammer the scheduler from many concurrent tasks; run them under
/// ThreadSanitizer (`swift test --sanitize=thread`) to prove the coalescing
/// state is race-free. Without the lock, the intent counter loses increments
/// (counts come out below the request total) and TSan reports the data race.
@Suite("FrameScheduler concurrency safety")
struct FrameSchedulerConcurrencyTests {
  @Test("concurrent requestInvalidation calls lose no intents or identities")
  func concurrentInvalidationsAreRaceFree() async {
    let scheduler = FrameScheduler()
    let count = 1_000

    await withTaskGroup(of: Void.self) { group in
      for index in 0..<count {
        group.addTask {
          scheduler.requestInvalidation(of: [testIdentity("conc", "\(index)")])
        }
      }
      await group.waitForAll()
    }

    let frame = scheduler.consumeReadyFrame()
    // Every concurrent request must be accounted for: a lost `+= 1` (a data race
    // on the intent counter) or a dropped Set insertion would make these < count.
    #expect(frame?.intentRequestCount == count)
    #expect(frame?.invalidatedIdentities.count == count)
  }

  @Test("a consumer racing producers never corrupts state and accounts for every intent")
  func concurrentConsumeIsRaceFree() async {
    let scheduler = FrameScheduler()
    let invalidations = 500

    let consumedDuringRace = await withTaskGroup(of: Int.self) { group in
      for index in 0..<invalidations {
        group.addTask {
          scheduler.requestInvalidation(of: [testIdentity("race", "\(index)")])
          return 0
        }
      }
      group.addTask {
        // Spin consuming while the producers run; the shared sets must neither
        // corrupt nor trap when read+cleared concurrently with insertions.
        var seen = 0
        for _ in 0..<invalidations {
          if let frame = scheduler.consumeReadyFrame() {
            seen += frame.intentRequestCount
          }
        }
        return seen
      }
      var total = 0
      for await partial in group {
        total += partial
      }
      return total
    }

    var tail = 0
    while let frame = scheduler.consumeReadyFrame() {
      tail += frame.intentRequestCount
    }
    // Each intent is consumed exactly once — by the racing consumer or the
    // final drain — and none are lost to a race.
    #expect(consumedDuringRace + tail == invalidations)
  }
}
