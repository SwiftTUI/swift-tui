import SwiftTUICore
import Testing

@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A selective (dirty-frontier) frame serves the ancestors of the nodes it
/// re-evaluates from committed snapshots, and a served ancestor's snapshot is
/// rebuilt from its child ViewNodes' own committed values. Two things that
/// rebuild dropped until the next root frame (org task T173):
///
/// - the decorations a presentation overlay stack authors onto ITS copy of
///   the hosted base — the modal-overlay interaction gate and the absorbed
///   focus-scope boundary — so a click behind an open sheet reached the base
///   action, the focus tracker recorded no modal restoration, and an
///   action-bearing popover tip left the base focusable;
/// - the scoped runtime-registration publication's reset selected identity
///   prefixes by the frontier root's structural identity while the paired
///   restore walked the root's ViewNode subtree, so beneath an exact-`.id`
///   host (whose descendants key their registrations under the RESOLVED
///   identity) the restore republished still-live entries on top of
///   themselves;
/// - a gesture stacked onto, or removed from, an identity DURING an active
///   drag never reached dispatch: the live gesture registry keeps a
///   mid-interaction recognizer and used to tear the re-authored record down
///   with it, and the pointer route dispatched through the discarded frame
///   draft that authored it. A root evaluation re-registered both on the next
///   frame; a selective frame never did;
/// - an exact-`.id` control resolved beneath an exact-`.id` owner changed
///   entity on a selective frame: the dirty-frontier evaluator re-ran outside
///   the enclosing owner's entity-route binding, so the control's entity was
///   scoped to its structural position instead of the owner's entity, the
///   modifier saw a foreign occupant on its slot node, and the forwarded claim
///   folded the control's node onto its `.frame` wrapper — a parent/child
///   cycle that tripped the DEBUG stamp-coherence oracle on the focus frame
///   and livelocked the next paste without it.
///
/// Every scenario here runs on the run loop's selective default and compares
/// against what a root evaluation produces.
@MainActor
@Suite(.serialized)
struct SelectiveServedHostParityTests {
  @Test("a sheet gates the base on the frame that opens it")
  func sheetGatesTheBaseOnItsOwnSelectiveFrame() throws {
    let rootIdentity = testIdentity("ServedHostSheetRoot")
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 60, height: 14),
      selectiveEvaluation: true
    ) {
      ServedHostSheetFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Increment Root")
    #expect(frame.contains("Root count 1"), "the root write did not render:\n\(frame)")
    let rootButtonPoint = try #require(harness.point(forText: "Increment Root"))
    #expect(harness.focusModalRestorationStackCount == 0)

    frame = try harness.clickText("Open Sheet")
    #expect(frame.contains("Sheet body"), "the sheet did not open:\n\(frame)")
    #expect(
      baseFocusRegionPaths(harness, rootIdentity: rootIdentity).isEmpty,
      "base focus regions survived beneath the modal sheet: \(baseFocusRegionPaths(harness, rootIdentity: rootIdentity))"
    )
    #expect(
      baseInteractionRegionPaths(harness, rootIdentity: rootIdentity).isEmpty,
      "base pointer regions survived beneath the modal sheet: \(baseInteractionRegionPaths(harness, rootIdentity: rootIdentity))"
    )
    #expect(
      harness.focusModalRestorationStackCount == 1,
      "the focus tracker recorded no modal restoration for the open sheet"
    )

    frame = try harness.click(rootButtonPoint)
    #expect(frame.contains("Sheet body"))
    #expect(frame.contains("Root count 1"))
    #expect(
      !frame.contains("Root count 2"), "a click behind the sheet reached the base action:\n\(frame)"
    )

    frame = try harness.clickText("Close Sheet", chooseLast: true)
    #expect(!frame.contains("Sheet body"), "the sheet did not close:\n\(frame)")
    #expect(harness.focusModalRestorationStackCount == 0)
    #expect(!baseFocusRegionPaths(harness, rootIdentity: rootIdentity).isEmpty)

    frame = try harness.clickText("Increment Root")
    #expect(
      frame.contains("Root count 2"), "the base did not come back after the sheet closed:\n\(frame)"
    )
  }

  @Test("a served overlay stack keeps its base's absorbed focus scope across a selective frame")
  func servedOverlayStackKeepsParityWithRootEvaluation() throws {
    let rootIdentity = testIdentity("ServedHostToastRoot")
    func makeHarness(selective: Bool) throws -> StressRuntimeHarness<ServedHostToastFixture> {
      try StressRuntimeHarness(
        rootIdentity: rootIdentity,
        size: .init(width: 60, height: 12),
        selectiveEvaluation: selective
      ) {
        ServedHostToastFixture()
      }
    }
    let control = try makeHarness(selective: false)
    defer { control.shutdown() }
    let selective = try makeHarness(selective: true)
    defer { selective.shutdown() }

    for harness in [control, selective] {
      let shown = try harness.clickText("Show Toast")
      #expect(shown.contains("Toast body"), "the toast did not appear:\n\(shown)")
      // A frame beneath the served stack while the (non-modal) toast stays up.
      let incremented = try harness.clickText("Increment")
      #expect(incremented.contains("count 1"), "the base write did not render:\n\(incremented)")
      #expect(incremented.contains("Toast body"), "the toast vanished:\n\(incremented)")
    }

    #expect(
      focusRegionShapes(selective) == focusRegionShapes(control),
      """
      selective focus regions diverged from the root evaluation:
      selective: \(focusRegionShapes(selective))
      control:   \(focusRegionShapes(control))
      """
    )
    #expect(
      selective.runLoop.latestSemanticSnapshot.interactionRegions.map(\.identity.path)
        == control.runLoop.latestSemanticSnapshot.interactionRegions.map(\.identity.path)
    )
  }

  @Test("a default-focus candidate under a replaced .id owner is published once per frame")
  func defaultFocusCandidateUnderReplacedIDOwnerPublishesOnce() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostDefaultFocusRoot"),
      size: .init(width: 60, height: 10),
      selectiveEvaluation: true
    ) {
      ServedHostDefaultFocusFixture()
    }
    defer { harness.shutdown() }

    for generation in 1...4 {
      let frame = try harness.clickText("Rebuild Owner")
      #expect(frame.contains("generation \(generation)"), "the owner did not rebuild:\n\(frame)")
      let snapshot = harness.runLoop.localDefaultFocusRegistry.snapshot()
      #expect(
        snapshot.scopes.count == 1,
        "generation \(generation): \(snapshot.scopes.count) default-focus scopes published"
      )
      #expect(
        snapshot.candidates.count == 1,
        "generation \(generation): \(snapshot.candidates.count) default-focus candidates published"
      )
    }
  }

  @Test("a tap removed during an active drag is gone once the drag ends")
  func tapRemovedDuringActiveDragIsGoneAfterTheDrag() throws {
    let taps = ServedHostCounterBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostRemovedTapRoot"),
      size: .init(width: 44, height: 7),
      selectiveEvaluation: true
    ) {
      ServedHostRemovedTapFixture(taps: taps)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Shrinking gesture stack"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.clickText("Shrinking gesture stack")

    #expect(taps.value == 0, "the tap removed during the drag still fired")
    #expect(harness.gestureRecognizerCount == 1)
  }

  @Test("a tap added during an active drag dispatches once the drag ends")
  func tapAddedDuringActiveDragDispatchesAfterTheDrag() throws {
    let taps = ServedHostCounterBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostAddedTapRoot"),
      size: .init(width: 44, height: 6),
      selectiveEvaluation: true
    ) {
      ServedHostAddedTapFixture(taps: taps)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Dynamic gesture"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 4, y: start.y))
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 4, y: start.y))
    _ = try harness.clickText("Dynamic gesture")

    #expect(taps.value == 1, "the tap added during the drag never dispatched")
  }

  @Test("an exact-.id editor beneath an exact-.id owner keeps its entity on the focus frame")
  func exactIDEditorBeneathExactIDOwnerKeepsItsEntityOnSelectiveFrames() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostPanelEditorRoot"),
      size: .init(width: 60, height: 10),
      selectiveEvaluation: true
    ) {
      ServedHostPanelEditorFixture()
    }
    defer { harness.shutdown() }

    let graph = harness.runLoop.renderer.viewGraph
    let controlIdentity = ServedHostPanelEditorFixture.controlIdentity

    for generation in 0..<3 {
      // The entity the owner's own resolve pass gave the editor (the initial
      // root frame, then each rebuild frame, which re-resolves the `.id`
      // chain inside the owner's route binding). The exact entity is scoped
      // to the owner's entity, so it changes with every rebuild by design.
      let referenceEntity = try #require(
        graph.nodeForIdentity(controlIdentity)?.committed.entityIdentity,
        "generation \(generation): the owner's frame resolved no entity for the editor"
      )
      // The focus write invalidates the editor precisely; the frontier lifts
      // to its `.frame` wrapper, which re-resolves the `.id` chain outside
      // the enclosing owner's resolve pass.
      var frame = try harness.focus(controlIdentity)
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == controlIdentity)
      let control = try #require(graph.nodeForIdentity(controlIdentity))
      #expect(
        control.committed.entityIdentity == referenceEntity,
        "generation \(generation): the selective focus frame re-homed the editor under a different entity"
      )
      #expect(
        graph.childCycleDescriptions().isEmpty,
        "generation \(generation): parent/child cycle after the focus frame: \(graph.childCycleDescriptions())"
      )

      frame = try harness.paste("line-\(generation)\nnext")
      #expect(
        frame.contains("text line-\(generation)|next"),
        "generation \(generation): the paste did not render:\n\(frame)"
      )

      frame = try harness.clickText("Rebuild Owner")
      #expect(frame.contains("generation \(generation + 1)"), "the owner did not rebuild:\n\(frame)")
      #expect(frame.contains("text empty"), "the rebuild did not reset the text:\n\(frame)")
    }
  }

  @Test("an AnyView-hosted exact-.id control publishes its pointer handlers once per selective frame")
  func anyViewHostedExactIDControlPublishesPointerHandlersOnce() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ServedHostAnyViewStepperRoot"),
      size: .init(width: 60, height: 8),
      selectiveEvaluation: true
    ) {
      ServedHostAnyViewStepperFixture()
    }
    defer { harness.shutdown() }

    let controlIdentity = ServedHostAnyViewStepperFixture.controlIdentity
    // The count a full publication produces: the control's own handler plus
    // its two buttons. Every scoped restore below must land on the same
    // number — the scoped reset and restore must cover the same node set.
    let fullPublicationCount = harness.pointerHandlerCount
    #expect(fullPublicationCount > 0)

    for generation in 0..<3 {
      _ = try harness.focus(controlIdentity)
      #expect(
        harness.pointerHandlerCount == fullPublicationCount,
        "generation \(generation): \(harness.pointerHandlerCount) pointer handlers after the focus frame"
      )
      // The key write lands on the fixture root through the binding while the
      // control itself re-resolves: a two-root selective frame whose scoped
      // restore has to cover the out-of-band-hosted `.id` control by prefix.
      let frame = try harness.pressKey(KeyPress(.arrowRight))
      #expect(frame.contains("int \(generation + 1)"), "the key press did not step:\n\(frame)")
      #expect(
        harness.pointerHandlerCount == fullPublicationCount,
        "generation \(generation): \(harness.pointerHandlerCount) pointer handlers after the key frame"
      )
      let rebuilt = try harness.clickText("Rebuild Owner")
      #expect(rebuilt.contains("generation \(generation + 1)"), "the owner did not rebuild:\n\(rebuilt)")
      #expect(
        harness.pointerHandlerCount == fullPublicationCount,
        "generation \(generation): \(harness.pointerHandlerCount) pointer handlers after the rebuild"
      )
    }
  }
}

