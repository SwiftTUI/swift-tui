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

    withKnownIssue("Read-only popover tips suppress base focus and interaction in the runtime") {
      #expect(readOnlyTipPreservedBaseInteraction)
    }
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
  var firstGeneration = 0
  var secondGeneration = 0
  var actionLog: [String] = []
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
            id: "shared-tip-id",
            titleText: "First duplicate tip \(generation)",
            messageText: nil,
            iconText: "1",
            actions: [.init(id: "first", title: "Acknowledge first")],
            isEligible: true
          ),
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
            id: "shared-tip-id",
            titleText: "Second duplicate tip \(generation)",
            messageText: nil,
            iconText: "2",
            actions: [.init(id: "second", title: "Acknowledge second")],
            isEligible: true
          ),
          arrowEdge: .trailing
        ) { action in
          model.actionLog.append("second:\(action.id)@\(generation)")
        }
    }
  }
}

private struct PopoverTipNestedPresentationStressRoot: View {
  @State private var presentsSheet = false
  @State private var presentsTip = true

  var body: some View {
    Button("Open nested tip sheet") {
      presentsSheet = true
    }
    .sheet("Nested tip sheet", isPresented: $presentsSheet) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Nested sheet body")
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
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .count
}
