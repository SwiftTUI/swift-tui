import Testing

@testable import SwiftTUICore

@Suite("FrameDropEligibility")
struct FrameDropEligibilityTests {
  @Test("an empty frame falls back to the unobservable blocker")
  func emptyFrameFallsBackToUnobservable() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(artifacts)
    #expect(eligibility.decision == .mustCommit(blockers: [.unobservable]))
    #expect(eligibility.blockers == [.unobservable])
    #expect(eligibility.canDrop == false)
  }

  @Test("appear lifecycle entries surface as lifecycleAppear")
  func appearLifecycleSurfaces() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "Leaf"),
        operation: .appear(handlerIDs: ["onAppear"])
      )
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.lifecycleAppear])
  }

  @Test("disappear lifecycle entries surface as lifecycleDisappear")
  func disappearLifecycleSurfaces() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "Leaf"),
        operation: .disappear(handlerIDs: ["onDisappear"])
      )
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.lifecycleDisappear])
  }

  @Test("change lifecycle entries surface as lifecycleChange")
  func changeLifecycleSurfaces() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "Leaf"),
        operation: .change(handlerIDs: ["onChange"])
      )
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.lifecycleChange])
  }

  @Test("taskStart entries surface as taskStart")
  func taskStartSurfaces() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "Leaf"),
        operation: .taskStart(.init(id: "load", priority: .medium))
      )
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.taskStart])
  }

  @Test("taskCancel entries surface as taskCancel")
  func taskCancelSurfaces() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "Leaf"),
        operation: .taskCancel(.init(id: "load", priority: .medium))
      )
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.taskCancel])
  }

  @Test("multiple lifecycle entries accumulate distinct blockers")
  func multipleLifecycleEntriesAccumulate() {
    let artifacts = makeArtifacts(lifecycle: [
      .init(
        identity: testIdentity("Root", "A"),
        operation: .appear(handlerIDs: ["onAppear"])
      ),
      .init(
        identity: testIdentity("Root", "B"),
        operation: .disappear(handlerIDs: ["onDisappear"])
      ),
      .init(
        identity: testIdentity("Root", "B"),
        operation: .taskCancel(.init(id: "load", priority: .medium))
      ),
    ])
    #expect(
      FrameDropEligibility.classify(artifacts).blockers == [
        .lifecycleAppear, .lifecycleDisappear, .taskCancel,
      ])
  }

  @Test("handler installations surface as handlerInstallations")
  func handlerInstallationsSurface() {
    let artifacts = makeArtifacts(handlerInstallations: [
      .init(handlerID: testRoute("Root", "Button"))
    ])
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.handlerInstallations])
  }

  @Test("custom-layout fallbacks surface as customLayoutFallback")
  func customLayoutFallbacksSurface() {
    let artifacts = makeArtifacts(customLayoutFallbackCount: 1)
    #expect(FrameDropEligibility.classify(artifacts).blockers == [.customLayoutFallback])
  }

  @Test("diagnostic blocker signals surface without unobservable")
  func diagnosticBlockerSignalsSurface() {
    let blockers: Set<FrameDropEligibility.Blocker> = [
      .focusGraph,
      .focusBindingSync,
      .focusedValueSync,
      .scrollSync,
      .preferenceObservationDelta,
      .animationCompletion,
      .animationTransition,
      .animationTransaction,
      .workerCustomLayoutCacheUpdate,
      .retainedLayoutBaseline,
      .retainedRasterBaseline,
      .diagnosticsFullRecord,
    ]
    let artifacts = makeArtifacts(dropEligibilityBlockers: blockers)
    #expect(FrameDropEligibility.classify(artifacts).blockers == blockers)
  }

  @Test("additional runtime blockers surface without unobservable")
  func additionalRuntimeBlockersSurface() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(
      artifacts,
      additionalBlockers: [.focusBindingSync, .preferenceObservationDelta]
    )
    #expect(eligibility.blockers == [.focusBindingSync, .preferenceObservationDelta])
  }

  @Test("presentation repaint and graphics barriers surface")
  func presentationBarriersSurface() {
    let artifacts = makeArtifacts(
      presentationDamage: PresentationDamage(
        dirtyRows: [],
        graphicsInvalidation: [testIdentity("Root", "Image")],
        requiresFullTextRepaint: true,
        requiresFullGraphicsReplay: true
      )
    )
    #expect(
      FrameDropEligibility.classify(artifacts).blockers == [
        .presentationFullRepaint,
        .graphicsReplay,
      ])
  }

  @Test("a fully classified visual-only candidate reports canDropVisualOnly")
  func fullyClassifiedVisualOnlyCandidateReportsCanDropVisualOnly() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(
      .init(
        artifacts: artifacts,
        hasCompleteBarrierSignals: true
      ))
    #expect(eligibility.decision == .canDropVisualOnly)
    #expect(eligibility.blockers == [])
    #expect(eligibility.impact.isVisualOnly)
    #expect(eligibility.canDrop == false)
  }

  @Test("every blocker maps to non-visual completed-frame impact")
  func everyBlockerMapsToNonVisualCompletedFrameImpact() {
    for blocker in FrameDropEligibility.Blocker.allCases {
      let impact = FrameDropEligibility.CompletedFrameImpact(blockers: [blocker])
      #expect(!impact.isVisualOnly, "\(blocker) must map to a non-visual impact")
    }
  }

  @Test("an incomplete visual-only candidate remains mustCommit")
  func incompleteVisualOnlyCandidateRemainsMustCommit() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(
      .init(
        artifacts: artifacts,
        hasCompleteBarrierSignals: false
      ))
    #expect(eligibility.decision == .mustCommit(blockers: [.unobservable]))
    #expect(eligibility.blockers == [.unobservable])
    #expect(!eligibility.impact.isVisualOnly)
  }

  @Test("a fully classified candidate with blockers remains mustCommit")
  func fullyClassifiedCandidateWithBlockersRemainsMustCommit() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(
      .init(
        artifacts: artifacts,
        additionalBlockers: [.focusBindingSync, .preferenceObservationDelta],
        hasCompleteBarrierSignals: true
      ))
    #expect(
      eligibility.decision
        == .mustCommit(
          blockers: [.focusBindingSync, .preferenceObservationDelta]
        ))
    #expect(eligibility.blockers == [.focusBindingSync, .preferenceObservationDelta])
    #expect(!eligibility.impact.isVisualOnly)
  }

  @Test("a frame with multiple kinds of work reports all of them")
  func multipleBlockersAccumulate() {
    let artifacts = makeArtifacts(
      lifecycle: [
        .init(
          identity: testIdentity("Root", "Leaf"),
          operation: .appear(handlerIDs: ["onAppear"])
        )
      ],
      handlerInstallations: [
        .init(handlerID: testRoute("Root", "Button"))
      ],
      customLayoutFallbackCount: 2
    )
    let eligibility = FrameDropEligibility.classify(artifacts)
    #expect(
      eligibility.blockers == [
        .lifecycleAppear, .handlerInstallations, .customLayoutFallback,
      ])
    #expect(!eligibility.impact.isVisualOnly)
    #expect(eligibility.canDrop == false)
  }

  @Test("canDrop is currently false for every decision")
  func canDropIsAlwaysFalse() {
    for decision in allDecisions() {
      let eligibility = FrameDropEligibility(decision: decision)
      #expect(eligibility.canDrop == false)
    }
  }

  @Test("an explicit empty blocker set records the visual-only decision")
  func explicitEmptyBlockerSetRecordsVisualOnlyDecision() {
    let eligibility = FrameDropEligibility(blockers: [])
    #expect(eligibility.decision == .canDropVisualOnly)
    #expect(eligibility.blockers == [])
    #expect(eligibility.impact.isVisualOnly)
    #expect(eligibility.canDrop == false)
  }
}