// MARK: - Support

extension ViewGraph {
  /// Every live parent/child edge whose child also lists the parent as a
  /// child — the shape a cross-identity re-entrant adoption leaves behind.
  fileprivate func childCycleDescriptions() -> [String] {
    var cycles: [String] = []
    for (_, node) in nodesByNodeID {
      for child in node.children where child !== node {
        if child.children.contains(where: { $0 === node }) {
          cycles.append("\(node.identity.path) <-> \(child.identity.path)")
        }
      }
    }
    return cycles.sorted()
  }
}

@MainActor
private func baseFocusRegionPaths<V: View>(
  _ harness: StressRuntimeHarness<V>,
  rootIdentity: Identity
) -> [String] {
  harness.runLoop.focusTracker.focusRegions
    .map(\.identity.path)
    .filter { $0.hasPrefix(rootIdentity.path) }
}

@MainActor
private func baseInteractionRegionPaths<V: View>(
  _ harness: StressRuntimeHarness<V>,
  rootIdentity: Identity
) -> [String] {
  harness.runLoop.latestSemanticSnapshot.interactionRegions
    .map(\.identity.path)
    .filter { $0.hasPrefix(rootIdentity.path) }
}

private struct FocusRegionShape: Equatable, CustomStringConvertible {
  var identity: String
  var scopePath: [String]
  var modalFocusScopePath: [String]?

