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
      Text("actions \(model.actionLog.joined(separator: ","))")
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
