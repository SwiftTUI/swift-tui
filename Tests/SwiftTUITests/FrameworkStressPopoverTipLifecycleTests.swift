import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressPopoverTipLifecycleTests {}

// MARK: - Attempt 001: stable tip title payload freshness

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 001 stable identity publishes its current title")
  func popoverTip001StableIdentityPublishesCurrentTitle() throws {
    // Hypothesis: a stable popover-tip portal entry can retain the first title
    // payload while its declaration keeps the same source and tip identities.
    let rootIdentity = testIdentity("PopoverTipStress001", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "stable-title"
    model.title = "Tip title 0"
    model.actions = []

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...12 {
      model.generation = generation
      model.title = "Tip title \(generation)"
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      #expect(frame.contains("Tip title \(generation)"))
      #expect(!frame.contains("Tip title \(generation - 1)"))
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 002: optional tip message topology freshness

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 002 optional message leaves no retained payload")
  func popoverTip002OptionalMessageLeavesNoRetainedPayload() throws {
    // Hypothesis: removing the optional message can leave the prior message
    // child retained in the detached portal content tree.
    let rootIdentity = testIdentity("PopoverTipStress002", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "optional-message"
    model.title = "Optional message tip"
    model.icon = nil
    model.actions = []

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...12 {
      model.generation = generation
      model.message = generation.isMultiple(of: 2) ? nil : "Message payload \(generation)"
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      if let message = model.message {
        #expect(frame.contains(message))
      } else {
        #expect(!frame.contains("Message payload \(generation - 1)"))
      }
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 003: optional tip icon topology freshness

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 003 optional icon follows every replacement")
  func popoverTip003OptionalIconFollowsEveryReplacement() throws {
    // Hypothesis: the tip header's optional icon branch can reuse a departed
    // Text payload or fail to rebuild after repeated nil transitions.
    let rootIdentity = testIdentity("PopoverTipStress003", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "optional-icon"
    model.title = "Optional icon tip"
    model.message = nil
    model.actions = []

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...12 {
      let priorIcon = model.icon
      model.generation = generation
      model.icon = generation.isMultiple(of: 3) ? nil : "I\(generation)"
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      if let icon = model.icon {
        #expect(frame.contains(icon))
      }
      if let priorIcon, priorIcon != model.icon {
        #expect(!frame.contains(priorIcon))
      }
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 004: tip action closure freshness

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 004 stable action dispatches its current closure")
  func popoverTip004StableActionDispatchesCurrentClosure() throws {
    // Hypothesis: a stable action ID can keep the closure captured by the
    // first detached tip payload after the source view re-resolves.
    let rootIdentity = testIdentity("PopoverTipStress004", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "action-freshness"
    model.title = "Action freshness tip"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "run", title: "Run current tip action")]

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.generation = generation
      model.primaryPresented = true
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let frame = try harness.clickText("Run current tip action", chooseLast: true)

      #expect(model.actionLog.last == "run@\(generation)")
      #expect(!model.primaryPresented)
      #expect(!frame.contains("Action freshness tip"))
      #expect(popoverTipStressEntryCount(in: harness) == 0)
    }
  }
}

// MARK: - Attempt 005: stable action title replacement

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 005 stable action id renders its current title")
  func popoverTip005StableActionIDRendersCurrentTitle() throws {
    // Hypothesis: ForEach may reuse the action button by ID while preserving
    // the prior label payload and its hit region.
    let rootIdentity = testIdentity("PopoverTipStress005", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "action-title"
    model.title = "Action title tip"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.generation = generation
      model.primaryPresented = true
      let title = "Current action title \(generation)"
      model.actions = [.init(id: "stable", title: title)]
      let refreshed = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      #expect(refreshed.contains(title))
      #expect(!refreshed.contains("Current action title \(generation - 1)"))
      _ = try harness.clickText(title, chooseLast: true)
      #expect(model.actionLog.last == "stable@\(generation)")
    }
  }
}

// MARK: - Attempt 006: action order churn

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 006 action routes follow current authored order")
  func popoverTip006ActionRoutesFollowCurrentAuthoredOrder() throws {
    // Hypothesis: retained portal children can preserve the original action
    // order even after the tip publishes the same IDs in a new order.
    let rootIdentity = testIdentity("PopoverTipStress006", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "action-order"
    model.title = "Action order tip"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    let authoredOrders = [
      ["Alpha", "Beta", "Gamma"],
      ["Gamma", "Alpha", "Beta"],
      ["Beta", "Gamma", "Alpha"],
    ]
    for generation in 1...9 {
      let order = authoredOrders[generation % authoredOrders.count]
      model.generation = generation
      model.primaryPresented = true
      model.actions = order.map { .init(id: $0, title: $0) }
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      let points = try order.map { try #require(harness.point(forText: $0)) }
      #expect(points[0].x < points[1].x)
      #expect(points[1].x < points[2].x)
      _ = try harness.clickText(order[0], chooseLast: true)
      #expect(model.actionLog.last == "\(order[0])@\(generation)")
    }
  }
}

// MARK: - Attempt 007: action removal route pruning

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 007 removed actions leave no live routes")
  func popoverTip007RemovedActionsLeaveNoLiveRoutes() throws {
    // Hypothesis: shrinking the action array can leave departed Button routes
    // registered in the detached portal subtree.
    let rootIdentity = testIdentity("PopoverTipStress007", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "action-removal"
    model.title = "Action removal tip"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...8 {
      model.generation = generation
      model.primaryPresented = true
      let removedA = "OldA\(generation)"
      let removedB = "OldB\(generation)"
      let survivor = "Keep\(generation)"
      model.actions = [
        .init(id: "old-a", title: removedA),
        .init(id: "keep", title: survivor),
        .init(id: "old-b", title: removedB),
      ]
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      model.actions = [.init(id: "keep", title: survivor)]
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(!frame.contains(removedA))
      #expect(!frame.contains(removedB))
      #expect(harness.point(forText: removedA) == nil)
      #expect(harness.point(forText: removedB) == nil)

      _ = try harness.clickText(survivor, chooseLast: true)
      #expect(model.actionLog.last == "keep@\(generation)")
      #expect(harness.actionRegistrationCount <= 2)
    }
  }
}

// MARK: - Attempt 008: action insertion changes modal policy

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 008 inserting an action gates the base immediately")
  func popoverTip008InsertingActionGatesBaseImmediately() throws {
    // Hypothesis: a tip that begins read-only can keep its nonmodal interaction
    // policy after an action is inserted into the same portal entry.
    let rootIdentity = testIdentity("PopoverTipStress008", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "action-insertion"
    model.title = "Action insertion tip"
    model.message = nil
    model.icon = nil
    model.actions = []
    model.hasTip = false

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    var readOnlyTipPreservedBaseInteraction = true
    for generation in 1...8 {
      model.primaryPresented = true
      model.hasTip = false
      model.actions = []
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let controlPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
      #expect(controlPaths.contains(popoverTipStressBaseIdentity.path))
      let controlCount = model.baseActionCount
      _ = try harness.clickText("Base action")
      #expect(model.baseActionCount == controlCount + 1)

      model.hasTip = true
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let nonmodalPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
      let nonmodalCount = model.baseActionCount
      _ = try harness.clickText("Base action")
      readOnlyTipPreservedBaseInteraction =
        readOnlyTipPreservedBaseInteraction
        && nonmodalPaths.contains(popoverTipStressBaseIdentity.path)
        && model.baseActionCount == nonmodalCount + 1

      model.generation = generation
      model.actions = [.init(id: "modal", title: "Inserted modal action")]
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let modalPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
      #expect(!modalPaths.contains(popoverTipStressBaseIdentity.path))

      _ = try harness.clickText("Inserted modal action", chooseLast: true)
      #expect(model.actionLog.last == "modal@\(generation)")
    }

    #expect(readOnlyTipPreservedBaseInteraction)
  }
}

// MARK: - Attempt 009: eligibility teardown

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 009 ineligible transition prunes the active entry")
  func popoverTip009IneligibleTransitionPrunesActiveEntry() throws {
    // Hypothesis: the early eligibility guard can skip publishing a new
    // declaration without retiring the prior active portal entry and routes.
    let rootIdentity = testIdentity("PopoverTipStress009", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "eligibility-teardown"
    model.title = "Eligibility teardown tip"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "eligible", title: "Eligible action")]

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for _ in 1...12 {
      model.isEligible = true
      var frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(frame.contains("Eligibility teardown tip"))
      #expect(popoverTipStressEntryCount(in: harness) == 1)

      model.isEligible = false
      frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(!frame.contains("Eligibility teardown tip"))
      #expect(!frame.contains("Eligible action"))
      #expect(popoverTipStressEntryCount(in: harness) == 0)
      #expect(harness.actionRegistrationCount <= 1)
    }
  }
}

// MARK: - Attempt 010: eligibility restoration payload freshness

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 010 restored eligibility uses the current payload")
  func popoverTip010RestoredEligibilityUsesCurrentPayload() throws {
    // Hypothesis: while an ineligible tip emits no declaration, its retained
    // trigger can miss payload changes and restore an older title or action.
    let rootIdentity = testIdentity("PopoverTipStress010", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "eligibility-restoration"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.primaryPresented = true
      model.isEligible = false
      model.generation = generation
      model.title = "Restored title \(generation)"
      model.actions = [.init(id: "restore", title: "Restore action \(generation)")]
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      model.isEligible = true
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(frame.contains("Restored title \(generation)"))
      #expect(frame.contains("Restore action \(generation)"))
      #expect(!frame.contains("Restored title \(generation - 1)"))

      _ = try harness.clickText("Restore action \(generation)", chooseLast: true)
      #expect(model.actionLog.last == "restore@\(generation)")
    }
  }
}

// MARK: - Attempt 011: explicit presentation binding retarget

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 011 Escape writes the current presentation binding")
  func popoverTip011EscapeWritesCurrentPresentationBinding() throws {
    // Hypothesis: an active tip can retain the dismiss closure for the binding
    // that first presented it after the stable modifier retargets.
    let rootIdentity = testIdentity("PopoverTipStress011", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "binding-retarget"
    model.title = "Binding retarget tip"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "dismiss", title: "Binding action")]
    model.primaryPresented = true
    model.secondaryPresented = true

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    model.usesSecondaryBinding = true
    _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(model.primaryPresented)
    #expect(!model.secondaryPresented)
    #expect(!frame.contains("Binding retarget tip"))
    #expect(popoverTipStressEntryCount(in: harness) == 0)
  }
}

// MARK: - Attempt 012: explicit binding reactivation lifetime

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 012 binding reactivation starts with current content")
  func popoverTip012BindingReactivationStartsWithCurrentContent() throws {
    // Hypothesis: repeatedly toggling the explicit binding can resurrect the
    // prior portal payload or its dismiss registration on reactivation.
    let rootIdentity = testIdentity("PopoverTipStress012", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "binding-reactivation"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.primaryPresented = false
      var frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(popoverTipStressEntryCount(in: harness) == 0)

      model.generation = generation
      model.title = "Reactivated tip \(generation)"
      model.actions = [.init(id: "reactivated", title: "Close reactivated \(generation)")]
      model.primaryPresented = true
      frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(frame.contains("Reactivated tip \(generation)"))
      #expect(!frame.contains("Reactivated tip \(generation - 1)"))
      #expect(popoverTipStressEntryCount(in: harness) == 1)

      frame = try harness.pressKey(KeyPress(.escape))
      #expect(!model.primaryPresented)
      #expect(!frame.contains("Reactivated tip \(generation)"))
    }
  }
}

