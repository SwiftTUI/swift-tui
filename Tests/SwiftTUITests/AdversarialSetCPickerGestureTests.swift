@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCPickerGestureTests {
  @Test func setC145MenuBatchDownDownExpandsAndSteps() throws {
    let box = SetCPickerBox()
    let h = try SetCPickerFixture.collapsedMenu(box, name: "setC145")
    defer { h.shutdown() }
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    _ = try h.render()
    #expect(box.selection == .normal, "\(h.frame)")
    #expect(h.frame.contains("High"), "menu must be expanded: \(h.frame)")
  }

  @Test func setC146MenuBatchDownEscapeCollapses() throws {
    let box = SetCPickerBox()
    let h = try SetCPickerFixture.collapsedMenu(box, name: "setC146")
    defer { h.shutdown() }
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    #expect(h.runLoop.handleKeyPress(KeyPress(.escape)) == nil)
    _ = try h.render()
    #expect(box.selection == .low)
    #expect(!h.frame.contains("High"), "menu must be collapsed: \(h.frame)")
  }

  @Test func setC147MenuBatchedOptionClickSelectsAndCollapses() throws {
    let box = SetCPickerBox()
    let h = try SetCPickerFixture.focusedMenu(box, name: "setC147")
    defer { h.shutdown() }
    try #require(h.frame.contains("High"), "menu expands on focus: \(h.frame)")
    let option = try #require(h.point(forText: "Normal"))
    #expect(
      h.runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: option))))
        == nil)
    #expect(
      h.runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: option)))) == nil
    )
    _ = try h.render()
    #expect(box.selection == .normal)
    #expect(!h.frame.contains("High"), "menu must collapse after a selection: \(h.frame)")
  }

  @Test func setC148MenuBatchTriggerClickTwiceNetsCollapsed() throws {
    let box = SetCPickerBox()
    let h = try SetCPickerFixture.collapsedMenu(box, name: "setC148")
    defer { h.shutdown() }
    let trigger = try #require(h.point(forText: "▾"), "\(h.frame)")
    for _ in 0..<2 {
      #expect(
        h.runLoop.handle(
          RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: trigger))))
          == nil)
      #expect(
        h.runLoop.handle(
          RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: trigger))))
          == nil)
    }
    _ = try h.render()
    #expect(box.selection == .low)
    #expect(!h.frame.contains("High"), "two toggles net to collapsed: \(h.frame)")
  }

  @Test func setC149MenuBatchDownDownEscapeKeepsSelection() throws {
    let box = SetCPickerBox()
    let h = try SetCPickerFixture.collapsedMenu(box, name: "setC149")
    defer { h.shutdown() }
    for key in [KeyPress(.arrowDown), KeyPress(.arrowDown), KeyPress(.escape)] {
      #expect(h.runLoop.handleKeyPress(key) == nil)
    }
    _ = try h.render()
    #expect(box.selection == .normal)
    #expect(!h.frame.contains("High"), "collapsed after Escape: \(h.frame)")
  }

  @Test func setC150AutomaticBatchDownDownStepsTwice() throws {
    let box = SetCPickerBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC150"),
      size: .init(width: 30, height: 8)
    ) { SetCPickerFixture.picker(box, menu: false) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    #expect(h.runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    _ = try h.render()
    #expect(box.selection == .high, "\(h.frame)")
  }

  @Test func setC151OnChangedFiresAfterOnEnded() throws {
    let log = SetCGestureLog()
    let recognizer = try SetCGestureFixture.endedComposite(log, name: "setC151")
    let changesAtEnd = log.changes.count
    _ = recognizer.handle(event: SetCGestureFixture.event(.dragged(.primary), x: 3))
    _ = recognizer.handle(event: SetCGestureFixture.event(.dragged(.primary), x: 6))
    // Predicted post-terminal onChanged did not occur: the ended composite's
    // value no longer changes while the drag sibling keeps handling events.
    #expect(log.changes.count == changesAtEnd, "\(log.changes)")
    recognizer.tearDown()
  }

  @Test func setC152OnEndedFiresOnce() throws {
    let log = SetCGestureLog()
    let recognizer = try SetCGestureFixture.endedComposite(log, name: "setC152")
    _ = recognizer.handle(event: SetCGestureFixture.event(.dragged(.primary), x: 3))
    _ = recognizer.replay(events: [SetCGestureFixture.event(.dragged(.primary), x: 4)])
    if let last = log.deadlines.max() {
      _ = recognizer.handleDeadline(at: last.advanced(by: .seconds(1)))
    }
    _ = recognizer.handle(event: SetCGestureFixture.event(.up(.primary), x: 6))
    #expect(log.ended == 1)
    recognizer.tearDown()
  }
}

