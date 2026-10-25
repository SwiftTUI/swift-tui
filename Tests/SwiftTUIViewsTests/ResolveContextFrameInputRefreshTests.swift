import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

// The frame-input refresh (`applyingCurrentFrameResolveInputs`) keeps captured
// evaluator contexts in sync with frame-level focus/press so finite
// suppression scopes can replace root-forced evaluation. These tests pin the
// provenance contract: frame-level values refresh, authored `.environment` /
// `.transformEnvironment` writes win below their modifier.
@MainActor
@Suite
struct ResolveContextFrameInputRefreshTests {
  @Test("frame-level focus and press refresh from current-frame inputs")
  func frameLevelFocusAndPressRefreshFromInputs() {
    let previousFocus = testIdentity("Root", "Previous")
    let currentFocus = testIdentity("Root", "Current")
    let pressed = testIdentity("Root", "Pressed")
    var context = resolveContext(focusedIdentity: previousFocus)
    context.frameInputs = inputBox(
      focusedIdentity: currentFocus,
      pressedIdentity: pressed
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == currentFocus)
    #expect(refreshed.environmentValues.pressedIdentity == pressed)
  }

  @Test("authored focus environment write survives the frame-input refresh")
  func authoredFocusWriteSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    let frameFocus = testIdentity("Root", "FrameLevel")
    let framePressed = testIdentity("Root", "FramePressed")
    var context = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
    context.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: framePressed
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
    #expect(refreshed.environmentValues.pressedIdentity == framePressed)
  }

  @Test("authored press environment write survives the frame-input refresh")
  func authoredPressWriteSurvivesRefresh() {
    let authoredPressed = testIdentity("Root", "AuthoredPressed")
    let frameFocus = testIdentity("Root", "FrameLevel")
    var context = resolveContext()
      .settingEnvironment(\.pressedIdentity, to: authoredPressed)
    context.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: nil
    )

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.pressedIdentity == authoredPressed)
    #expect(refreshed.environmentValues.focusedIdentity == frameFocus)
  }

  @Test("authored focus transform survives the frame-input refresh")
  func authoredFocusTransformSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    var context = resolveContext()
      .transformingEnvironment(\.focusedIdentity) { focus in
        focus = authoredFocus
      }
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("whole-values transform writing focus survives the frame-input refresh")
  func wholeValuesTransformWritingFocusSurvivesRefresh() {
    let authoredFocus = testIdentity("Root", "Authored")
    var context = resolveContext()
      .transformingEnvironment(\.self) { values in
        values.focusedIdentity = authoredFocus
      }
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("derived child contexts inherit the authored override across the refresh")
  func derivedChildContextsInheritAuthoredOverride() {
    let authoredFocus = testIdentity("Root", "Authored")
    let frameFocus = testIdentity("Root", "FrameLevel")
    var child = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
      .child(component: IdentityComponent(rawValue: "Interior"))
      .child(component: IdentityComponent(rawValue: "Leaf"))
    child.frameInputs = inputBox(
      focusedIdentity: frameFocus,
      pressedIdentity: nil
    )

    let refreshed = child.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
  }

  @Test("refresh re-derives isFocused against the surviving authored focus")
  func refreshRederivesIsFocusedAgainstAuthoredFocus() {
    let authoredFocus = testIdentity("Root", "Focusable")
    var context = resolveContext()
      .settingEnvironment(\.focusedIdentity, to: authoredFocus)
      .replacingIdentity(with: authoredFocus)
    context.frameInputs = inputBox(focusedIdentity: nil, pressedIdentity: nil)

    let refreshed = context.applyingCurrentFrameResolveInputs()

    #expect(refreshed.environmentValues.focusedIdentity == authoredFocus)
    #expect(refreshed.environmentValues.isFocused)
  }

  @Test("disjoint animation segments refresh only their claimed subtrees")
  func disjointAnimationSegmentsRefreshClaimedSubtrees() {
    let root = testIdentity("Root")
    let first = testIdentity("Root", "First")
    let second = testIdentity("Root", "Second")
    let clean = testIdentity("Root", "Clean")
    let secondRequest = AnimationRequest.animate(AnyHashableSendable("second"))
    let box = inputBox(
      focusedIdentity: nil,
      pressedIdentity: nil,
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [first],
          animationRequest: .disabled,
          animationBatchID: AnimationBatchID(1)
        ),
        AnimationInvalidationSegment(
          identities: [second],
          animationRequest: secondRequest,
          animationBatchID: AnimationBatchID(2)
        ),
      ]
    )

    func refreshed(_ identity: Identity) -> ResolveContext {
      var context = ResolveContext(identity: identity)
      context.frameInputs = box
      return context.applyingCurrentFrameResolveInputs()
    }

    #expect(refreshed(root).transaction.animationRequest == .inherit)
    #expect(refreshed(clean).transaction.animationRequest == .inherit)
    #expect(refreshed(first).transaction.animationRequest == .disabled)
    #expect(refreshed(first).transaction.animationBatchID == AnimationBatchID(1))
    #expect(refreshed(first.child(.named("Leaf"))).transaction.animationRequest == .disabled)
    #expect(refreshed(second).transaction.animationRequest == secondRequest)
    #expect(refreshed(second).transaction.animationBatchID == AnimationBatchID(2))
  }

  @Test("a deeper animation segment wins below a broader segment")
  func deeperAnimationSegmentWins() {
    let root = testIdentity("Root")
    let branch = testIdentity("Root", "Branch")
    let leaf = branch.child(.named("Leaf"))
    let deeperRequest = AnimationRequest.animate(AnyHashableSendable("deeper"))
    let box = inputBox(
      focusedIdentity: nil,
      pressedIdentity: nil,
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [root],
          animationRequest: .disabled
        ),
        AnimationInvalidationSegment(
          identities: [branch],
          animationRequest: deeperRequest
        ),
      ]
    )
    var context = ResolveContext(identity: leaf)
    context.frameInputs = box

    #expect(
      context.applyingCurrentFrameResolveInputs().transaction.animationRequest == deeperRequest)
  }

  @Test("an authored transaction override wins over the frame segment")
  func authoredTransactionOverrideWinsOverFrameSegment() {
    let identity = testIdentity("Root", "Authored")
    var authoredTransaction = TransactionSnapshot()
    authoredTransaction.animationRequest = .disabled
    var context = ResolveContext(identity: identity, transaction: authoredTransaction)
    context.propagated.authoredTransactionOverride = true
    context.frameInputs = inputBox(
      focusedIdentity: nil,
      pressedIdentity: nil,
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [identity],
          animationRequest: .animate(AnyHashableSendable("frame"))
        )
      ]
    )

    #expect(context.applyingCurrentFrameResolveInputs().transaction.animationRequest == .disabled)
  }

  @Test("portal-style identity rewrites keep the newest segment on a translated collision")
  func portalStyleRewriteNormalizesSegmentCollision() {
    let firstSource = testIdentity("Portal", "StaleFirst")
    let secondSource = testIdentity("Portal", "StaleSecond")
    let liveHost = testIdentity("Portal", "LiveHost")
    let ordinary = testIdentity("Root", "Ordinary")
    let firstBatchID = AnimationBatchID(3)
    let secondBatchID = AnimationBatchID(4)
    var inputs = frameInputs(
      invalidatedIdentities: [firstSource, secondSource, ordinary],
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [firstSource],
          animationRequest: .disabled,
          animationBatchID: firstBatchID
        ),
        AnimationInvalidationSegment(
          identities: [secondSource],
          animationRequest: .animate(AnyHashableSendable("newer")),
          animationBatchID: secondBatchID
        ),
      ]
    )

    let displacedBatchIDs = inputs.rewriteInvalidationIdentities { identities in
      Set(
        identities.map { identity in
          identity == firstSource || identity == secondSource ? liveHost : identity
        }
      )
    }

    #expect(inputs.invalidatedIdentities == [liveHost, ordinary])
    #expect(inputs.animationSegments.count == 1)
    #expect(inputs.animationSegments.first?.identities == [liveHost])
    #expect(inputs.animationSegments.first?.animationBatchID == secondBatchID)
    #expect(displacedBatchIDs == [firstBatchID])
  }

  // STUI-1232: the refresh runs on every resolve that reaches
  // `resolveViewWork` while renderer inputs are installed, so it must adopt
  // the frame's precomputed summary without constructing (and discarding) a
  // fresh one — the construction walks every ancestor of every invalidated
  // identity, which made a deep-palette gallery frame stall for seconds.
  #if DEBUG
    @Test("the frame-input refresh adopts the precomputed summary without rebuilding one")
    func refreshAdoptsPrecomputedSummaryWithoutRebuilding() {
      let invalidated: Set<Identity> = [
        testIdentity("Root", "Palette", "Body", "Row"),
        testIdentity("Root", "Tab", "Content"),
      ]
      let box = FrameResolveInputBox()
      box.store(frameInputs(invalidatedIdentities: invalidated, animationSegments: []))
      var context = ResolveContext(identity: testIdentity("Root", "Tab"))
      context.frameInputs = box

      let census = InvalidationSummaryConstructionCensus.Counter()
      let refreshed = InvalidationSummaryConstructionCensus.$counter.withValue(census) {
        context.applyingCurrentFrameResolveInputs()
      }

      #expect(census.count == 0)
      #expect(refreshed.invalidatedIdentities == invalidated)
      #expect(refreshed.invalidationSummary == box.inputs?.invalidationSummary)
    }

    @Test("a public invalidation-set write still rebuilds exactly one consistent summary")
    func publicInvalidationWriteRebuildsOneSummary() {
      let branch = testIdentity("Root", "Branch")
      let leaf = branch.child(.named("Leaf"))
      var context = ResolveContext(identity: testIdentity("Root"))

      let census = InvalidationSummaryConstructionCensus.Counter()
      InvalidationSummaryConstructionCensus.$counter.withValue(census) {
        context.invalidatedIdentities = [leaf]
      }

      #expect(census.count == 1)
      #expect(context.invalidationSummary == InvalidationSummary(invalidatedIdentities: [leaf]))
      #expect(context.invalidationAffectsSubtree(at: branch))
      #expect(context.invalidationAffectsSubtree(at: leaf.child(.named("Below"))))
      #expect(!context.invalidationAffectsSubtree(at: testIdentity("Root", "Sibling")))
    }
  #endif

  @Test("in-place invalidation-set mutation keeps the summary consistent")
  func inPlaceInvalidationMutationKeepsSummaryConsistent() {
    let first = testIdentity("Root", "First")
    let second = testIdentity("Root", "Second", "Leaf")
    var context = ResolveContext(identity: testIdentity("Root"), invalidatedIdentities: [first])

    context.invalidatedIdentities.insert(second)

    #expect(context.invalidatedIdentities == [first, second])
    #expect(
      context.invalidationSummary == InvalidationSummary(invalidatedIdentities: [first, second]))
    #expect(context.isInvalidated(second))
    #expect(context.invalidationAffectsSubtree(at: testIdentity("Root", "Second")))
  }

  @Test("refreshed invalidation queries match a summary built from the frame's identities")
  func refreshedInvalidationQueriesMatchFrameSummary() {
    let leaf = testIdentity("Root", "Branch", "Leaf")
    let box = FrameResolveInputBox()
    box.store(frameInputs(invalidatedIdentities: [leaf], animationSegments: []))
    // The captured context predates the frame: its own set is stale.
    var context = ResolveContext(
      identity: testIdentity("Root", "Branch"),
      invalidatedIdentities: [testIdentity("Root", "Stale")]
    )
    context.frameInputs = box

    let refreshed = context.applyingCurrentFrameResolveInputs()
    let reference = InvalidationSummary(invalidatedIdentities: [leaf])

    #expect(refreshed.invalidationSummary == reference)
    #expect(refreshed.isInvalidated(leaf))
    #expect(!refreshed.isInvalidated(testIdentity("Root", "Stale")))
    for probe in [
      testIdentity("Root"), testIdentity("Root", "Branch"), leaf,
      leaf.child(.named("Below")), testIdentity("Root", "Stale"),
      testIdentity("Root", "Other"),
    ] {
      #expect(
        refreshed.invalidationAffectsSubtree(at: probe) == reference.intersectsSubtree(at: probe),
        "intersection for \(probe.path) diverged from the frame summary"
      )
    }
  }

  @Test("context equality is unchanged by the refresh's summary adoption")
  func contextEqualityUnchangedByRefresh() {
    let leaf = testIdentity("Root", "Leaf")
    let box = FrameResolveInputBox()
    box.store(frameInputs(invalidatedIdentities: [leaf], animationSegments: []))
    var context = ResolveContext(identity: testIdentity("Root"))
    context.frameInputs = box

    let refreshed = context.applyingCurrentFrameResolveInputs()
    var written = context
    written.invalidatedIdentities = [leaf]
    var rewritten = context
    rewritten.invalidatedIdentities = [testIdentity("Root", "Other")]
    rewritten.invalidatedIdentities = [leaf]
    var other = context
    other.invalidatedIdentities = [testIdentity("Root", "Other")]

    #expect(written == rewritten)
    #expect(written != other)
    #expect(refreshed.invalidatedIdentities == written.invalidatedIdentities)
    #expect(refreshed.invalidationSummary == written.invalidationSummary)
  }
}