// MARK: - Attempt 013: bindingless dismissal across nil gaps

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 013 bindingless dismissal survives nil round trips")
  func popoverTip013BindinglessDismissalSurvivesNilRoundTrips() throws {
    // Hypothesis: temporarily removing a bindingless tip can discard its
    // one-shot dismissed ID and allow the same tip to resurrect.
    let rootIdentity = testIdentity("PopoverTipStress013", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "bindingless-nil"
    model.title = "Bindingless nil tip"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "acknowledge", title: "Dismiss bindingless tip")]

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model,
      bindingless: true
    )
    defer { harness.shutdown() }

    _ = try harness.clickText("Dismiss bindingless tip", chooseLast: true)
    #expect(model.actionLog == ["acknowledge@0"])
    var dismissalStayedSuppressed = popoverTipStressEntryCount(in: harness) == 0

    for generation in 1...12 {
      model.hasTip = false
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      model.generation = generation
      model.title = "Bindingless nil tip \(generation)"
      model.hasTip = true
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      dismissalStayedSuppressed =
        dismissalStayedSuppressed
        && !frame.contains("Bindingless nil tip \(generation)")
        && popoverTipStressEntryCount(in: harness) == 0
    }

    #expect(dismissalStayedSuppressed)
  }
}

// MARK: - Attempt 014: bindingless tip ID replacement

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 014 replacing the tip id remints the portal entry")
  func popoverTip014ReplacingTipIDRemintsPortalEntry() throws {
    // Hypothesis: a bindingless modifier can preserve its prior portal token
    // and payload when the tip's Identifiable ID changes in place.
    let rootIdentity = testIdentity("PopoverTipStress014", "Root")
    let model = PopoverTipStressModel()
    model.message = nil
    model.icon = nil
    model.actions = []

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model,
      bindingless: true
    )
    defer { harness.shutdown() }

    for generation in 1...12 {
      let priorTitle = model.title
      model.generation = generation
      model.tipID = "replacement-\(generation)"
      model.title = "Replacement tip \(generation)"
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      #expect(frame.contains("Replacement tip \(generation)"))
      #expect(!frame.contains(priorTitle))
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 015: source identity replacement

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 015 source identity replacement keeps one current entry")
  func popoverTip015SourceIdentityReplacementKeepsOneCurrentEntry() throws {
    // Hypothesis: reminting the declaration source while the same tip remains
    // active can leave the departed source's portal entry or action route live.
    let rootIdentity = testIdentity("PopoverTipStress015", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "stable-across-source"
    model.message = nil
    model.icon = nil

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.generation = generation
      model.sourceIdentity = generation
      model.primaryPresented = true
      model.title = "Source generation \(generation)"
      model.actions = [.init(id: "source", title: "Use source \(generation)")]
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      #expect(frame.contains("Source generation \(generation)"))
      #expect(!frame.contains("Source generation \(generation - 1)"))
      #expect(popoverTipStressEntryCount(in: harness) == 1)
      _ = try harness.clickText("Use source \(generation)", chooseLast: true)
      #expect(model.actionLog.last == "source@\(generation)")
      #expect(popoverTipStressEntryCount(in: harness) == 0)
    }
  }
}

