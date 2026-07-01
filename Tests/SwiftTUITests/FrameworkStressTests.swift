import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI framework stress behavior", .serialized)
struct FrameworkStressTests {
  @Test("mixed deferred runtime surfaces survive repeated teardown and recreation")
  func mixedDeferredRuntimeSurfacesSurviveRepeatedTeardownAndRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MixedDeferredStressRoot"),
      size: .init(width: 72, height: 20)
    ) {
      MixedDeferredStressFixture()
    }
    defer { harness.shutdown() }

    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for cycle in 1...6 {
      let rootButtonPoint = try #require(harness.point(forText: "Increment Root"))

      var frame = try harness.clickText("Increment Root")
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Open Sheet")
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.click(rootButtonPoint)
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Root count \(cycle + 1)"))
      frame = try harness.clickText("Close Sheet", chooseLast: true)
      #expect(!frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Nav root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Push Detail")
      #expect(frame.contains("Destination body"))
      frame = try harness.clickText("Pop Detail", chooseLast: true)
      #expect(!frame.contains("Destination body"))
      #expect(frame.contains("Nav root"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Presentation root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Open Confirm")
      #expect(frame.contains("Confirm body"))
      frame = try harness.clickText("Close Confirm", chooseLast: true)
      #expect(!frame.contains("Confirm body"))
      frame = try harness.clickText("Open Popover")
      #expect(frame.contains("Popover body"))
      frame = try harness.clickText("Close Popover", chooseLast: true)
      #expect(!frame.contains("Popover body"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Geometry tab"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Destination body"))
      #expect(!frame.contains("Confirm body"))
      #expect(!frame.contains("Popover body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(
      maxLifecycleRegistrations <= 24,
      """
      Deferred surface churn must not accumulate lifecycle handlers without \
      bound; max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test(".task(id:) stays bounded across lazy-tab selection, descriptor, and identity churn")
  func taskIDStaysBoundedAcrossLazyTabSelectionDescriptorAndIdentityChurn() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TaskCancellationStressRoot"),
      size: .init(width: 48, height: 12)
    ) {
      TaskCancellationStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 1)
    var maxActiveTasks = harness.activeTaskCount

    for generation in 1...40 {
      let frame = try harness.clickText("Cycle Task")
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)

      #expect(frame.contains("generation \(generation)"))
      #expect(harness.activeTaskCount == 1)
      #expect(harness.activeTaskDescriptorCount == 1)
    }

    #expect(maxActiveTasks == 1)
    harness.shutdown()
    #expect(harness.activeTaskCount == 0)
  }

  @Test("lazy tab actions keep hoisted state isolated across repeated recreation")
  func lazyTabActionsKeepHoistedStateIsolatedAcrossRepeatedRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LazyTabStateStressRoot"),
      size: .init(width: 52, height: 12)
    ) {
      LazyTabStateStressFixture()
    }
    defer { harness.shutdown() }

    var frame = harness.frame
    #expect(frame.contains("Totals alpha 0 beta 0"))
    #expect(frame.contains("Alpha action view"))
    #expect(!frame.contains("Beta action view"))

    for iteration in 1...12 {
      frame = try harness.clickText("Increment Alpha")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Increment Beta")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))
    }
  }

  @Test("deferred presentation sources prune overlays when their owner is recreated")
  func deferredPresentationSourcesPruneOverlaysWhenTheirOwnerIsRecreated() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DeferredSourcePruningStressRoot"),
      size: .init(width: 64, height: 16)
    ) {
      DeferredSourcePruningStressFixture()
    }
    defer { harness.shutdown() }

    var sourceVersion = 0
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for iteration in 1...15 {
      let surface = DeferredSourcePruningSurface(iteration: iteration)
      var frame = try harness.clickText(surface.openLabel)
      #expect(frame.contains(surface.bodyText))

      frame = try harness.clickText("Replace Source", chooseLast: true)
      sourceVersion += 1
      #expect(frame.contains("Owner version \(sourceVersion)"))
      #expect(!frame.contains("Sheet body"))
      #expect(!frame.contains("Alert body"))
      #expect(!frame.contains("Popover body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(
      maxLifecycleRegistrations <= 24,
      """
      Presentation owner churn must prune stale overlay lifecycle handlers; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("modal focus restoration stack drains when modal owners are recreated")
  func modalFocusRestorationStackDrainsWhenModalOwnersAreRecreated() throws {
    // Hypothesis: replacing a focused modal's source owner should tear down
    // both the overlay and the focus restoration record for that modal scope.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModalFocusRestorationStackStressRoot"),
      size: .init(width: 66, height: 12)
    ) {
      ModalFocusRestorationStackStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.focusModalRestorationStackCount == 0)

    var maxRestorationStackCount = harness.focusModalRestorationStackCount

    for generation in 0..<20 {
      _ = try harness.clickText("Base Focus \(generation)")
      var frame = try harness.clickText("Open Modal Owner")
      #expect(frame.contains("Modal body \(generation)"))
      #expect(harness.focusModalRestorationStackCount == 1)

      _ = try harness.clickText("Modal Focus \(generation)", chooseLast: true)
      frame = try harness.clickText("Replace Modal Owner", chooseLast: true)
      #expect(frame.contains("modal owner generation \(generation + 1)"))
      #expect(!frame.contains("Modal body"))

      maxRestorationStackCount = max(
        maxRestorationStackCount,
        harness.focusModalRestorationStackCount
      )

      #expect(harness.focusModalRestorationStackCount == 0)
    }

    #expect(maxRestorationStackCount <= 1)
  }

  @Test("collection identity churn keeps row actions and tasks bounded")
  func collectionIdentityChurnKeepsRowActionsAndTasksBounded() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionIdentityChurnStressRoot"),
      size: .init(width: 48, height: 14)
    ) {
      CollectionIdentityChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
    #expect(
      harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

    var expectedTotal = 0
    var maxActionRegistrations = harness.actionRegistrationCount
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount
    var maxActiveTasks = harness.activeTaskCount

    for epoch in 0..<20 {
      let firstRowID = CollectionIdentityChurnStressFixture.firstRowID(for: epoch)
      expectedTotal += firstRowID

      var frame = try harness.clickText("Row \(firstRowID)")
      #expect(frame.contains("epoch \(epoch) total \(expectedTotal)"))
      #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
      #expect(
        harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

      frame = try harness.clickText("Rebuild Rows")
      #expect(frame.contains("epoch \(epoch + 1) total \(expectedTotal)"))
      #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
      #expect(
        harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

      maxActionRegistrations = max(maxActionRegistrations, harness.actionRegistrationCount)
      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)
    }

    #expect(maxActiveTasks == CollectionIdentityChurnStressFixture.rowCount)
    #expect(
      maxActionRegistrations <= CollectionIdentityChurnStressFixture.rowCount + 1,
      """
      Row action registrations should stay bounded by the visible rows plus \
      the rebuild action; max=\(maxActionRegistrations)
      """
    )
    #expect(
      maxLifecycleRegistrations <= CollectionIdentityChurnStressFixture.rowCount * 2,
      """
      Row lifecycle registrations should stay bounded by the visible rows; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("gesture branch replacement keeps recognizers and gesture state bounded")
  func gestureBranchReplacementKeepsRecognizersAndGestureStateBounded() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureBranchReplacementStressRoot"),
      size: .init(width: 52, height: 10)
    ) {
      GestureBranchReplacementStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.pointerHandlerCount == 1)
    #expect(harness.gestureRecognizerCount == 1)
    #expect(harness.gestureStateBindingCount == 1)

    var expectedTotal = 0
    var maxPointerHandlers = harness.pointerHandlerCount
    var maxGestureRecognizers = harness.gestureRecognizerCount
    var maxGestureStateBindings = harness.gestureStateBindingCount

    for iteration in 1...16 {
      let start = try #require(harness.point(forText: "Drag Pad"))
      expectedTotal += 4
      var frame = try harness.drag(
        from: start,
        to: Point(x: start.x + 4, y: start.y)
      )
      #expect(frame.contains("total \(expectedTotal)"))

      frame = try harness.clickText("Swap Gesture Branch")
      #expect(frame.contains("gesture version \(iteration) total \(expectedTotal)"))
      #expect(frame.contains("Drag Pad \(iteration.isMultiple(of: 2) ? "A" : "B")"))

      maxPointerHandlers = max(maxPointerHandlers, harness.pointerHandlerCount)
      maxGestureRecognizers = max(maxGestureRecognizers, harness.gestureRecognizerCount)
      maxGestureStateBindings = max(
        maxGestureStateBindings,
        harness.gestureStateBindingCount
      )

      #expect(harness.pointerHandlerCount == 1)
      #expect(harness.gestureRecognizerCount == 1)
      #expect(harness.gestureStateBindingCount == 1)
    }

    #expect(maxPointerHandlers == 1)
    #expect(maxGestureRecognizers == 1)
    #expect(maxGestureStateBindings == 1)
  }

  @Test("pointer hover handlers stay live and bounded under owner churn")
  func pointerHoverHandlersStayLiveAndBoundedUnderOwnerChurn() throws {
    // Hypothesis: hover-only pointer handlers should be pruned with the owner
    // that authored them, and dispatch should use the current generation's
    // closure after a route identity replacement.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PointerHoverHandlerChurnStressRoot"),
      size: .init(width: 78, height: 8)
    ) {
      PointerHoverHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.pointerHoverHandlerCount == 1)

    var expectedEntered = 0
    var expectedMoved = 0
    var expectedExited = 0
    var maxHoverHandlers = harness.pointerHoverHandlerCount

    for generation in 0..<24 {
      let hoverPoint = try #require(harness.point(forText: "Hover Pad \(generation)"))
      expectedEntered += generation + 1
      var frame = try harness.movePointer(to: hoverPoint)
      if generation == 0 {
        withKnownIssue("Hover state mutations do not currently schedule a rendered frame") {
          #expect(
            frame.contains(
              """
              hover generation \(generation) entered \(expectedEntered) \
              moved \(expectedMoved) exited \(expectedExited)
              """
            ),
            "hover enter state mutation should render the current generation; frame:\n\(frame)"
          )
        }
      }

      expectedMoved += generation + 1
      frame = try harness.movePointer(to: Point(x: hoverPoint.x + 1, y: hoverPoint.y))

      expectedExited += generation + 1
      frame = try harness.movePointer(to: Point(x: 77, y: 7))

      frame = try harness.clickText("Rebuild Hover Owner")
      #expect(frame.contains("hover generation \(generation + 1)"))

      maxHoverHandlers = max(maxHoverHandlers, harness.pointerHoverHandlerCount)
      #expect(harness.pointerHoverHandlerCount == 1)
    }

    #expect(maxHoverHandlers == 1)
  }

  @Test("directed stress discovery case", arguments: FrameworkStressDiscoveryCase.allCases)
  func directedStressDiscoveryCase(_ discoveryCase: FrameworkStressDiscoveryCase) throws {
    try discoveryCase.run()
  }

  @Test("navigation destinations are pruned when their source subtree is recreated")
  func navigationDestinationsArePrunedWhenTheirSourceSubtreeIsRecreated() throws {
    // Hypothesis: replacing the source owner while a destination is active must
    // retire the destination and its Escape pop action instead of carrying stale
    // navigation state into the new owner.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NavigationSourcePruningStressRoot"),
      size: .init(width: 58, height: 12)
    ) {
      NavigationSourcePruningStressFixture()
    }
    defer { harness.shutdown() }

    var sourceVersion = 0
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for iteration in 1...12 {
      var frame = try harness.clickText("Show Detail")
      #expect(frame.contains("Detail body v\(sourceVersion)"))

      frame = try harness.clickText("Replace Navigation Source")
      sourceVersion += 1
      #expect(frame.contains("Nav owner \(sourceVersion)"))
      #expect(!frame.contains("Detail body"))

      frame = try harness.pressKey(KeyPress(.escape))
      #expect(frame.contains("Nav owner \(sourceVersion)"))
      #expect(!frame.contains("Detail body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      #expect(
        frame.contains("Nav epoch \(iteration + 1)"),
        "replacement loop should advance monotonically without stale navigation"
      )
    }

    #expect(
      maxLifecycleRegistrations <= 16,
      """
      Navigation source churn must not accumulate destination lifecycle \
      handlers; max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("focus owner replacement keeps focus registries bounded")
  func focusOwnerReplacementKeepsFocusRegistriesBounded() throws {
    // Hypothesis: replacing a subtree that owns @FocusState bindings and
    // namespace default-focus registrations must not accumulate stale focus
    // entries from prior owners.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusOwnerReplacementStressRoot"),
      size: .init(width: 62, height: 10)
    ) {
      FocusOwnerReplacementStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.focusBindingRegistrationCount == 2)
    #expect(harness.defaultFocusRegistrationCount == 2)
    #expect(harness.focusRegionCount == 3)

    var maxFocusBindings = harness.focusBindingRegistrationCount
    var maxDefaultFocusRegistrations = harness.defaultFocusRegistrationCount
    var maxFocusRegions = harness.focusRegionCount
    var maxActions = harness.actionRegistrationCount

    for generation in 1...24 {
      let frame = try harness.clickText("Replace Focus Owner")
      #expect(frame.contains("focus owner generation \(generation)"))
      #expect(frame.contains("Primary Focus \(generation)"))
      #expect(frame.contains("Preferred Focus \(generation)"))

      maxFocusBindings = max(maxFocusBindings, harness.focusBindingRegistrationCount)
      maxDefaultFocusRegistrations = max(
        maxDefaultFocusRegistrations,
        harness.defaultFocusRegistrationCount
      )
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)
      maxActions = max(maxActions, harness.actionRegistrationCount)

      #expect(harness.focusBindingRegistrationCount == 2)
      #expect(harness.defaultFocusRegistrationCount == 2)
      #expect(harness.focusRegionCount == 3)
    }

    #expect(maxFocusBindings == 2)
    #expect(maxDefaultFocusRegistrations == 2)
    #expect(maxFocusRegions == 3)
    #expect(maxActions == 3)
  }

  @Test("multiple preference observers stay paired under owner churn")
  func multiplePreferenceObserversStayPairedUnderOwnerChurn() throws {
    // Hypothesis: two preference observers on the same resolved owner should
    // keep distinct registrations and both observe every changed generation as
    // the owner is repeatedly recreated.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PreferenceObserverChurnStressRoot"),
      size: .init(width: 66, height: 8)
    ) {
      PreferenceObserverChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.preferenceObservationRegistrationCount == 2)

    var expectedTotal = 0
    var maxPreferenceObservers = harness.preferenceObservationRegistrationCount
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for generation in 1...24 {
      expectedTotal += generation

      let frame = try harness.clickText("Advance Preference Owner")
      #expect(frame.contains("preference generation \(generation)"))
      #expect(frame.contains("first \(expectedTotal) second \(expectedTotal)"))
      #expect(harness.preferenceObservationRegistrationCount == 2)

      maxPreferenceObservers = max(
        maxPreferenceObservers,
        harness.preferenceObservationRegistrationCount
      )
      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(maxPreferenceObservers == 2)
    #expect(
      maxLifecycleRegistrations <= 2,
      """
      Preference owner churn must retire stale lifecycle handlers; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("termination handlers stay paired and bounded under owner churn")
  func terminationHandlersStayPairedAndBoundedUnderOwnerChurn() throws {
    // Hypothesis: stacked termination handlers should stay attached to the live
    // owner only, and handler-driven state updates should schedule a renderable
    // frame even when dispatch starts outside the normal input event path.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TerminationHandlerChurnStressRoot"),
      size: .init(width: 72, height: 8)
    ) {
      TerminationHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.terminationHandlerCount == 2)

    var expectedTotal = 0
    var maxTerminationHandlers = harness.terminationHandlerCount
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for generation in 0..<24 {
      expectedTotal += generation + 1

      let result = try harness.requestTermination(.signal("SIGTERM"))
      #expect(result.disposition == .allow)
      #expect(
        result.frame.contains(
          "termination generation \(generation) first \(expectedTotal) second \(expectedTotal)"
        )
      )

      let frame = try harness.clickText("Advance Termination Owner")
      #expect(frame.contains("termination generation \(generation + 1)"))

      maxTerminationHandlers = max(maxTerminationHandlers, harness.terminationHandlerCount)
      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )

      #expect(harness.terminationHandlerCount == 2)
    }

    #expect(maxTerminationHandlers == 2)
    #expect(maxLifecycleRegistrations <= 2)
  }

  @Test("lifecycle handlers stay paired across teardown and recreation")
  func lifecycleHandlersStayPairedAcrossTeardownAndRecreation() throws {
    // Hypothesis: stacked appear/disappear handlers on a recreated owner should
    // each fire exactly once per owner generation while the live registrations
    // stay bounded to the current owner.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LifecycleHandlerChurnStressRoot"),
      size: .init(width: 82, height: 8)
    ) {
      LifecycleHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    var expectedAppearTotal = 1
    var expectedDisappearTotal = 0
    #expect(
      harness.frame.contains(
        "lifecycle generation 0 appear first 1 second 1 disappear first 0 second 0"
      )
    )
    #expect(harness.lifecycleRegistrationCount == 4)

    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for generation in 1...24 {
      expectedDisappearTotal += generation
      expectedAppearTotal += generation + 1

      let frame = try harness.clickText("Advance Lifecycle Owner")
      #expect(
        frame.contains(
          """
          lifecycle generation \(generation) appear first \(expectedAppearTotal) \
          second \(expectedAppearTotal) disappear first \(expectedDisappearTotal) \
          second \(expectedDisappearTotal)
          """
        )
      )

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      #expect(harness.lifecycleRegistrationCount == 4)
    }

    #expect(maxLifecycleRegistrations == 4)
  }

  @Test("onChange handlers stay paired across value churn and owner recreation")
  func onChangeHandlersStayPairedAcrossValueChurnAndOwnerRecreation() throws {
    // Hypothesis: stacked lifecycle-change handlers should fire once per value
    // change and leave no stale live change registrations after each commit.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ChangeHandlerChurnStressRoot"),
      size: .init(width: 86, height: 8)
    ) {
      ChangeHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.lifecycleRegistrationCount == 0)

    var expectedTotal = 0
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for iteration in 1...24 {
      expectedTotal += iteration

      var frame = try harness.clickText("Bump Change Value")
      #expect(
        frame.contains(
          "change generation \(iteration - 1) value \(iteration) first \(expectedTotal) second \(expectedTotal)"
        )
      )

      frame = try harness.clickText("Recreate Change Owner")
      #expect(frame.contains("change generation \(iteration) value \(iteration)"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      #expect(harness.lifecycleRegistrationCount == 0)
    }

    #expect(maxLifecycleRegistrations == 0)
  }

  @Test("scroll focus reveal anchors are pruned when scroll owners are recreated")
  func scrollFocusRevealAnchorsArePrunedWhenScrollOwnersAreRecreated() throws {
    // Hypothesis: focus-reveal state is interaction state for the live scroll
    // route and should not retain route identities after the owning ScrollView
    // has been torn down and recreated.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollFocusRevealPruningStressRoot"),
      size: .init(width: 54, height: 8)
    ) {
      ScrollFocusRevealPruningStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.scrollPositionRegistrationCount == 1)
    #expect(harness.scrollRevealAnchorCount <= 1)

    var maxScrollRegistrations = harness.scrollPositionRegistrationCount
    var maxRevealAnchors = harness.scrollRevealAnchorCount

    for generation in 1...24 {
      let frame = try harness.clickText("Replace Scroll Owner")
      #expect(frame.contains("scroll owner generation \(generation)"))
      #expect(frame.contains("Scroll Replace \(generation)"))

      maxScrollRegistrations = max(
        maxScrollRegistrations,
        harness.scrollPositionRegistrationCount
      )
      maxRevealAnchors = max(maxRevealAnchors, harness.scrollRevealAnchorCount)

      #expect(harness.scrollPositionRegistrationCount == 1)
      #expect(harness.scrollRevealAnchorCount <= 1)
    }

    #expect(maxScrollRegistrations == 1)
    #expect(maxRevealAnchors <= 1)
  }

  @Test("key press handlers stay paired and bounded under focus owner churn")
  func keyPressHandlersStayPairedAndBoundedUnderFocusOwnerChurn() throws {
    // Hypothesis: multiple focused key handlers on a recreated owner should
    // stay attached to the live focus target without retaining handlers from
    // previous identities.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("KeyPressHandlerChurnStressRoot"),
      size: .init(width: 62, height: 8)
    ) {
      KeyPressHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.keyPressHandlerCount == 2)
    #expect(harness.focusRegionCount == 2)

    var expectedKTotal = 0
    var expectedLTotal = 0
    var maxKeyPressHandlers = harness.keyPressHandlerCount
    var maxFocusRegions = harness.focusRegionCount

    for generation in 0..<20 {
      _ = try harness.clickText("Key Target \(generation)")

      expectedKTotal += generation + 1
      var frame = try harness.pressKey(KeyPress(.character("k")))
      #expect(frame.contains("key totals k \(expectedKTotal) l \(expectedLTotal)"))

      expectedLTotal += generation + 1
      frame = try harness.pressKey(KeyPress(.character("l")))
      #expect(frame.contains("key totals k \(expectedKTotal) l \(expectedLTotal)"))

      frame = try harness.clickText("Replace Key Owner")
      #expect(frame.contains("key owner generation \(generation + 1)"))

      maxKeyPressHandlers = max(maxKeyPressHandlers, harness.keyPressHandlerCount)
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)

      #expect(harness.keyPressHandlerCount == 2)
      #expect(harness.focusRegionCount == 2)
    }

    #expect(maxKeyPressHandlers == 2)
    #expect(maxFocusRegions == 2)
  }

  @Test("text input paste handlers stay live and bounded under owner churn")
  func textInputPasteHandlersStayLiveAndBoundedUnderOwnerChurn() throws {
    // Hypothesis: a text input with a stable identity inside a recreated owner
    // should replace its paste handler instead of stacking stale handlers, and
    // paste dispatch should keep writing through the live owner binding.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextInputPasteHandlerChurnStressRoot"),
      size: .init(width: 70, height: 8)
    ) {
      TextInputPasteHandlerChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.pasteHandlerCount == 1)

    var maxPasteHandlers = harness.pasteHandlerCount
    var maxFocusRegions = harness.focusRegionCount

    for generation in 0..<24 {
      _ = try harness.focus(TextInputPasteHandlerChurnStressFixture.fieldIdentity)

      let payload = "paste-\(generation)"
      var frame = try harness.paste(payload)
      #expect(
        frame.contains("text input generation \(generation) value \(payload)")
      )

      frame = try harness.clickText("Rebuild Text Input")
      #expect(frame.contains("text input generation \(generation + 1) value empty"))

      maxPasteHandlers = max(maxPasteHandlers, harness.pasteHandlerCount)
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)

      #expect(harness.pasteHandlerCount == 1)
      #expect(harness.focusRegionCount == 2)
    }

    #expect(maxPasteHandlers == 1)
    #expect(maxFocusRegions == 2)
  }

  @Test("focused value descendant identities stay bounded under child identity churn")
  func focusedValueDescendantIdentitiesStayBoundedUnderChildIdentityChurn() throws {
    // Hypothesis: a stable focused-value publisher wrapping a recreated child
    // should replace its descendant identity set with the current subtree,
    // rather than retaining descendant identities from prior child owners.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusedValueDescendantChurnStressRoot"),
      size: .init(width: 70, height: 8)
    ) {
      FocusedValueDescendantChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.focusedValueRegistrationCount == 1)
    let initialDescendantIdentityCount = harness.focusedValueDescendantIdentityCount

    var maxFocusedValueRegistrations = harness.focusedValueRegistrationCount
    var maxDescendantIdentityCount = harness.focusedValueDescendantIdentityCount

    for generation in 1...24 {
      let frame = try harness.clickText("Advance Focused Descendant")
      #expect(frame.contains("focused value generation \(generation)"))
      #expect(frame.contains("Focused Descendant \(generation)"))

      maxFocusedValueRegistrations = max(
        maxFocusedValueRegistrations,
        harness.focusedValueRegistrationCount
      )
      maxDescendantIdentityCount = max(
        maxDescendantIdentityCount,
        harness.focusedValueDescendantIdentityCount
      )

      #expect(harness.focusedValueRegistrationCount == 1)
      if harness.focusedValueDescendantIdentityCount > initialDescendantIdentityCount {
        #expect(harness.focusedValueDescendantIdentityCount == initialDescendantIdentityCount)
        return
      }
    }

    #expect(maxFocusedValueRegistrations == 1)
    #expect(maxDescendantIdentityCount == initialDescendantIdentityCount)
  }

  @Test("focused binding dispatch targets the live owner under identity churn")
  func focusedBindingDispatchTargetsTheLiveOwnerUnderIdentityChurn() throws {
    // Hypothesis: a @FocusedBinding reader above a recreated focused-value
    // publisher should retarget to the currently focused live owner, not retain
    // a binding into a prior owner whose identity has been torn down.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusedBindingChurnStressRoot"),
      size: .init(width: 82, height: 10)
    ) {
      FocusedBindingChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.focusedValueRegistrationCount == 2)

    var expectedFocusedValue = 0
    var maxFocusedValueRegistrations = harness.focusedValueRegistrationCount
    var maxFocusRegions = harness.focusRegionCount

    for generation in 0..<24 {
      _ = try harness.clickText("Focused Binding First \(generation)")
      expectedFocusedValue += generation + 1

      var frame = try harness.pressKey(KeyPress(.character("i"), modifiers: .ctrl))
      #expect(
        frame.contains(
          "focused binding generation \(generation) value \(expectedFocusedValue)"
        )
      )

      frame = try harness.clickText("Rebuild Focused Binding Owner")
      #expect(frame.contains("focused binding generation \(generation + 1)"))
      #expect(frame.contains("Focused Binding First \(generation + 1)"))
      #expect(frame.contains("Focused Binding Second \(generation + 1)"))

      maxFocusedValueRegistrations = max(
        maxFocusedValueRegistrations,
        harness.focusedValueRegistrationCount
      )
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)

      #expect(harness.focusedValueRegistrationCount == 2)
      #expect(harness.focusRegionCount == 3)
    }

    #expect(maxFocusedValueRegistrations == 2)
    #expect(maxFocusRegions == 3)
  }

  @Test("key commands stay scoped and bounded under inner panel identity churn")
  func keyCommandsStayScopedAndBoundedUnderInnerPanelIdentityChurn() throws {
    // Hypothesis: action-scope command registrations should remove stale inner
    // panel scopes while preserving shallowest-wins dispatch through the live
    // focus path.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("KeyCommandScopeChurnStressRoot"),
      size: .init(width: 72, height: 10)
    ) {
      KeyCommandScopeChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.keyCommandRegistrationCount == 2)

    var expectedOuterTotal = 0
    var maxKeyCommands = harness.keyCommandRegistrationCount
    var maxFocusRegions = harness.focusRegionCount

    for generation in 0..<24 {
      _ = try harness.clickText("Command Focus \(generation)")
      expectedOuterTotal += generation + 1

      var frame = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
      #expect(
        frame.contains("command generation \(generation) outer \(expectedOuterTotal) inner 0"))

      frame = try harness.clickText("Rebuild Command Scope")
      #expect(frame.contains("command generation \(generation + 1)"))

      maxKeyCommands = max(maxKeyCommands, harness.keyCommandRegistrationCount)
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)

      #expect(harness.keyCommandRegistrationCount == 2)
      #expect(harness.focusRegionCount == 2)
    }

    #expect(maxKeyCommands == 2)
    #expect(maxFocusRegions == 2)
  }

  @Test("drop destinations stay scoped and bounded under inner panel identity churn")
  func dropDestinationsStayScopedAndBoundedUnderInnerPanelIdentityChurn() throws {
    // Hypothesis: action-scope drop destinations should prune stale inner panel
    // scopes while leafmost-first dispatch continues to favor the focused live
    // inner scope.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DropDestinationScopeChurnStressRoot"),
      size: .init(width: 72, height: 10)
    ) {
      DropDestinationScopeChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.dropDestinationRegistrationCount == 2)

    var expectedInnerTotal = 0
    var maxDropDestinations = harness.dropDestinationRegistrationCount
    var maxFocusRegions = harness.focusRegionCount

    for generation in 0..<24 {
      _ = try harness.clickText("Drop Focus \(generation)")
      expectedInnerTotal += generation + 1

      var frame = try harness.drop(paths: [DroppedPath("/tmp/drop-\(generation)")])
      #expect(
        frame.contains("drop generation \(generation) outer 0 inner \(expectedInnerTotal)"))

      frame = try harness.clickText("Rebuild Drop Scope")
      #expect(frame.contains("drop generation \(generation + 1)"))

      maxDropDestinations = max(maxDropDestinations, harness.dropDestinationRegistrationCount)
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)

      #expect(harness.dropDestinationRegistrationCount == 2)
      #expect(harness.focusRegionCount == 2)
    }

    #expect(maxDropDestinations == 2)
    #expect(maxFocusRegions == 2)
  }

  @Test("multiple task modifiers stay paired and bounded under identity churn")
  func multipleTaskModifiersStayPairedAndBoundedUnderIdentityChurn() throws {
    // Hypothesis: repeated identity and descriptor churn on a node with two
    // tasks must preserve both authored task descriptors while cancelling old
    // generations promptly.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MultipleTaskModifierStressRoot"),
      size: .init(width: 54, height: 8)
    ) {
      MultipleTaskModifierStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 2)
    #expect(harness.activeTaskDescriptorCount == 2)

    var maxActiveTasks = harness.activeTaskCount
    var maxTaskDescriptors = harness.activeTaskDescriptorCount

    for generation in 1...36 {
      let frame = try harness.clickText("Cycle Multi Tasks")
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)
      maxTaskDescriptors = max(maxTaskDescriptors, harness.activeTaskDescriptorCount)

      #expect(frame.contains("multi-task generation \(generation)"))
      #expect(harness.activeTaskCount == 2)
      #expect(harness.activeTaskDescriptorCount == 2)
    }

    #expect(maxActiveTasks == 2)
    #expect(maxTaskDescriptors == 2)

    harness.shutdown()
    #expect(harness.activeTaskCount == 0)
  }
}

private struct MixedDeferredStressFixture: View {
  @State private var rootCount = 0
  @State private var selectedTab = "geometry"
  @State private var destinationPresented = false
  @State private var sheetPresented = false
  @State private var confirmationPresented = false
  @State private var popoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root count \(rootCount)")
      HStack(spacing: 1) {
        Button("Increment Root") { rootCount += 1 }
        Button("Next Tab") { selectedTab = nextTab(after: selectedTab) }
      }

      TabView(selection: $selectedTab) {
        Tab("Geometry", value: "geometry") {
          geometryTab
        }

        Tab("Navigation", value: "navigation") {
          navigationTab
        }

        Tab("Presentation", value: "presentation") {
          presentationTab
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 72, height: 20, alignment: .topLeading)
  }

  private var geometryTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Text("Geometry tab \(proxy.size.width)x\(proxy.size.height)")
            .onAppear {}
            .onDisappear {}
          Text("Geometry body")
        }
      }
      .frame(height: 2)

      ForEach(0..<6) { index in
        Text("Geometry row \(index)")
      }
      Button("Open Sheet") { sheetPresented = true }
    }
    .sheet("Stress Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close Sheet") { sheetPresented = false }
      }
      .onAppear {}
      .onDisappear {}
    }
  }

  private var navigationTab: some View {
    NavigationStack(id: "mixed-deferred-stress-navigation") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nav root")
          .onAppear {}
          .onDisappear {}
        Button("Push Detail") { destinationPresented = true }
      }
      .navigationDestination(isPresented: $destinationPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Destination body")
          Button("Pop Detail") { destinationPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
    }
  }

  private var presentationTab: some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      Text("Presentation root")
        .onAppear {}
        .onDisappear {}
      Button("Open Confirm") { confirmationPresented = true }
      Button("Open Popover") { popoverPresented = true }
    }

    return
      base
      .confirmationDialog(
        "Stress Confirm",
        isPresented: $confirmationPresented,
        actions: {
          Button("Close Confirm") { confirmationPresented = false }
        },
        message: {
          Text("Confirm body")
        }
      )
      .popover(isPresented: $popoverPresented, arrowEdge: .trailing) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Popover body")
          Button("Close Popover") { popoverPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
  }

  private func nextTab(after current: String) -> String {
    switch current {
    case "geometry": "navigation"
    case "navigation": "presentation"
    default: "geometry"
    }
  }
}

private struct TaskCancellationStressFixture: View {
  @State private var selectedTab = "left"
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle Task") {
        generation += 1
        selectedTab = selectedTab == "left" ? "right" : "left"
      }
      Text("selection \(selectedTab) generation \(generation)")

      TabView(selection: $selectedTab) {
        Tab("Left", value: "left") {
          TaskCancellationStressPane(label: "left", generation: generation)
            .id("left-\(generation % 5)")
        }

        Tab("Right", value: "right") {
          TaskCancellationStressPane(label: "right", generation: generation)
            .id("right-\(generation % 5)")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 48, height: 12, alignment: .topLeading)
  }
}

private struct TaskCancellationStressPane: View {
  let label: String
  let generation: Int

  var body: some View {
    GeometryReader { proxy in
      Text("task \(label) generation \(generation) size \(proxy.size.width)x\(proxy.size.height)")
        .task(
          id: TaskCancellationStressID(
            label: label,
            generation: generation,
            width: proxy.size.width,
            height: proxy.size.height
          )
        ) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
    }
  }
}

private struct TaskCancellationStressID: Equatable, Sendable {
  var label: String
  var generation: Int
  var width: Int
  var height: Int
}

private struct LazyTabStateStressFixture: View {
  @State private var selectedTab = "alpha"
  @State private var alphaTotal = 0
  @State private var betaTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Next Counter Tab") {
        selectedTab = selectedTab == "alpha" ? "beta" : "alpha"
      }
      Text("counter selection \(selectedTab)")
      Text("Totals alpha \(alphaTotal) beta \(betaTotal)")

      TabView(selection: $selectedTab) {
        Tab("Alpha", value: "alpha") {
          LazyTabCounterPane(label: "Alpha") {
            alphaTotal += 1
          }
        }

        Tab("Beta", value: "beta") {
          LazyTabCounterPane(label: "Beta") {
            betaTotal += 1
          }
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 52, height: 12, alignment: .topLeading)
  }
}

private struct LazyTabCounterPane: View {
  let label: String
  let increment: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) action view")
      Button("Increment \(label)") { increment() }
    }
    .onAppear {}
    .onDisappear {}
  }
}

private enum DeferredSourcePruningSurface {
  case sheet
  case alert
  case popover

  init(iteration: Int) {
    switch iteration % 3 {
    case 1: self = .sheet
    case 2: self = .alert
    default: self = .popover
    }
  }

  var openLabel: String {
    switch self {
    case .sheet: "Open Sheet Source"
    case .alert: "Open Alert Source"
    case .popover: "Open Popover Source"
    }
  }

  var bodyText: String {
    switch self {
    case .sheet: "Sheet body"
    case .alert: "Alert body"
    case .popover: "Popover body"
    }
  }
}

private struct DeferredSourcePruningStressFixture: View {
  @State private var sourceVersion = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Source root version \(sourceVersion)")
      DeferredSourcePruningOwner(version: sourceVersion) {
        sourceVersion += 1
      }
      .id("source-\(sourceVersion)")
    }
    .frame(width: 64, height: 16, alignment: .topLeading)
  }
}

private struct DeferredSourcePruningOwner: View {
  let version: Int
  let replaceSource: @MainActor () -> Void

  @State private var sheetPresented = false
  @State private var alertPresented = false
  @State private var popoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Owner version \(version)")
        .onAppear {}
        .onDisappear {}
      Button("Open Sheet Source") { sheetPresented = true }
      Button("Open Alert Source") { alertPresented = true }
      Button("Open Popover Source") { popoverPresented = true }
    }
    .sheet("Source Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body v\(version)")
        Button("Replace Source") { replaceSource() }
      }
      .onAppear {}
      .onDisappear {}
    }
    .alert(
      "Source Alert",
      isPresented: $alertPresented,
      actions: {
        Button("Replace Source") { replaceSource() }
      },
      message: {
        Text("Alert body v\(version)")
      }
    )
    .popover(isPresented: $popoverPresented, arrowEdge: .trailing) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Popover body v\(version)")
        Button("Replace Source") { replaceSource() }
      }
      .onAppear {}
      .onDisappear {}
    }
  }
}

private struct ModalFocusRestorationStackStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("modal owner generation \(generation)")
      ModalFocusRestorationStackOwner(generation: generation) {
        generation += 1
      }
      .id("modal-focus-owner-\(generation)")
    }
    .frame(width: 66, height: 12, alignment: .topLeading)
  }
}

private struct ModalFocusRestorationStackOwner: View {
  let generation: Int
  let replaceOwner: @MainActor () -> Void

  @State private var isPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Base Focus \(generation)") {}
      Button("Open Modal Owner") { isPresented = true }
    }
    .sheet("Modal Focus Sheet", isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Modal body \(generation)")
        Button("Modal Focus \(generation)") {}
        Button("Replace Modal Owner") { replaceOwner() }
      }
      .onAppear {}
      .onDisappear {}
    }
  }
}

private struct CollectionIdentityChurnStressFixture: View {
  static let rowCount = 6

  static func firstRowID(for epoch: Int) -> Int {
    epoch * 100 + 1
  }

  @State private var epoch = 0
  @State private var total = 0

  private var rowIDs: [Int] {
    (0..<Self.rowCount).map { Self.firstRowID(for: epoch) + $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Rows") { epoch += 1 }
      Text("epoch \(epoch) total \(total)")

      ForEach(rowIDs, id: \.self) { id in
        CollectionIdentityChurnRow(id: id) {
          total += id
        }
      }
    }
    .frame(width: 48, height: 14, alignment: .topLeading)
  }
}

private struct CollectionIdentityChurnRow: View {
  let id: Int
  let increment: @MainActor () -> Void

  var body: some View {
    Button("Row \(id)") { increment() }
      .onAppear {}
      .onDisappear {}
      .task(id: CollectionIdentityChurnTaskID(rowID: id)) {
        while !Task.isCancelled {
          await Task.yield()
        }
      }
  }
}

private struct CollectionIdentityChurnTaskID: Equatable, Sendable {
  var rowID: Int
}

private struct GestureBranchReplacementStressFixture: View {
  @State private var version = 0
  @State private var total = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Swap Gesture Branch") { version += 1 }
      Text("gesture version \(version) total \(total)")

      if version.isMultiple(of: 2) {
        GestureBranchReplacementPad(label: "A", version: version) { value in
          total += Int(value.translation.dx.rounded())
        }
        .id("gesture-pad-\(version)")
      } else {
        GestureBranchReplacementPad(label: "B", version: version) { value in
          total += Int(value.translation.dx.rounded())
        }
        .id("gesture-pad-\(version)")
      }
    }
    .frame(width: 52, height: 10, alignment: .topLeading)
  }
}

private struct GestureBranchReplacementPad: View {
  let label: String
  let version: Int
  let onEnded: @MainActor (DragGesture.Value) -> Void

  @GestureState private var dragOffset = Vector(dx: 0, dy: 0)

  var body: some View {
    Text("Drag Pad \(label) \(version) offset \(Int(dragOffset.dx.rounded()))")
      .frame(width: 32, height: 1, alignment: .leading)
      .gesture(
        DragGesture()
          .updating($dragOffset) { value, state, _ in
            state = value.translation
          }
          .onEnded { value in
            onEnded(value)
          }
      )
      .onAppear {}
      .onDisappear {}
  }
}

private struct PointerHoverHandlerChurnStressFixture: View {
  @State private var generation = 0
  @State private var enteredTotal = 0
  @State private var movedTotal = 0
  @State private var exitedTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Hover Owner") { generation += 1 }
      Text(
        """
        hover generation \(generation) entered \(enteredTotal) moved \(movedTotal) \
        exited \(exitedTotal)
        """
      )
      PointerHoverHandlerChurnOwner(
        generation: generation,
        onEntered: { enteredTotal += $0 + 1 },
        onMoved: { movedTotal += $0 + 1 },
        onExited: { exitedTotal += $0 + 1 }
      )
      .id(testIdentity("PointerHoverHandlerChurn", "owner", "\(generation)"))
    }
    .frame(width: 78, height: 8, alignment: .topLeading)
  }
}

private struct PointerHoverHandlerChurnOwner: View {
  let generation: Int
  let onEntered: @MainActor (Int) -> Void
  let onMoved: @MainActor (Int) -> Void
  let onExited: @MainActor (Int) -> Void

  var body: some View {
    Text("Hover Pad \(generation)")
      .id(testIdentity("PointerHoverHandlerChurn", "pad", "\(generation)"))
      .frame(width: 24, height: 1, alignment: .leading)
      .onPointerHover { phase in
        switch phase {
        case .entered:
          onEntered(generation)
        case .moved:
          onMoved(generation)
        case .exited:
          onExited(generation)
        }
      }
      .onAppear {}
      .onDisappear {}
  }
}

enum FrameworkStressDiscoveryCase: String, CaseIterable, CustomStringConvertible,
  Sendable
{
  case stableButtonActionRebinds
  case disabledButtonSkipsActionRegistration
  case stableToggleActionRebinds
  case disabledToggleSkipsActionRegistration
  case stableDisclosureActionRebinds
  case disabledDisclosureSkipsActionRegistration
  case textFieldKeyHandlerRebinds
  case disabledTextFieldSkipsInputHandlers
  case secureFieldPasteHandlerRebinds
  case textEditorPasteHandlerRebinds
  case stepperKeyHandlerRebinds
  case disabledStepperSkipsInputHandlers
  case sliderKeyHandlerRebinds
  case pickerKeyHandlerRebinds
  case scrollViewHandlersStayBounded
  case disabledScrollViewSkipsPointerHandlers
  case tapGestureRecognizerRebinds
  case dragGestureRecognizerRebinds
  case keyCommandScopeRebinds
  case dropDestinationScopeRebinds

  var description: String { rawValue }

  @MainActor
  func run() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FrameworkStressDiscovery", rawValue, "root"),
      size: .init(width: 90, height: 12)
    ) {
      FrameworkStressDiscoveryFixture(discoveryCase: self)
    }
    defer { harness.shutdown() }

    var expectedTotal = 0
    var maxActions = harness.actionRegistrationCount
    var maxKeyHandlers = harness.keyHandlerCount
    var maxKeyPressHandlers = harness.keyPressHandlerCount
    var maxPasteHandlers = harness.pasteHandlerCount
    var maxPointerHandlers = harness.pointerHandlerCount
    var maxGestureRecognizers = harness.gestureRecognizerCount
    var maxKeyCommands = harness.keyCommandRegistrationCount
    var maxDropDestinations = harness.dropDestinationRegistrationCount

    for generation in 0..<iterationCount {
      let frame = try exercise(harness: harness, generation: generation)
      expectedTotal = expectedTotalAfterExercise(
        generation: generation,
        previous: expectedTotal
      )
      assertExpectedFrame(
        frame,
        generation: generation,
        expectedTotal: expectedTotal
      )
      assertExpectedRegistrations(harness)

      maxActions = max(maxActions, harness.actionRegistrationCount)
      maxKeyHandlers = max(maxKeyHandlers, harness.keyHandlerCount)
      maxKeyPressHandlers = max(maxKeyPressHandlers, harness.keyPressHandlerCount)
      maxPasteHandlers = max(maxPasteHandlers, harness.pasteHandlerCount)
      maxPointerHandlers = max(maxPointerHandlers, harness.pointerHandlerCount)
      maxGestureRecognizers = max(maxGestureRecognizers, harness.gestureRecognizerCount)
      maxKeyCommands = max(maxKeyCommands, harness.keyCommandRegistrationCount)
      maxDropDestinations = max(
        maxDropDestinations,
        harness.dropDestinationRegistrationCount
      )

      let rebuilt = try harness.clickText("Rebuild Discovery")
      #expect(rebuilt.contains("case \(rawValue) generation \(generation + 1)"))
      if self == .stableButtonActionRebinds {
        withKnownIssue("Stable Button labels remain stale after owner identity churn") {
          #expect(rebuilt.contains("Probe Button \(generation + 1)"))
        }
      }
    }

    assertMaxRegistrations(
      actions: maxActions,
      keyHandlers: maxKeyHandlers,
      keyPressHandlers: maxKeyPressHandlers,
      pasteHandlers: maxPasteHandlers,
      pointerHandlers: maxPointerHandlers,
      gestureRecognizers: maxGestureRecognizers,
      keyCommands: maxKeyCommands,
      dropDestinations: maxDropDestinations
    )
  }

  @MainActor
  private func exercise(
    harness: StressRuntimeHarness<FrameworkStressDiscoveryFixture>,
    generation: Int
  ) throws -> String {
    switch self {
    case .stableButtonActionRebinds:
      return try harness.clickText("Probe Button \(generation)")

    case .disabledButtonSkipsActionRegistration:
      return harness.frame

    case .stableToggleActionRebinds:
      return try harness.clickText("Probe Toggle \(generation)")

    case .disabledToggleSkipsActionRegistration:
      return harness.frame

    case .stableDisclosureActionRebinds:
      return try harness.clickText("Probe Disclosure \(generation)")

    case .disabledDisclosureSkipsActionRegistration:
      return harness.frame

    case .textFieldKeyHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.pressKey(KeyPress(.character("x")))

    case .disabledTextFieldSkipsInputHandlers:
      return harness.frame

    case .secureFieldPasteHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.paste("secret-\(generation)")

    case .textEditorPasteHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.paste("line-\(generation)\nnext")

    case .stepperKeyHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.pressKey(KeyPress(.arrowRight))

    case .disabledStepperSkipsInputHandlers:
      return harness.frame

    case .sliderKeyHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.pressKey(KeyPress(.arrowRight))

    case .pickerKeyHandlerRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.controlIdentity)
      return try harness.pressKey(KeyPress(.arrowDown))

    case .scrollViewHandlersStayBounded:
      let point = try #require(harness.point(forText: "Scroll Row \(generation).1"))
      return try harness.scrollPointer(at: point, deltaY: 1)

    case .disabledScrollViewSkipsPointerHandlers:
      return harness.frame

    case .tapGestureRecognizerRebinds:
      return try harness.clickText("Tap Gesture \(generation)")

    case .dragGestureRecognizerRebinds:
      let start = try #require(harness.point(forText: "Drag Gesture \(generation)"))
      return try harness.drag(from: start, to: Point(x: start.x + 4, y: start.y))

    case .keyCommandScopeRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.focusIdentity)
      return try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))

    case .dropDestinationScopeRebinds:
      _ = try harness.focus(FrameworkStressDiscoveryFixture.focusIdentity)
      return try harness.drop(paths: [DroppedPath("/tmp/discovery-\(generation)")])
    }
  }

  private func expectedTotalAfterExercise(
    generation: Int,
    previous: Int
  ) -> Int {
    switch self {
    case .stableButtonActionRebinds,
      .tapGestureRecognizerRebinds,
      .dragGestureRecognizerRebinds,
      .keyCommandScopeRebinds,
      .dropDestinationScopeRebinds:
      previous + generation + 1
    default:
      previous
    }
  }

  private var iterationCount: Int {
    switch self {
    case .stableButtonActionRebinds:
      1
    default:
      8
    }
  }

  private func assertExpectedFrame(
    _ frame: String,
    generation: Int,
    expectedTotal: Int
  ) {
    #expect(frame.contains("case \(rawValue) generation \(generation)"))

    switch self {
    case .stableButtonActionRebinds,
      .tapGestureRecognizerRebinds,
      .dragGestureRecognizerRebinds,
      .keyCommandScopeRebinds,
      .dropDestinationScopeRebinds:
      #expect(frame.contains("total \(expectedTotal)"))

    case .disabledButtonSkipsActionRegistration,
      .disabledToggleSkipsActionRegistration,
      .disabledDisclosureSkipsActionRegistration,
      .disabledTextFieldSkipsInputHandlers,
      .disabledStepperSkipsInputHandlers,
      .disabledScrollViewSkipsPointerHandlers:
      #expect(frame.contains("total 0"))

    case .stableToggleActionRebinds:
      #expect(frame.contains("flag true"))

    case .stableDisclosureActionRebinds:
      #expect(frame.contains("flag true"))
      #expect(frame.contains("Disclosure body \(generation)"))

    case .textFieldKeyHandlerRebinds:
      #expect(frame.contains("text x"))

    case .secureFieldPasteHandlerRebinds:
      #expect(frame.contains("text secret-\(generation)"))
      #expect(!frame.contains("secret-\(generation)  "))

    case .textEditorPasteHandlerRebinds:
      #expect(frame.contains("text line-\(generation)|next"))

    case .stepperKeyHandlerRebinds,
      .sliderKeyHandlerRebinds:
      #expect(frame.contains("int 1"))

    case .pickerKeyHandlerRebinds:
      #expect(frame.contains("selection b"))

    case .scrollViewHandlersStayBounded:
      #expect(frame.contains("Scroll Row \(generation)."))
    }
  }

  @MainActor
  private func assertExpectedRegistrations(
    _ harness: StressRuntimeHarness<FrameworkStressDiscoveryFixture>
  ) {
    switch self {
    case .disabledButtonSkipsActionRegistration,
      .disabledToggleSkipsActionRegistration,
      .disabledDisclosureSkipsActionRegistration:
      #expect(harness.actionRegistrationCount == 1)

    case .disabledTextFieldSkipsInputHandlers:
      #expect(harness.keyHandlerCount == 0)
      #expect(harness.keyPressHandlerCount == 0)
      #expect(harness.pasteHandlerCount == 0)

    case .disabledStepperSkipsInputHandlers:
      #expect(harness.keyHandlerCount == 0)
      #expect(harness.pointerHandlerCount == 0)

    case .disabledScrollViewSkipsPointerHandlers:
      #expect(harness.keyHandlerCount == 0)
      #expect(harness.pointerHandlerCount == 0)

    default:
      break
    }
  }

  private func assertMaxRegistrations(
    actions: Int,
    keyHandlers: Int,
    keyPressHandlers: Int,
    pasteHandlers: Int,
    pointerHandlers: Int,
    gestureRecognizers: Int,
    keyCommands: Int,
    dropDestinations: Int
  ) {
    switch self {
    case .stableButtonActionRebinds,
      .stableToggleActionRebinds,
      .stableDisclosureActionRebinds:
      #expect(actions <= 2)

    case .disabledButtonSkipsActionRegistration,
      .disabledToggleSkipsActionRegistration,
      .disabledDisclosureSkipsActionRegistration:
      #expect(actions == 1)

    case .textFieldKeyHandlerRebinds,
      .secureFieldPasteHandlerRebinds,
      .textEditorPasteHandlerRebinds:
      #expect(keyHandlers <= (self == .textEditorPasteHandlerRebinds ? 4 : 1))
      #expect(keyPressHandlers <= 1)
      #expect(pasteHandlers <= 1)

    case .disabledTextFieldSkipsInputHandlers:
      #expect(keyHandlers == 0)
      #expect(keyPressHandlers == 0)
      #expect(pasteHandlers == 0)

    case .stepperKeyHandlerRebinds,
      .sliderKeyHandlerRebinds,
      .pickerKeyHandlerRebinds:
      #expect(keyHandlers <= 1)
      #expect(pointerHandlers <= 5)

    case .disabledStepperSkipsInputHandlers:
      #expect(keyHandlers == 0)
      #expect(pointerHandlers == 0)

    case .scrollViewHandlersStayBounded:
      #expect(keyHandlers <= 3)
      #expect(pointerHandlers <= 3)

    case .disabledScrollViewSkipsPointerHandlers:
      #expect(keyHandlers == 0)
      #expect(pointerHandlers == 0)

    case .tapGestureRecognizerRebinds,
      .dragGestureRecognizerRebinds:
      #expect(gestureRecognizers <= 1)
      #expect(pointerHandlers <= 1)

    case .keyCommandScopeRebinds:
      #expect(keyCommands <= 1)

    case .dropDestinationScopeRebinds:
      #expect(dropDestinations <= 1)
    }
  }
}

private struct FrameworkStressDiscoveryFixture: View {
  static let controlIdentity = testIdentity("FrameworkStressDiscovery", "control")
  static let focusIdentity = testIdentity("FrameworkStressDiscovery", "focus")
  static let scopeIdentity = testIdentity("FrameworkStressDiscovery", "scope")

  let discoveryCase: FrameworkStressDiscoveryCase

  @State private var generation = 0
  @State private var total = 0
  @State private var flag = false
  @State private var intValue = 0
  @State private var textValue = ""
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Discovery") {
        generation += 1
        flag = false
        intValue = 0
        textValue = ""
        selection = "a"
      }
      Text(
        """
        case \(discoveryCase.rawValue) generation \(generation) total \(total) \
        flag \(flag) int \(intValue) text \(displayText) selection \(selection)
        """
      )
      FrameworkStressDiscoveryOwner(
        discoveryCase: discoveryCase,
        generation: generation,
        total: $total,
        flag: $flag,
        intValue: $intValue,
        textValue: $textValue,
        selection: $selection
      )
      .id(testIdentity("FrameworkStressDiscovery", "owner", "\(generation)"))
    }
    .frame(width: 90, height: 12, alignment: .topLeading)
  }

  private var displayText: String {
    textValue.isEmpty ? "empty" : textValue.replacingOccurrences(of: "\n", with: "|")
  }
}

private struct FrameworkStressDiscoveryOwner: View {
  let discoveryCase: FrameworkStressDiscoveryCase
  let generation: Int
  @Binding var total: Int
  @Binding var flag: Bool
  @Binding var intValue: Int
  @Binding var textValue: String
  @Binding var selection: String

  var body: some View {
    switch discoveryCase {
    case .stableButtonActionRebinds:
      Button("Probe Button \(generation)") { total += generation + 1 }
        .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .disabledButtonSkipsActionRegistration:
      Button("Disabled Button \(generation)") { total += generation + 1 }
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .disabled(true)

    case .stableToggleActionRebinds:
      Toggle("Probe Toggle \(generation)", isOn: $flag)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .disabledToggleSkipsActionRegistration:
      Toggle("Disabled Toggle \(generation)", isOn: $flag)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .disabled(true)

    case .stableDisclosureActionRebinds:
      DisclosureGroup("Probe Disclosure \(generation)", isExpanded: $flag) {
        Text("Disclosure body \(generation)")
      }
      .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .disabledDisclosureSkipsActionRegistration:
      DisclosureGroup("Disabled Disclosure \(generation)", isExpanded: $flag) {
        Text("Disabled disclosure body \(generation)")
      }
      .id(FrameworkStressDiscoveryFixture.controlIdentity)
      .disabled(true)

    case .textFieldKeyHandlerRebinds:
      TextField("Probe TextField \(generation)", text: $textValue)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .textFieldStyle(.plain)

    case .disabledTextFieldSkipsInputHandlers:
      TextField("Disabled TextField \(generation)", text: $textValue)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .textFieldStyle(.plain)
        .disabled(true)

    case .secureFieldPasteHandlerRebinds:
      SecureField("Probe SecureField \(generation)", text: $textValue)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .textFieldStyle(.plain)

    case .textEditorPasteHandlerRebinds:
      TextEditor(text: $textValue)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .frame(width: 24, height: 3, alignment: .leading)

    case .stepperKeyHandlerRebinds:
      Stepper("Probe Stepper \(generation)", value: $intValue, in: 0...999)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .disabledStepperSkipsInputHandlers:
      Stepper("Disabled Stepper \(generation)", value: $intValue, in: 0...999)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .disabled(true)

    case .sliderKeyHandlerRebinds:
      Slider("Probe Slider \(generation)", value: $intValue, in: 0...999)
        .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .pickerKeyHandlerRebinds:
      Picker("Probe Picker \(generation)", selection: $selection) {
        Text("Option A").tag("a")
        Text("Option B").tag("b")
        Text("Option C").tag("c")
      }
      .id(FrameworkStressDiscoveryFixture.controlIdentity)

    case .scrollViewHandlersStayBounded:
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10, id: \.self) { row in
            Text("Scroll Row \(generation).\(row)")
          }
        }
      }
      .id(FrameworkStressDiscoveryFixture.controlIdentity)
      .frame(width: 36, height: 4, alignment: .topLeading)

    case .disabledScrollViewSkipsPointerHandlers:
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<10, id: \.self) { row in
            Text("Disabled Scroll Row \(generation).\(row)")
          }
        }
      }
      .id(FrameworkStressDiscoveryFixture.controlIdentity)
      .frame(width: 36, height: 4, alignment: .topLeading)
      .disabled(true)

    case .tapGestureRecognizerRebinds:
      Text("Tap Gesture \(generation)")
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .frame(width: 30, height: 1, alignment: .leading)
        .onTapGesture { total += generation + 1 }

    case .dragGestureRecognizerRebinds:
      Text("Drag Gesture \(generation)")
        .id(FrameworkStressDiscoveryFixture.controlIdentity)
        .frame(width: 30, height: 1, alignment: .leading)
        .gesture(
          DragGesture()
            .onEnded { _ in total += generation + 1 }
        )

    case .keyCommandScopeRebinds:
      Panel(id: FrameworkStressDiscoveryFixture.scopeIdentity) {
        Text("Key Command Focus \(generation)")
          .id(FrameworkStressDiscoveryFixture.focusIdentity)
          .focusable()
      }
      .keyCommand("Discovery Save", key: .character("s"), modifiers: .ctrl) {
        total += generation + 1
      }

    case .dropDestinationScopeRebinds:
      Panel(id: FrameworkStressDiscoveryFixture.scopeIdentity) {
        Text("Drop Destination Focus \(generation)")
          .id(FrameworkStressDiscoveryFixture.focusIdentity)
          .focusable()
      }
      .dropDestination { paths in
        total += paths.count * (generation + 1)
        return true
      }
    }
  }
}

private struct NavigationSourcePruningStressFixture: View {
  @State private var sourceVersion = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Nav epoch \(sourceVersion + 1)")
      NavigationSourcePruningOwner(version: sourceVersion) {
        sourceVersion += 1
      }
      .id("navigation-source-\(sourceVersion)")
    }
    .frame(width: 58, height: 12, alignment: .topLeading)
  }
}

private struct NavigationSourcePruningOwner: View {
  let version: Int
  let replaceSource: @MainActor () -> Void

  @State private var detailPresented = false

  var body: some View {
    NavigationStack(id: "navigation-source-pruning-\(version)") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nav owner \(version)")
          .onAppear {}
          .onDisappear {}
        Button("Show Detail") { detailPresented = true }
      }
      .navigationDestination(isPresented: $detailPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Detail body v\(version)")
          Button("Replace Navigation Source") { replaceSource() }
        }
        .onAppear {}
        .onDisappear {}
      }
    }
  }
}

private enum FocusOwnerReplacementField: Hashable {
  case primary
  case preferred
}

private struct FocusOwnerReplacementStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Focus Owner") { generation += 1 }
      Text("focus owner generation \(generation)")
      FocusOwnerReplacementOwner(generation: generation)
        .id("focus-owner-\(generation)")
    }
    .frame(width: 62, height: 10, alignment: .topLeading)
  }
}

private struct FocusOwnerReplacementOwner: View {
  @Namespace private var namespace
  @FocusState private var focusedField: FocusOwnerReplacementField?

  let generation: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Primary Focus \(generation)") {}
        .id(testIdentity("FocusOwnerReplacement", "\(generation)", "primary"))
        .focused($focusedField, equals: .primary)
      Button("Preferred Focus \(generation)") {}
        .id(testIdentity("FocusOwnerReplacement", "\(generation)", "preferred"))
        .focused($focusedField, equals: .preferred)
        .prefersDefaultFocus(in: namespace)
    }
    .focusScope(namespace)
    .onAppear {}
    .onDisappear {}
  }
}

private enum PreferenceObserverStressKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

private struct PreferenceObserverChurnStressFixture: View {
  @State private var generation = 0
  @State private var firstTotal = 0
  @State private var secondTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Preference Owner") { generation += 1 }
      Text("preference generation \(generation)")
      Text("preference totals first \(firstTotal) second \(secondTotal)")
      PreferenceObserverChurnOwner(
        generation: generation,
        onFirst: { firstTotal += $0 },
        onSecond: { secondTotal += $0 }
      )
      .id("preference-owner-\(generation)")
    }
    .frame(width: 66, height: 8, alignment: .topLeading)
  }
}

private struct PreferenceObserverChurnOwner: View {
  let generation: Int
  let onFirst: @MainActor (Int) -> Void
  let onSecond: @MainActor (Int) -> Void

  var body: some View {
    Text("Preference Source \(generation)")
      .preference(key: PreferenceObserverStressKey.self, value: generation)
      .onPreferenceChange(PreferenceObserverStressKey.self) { value in
        onFirst(value)
      }
      .onPreferenceChange(PreferenceObserverStressKey.self) { value in
        onSecond(value)
      }
      .onAppear {}
      .onDisappear {}
  }
}

private struct TerminationHandlerChurnStressFixture: View {
  @State private var generation = 0
  @State private var firstTotal = 0
  @State private var secondTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Termination Owner") { generation += 1 }
      Text("termination generation \(generation) first \(firstTotal) second \(secondTotal)")
      TerminationHandlerChurnOwner(
        generation: generation,
        onFirst: { firstTotal += generation + 1 },
        onSecond: { secondTotal += generation + 1 }
      )
      .id("termination-owner-\(generation)")
    }
    .frame(width: 72, height: 8, alignment: .topLeading)
  }
}

private struct TerminationHandlerChurnOwner: View {
  let generation: Int
  let onFirst: @MainActor () -> Void
  let onSecond: @MainActor () -> Void

  var body: some View {
    Text("Termination Owner \(generation)")
      .onTerminationRequest { _ in
        onFirst()
        return .allow
      }
      .onTerminationRequest { _ in
        onSecond()
        return .allow
      }
      .onAppear {}
      .onDisappear {}
  }
}

private struct LifecycleHandlerChurnStressFixture: View {
  @State private var generation = 0
  @State private var firstAppearTotal = 0
  @State private var secondAppearTotal = 0
  @State private var firstDisappearTotal = 0
  @State private var secondDisappearTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Lifecycle Owner") { generation += 1 }
      Text(
        """
        lifecycle generation \(generation) appear first \(firstAppearTotal) \
        second \(secondAppearTotal) disappear first \(firstDisappearTotal) \
        second \(secondDisappearTotal)
        """
      )
      LifecycleHandlerChurnOwner(
        generation: generation,
        onFirstAppear: { firstAppearTotal += $0 + 1 },
        onSecondAppear: { secondAppearTotal += $0 + 1 },
        onFirstDisappear: { firstDisappearTotal += $0 + 1 },
        onSecondDisappear: { secondDisappearTotal += $0 + 1 }
      )
      .id("lifecycle-owner-\(generation)")
    }
    .frame(width: 82, height: 8, alignment: .topLeading)
  }
}

private struct LifecycleHandlerChurnOwner: View {
  let generation: Int
  let onFirstAppear: @MainActor (Int) -> Void
  let onSecondAppear: @MainActor (Int) -> Void
  let onFirstDisappear: @MainActor (Int) -> Void
  let onSecondDisappear: @MainActor (Int) -> Void

  var body: some View {
    Text("Lifecycle Owner \(generation)")
      .onAppear { onFirstAppear(generation) }
      .onAppear { onSecondAppear(generation) }
      .onDisappear { onFirstDisappear(generation) }
      .onDisappear { onSecondDisappear(generation) }
  }
}

private struct ChangeHandlerChurnStressFixture: View {
  @State private var generation = 0
  @State private var value = 0
  @State private var firstTotal = 0
  @State private var secondTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Bump Change Value") { value += 1 }
      Button("Recreate Change Owner") { generation += 1 }
      Text(
        """
        change generation \(generation) value \(value) first \(firstTotal) \
        second \(secondTotal)
        """
      )
      ChangeHandlerChurnOwner(
        generation: generation,
        value: value,
        onFirst: { firstTotal += $0 },
        onSecond: { secondTotal += $0 }
      )
      .id("change-owner-\(generation)")
    }
    .frame(width: 86, height: 8, alignment: .topLeading)
  }
}

private struct ChangeHandlerChurnOwner: View {
  let generation: Int
  let value: Int
  let onFirst: @MainActor (Int) -> Void
  let onSecond: @MainActor (Int) -> Void

  var body: some View {
    Text("Change Owner \(generation) value \(value)")
      .onChange(of: value) { _, newValue in
        onFirst(newValue)
      }
      .onChange(of: value) { _, newValue in
        onSecond(newValue)
      }
  }
}

private struct ScrollFocusRevealPruningStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("scroll owner generation \(generation)")
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          Button("Replace Scroll Owner") { generation += 1 }
          Text("Scroll Replace \(generation)")
          ForEach(0..<18, id: \.self) { row in
            Text("scroll row \(generation).\(row)")
          }
        }
      }
      .id("scroll-owner-\(generation)")
      .frame(width: 54, height: 6, alignment: .topLeading)
    }
    .frame(width: 54, height: 8, alignment: .topLeading)
  }
}

private struct KeyPressHandlerChurnStressFixture: View {
  @State private var generation = 0
  @State private var kTotal = 0
  @State private var lTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Key Owner") { generation += 1 }
      Text("key owner generation \(generation)")
      Text("key totals k \(kTotal) l \(lTotal)")
      KeyPressHandlerChurnOwner(
        generation: generation,
        onK: { kTotal += generation + 1 },
        onL: { lTotal += generation + 1 }
      )
      .id("key-owner-\(generation)")
    }
    .frame(width: 62, height: 8, alignment: .topLeading)
  }
}

private struct KeyPressHandlerChurnOwner: View {
  let generation: Int
  let onK: @MainActor () -> Void
  let onL: @MainActor () -> Void

  var body: some View {
    Text("Key Target \(generation)")
      .focusable()
      .onKeyPress(.character("k")) { _ in
        onK()
        return .handled
      }
      .onKeyPress(.character("l")) { _ in
        onL()
        return .handled
      }
      .onAppear {}
      .onDisappear {}
  }
}

private struct TextInputPasteHandlerChurnStressFixture: View {
  static let fieldIdentity = testIdentity("TextInputPasteHandlerChurn", "field")

  @State private var generation = 0
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Text Input") {
        generation += 1
        text = ""
      }
      Text("text input generation \(generation) value \(text.isEmpty ? "empty" : text)")
      TextInputPasteHandlerChurnOwner(generation: generation, text: $text)
        .id(testIdentity("TextInputPasteHandlerChurn", "owner", "\(generation)"))
    }
    .frame(width: 70, height: 8, alignment: .topLeading)
  }
}

private struct TextInputPasteHandlerChurnOwner: View {
  let generation: Int
  @Binding var text: String

  var body: some View {
    TextField("Paste Target \(generation)", text: $text)
      .id(TextInputPasteHandlerChurnStressFixture.fieldIdentity)
      .textFieldStyle(.plain)
      .onAppear {}
      .onDisappear {}
  }
}

private enum FocusedValueDescendantChurnKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var focusedValueDescendantChurnValue: String? {
    get { self[FocusedValueDescendantChurnKey.self] }
    set { self[FocusedValueDescendantChurnKey.self] = newValue }
  }
}

private struct FocusedValueDescendantChurnStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Focused Descendant") { generation += 1 }
      Text("focused value generation \(generation)")
      FocusedValueDescendantChurnOwner(generation: generation)
        .id(testIdentity("FocusedValueDescendantChurn", "owner"))
        .focusedValue(
          \.focusedValueDescendantChurnValue,
          "focused value \(generation)"
        )
    }
    .frame(width: 70, height: 8, alignment: .topLeading)
  }
}

private struct FocusedValueDescendantChurnOwner: View {
  let generation: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Focused Value Owner")
      Text("Focused Descendant \(generation)")
        .id(testIdentity("FocusedValueDescendantChurn", "descendant", "\(generation)"))
        .focusable()
    }
  }
}

private enum FocusedBindingChurnKey: FocusedValueKey {
  typealias Value = Binding<Int>
}

extension FocusedValues {
  fileprivate var focusedBindingChurnValue: Binding<Int>? {
    get { self[FocusedBindingChurnKey.self] }
    set { self[FocusedBindingChurnKey.self] = newValue }
  }
}

private struct FocusedBindingChurnStressFixture: View {
  @State private var generation = 0
  @State private var first = 0
  @State private var second = 100
  @FocusedBinding(\.focusedBindingChurnValue) private var focusedNumber

  var body: some View {
    Panel(id: testIdentity("FocusedBindingChurn", "panel")) {
      VStack(alignment: .leading, spacing: 0) {
        Text(
          """
          focused binding generation \(generation) value \
          \(focusedNumber.map(String.init) ?? "none")
          """
        )
        Button("Rebuild Focused Binding Owner") { generation += 1 }
        FocusedBindingChurnOwner(
          generation: generation,
          first: $first,
          second: $second
        )
        .id(testIdentity("FocusedBindingChurn", "owner", "\(generation)"))
      }
    }
    .keyCommand("Increment focused binding", key: .character("i"), modifiers: .ctrl) {
      if let focusedNumber {
        self.focusedNumber = focusedNumber + generation + 1
      }
    }
    .frame(width: 82, height: 10, alignment: .topLeading)
  }
}

private struct FocusedBindingChurnOwner: View {
  let generation: Int
  @Binding var first: Int
  @Binding var second: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Focused Binding First \(generation) \(first)") {}
        .id(testIdentity("FocusedBindingChurn", "first", "\(generation)"))
        .focusedValue(\.focusedBindingChurnValue, $first)
      Button("Focused Binding Second \(generation) \(second)") {}
        .id(testIdentity("FocusedBindingChurn", "second", "\(generation)"))
        .focusedValue(\.focusedBindingChurnValue, $second)
    }
  }
}

private struct KeyCommandScopeChurnStressFixture: View {
  @State private var generation = 0
  @State private var outerTotal = 0
  @State private var innerTotal = 0

  var body: some View {
    Panel(id: testIdentity("KeyCommandScopeChurn", "outer")) {
      VStack(alignment: .leading, spacing: 0) {
        Text("command generation \(generation) outer \(outerTotal) inner \(innerTotal)")
        Button("Rebuild Command Scope") { generation += 1 }
        Panel(id: testIdentity("KeyCommandScopeChurn", "inner", "\(generation)")) {
          Text("Command Focus \(generation)")
            .focusable()
        }
        .keyCommand("Inner save", key: .character("s"), modifiers: .ctrl) {
          innerTotal += generation + 1
        }
      }
    }
    .keyCommand("Outer save", key: .character("s"), modifiers: .ctrl) {
      outerTotal += generation + 1
    }
    .frame(width: 72, height: 10, alignment: .topLeading)
  }
}

private struct DropDestinationScopeChurnStressFixture: View {
  @State private var generation = 0
  @State private var outerTotal = 0
  @State private var innerTotal = 0

  var body: some View {
    Panel(id: testIdentity("DropDestinationScopeChurn", "outer")) {
      VStack(alignment: .leading, spacing: 0) {
        Text("drop generation \(generation) outer \(outerTotal) inner \(innerTotal)")
        Button("Rebuild Drop Scope") { generation += 1 }
        Panel(id: testIdentity("DropDestinationScopeChurn", "inner", "\(generation)")) {
          Text("Drop Focus \(generation)")
            .focusable()
        }
        .dropDestination { paths in
          innerTotal += paths.count * (generation + 1)
          return true
        }
      }
    }
    .dropDestination { paths in
      outerTotal += paths.count * (generation + 1)
      return true
    }
    .frame(width: 72, height: 10, alignment: .topLeading)
  }
}

private struct MultipleTaskModifierStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle Multi Tasks") { generation += 1 }
      Text("multi-task generation \(generation)")
        .id("multi-task-\(generation % 7)")
        .task(id: MultipleTaskModifierStressID(slot: "first", generation: generation)) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
        .task(id: MultipleTaskModifierStressID(slot: "second", generation: generation)) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
    }
    .frame(width: 54, height: 8, alignment: .topLeading)
  }
}

private struct MultipleTaskModifierStressID: Equatable, Sendable {
  var slot: String
  var generation: Int
}

@MainActor
private final class StressRuntimeHarness<Content: View> {
  private let terminal: StressRecordingHost
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private var renderedFrames = 0
  private var didShutdown = false

  init(
    rootIdentity: Identity,
    size: CellSize,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let terminal = StressRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: StressEmptyKeyReader(),
      signalReader: StressEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in content() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String {
    terminal.frames.last ?? ""
  }

  var activeTaskCount: Int {
    runLoop.lifecycleCoordinator.activeTaskCount
  }

  var activeTaskDescriptorCount: Int {
    runLoop.lifecycleCoordinator.activeTaskDescriptors.values.reduce(0) {
      $0 + $1.count
    }
  }

  var lifecycleRegistrationCount: Int {
    let snapshot = runLoop.localLifecycleRegistry.snapshot()
    return snapshot.appearHandlers.count
      + snapshot.disappearHandlers.count
      + snapshot.changeHandlers.count
  }

  var actionRegistrationCount: Int {
    runLoop.localActionRegistry.snapshot().count
  }

  var keyHandlerCount: Int {
    runLoop.localKeyHandlerRegistry.snapshot().count
  }

  var pointerHandlerCount: Int {
    runLoop.localPointerHandlerRegistry.snapshot().count
  }

  var pointerHoverHandlerCount: Int {
    runLoop.localPointerHandlerRegistry.snapshotHover().count
  }

  var gestureRecognizerCount: Int {
    runLoop.localGestureRegistry.snapshot().count
  }

  var gestureStateBindingCount: Int {
    runLoop.localGestureStateRegistry.snapshot().values.reduce(0) { count, bindings in
      count + bindings.count
    }
  }

  var defaultFocusRegistrationCount: Int {
    let snapshot = runLoop.localDefaultFocusRegistry.snapshot()
    return snapshot.scopes.count + snapshot.candidates.count
  }

  var focusBindingRegistrationCount: Int {
    runLoop.localFocusBindingRegistry.snapshot().count
  }

  var focusRegionCount: Int {
    runLoop.focusTracker.focusRegions.count
  }

  var focusModalRestorationStackCount: Int {
    let mirror = Mirror(reflecting: runLoop.focusTracker)
    guard let child = mirror.children.first(where: { $0.label == "modalRestorationStack" })
    else {
      return -1
    }
    return Mirror(reflecting: child.value).children.count
  }

  var preferenceObservationRegistrationCount: Int {
    runLoop.localPreferenceObservationRegistry.snapshot().count
  }

  var terminationHandlerCount: Int {
    runLoop.localTerminationRegistry.snapshot().values.reduce(0) {
      count,
      handlers in
      count + handlers.count
    }
  }

  var keyPressHandlerCount: Int {
    runLoop.localKeyHandlerRegistry.snapshotKeyPressHandlers().values.reduce(0) {
      count,
      handlers in
      count + handlers.count
    }
  }

  var pasteHandlerCount: Int {
    runLoop.localKeyHandlerRegistry.snapshotPasteHandlers().values.reduce(0) {
      count,
      handlers in
      count + handlers.count
    }
  }

  var focusedValueRegistrationCount: Int {
    runLoop.localFocusedValuesRegistry.snapshot().count
  }

  var focusedValueDescendantIdentityCount: Int {
    runLoop.localFocusedValuesRegistry.snapshot().reduce(0) { count, registration in
      count + registration.descendantIdentities.count
    }
  }

  var keyCommandRegistrationCount: Int {
    runLoop.commandRegistry.snapshot().keyCommandsByScope.values.reduce(0) {
      count,
      commands in
      count + commands.count
    }
  }

  var dropDestinationRegistrationCount: Int {
    runLoop.dropDestinationRegistry.snapshot().handlersByScope.count
  }

  var scrollPositionRegistrationCount: Int {
    runLoop.localScrollPositionRegistry.snapshot().count
  }

  var scrollRevealAnchorCount: Int {
    let mirror = Mirror(reflecting: runLoop.localScrollPositionRegistry)
    guard let child = mirror.children.first(where: { $0.label == "lastRevealAnchors" })
    else {
      return -1
    }
    return Mirror(reflecting: child.value).children.count
  }

  func shutdown() {
    guard !didShutdown else {
      return
    }
    didShutdown = true
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  func point(forText text: String, chooseLast: Bool = false) -> Point? {
    terminal.centerOfText(text, chooseLast: chooseLast)
  }

  @discardableResult
  func clickText(_ label: String, chooseLast: Bool = false) throws -> String {
    let point = try #require(
      terminal.centerOfText(label, chooseLast: chooseLast),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    return try click(point)
  }

  @discardableResult
  func click(_ point: Point) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }

  @discardableResult
  func pressKey(_ keyPress: KeyPress) throws -> String {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    return try render()
  }

  @discardableResult
  func paste(_ content: String) throws -> String {
    runLoop.handlePaste(PasteEvent(content: content))
    return try render()
  }

  @discardableResult
  func focus(_ identity: Identity) throws -> String {
    #expect(runLoop.focusTracker.setFocus(to: identity))
    return try render()
  }

  @discardableResult
  func requestTermination(
    _ exitReason: RunLoopExitReason
  ) throws -> (disposition: TerminationDisposition, frame: String) {
    let disposition = runLoop.terminationDisposition(for: exitReason)
    return (disposition, try render())
  }

  @discardableResult
  func drop(paths: [DroppedPath], context: DropContext = .init()) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(.drop(paths: paths, context: context))
      ) == nil
    )
    return try render()
  }

  @discardableResult
  func drag(from start: Point, to end: Point) throws -> String {
    _ = try sendMouse(.down(.primary), at: start)
    _ = try sendMouse(.dragged(.primary), at: end)
    return try sendMouse(.up(.primary), at: end)
  }

  @discardableResult
  func movePointer(to point: Point) throws -> String {
    try sendMouse(.moved, at: point)
  }

  @discardableResult
  func scrollPointer(at point: Point, deltaY: Int) throws -> String {
    try sendMouse(.scrolled(deltaX: 0, deltaY: deltaY), at: point)
  }

  @discardableResult
  private func sendMouse(_ kind: MouseEvent.Kind, at point: Point) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: kind, location: point)))
      ) == nil
    )
    return try render()
  }
}

private final class StressRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(rendered.filter { $0 != "\r" }))
    lastPresentedSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(String(output.filter { $0 != "\r" }))
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }

    let rows = chooseLast ? Array(surface.lines.indices.reversed()) : Array(surface.lines.indices)
    for row in rows {
      let line = surface.lines[row]
      let options: String.CompareOptions = chooseLast ? .backwards : []
      guard let range = line.range(of: target, options: options) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class StressEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class StressEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