private enum SetCPriority: String, CaseIterable, Hashable, Sendable {
  case low = "Low"
  case normal = "Normal"
  case high = "High"
}

@MainActor
private final class SetCPickerBox {
  var selection = SetCPriority.low
  var binding: Binding<SetCPriority> {
    .init(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
private enum SetCPickerFixture {
  @ViewBuilder
  static func picker(_ box: SetCPickerBox, menu: Bool) -> some View {
    let picker = Picker("Priority", selection: box.binding) {
      ForEach(SetCPriority.allCases, id: \.self) { option in
        Text(option.rawValue).tag(option)
      }
    }
    if menu {
      picker.pickerStyle(.menu)
    } else {
      picker.pickerStyle(.automatic)
    }
  }

  /// A focused menu picker: the menu expands on focus by default.
  static func focusedMenu(_ box: SetCPickerBox, name: String) throws -> StressRuntimeHarness<
    some View
  > {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 30, height: 8)
    ) { picker(box, menu: true) }
    _ = try h.pressKey(.init(.tab))
    return h
  }

  /// A focused menu picker collapsed by one Escape, so the next arrow expands it.
  static func collapsedMenu(_ box: SetCPickerBox, name: String) throws -> StressRuntimeHarness<
    some View
  > {
    let h = try focusedMenu(box, name: name)
    _ = try h.pressKey(.init(.escape))
    try #require(!h.frame.contains("High"), "collapsed precondition: \(h.frame)")
    try #require(h.frame.contains("Low"), "collapsed trigger shows the selection: \(h.frame)")
    return h
  }
}

@MainActor
private final class SetCGestureLog {
  var changes: [Double] = []
  var ended = 0
  var deadlines: [MonotonicInstant] = []
}

@MainActor
private enum SetCGestureFixture {
  static func event(_ kind: LocalPointerEvent.Kind, x: Double) -> LocalPointerEvent {
    .init(
      kind: kind,
      location: Point(x: x, y: 0),
      targetRect: CellRect(origin: .zero, size: CellSize(width: 12, height: 1))
    )
  }

  /// A long press simultaneous with a drag, mapped to the drag's horizontal
  /// translation, pressed and then completed at the long-press deadline so the
  /// composite has ended while the drag sibling is still live (STUI-1117).
  static func endedComposite(_ log: SetCGestureLog, name: String) throws -> AnyGestureRecognizer {
    let context = GestureRecognizerBuildContext(
      attachingIdentity: Identity(components: [IdentityComponent(rawValue: name)]),
      gestureStateRegistry: nil,
      requestDeadline: { log.deadlines.append($0) }
    )
    let gesture = LongPressGesture(minimumDuration: .milliseconds(50))
      .simultaneously(with: DragGesture())
      .map { $0.second?.translation.dx ?? 0 }
      .onChanged { log.changes.append($0) }
      .onEnded { _ in log.ended += 1 }
    let recognizer = gesture._makeRecognizer(context: context)
    _ = recognizer.handle(event: event(.down(.primary), x: 0))
    let deadline = try #require(log.deadlines.min())
    _ = recognizer.handleDeadline(at: deadline)
    try #require(recognizer.phase.isTerminal, "the composite must end at the long-press deadline")
    try #require(log.ended == 1)
    return recognizer
  }
}
