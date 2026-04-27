import Testing

@testable import Core

@Suite("FrameDropEligibility")
struct FrameDropEligibilityTests {
  @Test("an empty frame falls back to the unobservable blocker")
  func emptyFrameFallsBackToUnobservable() {
    let artifacts = makeArtifacts()
    let eligibility = FrameDropEligibility.classify(artifacts)
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
    #expect(eligibility.canDrop == false)
  }

  @Test("canDrop is currently false for every blocker")
  func canDropIsAlwaysFalse() {
    for blocker in FrameDropEligibility.Blocker.allCases {
      let eligibility = FrameDropEligibility(blockers: [blocker])
      #expect(
        eligibility.canDrop == false,
        "blocker \(blocker.rawValue) should not permit dropping"
      )
    }
  }

  @Test("an explicit empty blocker set is treated as droppable")
  func explicitEmptyBlockerSetIsDroppable() {
    // The classifier never produces this state — it injects
    // `.unobservable` when no signal is detected — but the type itself
    // exposes `canDrop` as a derived property.  Pin the contract so a
    // future stage that wants to flip a frame to droppable has a clear
    // construction path.
    let eligibility = FrameDropEligibility(blockers: [])
    #expect(eligibility.canDrop == true)
  }
}

private func makeArtifacts(
  lifecycle: [LifecycleCommitEntry] = [],
  handlerInstallations: [HandlerInstallation] = [],
  customLayoutFallbackCount: Int = 0
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
    customLayoutFallbackCount: customLayoutFallbackCount
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
    presentationDamage: nil,
    commitPlan: commitPlan,
    diagnostics: diagnostics
  )
}
