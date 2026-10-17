import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetATerminalInteractionDepthTests {
  @Test func setA1051KeyedEditorReorderPreservesFocusedCaretOwnership() throws {
    // Hypothesis: a keyed row move retargets the terminal input route while retaining another editor's caret.
    let m = DepthModel()
    m.texts = ["alpha", "bravo"]
    let h = try make(1051) {
      VStack { ForEach(m.order, id: \.self) { TextField("Entry \($0)", text: m.text($0)) } }
    }
    defer { h.shutdown() }
    try h.focusValue("alpha")
    try h.key(.arrowLeft)
    let owner = h.loop.focusTracker.currentFocusIdentity
    m.order.reverse()
    try h.refresh()
    #expect(h.loop.focusTracker.currentFocusIdentity == owner)
    try h.paste("X")
    #expect(m.texts == ["alphXa", "bravo"])
  }

  @Test func setA1052TerminalWidthShrinkPreservesTheSelectedSourceRange() throws {
    // Hypothesis: rebuilding clipped single-line caret geometry during SIGWINCH resets the source selection.
    let m = DepthModel()
    let h = try make(1052) { TextField("Resize field", text: m.text(0)) }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    try h.key(.arrowLeft, modifiers: .shift)
    #expect(try h.editor().textInput?.selection == 4..<6)
    try h.resize(width: 9, height: 8)
    #expect(h.surface.surface?.size.width == 9)
    #expect(try h.editor().textInput?.selection == 4..<6)
    try h.paste("X")
    #expect(m.texts[0] == "abcdX")
  }

  @Test func setA1053FirstVerticalKeyAfterResizeUsesTheNewWrappedWidth() throws {
    // Hypothesis: the live TextEditor key closure keeps its pre-SIGWINCH measured content width.
    let m = DepthModel()
    m.texts[0] = "abcdefghijklmnopqr"
    let h = try make(1053) { TextEditor(text: m.text(0)) }
    defer { h.shutdown() }
    try h.focusValue(m.texts[0])
    try h.key(.arrowUp)
    try #require(h.editor().textInput?.insertionOffset == 18)
    try h.resize(width: 10, height: 8)
    try h.key(.arrowUp)
    let offset = try #require(h.editor().textInput?.insertionOffset)
    #expect(offset > 0 && offset < 18)
    try h.paste("X")
    #expect(m.texts[0].count == 19 && !m.texts[0].hasSuffix("X"))
  }

  @Test func setA1054OverflowingEditorContributesOnlyOneTerminalTabStop() throws {
    // Hypothesis: the editor's newly needed scrollbar leaks its internal ScrollView onto terminal Tab traversal.
    let m = DepthModel()
    m.texts[0] = (0..<20).map { "Line \($0)" }.joined(separator: "\n")
    let h = try make(1054) {
      VStack {
        Button("Before editor") {}
        TextEditor(text: m.text(0)).frame(height: 3)
        Button("After editor") { m.events.append("after") }
      }
    }
    defer { h.shutdown() }
    try h.focusLabel("Before editor")
    try h.key(.tab)
    try #require(h.focusedNode()?.role == .textEditor)
    try h.key(.tab)
    #expect(try h.focusedNode()?.label == "After editor")
    try h.key(.return)
    #expect(m.events == ["after"])
  }

  @Test func setA1055MultilineRowEditingConsumesArrowsBeforeListNavigation() throws {
    // Hypothesis: List's ancestor key route advances selection after its descendant editor moved the caret.
    let m = DepthModel()
    m.texts = ["ab\ncd", "other"]
    m.selected = 0
    let h = try make(1055) {
      List([0, 1], id: \.self, selection: m.selection) { index in
        TextEditor(text: m.text(index)).frame(height: 3)
      }
    }
    defer { h.shutdown() }
    try h.focusValue("ab\ncd")
    try h.key(.arrowUp)
    try h.paste("X")
    #expect(m.texts[0] == "abX\ncd")
    #expect(m.selected == 0 && m.texts[1] == "other")
  }

  @Test func setA1056TerminalResizeUpdatesTheReleaseBoundsOfAPressedButton() throws {
    // Hypothesis: a captured terminal press validates release against the button's pre-resize bounds.
    let m = DepthModel()
    let h = try make(1056) {
      HStack {
        Spacer()
        Button("Resize pressed button") { m.events.append("activated") }
      }
    }
    defer { h.shutdown() }
    let point = try h.point("button")
    try #require(point.x >= 30)
    try h.mouse(.down(.primary), at: point)
    try #require(h.loop.pressedIdentity != nil)
    try h.resize(width: 30, height: 9)
    try #require(h.point("button").x < point.x)
    try h.mouse(.up(.primary), at: point)
    #expect(m.events.isEmpty && h.loop.pressedIdentity == nil)
    try h.click("Resize pressed button")
    #expect(m.events == ["activated"])
  }

  @Test func setA1057MovedScrollViewportReplacesItsPointerCoordinates() throws {
    // Hypothesis: scroll translation and parent placement leave a child's hit route at its previous screen position.
    let m = DepthModel()
    let h = try make(1057) {
      VStack(spacing: 0) {
        Text("Spacer").frame(height: m.height)
        ScrollView {
          Button("Moving action") { m.events.append("hit") }
          Text("Tail").frame(height: 12)
        }.scrollIndicators(.hidden).frame(width: 24, height: 4)
      }
    }
    defer { h.shutdown() }
    let old = try h.point("Moving action")
    try h.click("Moving action")
    try #require(m.events == ["hit"])
    m.events.removeAll()
    m.height += 4
    try h.refresh()
    let moved = try h.point("Moving action")
    try #require(moved.y > old.y)
    try h.mouse(.down(.primary), at: old)
    try h.mouse(.up(.primary), at: old)
    #expect(m.events.isEmpty)
    try h.click("Moving action")
    #expect(m.events == ["hit"])
  }

  @Test func setA1058CollectionPagingUsesTheNewTerminalHeight() throws {
    // Hypothesis: List PageDown keeps a cached page size after the host adds visible terminal rows.
    let m = DepthModel()
    let h = try make(1058, height: 5) {
      List(Array(0..<50), id: \.self, selection: m.selection) { Text("Page row \($0)") }
    }
    defer { h.shutdown() }
    try h.focusText("Page row 0")
    let oldWindow = try #require(
      h.loop.latestSemanticSnapshot.scrollRoutes.first?.collectionScrollLayout)
    try h.resize(width: 40, height: 11)
    let resized = try #require(
      h.loop.latestSemanticSnapshot.scrollRoutes.first?.collectionScrollLayout)
    try #require(resized.visibleLines.count > oldWindow.visibleLines.count)
    try #require(resized.visibleLines.lowerBound == 0)
    try #require(resized.geometry.lineRange(forRow: 0).count == 1)
    try h.key(.pageDown)
    let after = try #require(
      h.loop.latestSemanticSnapshot.scrollRoutes.first?.collectionScrollLayout)
    // List publishes a logical row window; contentBounds is not a translated document rectangle.
    let expectedFirst = resized.visibleLines.count - 1
    #expect(
      after.visibleLines.lowerBound == expectedFirst,
      "resized=\(resized.visibleLines), after=\(after.visibleLines), frame=\(h.frame)")
    #expect(h.frame.contains("Page row \(expectedFirst)"))
    #expect(m.selected == nil)
  }

  @Test func setA1059LazyRealizationInstallsTheRevealedEditorsOwnPasteRoute() throws {
    // Hypothesis: realizing a distant editable row reuses a nearby row's text binding in the paste registry.
    let m = DepthModel()
    m.texts = (0..<100).map { "record-\($0)" }
    let h = try make(1059) {
      ScrollViewReader { proxy in
        let _ = m.capture(proxy)
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(0..<100, id: \.self) { TextField("Record \($0)", text: m.text($0)) }
          }
        }.scrollIndicators(.hidden).frame(height: 5)
      }
    }
    defer { h.shutdown() }
    try #require(!h.frame.contains("record-90"))
    #expect(try #require(m.proxy).scrollTo(90, anchor: .top))
    try h.render()
    try h.focusValue("record-90")
    try h.paste("X")
    #expect(m.texts[90] == "record-90X")
    #expect(m.texts[0] == "record-0" && m.texts[89] == "record-89")
  }

  @Test func setA1060ExpandedTerminalClampsTheScrollEndpointWithoutSelecting() throws {
    // Hypothesis: growing the terminal leaves collection bottom scroll beyond the new maximum or selects its anchor.
    let m = DepthModel()
    let h = try make(1060, height: 5) {
      List(Array(0..<30), id: \.self, selection: m.selection) { Text("End row \($0)") }
    }
    defer { h.shutdown() }
    try h.focusText("End row 0")
    try h.key(.end)
    try #require(h.frame.contains("End row 29"))
    let oldWindow = try #require(
      h.loop.latestSemanticSnapshot.scrollRoutes.first?.collectionScrollLayout)
    try h.resize(width: 40, height: 12)
    let after = try #require(
      h.loop.latestSemanticSnapshot.scrollRoutes.first?.collectionScrollLayout)
    #expect(after.visibleLines.count > oldWindow.visibleLines.count)
    #expect(
      after.visibleLines.upperBound == after.geometry.displayLineCount,
      "window=\(after.visibleLines), total=\(after.geometry.displayLineCount), frame=\(h.frame)")
    #expect(h.frame.contains("End row \(after.visibleLines.lowerBound)"))
    #expect(h.frame.contains("End row 29") && m.selected == nil)
  }

  @Test func setA1061SheetRoundTripPreservesTheUnderlyingEditorsSelection() throws {
    // Hypothesis: restoring terminal focus after sheet dismissal reconstructs the text field with a collapsed caret.
    let m = DepthModel()
    let h = try make(1061) {
      TextField("Underlying editor", text: m.text(0))
        .sheet(isPresented: m.flag) { Button("Sheet action") {} }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    try h.key(.arrowLeft, modifiers: .shift)
    let owner = h.loop.focusTracker.currentFocusIdentity
    m.show = true
    try h.refresh()
    try #require(h.frame.contains("Sheet action"))
    try h.key(.escape)
    #expect(!m.show && h.loop.focusTracker.currentFocusIdentity == owner)
    try h.paste("X")
    #expect(m.texts[0] == "abcdX")
  }

  @Test func setA1062NestedSheetEscapeRestoresTheOuterEditorsInputOwner() throws {
    // Hypothesis: retiring the top modal restores the original background editor instead of the still-mounted sheet.
    let m = DepthModel()
    m.texts = ["background", "outer", "inner"]
    let h = try make(1062) {
      TextField("Background", text: m.text(0))
        .sheet(isPresented: m.flag) {
          TextField("Outer", text: m.text(1))
            .sheet(isPresented: m.secondFlag) { TextField("Inner", text: m.text(2)) }
        }
    }
    defer { h.shutdown() }
    m.show = true
    try h.refresh()
    try h.focusValue("outer")
    m.second = true
    try h.refresh()
    try h.focusValue("inner")
    try h.key(.escape)
    try h.paste("X")
    #expect(m.show && !m.second)
    #expect(m.texts == ["background", "outerX", "inner"])
  }

  @Test func setA1063ModalTraversalWrapsWithoutEditingBackgroundFields() throws {
    // Hypothesis: a modal's forward/backward Tab boundary leaks into the retained presenter focus ring.
    let m = DepthModel()
    m.texts = ["background", "first-modal", "last-modal"]
    let h = try make(1063) {
      TextField("Behind modal", text: m.text(0))
        .sheet(isPresented: m.flag) {
          VStack {
            TextField("Modal first", text: m.text(1))
            TextField("Modal last", text: m.text(2))
          }
        }
    }
    defer { h.shutdown() }
    try h.focusValue("background")
    let backgroundOwner = try #require(h.loop.focusTracker.currentFocusIdentity)
    m.show = true
    try h.refresh()
    try h.focusValue("last-modal")
    let lastOwner = try #require(h.loop.focusTracker.currentFocusIdentity)
    let closeOwner = try #require(
      h.loop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Close" && $0.role == .button
      }?.identity)
    let count = h.loop.focusTracker.focusRegions.count
    try #require(count >= 3 && count <= 8)
    var forward: [Identity] = []
    var editedFirst = false
    for _ in 0..<count {
      try h.key(.tab)
      let owner = try #require(h.loop.focusTracker.currentFocusIdentity)
      forward.append(owner)
      #expect(owner != backgroundOwner)
      if try h.focusedNode()?.control?.value == .text("first-modal") {
        try h.paste("X")
        editedFirst = true
      }
    }
    #expect(forward.contains(closeOwner) && forward.last == lastOwner)
    #expect(editedFirst && m.texts == ["background", "first-modalX", "last-modal"])
    var backward: [Identity] = []
    for _ in 0..<count {
      try h.key(.tab, modifiers: .shift)
      let owner = try #require(h.loop.focusTracker.currentFocusIdentity)
      backward.append(owner)
      #expect(owner != backgroundOwner)
    }
    #expect(backward.contains(closeOwner) && backward.last == lastOwner)
    try h.paste("Y")
    #expect(m.texts == ["background", "first-modalX", "last-modalY"])
  }

  @Test func setA1064RemovingAMountedPresenterRetiresItsModalPasteConsumer() throws {
    // Hypothesis: removing a presentation source leaves the departing modal editor registered after focus fallback.
    let m = DepthModel()
    m.texts = ["survivor", "modal"]
    m.show = true
    let h = try make(1064) {
      VStack {
        TextField("Survivor", text: m.text(0))
        if m.present {
          Text("Source").sheet(isPresented: m.flag) { TextField("Modal", text: m.text(1)) }
        }
      }
    }
    defer { h.shutdown() }
    try h.focusValue("modal")
    try h.paste("A")
    try #require(m.texts[1] == "modalA")
    m.present = false
    try h.refresh()
    try #require(!h.frame.contains("modalA"))
    try h.focusValue("survivor")
    try h.paste("B")
    #expect(m.texts == ["survivorB", "modalA"])
  }

  @Test func setA1065NavigationRoundTripRestoresTheRootEditorsCaret() throws {
    // Hypothesis: replacing a navigation surface archives text but loses the root editor's insertion position.
    let m = DepthModel()
    let h = try make(1065) {
      NavigationStack(path: m.pathBinding) {
        TextField("Root field", text: m.text(0))
          .navigationDestination(for: Int.self) { _ in Button("Destination") {} }
      }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft)
    try h.key(.arrowLeft)
    m.path.append(1)
    try h.refresh()
    try #require(h.frame.contains("Destination"))
    try h.key(.escape)
    try #require(m.path.isEmpty)
    try h.focusValue("abcdef")
    try h.paste("X")
    #expect(m.texts[0] == "abcdXef")
  }

  @Test func setA1066DormantEditorRemeasuresBeforeItsFirstVerticalKey() throws {
    // Hypothesis: an editor restored after a terminal resize uses its dormant transient width carrier.
    let m = DepthModel()
    m.texts[0] = "abcdefghijklmnopqr"
    let h = try make(1066) {
      TabView(selection: m.tabBinding) {
        Tab("Edit", value: 0) { TextEditor(text: m.text(0)) }
        Tab("Other", value: 1) { Text("Dormant editor") }
      }
    }
    defer { h.shutdown() }
    try h.focusValue(m.texts[0])
    try h.key(.arrowLeft)
    m.tab = 1
    try h.refresh()
    try #require(h.frame.contains("Dormant editor"))
    try h.resize(width: 10, height: 10)
    m.tab = 0
    try h.refresh()
    try h.focusValue(m.texts[0])
    try #require(h.editor().textInput?.insertionOffset == 17)
    try h.key(.arrowUp)
    let offset = try #require(h.editor().textInput?.insertionOffset)
    #expect(offset < 17 && offset >= 0)
  }

  @Test func setA1067ToastPublicationLeavesAnActiveSelectionEditable() throws {
    // Hypothesis: adding nonmodal overlay chrome resets the focused editor's selection or replaces its paste owner.
    let m = DepthModel()
    let h = try make(1067) {
      TextField("Toast editor", text: m.text(0))
        .toast("Nonmodal notice", isPresented: m.flag, duration: nil)
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    let owner = h.loop.focusTracker.currentFocusIdentity
    m.show = true
    try h.refresh()
    try #require(h.frame.contains("Nonmodal notice"))
    #expect(h.loop.focusTracker.currentFocusIdentity == owner)
    try h.paste("X")
    #expect(m.texts[0] == "abcdeX" && m.show)
  }

  @Test func setA1068AlertReturnCannotSubmitTheCoveredEditor() throws {
    // Hypothesis: the modal action consumes Return but the covered field's submit chain also runs.
    let m = DepthModel()
    let h = try make(1068) {
      TextField("Covered field", text: m.text(0))
        .onSubmit { m.events.append("submitted") }
        .alert("Confirmation", isPresented: m.flag) {
          Button("Accept depth") {
            m.events.append("accepted")
            m.show = false
          }
        } message: {
          Text("Confirm once")
        }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    m.show = true
    try h.refresh()
    try h.focusLabel("Accept depth")
    try h.key(.return)
    #expect(m.events == ["accepted"] && !m.show)
    #expect(m.texts[0] == "abcdef")
  }

  @Test func setA1069SubmitFocusTransferCannotReplayTheSameReturn() throws {
    // Hypothesis: focus synchronization during submit redispatches the event to the newly selected field.
    let m = DepthModel()
    let h = try make(1069) { DepthSubmitTransfer(model: m) }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.return)
    try h.paste("X")
    #expect(m.events == ["first"])
    #expect(m.texts == ["abcdef", "secondX"])
  }

  @Test func setA1070SubmitSelfRemovalRetiresItsHandlerBeforeTheNextReturn() throws {
    // Hypothesis: an editor removed by its own submission remains in the input registry for a later Return.
    let m = DepthModel()
    let h = try make(1070) {
      VStack {
        if m.present {
          TextField("One shot", text: m.text(0))
            .onSubmit {
              m.events.append("submit")
              m.present = false
            }
        }
        Button("Remaining action") { m.events.append("button") }
      }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.return)
    try #require(!m.present && m.events == ["submit"])
    try h.focusLabel("Remaining action")
    try h.key(.return)
    #expect(m.events == ["submit", "button"])
  }

  @Test func setA1071DisabledFieldInsideASheetCannotKeepItsPasteBindingLive() throws {
    // Hypothesis: modal-host reuse bypasses refreshed editor enablement after an active selection is disabled.
    let m = DepthModel()
    m.show = true
    let h = try make(1071) {
      Text("Source").sheet(isPresented: m.flag) {
        TextField("Disable modal editor", text: m.text(0)).disabled(m.disabled)
      }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    m.disabled = true
    try h.refresh()
    try h.paste("X")
    #expect(m.texts[0] == "abcdef" && m.writes == 0)
    m.disabled = false
    try h.refresh()
    try h.focusValue("abcdef")
    try h.paste("Y")
    #expect(m.writes == 1 && m.texts[0].contains("Y"))
  }

  @Test func setA1072InnerSubmitMutationCannotSkipItsCapturedAncestorAction() throws {
    // Hypothesis: changing the editor subtree in an inner submit callback drops the enclosing submit from that event.
    let m = DepthModel()
    let h = try make(1072) {
      if m.present {
        TextField("Original submit", text: m.text(0))
          .onSubmit {
            m.events.append("inner")
            m.present = false
          }
          .onSubmit { m.events.append("outer") }
      } else {
        TextField("Replacement submit", text: m.text(1))
          .onSubmit { m.events.append("replacement") }
      }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.return)
    #expect(m.events == ["inner", "outer"] && !m.present)
    try h.focusValue("second")
    try h.key(.return)
    #expect(m.events == ["inner", "outer", "replacement"])
  }

  @Test func setA1073SheetTeardownCancelsItsTaskAndRestoresLiveInput() async throws {
    // Hypothesis: a modal editor's task outlives its presentation owner and prevents clean input restoration.
    let m = DepthModel()
    let h = try make(1073) {
      TextField("Task background", text: m.text(0))
        .sheet(isPresented: m.flag) {
          TextField("Task modal", text: m.text(1))
            .task {
              m.events.append("started")
              await suspendUntilCancelled()
              m.events.append("cancelled")
            }
        }
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    m.show = true
    try h.refresh()
    try await waitUntil(
      "modal task starts", lastObservation: { "\(m.events)" },
      condition: { m.events == ["started"] })
    try h.key(.escape)
    try await waitUntil(
      "modal task cancels", lastObservation: { "\(m.events)" },
      condition: { m.events.contains("cancelled") })
    #expect(h.loop.lifecycleCoordinator.activeTaskCount == 0)
    try h.paste("X")
    #expect(m.texts == ["abcdefX", "second"])
    #expect(m.events == ["started", "cancelled"])
  }

  @Test func setA1074RejectedClipboardCopyConsumesExitOnlyWhileASelectionExists() throws {
    // Hypothesis: a failed terminal clipboard write lets selected Ctrl+C fall through to session termination.
    let m = DepthModel()
    let h = try make(1074) {
      TextField("Copy before exit", text: m.text(0))
        .environment(
          \.clipboardWriteAction,
          ClipboardWriteAction {
            m.events.append($0)
            return false
          })
    }
    defer { h.shutdown() }
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    try h.key(.character("c"), modifiers: .ctrl)
    #expect(m.events == ["f"] && m.texts[0] == "abcdef")
    #expect(try h.editor().textInput?.selection == 5..<6)
    try h.key(.arrowRight)
    let chord = KeyPress(.character("c"), modifiers: .ctrl)
    let result = h.loop.withRuntimeRegistrationScope { h.loop.handle(.input(.key(chord))) }
    #expect(result == .userExit(chord))
    #expect(m.events == ["f"])
  }

  @Test func setA1075TaskOnlySiblingUpdatePreservesTheEditorsPendingSelection() async throws {
    // Hypothesis: a selective frame initiated by a sibling task loses the focused editor's uncommitted selection.
    let m = DepthModel()
    let gate = DepthGate()
    let h = try make(1075) { DepthTaskSibling(model: m, gate: gate) }
    defer {
      gate.open()
      h.shutdown()
    }
    try await waitUntil(
      "sibling task waits", lastObservation: { "\(m.events)" },
      condition: { m.events.contains("waiting") })
    try h.focusValue("abcdef")
    try h.key(.arrowLeft, modifiers: .shift)
    try h.key(.arrowLeft, modifiers: .shift)
    gate.open()
    try await waitUntil(
      "sibling task writes", lastObservation: { "\(m.events)" },
      condition: { m.events.contains("written") })
    try h.render()
    try #require(h.frame.contains("Async sibling 1"))
    #expect(try h.editor().textInput?.selection == 4..<6)
    try h.paste("X")
    #expect(m.texts[0] == "abcdX")
  }

  private func make<V: View>(_ id: Int, height: Int = 16, @ViewBuilder content: @escaping () -> V)
    throws -> DepthHarness<V>
  {
    try DepthHarness(id: id, size: .init(width: 40, height: height), content: content)
  }
}

@MainActor
private final class DepthModel {
  var texts = ["abcdef", "second"]
  var order = [0, 1]
  var events: [String] = []
  var writes = 0
  var show = false
  var second = false
  var present = true
  var disabled = false
  var height = 1
  var selected: Int?
  var tab = 0
  var path: [Int] = []
  var proxy: ScrollViewProxy?
  func capture(_ proxy: ScrollViewProxy) { self.proxy = proxy }
  func text(_ index: Int) -> Binding<String> {
    Binding(
      get: { self.texts[index] },
      set: {
        self.texts[index] = $0
        self.writes += 1
      })
  }
  var flag: Binding<Bool> { Binding(get: { self.show }, set: { self.show = $0 }) }
  var secondFlag: Binding<Bool> { Binding(get: { self.second }, set: { self.second = $0 }) }
  var selection: Binding<Int?> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
  var tabBinding: Binding<Int> { Binding(get: { self.tab }, set: { self.tab = $0 }) }
  var pathBinding: Binding<[Int]> { Binding(get: { self.path }, set: { self.path = $0 }) }
}

@MainActor
private struct DepthSubmitTransfer: View {
  let model: DepthModel
  @FocusState private var focused: Int?
  var body: some View {
    VStack {
      TextField("Transfer first", text: model.text(0)).focused($focused, equals: 0)
        .onSubmit {
          model.events.append("first")
          focused = 1
        }
      TextField("Transfer second", text: model.text(1)).focused($focused, equals: 1)
        .onSubmit { model.events.append("second") }
    }
  }
}

@MainActor
private struct DepthTaskSibling: View {
  let model: DepthModel
  let gate: DepthGate
  @State private var tick = 0
  var body: some View {
    VStack {
      TextField("Task sibling field", text: model.text(0))
      Text("Async sibling \(tick)").task {
        model.events.append("waiting")
        await gate.wait()
        guard !Task.isCancelled else { return }
        tick += 1
        model.events.append("written")
      }
    }
  }
}

@MainActor
private final class DepthGate {
  private var opened = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if opened { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func open() {
    opened = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class DepthHarness<Content: View> {
  let surface: DepthTerminalSurface
  let loop: SwiftTUIRuntime.RunLoop<Int, Content>
  private let root: Identity
  private var rendered = 0
  init(id: Int, size: CellSize, @ViewBuilder content: @escaping () -> Content) throws {
    root = testIdentity("SetATerminalDepth", "\(id)")
    surface = DepthTerminalSurface(size: size)
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      inputReader: DepthInput(), signalReader: DepthSignals(), scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus,
      viewBuilder: { _, _ in content() })
    focus.invalidator = scheduler
    scheduler.requestInvalidation(of: [root])
    try render()
    loop.renderer.enableSelectiveEvaluation()
  }
  var frame: String { surface.surface?.lines.joined(separator: "\n") ?? "" }
  func render() throws { try loop.renderPendingFrames(renderedFrames: &rendered) }
  func refresh() throws {
    loop.scheduler.requestInvalidation(of: [root])
    try render()
  }
  func shutdown() { loop.lifecycleCoordinator.shutdown() }
  func send(_ event: RuntimeEvent) throws {
    #expect(loop.withRuntimeRegistrationScope { loop.handle(event) } == nil)
    try render()
  }
  func key(_ event: KeyEvent, modifiers: EventModifiers = []) throws {
    try send(.input(.key(.init(event, modifiers: modifiers))))
  }
  func paste(_ text: String) throws { try send(.input(.paste(.init(content: text)))) }
  func mouse(_ kind: MouseEvent.Kind, at point: Point) throws {
    try send(.input(.mouse(.init(kind: kind, location: point))))
  }
  func resize(width: Int, height: Int) throws {
    surface.surfaceSize = .init(width: width, height: height)
    try send(.signal("SIGWINCH"))
  }
  func point(_ text: String) throws -> Point {
    let rows = try #require(surface.surface).lines
    for (y, row) in rows.enumerated() {
      if let range = row.range(of: text) {
        return Point(
          x: Double(row.distance(from: row.startIndex, to: range.lowerBound) + text.count / 2),
          y: Double(y))
      }
    }
    Issue.record("Missing '\(text)' in frame:\n\(frame)")
    throw DepthFixtureError.missing
  }
  func click(_ text: String) throws {
    let location = try point(text)
    try mouse(.down(.primary), at: location)
    try mouse(.up(.primary), at: location)
  }
  func focus(_ node: AccessibilityNode) throws {
    let region = try #require(loop.focusTracker.focusRegions.first { $0.identity == node.identity })
    let changed = loop.focusTracker.setFocus(to: region.identity)
    try #require(changed || loop.focusTracker.currentFocusIdentity == region.identity)
    try render()
  }
  func focusValue(_ value: String) throws {
    let node = try #require(
      loop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.control?.value == .text(value)
      })
    try focus(node)
  }
  func focusText(_ text: String) throws {
    let location = try point(text)
    let region = try #require(
      loop.focusTracker.focusRegions.last { $0.rect.contains(location.containingCell) })
    let changed = loop.focusTracker.setFocus(to: region.identity)
    try #require(changed || loop.focusTracker.currentFocusIdentity == region.identity)
    try render()
  }
  func focusLabel(_ label: String) throws {
    try focus(
      try #require(
        loop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label }))
  }
  func focusedNode() throws -> AccessibilityNode? {
    loop.publishedAccessibilitySnapshot.accessibilityNodes.first {
      $0.identity == loop.focusTracker.currentFocusIdentity
    }
  }
  func editor() throws -> AccessibilityNode {
    try #require(
      loop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .textField || $0.role == .textEditor
      })
  }
}

private enum DepthFixtureError: Error { case missing }

private final class DepthTerminalSurface: PresentationSurface {
  let supportsUserExit = true
  var surfaceSize: CellSize
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var surface: RasterSurface?
  init(size: CellSize) { surfaceSize = size }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}
  func present(_ surface: RasterSurface) throws -> PresentationMetrics {
    self.surface = surface
    return .init(
      linesTouched: surface.size.height, cellsChanged: surface.size.width * surface.size.height)
  }
}
private final class DepthInput: InputReading {
  func events() -> AsyncStream<KeyPress> { AsyncStream { $0.finish() } }
}
private final class DepthSignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}