// MARK: - Attempt 016: duplicate tip ID source isolation

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 016 duplicate tip ids keep both sources")
  func popoverTip016DuplicateTipIDsKeepBothSources() throws {
    // Hypothesis: two sources publishing the same tip ID can collide in the
    // coordinator and share the wrong dismiss binding.
    let rootIdentity = testIdentity("PopoverTipStress016", "Root")
    let model = PopoverTipDuplicateStressModel()
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 88, height: 24)
    ) {
      PopoverTipDuplicateStressRoot(model: model)
    }
    defer { harness.shutdown() }

    // Each source owns an independently mounted popover entry even when the
    // authored tip IDs match. Dismissing one must not disturb the other.
    #expect(popoverTipStressEntryCount(in: harness) == 2)
    #expect(harness.frame.contains("First duplicate tip"))
    #expect(harness.frame.contains("Second duplicate tip"))

    _ = try harness.clickText("Acknowledge second", chooseLast: true)
    #expect(model.firstPresented)
    #expect(!model.secondPresented)
    #expect(popoverTipStressEntryCount(in: harness) == 1)
    #expect(harness.frame.contains("First duplicate tip"))

    _ = try harness.clickText("Acknowledge first", chooseLast: true)
    #expect(!model.firstPresented)
    #expect(!model.secondPresented)
    #expect(popoverTipStressEntryCount(in: harness) == 0)
  }
}