private func allDecisions() -> [FrameDropEligibility.Decision] {
  FrameDropEligibility.Blocker.allCases.map { blocker in
    .mustCommit(blockers: [blocker])
  } + [.canDropVisualOnly]
}

private func makeArtifacts(
  lifecycle: [LifecycleCommitEntry] = [],
  handlerInstallations: [HandlerInstallation] = [],
  customLayoutFallbackCount: Int = 0,
  dropEligibilityBlockers: Set<FrameDropEligibility.Blocker> = [],
  presentationDamage: PresentationDamage? = nil
) -> FrameArtifacts {
  let identity = testIdentity("Root")
  let resolved = ResolvedNode(identity: identity, kind: .root)
  let measured = MeasuredNode(
    identity: identity,
    proposal: .unspecified,
    measuredSize: .zero
  )
  let placed = PlacedNode(
    identity: identity,
    bounds: .init(origin: .zero, size: .zero)
  )
  let draw = DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
  let diagnostics = FrameDiagnostics(
    work: .init(customLayoutFallbackCount: customLayoutFallbackCount),
    presentation: .init(
      damage: presentationDamage.map {
        .init(
          damage: $0,
          surfaceWidth: 0
        )
      }
    ),
    drop: .init(eligibilityBlockers: dropEligibilityBlockers)
  )
  let commitPlan = CommitPlan(
    transaction: .init(),
    semanticSnapshot: .init(),
    lifecycle: lifecycle,
    handlerInstallations: handlerInstallations
  )
  return FrameArtifacts(
    resolvedTree: resolved,
    measuredTree: measured,
    placedTree: placed,
    semanticSnapshot: .init(),
    drawTree: draw,
    rasterSurface: .init(),
    presentationDamage: presentationDamage,
    commitPlan: commitPlan,
    diagnostics: diagnostics
  )
}