  var description: String {
    "\(identity) scope=\(scopePath) modal=\(modalFocusScopePath ?? [])"
  }
}

@MainActor
private func focusRegionShapes<V: View>(_ harness: StressRuntimeHarness<V>) -> [FocusRegionShape] {
  harness.runLoop.focusTracker.focusRegions.map { region in
    FocusRegionShape(
      identity: region.identity.path,
      scopePath: region.scopePath.map(\.path),
      modalFocusScopePath: region.modalFocusScopePath?.map(\.path)
    )
  }
}

private struct ServedHostSheetFixture: View {
  @State private var rootCount = 0
  @State private var sheetPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root count \(rootCount)")
      Button("Increment Root") { rootCount += 1 }
      Button("Open Sheet") { sheetPresented = true }
    }
    .sheet("Served Host Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close Sheet") { sheetPresented = false }
      }
    }
    .frame(width: 60, height: 14, alignment: .topLeading)
  }
}

private struct ServedHostToastFixture: View {
  @State private var toastPresented = false

  var body: some View {
    // The panel is a focus-scope boundary at the overlay stack's base: the
    // stack absorbs it (`focusScopeIdentity`) and clears the base's own
    // boundary so the scope path does not repeat the panel.
    Panel(id: testIdentity("ServedHostToast", "panel")) {
      VStack(alignment: .leading, spacing: 0) {
        ServedHostToastCounter()
        Button("Show Toast") { toastPresented = true }
      }
      .toast("Toast body", isPresented: $toastPresented, duration: nil)
    }
  }
}