// MARK: - Attempt 017: duplicate-source traversal reorder

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 017 reordered sources preserve both current entries")
  func popoverTip017ReorderedSourcesPreserveBothCurrentEntries() throws {
    // Hypothesis: traversal reordering can remount, reorder, or stale either
    // independently active entry even though both source identities survive.
    let rootIdentity = testIdentity("PopoverTipStress017", "Root")
    let model = PopoverTipDuplicateStressModel()
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 88, height: 24)
    ) {
      PopoverTipDuplicateStressRoot(model: model)
    }
    defer { harness.shutdown() }
    let initialEntryIDs = popoverTipStressEntryIDs(in: harness)
    #expect(initialEntryIDs.count == 2)

    for generation in 1...12 {
      model.firstGeneration = generation
      model.secondGeneration = generation
      model.reverseSources.toggle()
      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)

      #expect(frame.contains("First duplicate tip \(generation)"))
      #expect(frame.contains("Second duplicate tip \(generation)"))
      #expect(popoverTipStressEntryIDs(in: harness) == initialEntryIDs)
      #expect(harness.actionRegistrationCount <= 2)
    }
  }
}

// MARK: - Attempt 018: attachment-point replacement

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 018 attachment point follows current source geometry")
  func popoverTip018AttachmentPointFollowsCurrentSourceGeometry() throws {
    // Hypothesis: a stable popover item can retain the first attachment anchor
    // even though the current source frame and preferred edge are unchanged.
    let rootIdentity = testIdentity("PopoverTipStress018", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "attachment-point"
    model.title = "Attachment point tip"
    model.message = nil
    model.icon = nil
    model.actions = []
    model.sourceOffset = 10
    model.sourceWidth = 40
    model.arrowEdge = .bottom

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for _ in 1...10 {
      model.attachmentAnchor = .point(.leading)
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let leading = try #require(harness.point(forText: "Attachment point tip"))

      model.attachmentAnchor = .point(.trailing)
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let trailing = try #require(harness.point(forText: "Attachment point tip"))

      #expect(trailing.x > leading.x)
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 019: preferred-edge replacement

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 019 preferred edge relocates the live tip")
  func popoverTip019PreferredEdgeRelocatesLiveTip() throws {
    // Hypothesis: placement can reuse the first PopoverPresentationItem's
    // arrow edge while every other item field remains stable.
    let rootIdentity = testIdentity("PopoverTipStress019", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "preferred-edge"
    model.title = "Preferred edge tip"
    model.message = nil
    model.icon = nil
    model.actions = []
    model.sourceOffset = 38
    model.sourceWidth = 10

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for _ in 1...10 {
      model.arrowEdge = .leading
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let source = try #require(harness.point(forText: "Tip anchor"))
      let leading = try #require(harness.point(forText: "Preferred edge tip"))
      #expect(leading.x < source.x)

      model.arrowEdge = .trailing
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let trailing = try #require(harness.point(forText: "Preferred edge tip"))
      #expect(trailing.x > source.x)
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 020: live source-frame relocation

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 020 tip follows its relocated source frame")
  func popoverTip020TipFollowsRelocatedSourceFrame() throws {
    // Hypothesis: HostedPopoverPresentation can consult a retained placed-frame
    // table and leave the tip attached to a source's former location.
    let rootIdentity = testIdentity("PopoverTipStress020", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "source-relocation"
    model.title = "Relocated source tip"
    model.message = nil
    model.icon = nil
    model.actions = []
    model.sourceWidth = 12
    model.arrowEdge = .bottom
    model.attachmentAnchor = .point(.center)

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for _ in 1...10 {
      model.sourceOffset = 2
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let leftTip = try #require(harness.point(forText: "Relocated source tip"))

      model.sourceOffset = 54
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let rightTip = try #require(harness.point(forText: "Relocated source tip"))

      #expect(rightTip.x > leftTip.x + 30)
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }
  }
}

// MARK: - Attempt 021: modal-to-read-only focus restoration

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 021 removing the last action restores base focus")
  func popoverTip021RemovingLastActionRestoresBaseFocus() throws {
    // Hypothesis: when an action-bearing tip becomes read-only, the portal can
    // retain its old focus gate instead of adopting the current nonmodal policy.
    let rootIdentity = testIdentity("PopoverTipStress021", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "focus-restoration"
    model.title = "Focus restoration tip"
    model.message = nil
    model.icon = nil
    model.hasTip = false

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    let controlPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
    #expect(controlPaths.contains(popoverTipStressBaseIdentity.path))

    var removalRestoredBaseFocus = true
    for _ in 1...12 {
      model.hasTip = true
      model.actions = [.init(id: "modal", title: "Modal focus action")]
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let modalPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
      #expect(!modalPaths.contains(popoverTipStressBaseIdentity.path))

      model.actions = []
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let readOnlyPaths = harness.runLoop.focusTracker.focusRegions.map(\.identity.path)
      removalRestoredBaseFocus =
        removalRestoredBaseFocus
        && readOnlyPaths.contains(popoverTipStressBaseIdentity.path)
      #expect(popoverTipStressEntryCount(in: harness) == 1)
    }

    #expect(removalRestoredBaseFocus)
  }
}

// MARK: - Attempt 022: disabled environment propagation

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 022 disabled source disables the detached action")
  func popoverTip022DisabledSourceDisablesDetachedAction() throws {
    // Hypothesis: portal attachment payloads can lose the source environment,
    // leaving tip actions enabled while their declaration subtree is disabled.
    let rootIdentity = testIdentity("PopoverTipStress022", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "disabled-environment"
    model.title = "Disabled environment tip"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "environment", title: "Environment action")]

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    var disabledActionsStayedInert = true
    for generation in 1...8 {
      model.generation = generation
      model.primaryPresented = true
      model.sourceDisabled = false
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      _ = try harness.clickText("Environment action", chooseLast: true)
      #expect(model.actionLog.last == "environment@\(generation)")
      #expect(!model.primaryPresented)

      let actionCount = model.actionLog.count
      model.primaryPresented = true
      model.sourceDisabled = true
      _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      _ = try harness.clickText("Environment action", chooseLast: true)
      disabledActionsStayedInert =
        disabledActionsStayedInert
        && model.actionLog.count == actionCount
        && model.primaryPresented
    }

    #expect(disabledActionsStayedInert)
  }
}

// MARK: - Attempt 023: active source teardown and reinsertion

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 023 source teardown prunes entry and routes")
  func popoverTip023SourceTeardownPrunesEntryAndRoutes() throws {
    // Hypothesis: removing an active declaration source can leave its portal
    // item or Button route alive until another presentation replaces it.
    let rootIdentity = testIdentity("PopoverTipStress023", "Root")
    let model = PopoverTipStressModel()
    model.tipID = "source-teardown"
    model.title = "Source teardown tip 0"
    model.message = nil
    model.icon = nil
    model.actions = [.init(id: "teardown", title: "Current teardown action")]

    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...10 {
      model.sourceVisible = false
      var frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(!frame.contains("Source teardown tip"))
      #expect(!frame.contains("Current teardown action"))
      #expect(popoverTipStressEntryCount(in: harness) == 0)
      #expect(harness.actionRegistrationCount <= 1)

      model.generation = generation
      model.sourceIdentity = generation
      model.primaryPresented = true
      model.title = "Source teardown tip \(generation)"
      model.sourceVisible = true
      frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      #expect(frame.contains("Source teardown tip \(generation)"))
      #expect(popoverTipStressEntryCount(in: harness) == 1)

      _ = try harness.clickText("Current teardown action", chooseLast: true)
      #expect(model.actionLog.last == "teardown@\(generation)")
    }
  }
}

// MARK: - Attempt 024: nested sheet presentation ordering

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 024 nested sheet publishes its tip above the sheet")
  func popoverTip024NestedSheetPublishesTipAboveSheet() throws {
    // Hypothesis: a tip declared inside a sheet can register below its owning
    // sheet or lose its dismiss route when both coordinators are active.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PopoverTipStress024", "Root"),
      size: .init(width: 72, height: 20)
    ) {
      PopoverTipNestedPresentationStressRoot()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Open nested tip sheet")
    #expect(frame.contains("Nested sheet body"))
    #expect(popoverTipStressEntryCount(in: harness) == 1)

    frame = try harness.clickText("Open nested tip", chooseLast: true)
    #expect(frame.contains("nested tip presented true"))
    #expect(frame.contains("Nested presentation tip"))
    #expect(popoverTipStressEntryCount(in: harness) == 2)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Nested sheet body"))
    #expect(!frame.contains("Nested presentation tip"))
    #expect(popoverTipStressEntryCount(in: harness) == 1)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Open nested tip sheet"))
    #expect(!frame.contains("Nested sheet body"))
    #expect(popoverTipStressEntryCount(in: harness) == 0)
  }
}

// MARK: - Attempt 025: mixed registration and teardown bounds

extension FrameworkStressPopoverTipLifecycleTests {
  @Test("stress popover tip 025 mixed churn keeps registrations bounded")
  func popoverTip025MixedChurnKeepsRegistrationsBounded() throws {
    // Hypothesis: combining source remints, eligibility, presentation binding,
    // tip IDs, and action cardinality can leak portal or input registrations.
    let baselineViolations = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let rootIdentity = testIdentity("PopoverTipStress025", "Root")
    let model = PopoverTipStressModel()
    model.message = nil
    model.icon = nil
    let harness = try makePopoverTipStressHarness(
      rootIdentity: rootIdentity,
      model: model
    )
    defer { harness.shutdown() }

    for generation in 1...50 {
      model.generation = generation
      model.sourceVisible = !generation.isMultiple(of: 5)
      model.hasTip = !generation.isMultiple(of: 7)
      model.isEligible = !generation.isMultiple(of: 4)
      model.primaryPresented = !generation.isMultiple(of: 3)
      model.sourceIdentity = generation % 6
      model.tipID = "mixed-tip-\(generation % 4)"
      model.title = "Mixed tip generation \(generation)"
      switch generation % 3 {
      case 0:
        model.actions = []
      case 1:
        model.actions = [.init(id: "one", title: "Mixed one")]
      default:
        model.actions = [
          .init(id: "one", title: "Mixed one"),
          .init(id: "two", title: "Mixed two"),
          .init(id: "three", title: "Mixed three"),
        ]
      }

      let frame = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
      let expectsEntry =
        model.sourceVisible && model.hasTip && model.isEligible && model.primaryPresented
      #expect(popoverTipStressEntryCount(in: harness) == (expectsEntry ? 1 : 0))
      #expect(frame.contains(model.title) == expectsEntry)
      #expect(harness.actionRegistrationCount <= 4)
      #expect(harness.focusRegionCount <= 3)
    }

    model.sourceVisible = false
    model.hasTip = false
    model.primaryPresented = false
    _ = try refreshPopoverTipStressHarness(harness, rootIdentity: rootIdentity)
    #expect(popoverTipStressEntryCount(in: harness) == 0)
    #expect(harness.actionRegistrationCount <= 1)
    #expect(harness.focusRegionCount <= 1)
    #expect(
      SoundnessProbeConfiguration.teardownCoherenceViolationCount == baselineViolations,
      "\(SoundnessProbeConfiguration.lastViolationDetail ?? "no violation detail")"
    )
  }
}

@MainActor
private final class PopoverTipStressModel {
  var generation = 0
  var tipID = "stress-tip"
  var title = "Stress tip"
  var message: String? = "Stress message"
  var icon: String? = "!"
  var actions: [PopoverTipAction] = []
  var isEligible = true
  var hasTip = true
  var primaryPresented = true
  var secondaryPresented = true
  var usesSecondaryBinding = false
  var sourceVisible = true
  var sourceIdentity = 0
  var sourceOffset = 1
  var sourceWidth = 18
  var sourceDisabled = false
  var attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds)
  var arrowEdge: Edge? = .trailing
  var baseActionCount = 0
  var actionLog: [String] = []

  func activeBinding() -> Binding<Bool> {
    if usesSecondaryBinding {
      return Binding(
        get: { self.secondaryPresented },
        set: { self.secondaryPresented = $0 }
      )
    }
    return Binding(
      get: { self.primaryPresented },
      set: { self.primaryPresented = $0 }
    )
  }
}

