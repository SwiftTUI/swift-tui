import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// Exit-during-phase drain-policy matrix (campaign two F4, setF071–setF085).
/// The run loop's `FrameDrainPolicy` owns the acquisition bound, work budget,
/// callback-invalidation observation and continuation rule for each phase
/// (initial presentation, normal, cooperative exit, signal exit), and
/// `FrameCallbackInvalidations.observe` reads the scheduler's generation only
/// under the two observing policies
/// (`Sources/SwiftTUIRuntime/RunLoop/RunLoop+RenderDriverSupport.swift:5-101`,
/// `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:14-17`;
/// contract: `Runtime-Render-Pipeline.md` "Frame drain fairness").
@Suite("set F drain policy matrix")
struct AdversarialSetFDrainPolicyTests {
  private typealias Loop = RunLoop<Int, Text>
  private typealias Policy = Loop.FrameDrainPolicy
  private typealias Invalidations = Loop.FrameCallbackInvalidations

  @Test("setF071 a programmatic exit selects the cooperative-exit policy")
  func setF071ProgrammaticIsCooperative() {
    #expect(Policy(exitReason: .programmatic) == .cooperativeExit)
  }

  @Test("setF072 a user-key exit selects the cooperative-exit policy")
  func setF072UserExitIsCooperative() {
    #expect(
      Policy(exitReason: .userExit(KeyPress(.character("c"), modifiers: .ctrl))) == .cooperativeExit
    )
  }

  @Test("setF073 end-of-input selects the cooperative-exit policy")
  func setF073InputEndedIsCooperative() {
    #expect(Policy(exitReason: .inputEnded) == .cooperativeExit)
  }

  @Test("setF074 a signal exit selects the signal-exit policy")
  func setF074SignalIsSignalExit() {
    #expect(Policy(exitReason: .signal("SIGTERM")) == .signalExit)
  }

  @Test("setF075 only the signal exit caps acquisition at one; others keep the sixteen bound")
  func setF075AcquisitionLimits() {
    #expect(Loop.maxFramesPerDrainPass == 16)
    #expect(Policy.initialPresentation.acquisitionLimit == 16)
    #expect(Policy.normal.acquisitionLimit == 16)
    #expect(Policy.cooperativeExit.acquisitionLimit == 16)
    #expect(Policy.signalExit.acquisitionLimit == 1)
  }

  @Test("setF076 only initial presentation and cooperative exit observe callback invalidations")
  func setF076ObservesCallbackInvalidations() {
    #expect(Policy.initialPresentation.observesCallbackInvalidations)
    #expect(Policy.cooperativeExit.observesCallbackInvalidations)
    #expect(!Policy.normal.observesCallbackInvalidations)
    #expect(!Policy.signalExit.observesCallbackInvalidations)
  }

  @Test("setF077 only normal rendering applies the elapsed-work budget")
  func setF077AppliesWorkBudget() {
    #expect(Policy.normal.appliesWorkBudget)
    #expect(!Policy.initialPresentation.appliesWorkBudget)
    #expect(!Policy.cooperativeExit.appliesWorkBudget)
    #expect(!Policy.signalExit.appliesWorkBudget)
  }

  @Test("setF078 without observed callbacks normal continues, the exits stop")
  func setF078ContinueAfterNone() {
    #expect(Policy.normal.shouldContinue(after: .none))
    #expect(!Policy.signalExit.shouldContinue(after: .none))
    #expect(!Policy.initialPresentation.shouldContinue(after: .none))
    #expect(!Policy.cooperativeExit.shouldContinue(after: .none))
  }

  @Test("setF079 an observed callback keeps the observing policies going but not the signal exit")
  func setF079ContinueAfterObserved() {
    #expect(Policy.normal.shouldContinue(after: .observed))
    #expect(!Policy.signalExit.shouldContinue(after: .observed))
    #expect(Policy.initialPresentation.shouldContinue(after: .observed))
    #expect(Policy.cooperativeExit.shouldContinue(after: .observed))
  }

  @Test("setF080 an unavailable generation conservatively keeps the observing policies going")
  func setF080ContinueAfterUnavailable() {
    #expect(Policy.normal.shouldContinue(after: .unavailable))
    #expect(!Policy.signalExit.shouldContinue(after: .unavailable))
    #expect(Policy.initialPresentation.shouldContinue(after: .unavailable))
    #expect(Policy.cooperativeExit.shouldContinue(after: .unavailable))
  }

  @Test("setF081 normal rendering never reads the generation and reports no invalidation")
  func setF081NormalNeverReadsGeneration() {
    var reads = 0
    let result = Invalidations.observe(
      under: .normal,
      generation: {
        reads += 1
        return 0
      }
    ) {}
    #expect(reads == 0)
    #expect(result.invalidations == .none)
  }

  @Test("setF082 a signal exit never reads the generation and reports no invalidation")
  func setF082SignalExitNeverReadsGeneration() {
    var reads = 0
    let result = Invalidations.observe(
      under: .signalExit,
      generation: {
        reads += 1
        return 0
      }
    ) {}
    #expect(reads == 0)
    #expect(result.invalidations == .none)
  }

  @Test("setF083 an unchanged generation under an observing policy reports no invalidation")
  func setF083UnchangedGenerationIsNone() {
    var reads = 0
    let generation: UInt64 = 7
    let result = Invalidations.observe(
      under: .cooperativeExit,
      generation: {
        reads += 1
        return generation
      }
    ) {}
    #expect(reads == 2)
    #expect(result.invalidations == .none)
  }

  @Test("setF084 a changed generation under an observing policy reports an observed invalidation")
  func setF084ChangedGenerationIsObserved() {
    var generation: UInt64 = 0
    let result = Invalidations.observe(under: .initialPresentation, generation: { generation }) {
      generation += 1
    }
    #expect(result.invalidations == .observed)
  }

  @Test("setF085 an unavailable generation is reported and merging promotes toward observed")
  func setF085UnavailableAndMerging() {
    let unavailable = Invalidations.observe(under: .cooperativeExit, generation: { nil }) {}
    #expect(unavailable.invalidations == .unavailable)
    #expect(Invalidations.none.merging(.observed) == .observed)
    #expect(Invalidations.none.merging(.none) == .none)
    #expect(Invalidations.unavailable.merging(.none) == .unavailable)
    #expect(Invalidations.unavailable.merging(.observed) == .observed)
    #expect(Invalidations.observed.merging(.none) == .observed)
  }
}