/// Owns the counter so its write invalidates only this node: the frame it
/// schedules serves the overlay stack above from its committed snapshot.
private struct ServedHostToastCounter: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(count)")
      Button("Increment") { count += 1 }
    }
  }
}

private enum ServedHostFocusField: Hashable {
  case target
}

private struct ServedHostDefaultFocusFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Owner") { generation += 1 }
      Text("generation \(generation)")
      ServedHostDefaultFocusOwner(generation: generation)
        .id(testIdentity("ServedHostDefaultFocus", "owner", "\(generation)"))
    }
    .frame(width: 60, height: 10, alignment: .topLeading)
  }
}

private struct ServedHostDefaultFocusOwner: View {
  let generation: Int
  @Namespace private var namespace
  @FocusState private var focusedField: ServedHostFocusField?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Default focus target \(generation)")
        .id(testIdentity("ServedHostDefaultFocus", "target"))
        .focusable()
        .focused($focusedField, equals: .target)
        .prefersDefaultFocus(in: namespace)
    }
    .focusScope(namespace)
  }
}

private final class ServedHostCounterBox {
  var value: Int
  init(_ value: Int) { self.value = value }
}

/// The drag's first change flips the branch over the same `.id`, dropping
/// the stacked tap while the drag is still active.
private struct ServedHostRemovedTapFixture: View {
  static let identity = testIdentity("ServedHostRemovedTap", "Target")