private struct PopoverTipStressTip: PopoverTip {
  var id: String
  var titleText: String
  var messageText: String?
  var iconText: String?
  var actions: [PopoverTipAction]
  var isEligible: Bool

  @MainActor
  var title: Text {
    Text(titleText)
  }

  @MainActor
  var message: Text? {
    messageText.map { Text($0) }
  }

  @MainActor
  var icon: Text? {
    iconText.map { Text($0) }
  }
}

private struct PopoverTipStressRoot: View {
  let model: PopoverTipStressModel
  let bindingless: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Base action") {
        model.baseActionCount += 1
      }
      .id(popoverTipStressBaseIdentity)

      if model.sourceVisible {
        source
      } else {
        Text("Tip source absent")
      }

      Text("base count \(model.baseActionCount)")
      Text("action count \(model.actionLog.count)")
    }
    .frame(width: 88, height: 22, alignment: .topLeading)
  }

  private var source: some View {
    let generation = model.generation
    let tip =
      model.hasTip
      ? PopoverTipStressTip(
        id: model.tipID,
        titleText: model.title,
        messageText: model.message,
        iconText: model.icon,
        actions: model.actions,
        isEligible: model.isEligible
      )
      : nil
    let isPresented: Binding<Bool>? = bindingless ? nil : model.activeBinding()

    return HStack(alignment: .top, spacing: 0) {
      Spacer().frame(width: model.sourceOffset)
      Text("Tip anchor")
        .frame(width: model.sourceWidth, height: 1, alignment: .leading)
        .id(model.sourceIdentity)
        .popoverTip(
          tip,
          isPresented: isPresented,
          attachmentAnchor: model.attachmentAnchor,
          arrowEdge: model.arrowEdge
        ) { action in
          model.actionLog.append("\(action.id)@\(generation)")
        }
    }
    .disabled(model.sourceDisabled)
  }
}