private func resolveContext(
  focusedIdentity: Identity? = nil,
  pressedIdentity: Identity? = nil
) -> ResolveContext {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  environmentValues.pressedIdentity = pressedIdentity
  return ResolveContext(
    identity: testIdentity("Root"),
    environmentValues: environmentValues,
    applyEnvironmentValues: true
  )
}

@MainActor
private func inputBox(
  focusedIdentity: Identity?,
  pressedIdentity: Identity?,
  animationSegments: [AnimationInvalidationSegment] = []
) -> FrameResolveInputBox {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  environmentValues.pressedIdentity = pressedIdentity
  let box = FrameResolveInputBox()
  box.store(
    frameInputs(
      invalidatedIdentities: [],
      animationSegments: animationSegments,
      environmentValues: environmentValues
    )
  )
  return box
}

@MainActor
private func frameInputs(
  invalidatedIdentities: Set<Identity>,
  animationSegments: [AnimationInvalidationSegment],
  environmentValues: EnvironmentValues = .init()
) -> FrameResolveInputs {
  FrameResolveInputs(
    invalidatedIdentities: invalidatedIdentities,
    invalidationSummary: .init(invalidatedIdentities: invalidatedIdentities),
    environmentValues: environmentValues,
    environment: .init(),
    focusedValues: .init(),
    transaction: .init(),
    animationSegments: animationSegments,
    resolveWorkTracker: nil,
    proposal: ProposedSize(width: 80, height: 24),
    usesSelectiveEvaluation: true,
    environmentRequiresRootEvaluation: false
  )
}
