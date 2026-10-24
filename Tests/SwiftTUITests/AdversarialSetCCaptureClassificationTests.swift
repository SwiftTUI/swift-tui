@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCCaptureClassificationTests {
  @Test func setC166RetiredFocusCaptureRecordsCensus() throws {
    let log = SetCCaptureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC166"),
      size: .init(width: 30, height: 6)
    ) { SetCCaptureRoot(log: log) }
    defer { h.shutdown() }
    let retired = try #require(log.readFocus)
    _ = try h.focusText("field")
    try #require(retired() == true, "the first owner's field is focused")
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(log.shown).wrappedValue = true
    _ = try h.render()
    let successor = try #require(log.readFocus)
    // Focus returns to the re-minted field (same identity), so the live
    // successor reads true while the retired capture reads its own fallback.
    try #require(successor() == true, "focus is restored to the remounted field")
    StateCaptureCensus.resetForTesting()
    #expect(retired() == false, "retired fallback, not the successor's value")
    #expect(StateCaptureCensus.count(of: .focusRetired) >= 1)
  }

  @Test func setC167UnpreparedGestureStateIsInert() {
    let state = GestureState(initialValue: 3)
    StateCaptureCensus.resetForTesting()
    #expect(state.wrappedValue == 3)
    #expect(StateCaptureCensus.count(of: .gestureUnprepared) >= 1)
    #expect(StateCaptureCensus.count(of: .gestureRetired) == 0)
  }

  @Test func setC168RetainedSubtreeAddsNoBindEvents() throws {
    let log = SetCCaptureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC168"),
      size: .init(width: 30, height: 6)
    ) { SetCCaptureRoot(log: log) }
    defer { h.shutdown() }
    let count = try #require(log.count)
    try #require(h.frame.contains("count 0"))
    let passes = log.bindPasses
    try #require(passes > 0, "the first frame prepares the retained subtree")
    try #require(log.phase).wrappedValue = 1
    _ = try h.render()
    try #require(h.frame.contains("phase 1"))
    #expect(log.bindPasses == passes, "a retained subtree adds no capture pass")
    count.wrappedValue = 5
    _ = try h.render()
    #expect(h.frame.contains("count 5"), "\(h.frame)")
  }

  @Test func setC169BindingOwnershipNotTransferred() throws {
    let log = SetCCaptureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC169"),
      size: .init(width: 30, height: 6)
    ) { SetCCaptureRoot(log: log) }
    defer { h.shutdown() }
    let first = try #require(log.childBinding)
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(log.shown).wrappedValue = true
    _ = try h.render()
    first.wrappedValue = 7
    _ = try h.render()
    #expect(h.frame.contains("parent 7"), "\(h.frame)")
    #expect(h.frame.contains("child 7"), "\(h.frame)")
  }

  @Test func setC170RetainedNamespaceFollowsStatePolicy() throws {
    let log = SetCCaptureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC170"),
      size: .init(width: 30, height: 6)
    ) { SetCCaptureRoot(log: log) }
    defer { h.shutdown() }
    let oldRead = try #require(log.readNamespace)
    let first = oldRead()
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(log.shown).wrappedValue = true
    _ = try h.render()
    let newRead = try #require(log.readNamespace)
    let second = newRead()
    try #require(second != first, "a remounted owner allocates a new namespace id")
    // Predicted retired id did not occur: the retained read refreshes to the
    // live occupant, as the nested State's policy says.
    #expect(oldRead() == second, "old \(oldRead()) first \(first) second \(second)")
  }
}

@MainActor
private final class SetCCaptureLog {
  var shown: Binding<Bool>?
  var phase: Binding<Int>?
  var count: Binding<Int>?
  var childBinding: Binding<Int>?
  var readFocus: (() -> Bool)?
  var readNamespace: (() -> Namespace.ID)?
  var bindPasses = 0
}

/// Counts capture-preparation passes over the subtree that declares it.
private struct SetCBindProbe: DynamicProperty, CaptureBindableDynamicProperty {
  let log: SetCCaptureLog
  mutating func bindCapture(_ context: DynamicPropertyCaptureContext) {
    log.bindPasses += 1
  }
  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult { .unchanged }
}

private struct SetCCaptureRoot: View {
  @State private var shown = true
  @State private var phase = 0
  @State private var parent = 0
  let log: SetCCaptureLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("phase \(phase)")
      Text("parent \(parent)")
      SetCRetainedCounter(log: log).equatable()
      if shown {
        SetCCaptureLeaf(value: $parent, log: log)
      }
    }
  }

  private func capture() {
    log.shown = $shown
    log.phase = $phase
  }
}

private struct SetCRetainedCounter: View, @MainActor Equatable {
  @State private var count = 0
  var probe: SetCBindProbe
  let log: SetCCaptureLog

  init(log: SetCCaptureLog) {
    self.log = log
    probe = SetCBindProbe(log: log)
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.log === rhs.log }

  var body: some View {
    log.count = $count
    return Text("count \(count)")
  }
}

private struct SetCCaptureLeaf: View {
  @FocusState private var focused: Bool
  @Namespace private var namespace
  @State private var draft = ""
  var value: Binding<Int>
  let log: SetCCaptureLog

  var body: some View {
    log.readFocus = { focused }
    log.readNamespace = { namespace }
    log.childBinding = value
    return VStack(alignment: .leading, spacing: 0) {
      TextField("field", text: $draft).focused($focused)
      Text("child \(value.wrappedValue)")
    }
  }
}