@MainActor
private final class PopoverTipDuplicateStressModel {
  var reverseSources = false
  var firstVisible = true
  var secondVisible = true
  var firstTipID = "shared-tip-id"
  var secondTipID = "shared-tip-id"
  var firstPresented = true
  var secondPresented = true
  var firstGeneration = 0
  var secondGeneration = 0
  var actionLog: [String] = []

  func firstBinding() -> Binding<Bool> {
    Binding(get: { self.firstPresented }, set: { self.firstPresented = $0 })
  }

  func secondBinding() -> Binding<Bool> {
    Binding(get: { self.secondPresented }, set: { self.secondPresented = $0 })
  }
}

private struct PopoverTipDuplicateStressRoot: View {
  let model: PopoverTipDuplicateStressModel

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if model.reverseSources {
        secondSource
        firstSource
      } else {
        firstSource
        secondSource
      }
      Text("duplicate actions \(model.actionLog.joined(separator: ","))")
    }
    .frame(width: 88, height: 24, alignment: .topLeading)
  }

  @ViewBuilder
  private var firstSource: some View {
    if model.firstVisible {
      let generation = model.firstGeneration
      Text("First duplicate anchor")
        .id("first-duplicate-source")
        .popoverTip(
          PopoverTipStressTip(
            id: model.firstTipID,
            titleText: "First duplicate tip \(generation)",
            messageText: nil,
            iconText: "1",
            actions: [.init(id: "first", title: "Acknowledge first")],
            isEligible: true
          ),
          isPresented: model.firstBinding(),
          arrowEdge: .trailing
        ) { action in
          model.actionLog.append("first:\(action.id)@\(generation)")
        }
    }
  }

  @ViewBuilder
  private var secondSource: some View {
    if model.secondVisible {
      let generation = model.secondGeneration
      Text("Second duplicate anchor")
        .id("second-duplicate-source")
        .popoverTip(
          PopoverTipStressTip(
            id: model.secondTipID,
            titleText: "Second duplicate tip \(generation)",
            messageText: nil,
            iconText: "2",
            actions: [.init(id: "second", title: "Acknowledge second")],
            isEligible: true
          ),
          isPresented: model.secondBinding(),
          arrowEdge: .trailing
        ) { action in
          model.actionLog.append("second:\(action.id)@\(generation)")
        }
    }
  }
}

