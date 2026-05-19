import Testing

@testable import SwiftTUIRuntime

@Suite("Input poll backoff")
struct InputPollBackoffTests {
  @Test("starts at the floor delay")
  func startsAtFloor() {
    let backoff = InputPollBackoff()
    #expect(backoff.delayNanoseconds == InputPollBackoff.floorNanoseconds)
  }

  @Test("an idle poll doubles the delay")
  func idlePollDoubles() {
    var backoff = InputPollBackoff()
    backoff.recordIdlePoll()
    #expect(backoff.delayNanoseconds == InputPollBackoff.floorNanoseconds * 2)
  }

  @Test("repeated idle polls grow geometrically up to the ceiling")
  func idlePollsGrowToCeiling() {
    var backoff = InputPollBackoff()
    var seen: [UInt64] = [backoff.delayNanoseconds]
    for _ in 0..<10 {
      backoff.recordIdlePoll()
      seen.append(backoff.delayNanoseconds)
    }

    // Each step at most doubles, and never exceeds the ceiling.
    for (previous, next) in zip(seen, seen.dropFirst()) {
      #expect(next <= previous * 2)
      #expect(next <= InputPollBackoff.ceilingNanoseconds)
    }
    // Enough idle polls eventually pin the delay at the ceiling.
    #expect(backoff.delayNanoseconds == InputPollBackoff.ceilingNanoseconds)
  }

  @Test("real input resets the delay to the floor")
  func inputResetsToFloor() {
    var backoff = InputPollBackoff()
    for _ in 0..<10 {
      backoff.recordIdlePoll()
    }
    #expect(backoff.delayNanoseconds == InputPollBackoff.ceilingNanoseconds)

    backoff.recordInput()
    #expect(backoff.delayNanoseconds == InputPollBackoff.floorNanoseconds)
  }

  @Test("the ceiling stays a small multiple of the floor")
  func ceilingIsAModestMultiple() {
    // The ceiling bounds worst-case latency for the first keystroke
    // after an idle period; keep it within ~one display frame.
    #expect(InputPollBackoff.ceilingNanoseconds <= InputPollBackoff.floorNanoseconds * 16)
    #expect(InputPollBackoff.ceilingNanoseconds > InputPollBackoff.floorNanoseconds)
  }
}