  let taps: ServedHostCounterBox
  @State private var includesTap = true

  var body: some View {
    if includesTap {
      Text("Shrinking gesture stack")
        .id(Self.identity)
        .frame(width: 28, height: 1, alignment: .leading)
        .gesture(DragGesture().onChanged { _ in includesTap = false })
        .onTapGesture { taps.value += 1 }
    } else {
      Text("Shrinking gesture stack")
        .id(Self.identity)
        .frame(width: 28, height: 1, alignment: .leading)
        .gesture(DragGesture().onChanged { _ in })
    }
  }
}

/// The mirror: the drag's first change stacks a tap onto the same `.id`.
private struct ServedHostAddedTapFixture: View {
  static let identity = testIdentity("ServedHostAddedTap", "Gesture")

  let taps: ServedHostCounterBox
  @State private var installsTap = false

  var body: some View {
    if installsTap {
      Text("Dynamic gesture")
        .id(Self.identity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(DragGesture().onChanged { _ in })
        .onTapGesture { taps.value += 1 }
    } else {
      Text("Dynamic gesture")
        .id(Self.identity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(DragGesture().onChanged { _ in installsTap = true })
    }
  }
}


/// The T173 residual's shape: a `Panel`-hosted `TextEditor` with its own exact
/// `.id`, under a `.frame` wrapper, inside an owner replaced by exact `.id`.
private struct ServedHostPanelEditorFixture: View {
  static let controlIdentity = testIdentity("ServedHostPanelEditor", "control")
  static let scopeIdentity = testIdentity("ServedHostPanelEditor", "scope")

  @State private var generation = 0
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Owner") {
        generation += 1
        text = ""
      }
      Text("generation \(generation) text \(displayText)")
      ServedHostPanelEditorOwner(text: $text)
        .id(testIdentity("ServedHostPanelEditor", "owner", "\(generation)"))
    }
    .frame(width: 60, height: 10, alignment: .topLeading)
  }

  private var displayText: String {
    text.isEmpty
      ? "empty"
      : text.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "|")
  }
}

private struct ServedHostPanelEditorOwner: View {
  @Binding var text: String

  var body: some View {
    Panel(id: ServedHostPanelEditorFixture.scopeIdentity) {
      TextEditor(text: $text)
        .id(ServedHostPanelEditorFixture.controlIdentity)
        .frame(width: 30, height: 3, alignment: .leading)
    }
  }
}

/// An exact-`.id` `Stepper` hosted out-of-band by an `AnyView` payload under
/// a replaced `.id` owner: the scoped registration restore reaches the
/// control only by identity prefix.
private struct ServedHostAnyViewStepperFixture: View {
  static let controlIdentity = testIdentity("ServedHostAnyViewStepper", "control")

  @State private var generation = 0
  @State private var intValue = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Owner") { generation += 1 }
      Text("generation \(generation) int \(intValue)")
      ServedHostAnyViewStepperOwner(intValue: $intValue)
        .id(testIdentity("ServedHostAnyViewStepper", "owner", "\(generation)"))
    }
    .frame(width: 60, height: 8, alignment: .topLeading)
  }
}

private struct ServedHostAnyViewStepperOwner: View {
  @Binding var intValue: Int

  var body: some View {
    AnyView(
      Stepper("AnyView Stepper", value: $intValue, in: 0...999)
        .id(ServedHostAnyViewStepperFixture.controlIdentity)
    )
  }
}