private struct PopoverTipNestedPresentationStressRoot: View {
  @State private var presentsSheet = false
  @State private var presentsTip = false

  var body: some View {
    Button("Open nested tip sheet") {
      presentsSheet = true
    }
    .sheet("Nested tip sheet", isPresented: $presentsSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Nested sheet body")
        Text("nested tip presented \(presentsTip)")
        Button("Open nested tip") {
          presentsTip = true
        }
        Text("Nested tip anchor")
          .popoverTip(
            PopoverTipStressTip(
              id: "nested-tip",
              titleText: "Nested presentation tip",
              messageText: "Tip above sheet",
              iconText: nil,
              actions: [.init(id: "nested", title: "Nested tip action")],
              isEligible: true
            ),
            isPresented: $presentsTip,
            arrowEdge: .trailing
          )
      }
    }
  }
}

private let popoverTipStressBaseIdentity = testIdentity("PopoverTipStress", "Base")

@MainActor
private func makePopoverTipStressHarness(
  rootIdentity: Identity,
  model: PopoverTipStressModel,
  bindingless: Bool = false
) throws -> StressRuntimeHarness<PopoverTipStressRoot> {
  try StressRuntimeHarness(
    rootIdentity: rootIdentity,
    size: .init(width: 88, height: 22)
  ) {
    PopoverTipStressRoot(model: model, bindingless: bindingless)
  }
}

@MainActor
@discardableResult
private func refreshPopoverTipStressHarness<Content: View>(
  _ harness: StressRuntimeHarness<Content>,
  rootIdentity: Identity
) throws -> String {
  harness.runLoop.scheduler.requestInvalidation(of: [rootIdentity])
  return try harness.render()
}

@MainActor
private func popoverTipStressEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  popoverTipStressEntryIDs(in: harness).count
}

@MainActor
private func popoverTipStressEntryIDs<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> [String] {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .map(\.id)
}
