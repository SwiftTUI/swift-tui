@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAPresentationCompositionTests {
  @Test func setA601SameItemActivationRefreshesItsActionPayload() throws {
    // Hypothesis: an item presentation refreshes its label but retains an action capturing the old value.
    let model = SetAPresentationModel()
    model.item = .init(id: 1, title: "original")
    let h = try make("601") {
      Text("Presenter").sheet(item: model.itemBinding) { item in
        Button("Record \(item.title)") { model.events.append(item.title) }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Record original")
    try #require(model.events == ["original"])
    model.item = .init(id: 1, title: "updated")
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Record updated"), "\(h.frame)")
    try h.clickText("Record updated")
    #expect(model.events == ["original", "updated"])
  }

  @Test func setA602DismissalUsesTheCurrentObserverCapture() throws {
    // Hypothesis: a continuously mounted activation freezes its teardown observer at first presentation.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("602") {
      let revision = model.revision
      Text("Presenter").sheet(
        isPresented: model.firstBinding,
        onDismiss: { model.events.append("observer:\(revision)") }
      ) { Text("Observer revision \(revision)") }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Observer revision 0"))
    model.revision = 7
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Observer revision 7"))
    try h.pressKey(.init(.escape))
    #expect(!model.first)
    #expect(model.events == ["observer:7"])
  }

  @Test func setA603RejectedDismissalCannotTeardownTheMountedSheet() throws {
    // Hypothesis: Escape imperatively removes an overlay even when its source binding rejects false.
    let model = SetAPresentationModel()
    let h = try make("603") {
      Text("Presenter").sheet(
        isPresented: Binding(get: { true }, set: { model.events.append("write:\($0)") }),
        onDismiss: { model.events.append("dismissed") }
      ) { Button("Still mounted") { model.events.append("action") } }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Still mounted"))
    try h.pressKey(.init(.escape))
    #expect(model.events == ["write:false"])
    #expect(h.frame.contains("Still mounted"), "\(h.frame)")
    try h.clickText("Still mounted")
    #expect(model.events == ["write:false", "action"])
  }

  @Test func setA604DismissObserverCanPresentTheNextSheet() throws {
    // Hypothesis: state writes from committed teardown are discarded by the completing portal frame.
    let model = SetAPresentationModel()
    let h = try make("604") { SetAChainedDismissFixture(model: model) }
    defer { h.shutdown() }
    try #require(h.frame.contains("First activation"))
    try h.pressKey(.init(.escape))
    #expect(model.events == ["first dismissed"])
    #expect(h.frame.contains("Second activation"), "\(h.frame)")
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Second activation"))
    #expect(model.events == ["first dismissed", "second dismissed"])
  }

  @Test func setA605CanceledQueuedPromptNeverAcquiresAMountedLifetime() throws {
    // Hypothesis: a queued alert fires onDismiss despite never entering the committed visible tree.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("605") {
      Text("Presenter")
        .alert("Queue head", isPresented: model.firstBinding)
        .alert(
          "Canceled waiter", isPresented: model.secondBinding,
          onDismiss: { model.events.append("waiter dismissed") })
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Queue head"))
    model.second = true
    try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("Canceled waiter") && model.second)
    model.second = false
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.escape))
    #expect(!model.first && !model.second)
    #expect(model.events.isEmpty)
    #expect(!h.frame.contains("Canceled waiter"))
  }

  @Test func setA606QueuedItemPromptMountsTheLatestBoundPayload() throws {
    // Hypothesis: the FIFO queue stores the initial item payload instead of the current same-ID value.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("606") {
      Text("Presenter")
        .alert("Queue head", isPresented: model.firstBinding)
        .alert(
          "Queued item", item: model.itemBinding,
          actions: { item in Button("Use \(item.title)") { model.events.append(item.title) } },
          message: { item in Text("Payload \(item.title)") })
    }
    defer { h.shutdown() }
    model.item = .init(id: 9, title: "old")
    try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("Payload old"))
    model.item = .init(id: 9, title: "latest")
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.escape))
    try #require(h.frame.contains("Payload latest"), "\(h.frame)")
    try h.clickText("Use latest")
    #expect(model.events == ["latest"])
  }

  @Test func setA607AnInvisibleQueuedAlertCannotStealTheTopSheetEscape() throws {
    // Hypothesis: cross-family dismissal recency considers a newer queued alert that is not visible.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("607") {
      Text("Presenter")
        .alert("Old visible alert", isPresented: model.firstBinding)
        .alert("New queued alert", isPresented: model.secondBinding)
        .sheet(isPresented: model.thirdBinding) { Text("Later visible sheet") }
    }
    defer { h.shutdown() }
    model.third = true
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Later visible sheet"))
    model.second = true
    try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("New queued alert"))
    try h.pressKey(.init(.escape))
    #expect(!model.third && model.first && model.second)
    #expect(!h.frame.contains("Later visible sheet"))
    try h.pressKey(.init(.escape))
    #expect(!model.first && model.second)
    #expect(h.frame.contains("New queued alert"), "\(h.frame)")
  }

  @Test func setA608ReopenedPopoverReceivesANewCrossFamilyActivationOrder() throws {
    // Hypothesis: reactivating the same source reuses its old ordinal beneath a still-mounted sheet.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("608") {
      Text("Anchor")
        .popover(isPresented: model.firstBinding) { Text("Reopened popover") }
        .sheet(isPresented: model.secondBinding) { Text("Persistent sheet") }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Reopened popover"))
    model.first = false
    model.second = true
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Persistent sheet"))
    model.first = true
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Reopened popover"))
    try h.pressKey(.init(.escape))
    #expect(!model.first && model.second)
    #expect(h.frame.contains("Persistent sheet"))
  }

  @Test func setA609FullScreenCoverEscapesThePresentersSmallProposal() throws {
    // Hypothesis: a cover declared on a small control inherits that control's bounds instead of the viewport.
    let h = try make("609", width: 67, height: 19) {
      Text("Tiny").frame(width: 4, height: 1)
        .fullScreenCover(isPresented: .constant(true)) {
          GeometryReader { proxy in
            Text("Cover size \(Int(proxy.size.width))x\(Int(proxy.size.height))")
          }
        }
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("Cover size 67x19"), "\(h.frame)")
    #expect(!h.frame.contains("×"))
  }

  @Test func setA610BackgroundSemanticActivationIsGatedByTheVisibleModal() throws {
    // Hypothesis: host accessibility activation bypasses the modal barrier that filters pointer focus.
    let model = SetAPresentationModel()
    let h = try make("610") {
      Button("Background command") { model.events.append("background") }
        .sheet(isPresented: model.firstBinding) {
          Button("Foreground command") { model.events.append("foreground") }
        }
    }
    defer { h.shutdown() }
    try send(.activate, to: "Background command", role: .button, in: h)
    try #require(model.events == ["background"])
    let background = try #require(try node("Background command", role: .button, in: h).actionTarget)
    model.first = true
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Foreground command"))
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: background, action: .activate)) != .accepted
    )
    #expect(model.events == ["background"])
    try send(.activate, to: "Foreground command", role: .button, in: h)
    #expect(model.events == ["background", "foreground"])
  }

  @Test func setA611LivePopoverAnchorMovementUpdatesOverlayPlacement() throws {
    // Hypothesis: an already active popover retains the anchor's activation-time placed geometry.
    let model = SetAPresentationModel()
    let h = try make("611", width: 90, height: 18) {
      HStack(spacing: 0) {
        Spacer().frame(width: 2 + model.revision)
        Text("Moving anchor").popover(isPresented: .constant(true), arrowEdge: .trailing) {
          Text("Anchored payload")
        }
      }
    }
    defer { h.shutdown() }
    let initialAnchor = try #require(h.point(forText: "Moving anchor"))
    let initialPayload = try #require(h.point(forText: "Anchored payload"))
    try #require(initialPayload.x > initialAnchor.x)
    model.revision = 11
    try h.renderAfterExternalMutation()
    let movedAnchor = try #require(h.point(forText: "Moving anchor"))
    let movedPayload = try #require(h.point(forText: "Anchored payload"))
    try #require(movedAnchor.x - initialAnchor.x == 11)
    #expect(movedPayload.x - initialPayload.x == 11)
    #expect(movedPayload.y == initialPayload.y)
  }

  @Test func setA612SiblingItemPresentersDoNotShareAnEqualModelID() throws {
    // Hypothesis: presentation item IDs are global rather than scoped to their independent source bindings.
    let model = SetAPresentationModel()
    model.item = .init(id: 1, title: "first")
    let h = try make("612") {
      HStack {
        Text("Source one").sheet(item: model.itemBinding) { Text("First source \($0.title)") }
        Text("Source two").sheet(item: model.otherItemBinding) { Text("Second source \($0.title)") }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("First source first"))
    model.otherItem = .init(id: 1, title: "second")
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Second source second"))
    try h.pressKey(.init(.escape))
    #expect(model.item?.title == "first" && model.otherItem == nil)
    #expect(h.frame.contains("First source first"), "\(h.frame)")
  }

  @Test func setA613SemanticBackRetiresItsActionWhenThePathBecomesEmpty() throws {
    // Hypothesis: the navigation region keeps a Back route after the last destination is removed.
    let model = SetAPresentationModel()
    model.path = [3]
    let h = try make("613") {
      NavigationStack(path: model.pathBinding) {
        Text("Path root").navigationTitle("Root region")
          .navigationDestination(for: Int.self) { value in
            Text("Path value \(value)").navigationTitle("Destination region")
          }
      }
    }
    defer { h.shutdown() }
    let pushed = try node("Destination region", role: .region, in: h)
    try #require(pushed.control?.customActions.contains("Back") == true)
    try send(.custom("Back"), to: "Destination region", role: .region, in: h)
    #expect(model.path.isEmpty)
    #expect(h.frame.contains("Path root"))
    let root = try node("Root region", role: .region, in: h)
    #expect(root.control?.customActions.contains("Back") != true)
  }

  @Test func setA614NestedNavigationEscapePopsOnlyTheInnermostStack() throws {
    // Hypothesis: the outer navigation scope consumes Escape before its focused nested stack.
    let model = SetAPresentationModel()
    model.path = [1]
    model.childPath = [2]
    let h = try make("614") {
      NavigationStack(path: model.pathBinding) {
        Text("Outer root").navigationDestination(for: Int.self) { _ in
          NavigationStack(path: model.childPathBinding) {
            Button("Inner root") {}
              .navigationDestination(for: Int.self) { value in Button("Inner value \(value)") {} }
          }
        }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Inner value 2")
    try h.pressKey(.init(.escape))
    #expect(model.childPath.isEmpty && model.path == [1])
    try #require(h.frame.contains("Inner root"), "\(h.frame)")
    try h.focusText("Inner root")
    try h.pressKey(.init(.escape))
    #expect(model.path.isEmpty)
    #expect(h.frame.contains("Outer root"))
  }

  @Test func setA615RejectedPathPopLeavesTheCanonicalDestinationVisible() throws {
    // Hypothesis: path dismissal mutates internal activation before checking the binding's retained value.
    let model = SetAPresentationModel()
    let h = try make("615") {
      NavigationStack(path: Binding(get: { [8] }, set: { model.events.append("pop:\($0.count)") }))
      {
        Text("Rejected root").navigationDestination(for: Int.self) { value in
          Button("Retained destination \(value)") { model.events.append("destination") }
        }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Retained destination 8")
    try h.pressKey(.init(.escape))
    #expect(model.events == ["pop:0"])
    #expect(h.frame.contains("Retained destination 8"), "\(h.frame)")
    try h.clickText("Retained destination 8")
    #expect(model.events == ["pop:0", "destination"])
  }

  @Test func setA616SiblingStacksScopeBuildersForTheSameValueType() throws {
    // Hypothesis: consuming a value destination declaration leaks its builder into a sibling stack.
    let model = SetAPresentationModel()
    model.path = [1]
    model.childPath = [1]
    let h = try make("616") {
      HStack {
        NavigationStack(path: model.pathBinding) {
          Text("Left root").navigationDestination(for: Int.self) { value in
            Button("Left destination \(value)") { model.events.append("left") }
          }
        }
        NavigationStack(path: model.childPathBinding) {
          Text("Right root").navigationDestination(for: Int.self) { value in
            Button("Right destination \(value)") { model.events.append("right") }
          }
        }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Left destination 1")
    try h.clickText("Right destination 1")
    #expect(model.events == ["left", "right"])
    try h.focusText("Right destination 1")
    try h.pressKey(.init(.escape))
    #expect(model.path == [1] && model.childPath.isEmpty)
    #expect(h.frame.contains("Left destination 1") && h.frame.contains("Right root"))
  }

  @Test func setA617DormantTabRestoresNavigationActivationAndItsPopOwner() throws {
    // Hypothesis: archiving a tab preserves visible path data but loses the restored stack's pop handler.
    let h = try make("617") { SetATabNavigationFixture() }
    defer { h.shutdown() }
    try h.clickText("Push tab detail")
    try #require(h.frame.contains("Tab detail 4"))
    try h.clickText("Other screen")
    try #require(h.frame.contains("Other payload"))
    try h.clickText("Navigation screen")
    try #require(h.frame.contains("Tab detail 4"), "\(h.frame)")
    try h.focusText("Tab detail 4")
    try h.pressKey(.init(.escape))
    #expect(h.frame.contains("Push tab detail"), "\(h.frame)")
  }

  @Test func setA618UnmatchedTabSelectionFallsBackWithoutWritingTheBinding() throws {
    // Hypothesis: resolving the first visual fallback silently replaces an unmatched application selection.
    let model = SetAPresentationModel()
    model.selection = 99
    let h = try make("618") {
      TabView(
        selection: Binding(
          get: { model.selection },
          set: {
            model.events.append("write:\($0)")
            model.selection = $0
          })
      ) {
        Tab("First tab", value: 1) { Text("Fallback payload") }
        Tab("Second tab", value: 2) { Text("Second payload") }
      }
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("Fallback payload"))
    #expect(model.selection == 99 && model.events.isEmpty)
    try h.clickText("Second tab")
    #expect(model.selection == 2 && model.events == ["write:2"])
    #expect(h.frame.contains("Second payload"))
  }

  @Test func setA619RejectedTabSelectionCannotMountTheRequestedBody() throws {
    // Hypothesis: pointer highlight becomes effective selection despite the application rejecting its write.
    let model = SetAPresentationModel()
    let h = try make("619") {
      TabView(selection: Binding(get: { 1 }, set: { model.events.append("requested:\($0)") })) {
        Tab("Accepted tab", value: 1) { Text("Canonical payload") }
        Tab("Rejected tab", value: 2) { Text("Forbidden payload") }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Canonical payload"))
    try h.clickText("Rejected tab")
    #expect(model.events == ["requested:2"])
    #expect(h.frame.contains("Canonical payload") && !h.frame.contains("Forbidden payload"))
  }

  @Test func setA620ReorderedTabsMoveFromTheHighlightedTagRatherThanItsOldIndex() throws {
    // Hypothesis: tab-strip focus survives option churn as a position instead of the previously highlighted tag.
    let model = SetAPresentationModel()
    model.selection = 1
    var order = [1, 2, 3]
    let h = try make("620") {
      TabView(selection: model.selectionBinding) {
        ForEach(order, id: \.self) { value in
          Tab("Tab \(value)", value: value) { Text("Body \(value)") }
        }
      }
    }
    defer { h.shutdown() }
    try h.focusText("Tab 1")
    try h.pressKey(.init(.arrowRight))
    try #require(model.selection == 1)
    order = [2, 1, 3]
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.arrowRight))
    try h.pressKey(.init(.return))
    #expect(model.selection == 1)
    #expect(h.frame.contains("Body 1"))
  }

  @Test func setA621ChangingTabMetadataDoesNotReplaceItsActiveStateOwner() throws {
    // Hypothesis: a label or badge update is treated as a new tab lifetime despite an unchanged tag.
    let model = SetAPresentationModel()
    let h = try make("621") {
      TabView(selection: .constant(1)) {
        Tab("Inbox \(model.revision)", badge: "\(model.revision)", value: 1) { SetATabCounter() }
        Tab("Archive", value: 2) { Text("Archive payload") }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Increment tab count")
    try #require(h.frame.contains("Tab count 1"))
    model.revision = 6
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Inbox 6"), "\(h.frame)")
    #expect(h.frame.contains("Tab count 1"), "\(h.frame)")
    try h.clickText("Increment tab count")
    #expect(h.frame.contains("Tab count 2"))
  }

  @Test func setA622AnOpenMenuMigratesBetweenFloatingAndInlineOwnership() throws {
    // Hypothesis: changing presentation style leaves both the old portal and new inline payload mounted.
    let model = SetAPresentationModel()
    let h = try make("622") {
      Menu("Migrating commands") {
        Button("Migrating action") { model.events.append("run") }
      }.menuStyle(model.first ? .inline : .automatic)
    }
    defer { h.shutdown() }
    try h.clickText("Migrating commands")
    try h.clickText("Migrating action")
    try #require(model.events == ["run"])
    try #require(try node("Migrating action", role: .menuItem, in: h).control != nil)
    model.first = true
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Migrating action"), "\(h.frame)")
    #expect(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
        $0.label == "Migrating action" && $0.role == .menuItem
      }.count == 1)
    try h.clickText("Migrating action")
    #expect(model.events == ["run", "run"])
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Migrating action"))
  }

  @Test func setA623DisabledMenuCommandCannotBypassItsInheritedEnablement() throws {
    // Hypothesis: the menu overlay detaches a disabled command from the environment governing its action.
    let model = SetAPresentationModel()
    let h = try make("623") {
      Menu("Guarded commands") {
        Group { Button("Blocked command") { model.events.append("blocked") } }.disabled(true)
        Button("Allowed command") { model.events.append("allowed") }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Guarded commands")
    let disabled = try node("Blocked command", role: .menuItem, in: h)
    try #require(!disabled.isEnabled)
    let target = try #require(disabled.actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate)) == .disabled)
    #expect(model.events.isEmpty)
    try send(.activate, to: "Allowed command", role: .menuItem, in: h)
    #expect(model.events == ["allowed"])
  }

  @Test func setA624RemovingAnOpenMenuRetiresItsOverlayCommandTarget() throws {
    // Hypothesis: removing the trigger leaves the separately hosted overlay's old action callable.
    let model = SetAPresentationModel()
    model.first = true
    let h = try make("624") {
      VStack {
        if model.first {
          Menu("Transient commands") {
            Button("Transient action") { model.events.append("transient") }
          }
        }
        Button("Surviving action") { model.events.append("survivor") }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Transient commands")
    try send(.activate, to: "Transient action", role: .menuItem, in: h)
    try #require(model.events == ["transient"])
    let target = try #require(try node("Transient action", role: .menuItem, in: h).actionTarget)
    model.first = false
    try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("Transient action"))
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate)) == .staleTarget)
    try h.clickText("Surviving action")
    #expect(model.events == ["transient", "survivor"])
  }

  @Test func setA625NestedMenuEscapeRetiresOnlyTheLeafOverlay() throws {
    // Hypothesis: two menu-family overlays collapse into one dismissal entry and close their parent together.
    let model = SetAPresentationModel()
    let h = try make("625") {
      Menu("Outer commands") {
        Menu("Inner commands") { Button("Leaf command") { model.events.append("leaf") } }
        Button("Parent command") { model.events.append("parent") }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Outer commands")
    try #require(h.frame.contains("Parent command"))
    try h.clickText("Inner commands")
    try #require(h.frame.contains("Leaf command"), "\(h.frame)")
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Leaf command"))
    #expect(h.frame.contains("Parent command"), "\(h.frame)")
    try h.clickText("Parent command")
    #expect(model.events == ["parent"])
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Parent command"))
  }

  private func make<V: View>(
    _ id: String, width: Int = 80, height: Int = 24, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAPresentationComposition", id),
      size: .init(width: width, height: height), content: content)
  }

  private func node<V: View>(
    _ label: String, role: AccessibilityRole, in h: StressRuntimeHarness<V>
  ) throws -> AccessibilityNode {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == label && $0.role == role
      },
      "Missing \(role) named \(label); frame:\n\(h.frame)")
  }

  private func send<V: View>(
    _ action: AccessibilityAction, to label: String, role: AccessibilityRole,
    in h: StressRuntimeHarness<V>
  ) throws {
    let target = try #require(try node(label, role: role, in: h).actionTarget)
    #expect(h.runLoop.handleAccessibilityAction(.init(target: target, action: action)) == .accepted)
    try h.render()
  }
}

private struct SetAPresentationItem: Identifiable, Sendable {
  let id: Int
  let title: String
}

@MainActor
private final class SetAPresentationModel {
  var first = false
  var second = false
  var third = false
  var revision = 0
  var selection = 1
  var path: [Int] = []
  var childPath: [Int] = []
  var item: SetAPresentationItem?
  var otherItem: SetAPresentationItem?
  var events: [String] = []

  var firstBinding: Binding<Bool> { Binding(get: { self.first }, set: { self.first = $0 }) }
  var secondBinding: Binding<Bool> { Binding(get: { self.second }, set: { self.second = $0 }) }
  var thirdBinding: Binding<Bool> { Binding(get: { self.third }, set: { self.third = $0 }) }
  var selectionBinding: Binding<Int> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
  var pathBinding: Binding<[Int]> { Binding(get: { self.path }, set: { self.path = $0 }) }
  var childPathBinding: Binding<[Int]> {
    Binding(get: { self.childPath }, set: { self.childPath = $0 })
  }
  var itemBinding: Binding<SetAPresentationItem?> {
    Binding(get: { self.item }, set: { self.item = $0 })
  }
  var otherItemBinding: Binding<SetAPresentationItem?> {
    Binding(get: { self.otherItem }, set: { self.otherItem = $0 })
  }
}

@MainActor
private struct SetAChainedDismissFixture: View {
  let model: SetAPresentationModel
  @State private var first = true
  @State private var second = false

  var body: some View {
    Text("Chained presenter")
      .sheet(
        isPresented: $first,
        onDismiss: {
          model.events.append("first dismissed")
          second = true
        },
        content: { Text("First activation") }
      )
      .sheet(
        isPresented: $second, onDismiss: { model.events.append("second dismissed") },
        content: { Text("Second activation") })
  }
}

@MainActor
private struct SetATabNavigationFixture: View {
  @State private var selection = 1

  var body: some View {
    TabView(selection: $selection) {
      Tab("Navigation screen", value: 1) { SetANavigationTabBody() }
      Tab("Other screen", value: 2) { Text("Other payload") }
    }
  }
}

@MainActor
private struct SetANavigationTabBody: View {
  @State private var path: [Int] = []

  var body: some View {
    NavigationStack(path: $path) {
      Button("Push tab detail") { path.append(4) }
        .navigationDestination(for: Int.self) { value in Button("Tab detail \(value)") {} }
    }
  }
}

@MainActor
private struct SetATabCounter: View {
  @State private var count = 0

  var body: some View {
    VStack {
      Text("Tab count \(count)")
      Button("Increment tab count") { count += 1 }
    }
  }
}
