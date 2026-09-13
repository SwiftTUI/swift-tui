import Testing

@testable import SwiftTUIGraph

@Suite("Merge pressure pacing")
struct MergePressurePacingTests {
  private let t = MonotonicInstant(offset: .seconds(100))

  private func pressured(enabled: Bool = true) -> FrameScheduler {
    let scheduler = FrameScheduler(mergePressurePacingEnabled: enabled)
    scheduler.requestInvalidation(of: [])
    scheduler.requestInvalidation(of: [])
    #expect(scheduler.consumeReadyFrame(at: t)?.mergedInvalidationRequestCount == 1)
    scheduler.recordCommittedFrame(cost: .milliseconds(40), at: t)
    scheduler.requestInvalidation(of: [])
    return scheduler
  }

  @Test("all readiness queries agree and preserve the pending invalidation")
  func readiness() throws {
    let scheduler = pressured()
    #expect(!scheduler.hasPendingFrame(at: t))
    let wake = try #require(scheduler.nextWakeInstant(after: t))
    #expect(wake == t.advanced(by: .milliseconds(10)))
    #expect(scheduler.consumeReadyFrame(at: t) == nil)
    let frame = try #require(scheduler.consumeReadyFrame(at: wake))
    #expect(frame.causes == [.invalidation])
    #expect(frame.triggeredDeadline == nil)
    #expect(frame.pacing.engaged)
    #expect(frame.pacing.ewmaFrameCost == .milliseconds(20))
    #expect(frame.mergedInvalidationRequestCount == 0)
    #expect(!scheduler.hasPendingFrame(at: wake))
    #expect(scheduler.nextWakeInstant(after: wake) == nil)
  }

  @Test("input, signal, external wakes and eligible deadlines bypass pressure", arguments: 0..<4)
  func exemptions(kind: Int) throws {
    let scheduler = pressured()
    #expect(!scheduler.hasPendingFrame(at: t))
    switch kind {
    case 0: scheduler.requestInput()
    case 1: scheduler.requestSignal(named: "resize")
    case 2: scheduler.requestExternalWake(reason: "host")
    default: scheduler.requestDeadline(t)
    }
    #expect(scheduler.hasPendingFrame(at: t))
    #expect(scheduler.nextWakeInstant(after: t) == t)
    let frame = try #require(scheduler.consumeReadyFrame(at: t))
    #expect(frame.causes.contains(.invalidation))
    #expect(frame.causes.count == 2)
  }

  @Test("future deadlines bound a paced wake and post-cut deadlines remain withheld")
  func deadlinesAndCut() throws {
    let scheduler = pressured()
    let deadline = t.advanced(by: .milliseconds(3))
    let cut = scheduler.deadlineArmCut
    scheduler.requestDeadline(deadline)
    #expect(scheduler.nextWakeInstant(after: t) == deadline)
    #expect(scheduler.consumeReadyFrame(at: deadline, armedBefore: cut) == nil)
    let frame = try #require(
      scheduler.consumeReadyFrame(at: deadline, armedBefore: scheduler.deadlineArmCut))
    #expect(frame.triggeredDeadline == deadline)
    #expect(frame.causes == [.invalidation, .deadline])
  }

  @Test("fresh animation-aware requests count; replay and other wake kinds do not")
  func mergeCounting() throws {
    let scheduler = FrameScheduler(mergePressurePacingEnabled: false)
    scheduler.requestInput()
    scheduler.requestInvalidation(of: [])
    scheduler.requestInvalidation(
      of: [], animation: .disabled, batchID: nil,
      isContinuous: false, customValues: [:], tracksVelocity: false)
    let first = try #require(scheduler.consumeReadyFrame(at: t))
    #expect(first.mergedInvalidationRequestCount == 1)
    scheduler.replayCancelledFrameIntent(first)
    scheduler.replayCancelledFrameIntent(first)
    #expect(scheduler.consumeReadyFrame(at: t)?.mergedInvalidationRequestCount == 0)
  }

  @Test("cost fold, ceiling, pressure expiry, reset and default-off behavior")
  func lifecycle() throws {
    let scheduler = pressured()
    scheduler.recordCommittedFrame(cost: .milliseconds(60), at: t)
    #expect(scheduler.pacingSnapshot(at: t).ewmaFrameCost == .milliseconds(40))
    scheduler.recordCommittedFrame(cost: .seconds(1), at: t)
    #expect(scheduler.nextWakeInstant(after: t) == t.advanced(by: .milliseconds(50)))
    let idle = t.advanced(by: .seconds(2))
    scheduler.recordCommittedFrame(cost: .seconds(1), at: idle)
    #expect(scheduler.consumeReadyFrame(at: idle) != nil)
    #expect(scheduler.pacingSnapshot(at: idle).gap == .zero)
    scheduler.reset()
    #expect(scheduler.pacingSnapshot(at: idle) == .init())
    #expect(scheduler.nextWakeInstant(after: idle) == nil)
    let disabled = pressured(enabled: false)
    #expect(disabled.consumeReadyFrame(at: t) != nil)
    #expect(disabled.pacingSnapshot(at: t).ewmaFrameCost > .zero)
    #expect(!FeatureGate.mergePressurePacing.defaultIsEnabled)
  }

  @Test("a sustained invalidation storm releases occupancy without losing requests")
  func occupancy() throws {
    func simulate(enabled: Bool) throws -> Double {
      let scheduler = FrameScheduler(mergePressurePacingEnabled: enabled)
      var now = t
      for _ in 0..<100 {
        scheduler.requestInvalidation(of: [])
        scheduler.requestInvalidation(of: [])
        if !scheduler.hasPendingFrame(at: now) {
          now = try #require(scheduler.nextWakeInstant(after: now))
        }
        #expect(scheduler.consumeReadyFrame(at: now)?.mergedInvalidationRequestCount == 1)
        now = now.advanced(by: .milliseconds(20))
        scheduler.recordCommittedFrame(cost: .milliseconds(20), at: now)
      }
      let elapsed = t.duration(to: now).components
      return 2 / (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
    #expect(try simulate(enabled: true) < 0.69)
    #expect(try simulate(enabled: false) == 1)
  }
}
