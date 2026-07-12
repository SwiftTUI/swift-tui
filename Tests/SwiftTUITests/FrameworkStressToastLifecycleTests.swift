import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI toast lifecycle stress behavior", .serialized)
struct FrameworkStressToastLifecycleTests {}

@MainActor
private func toastLifecycleEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .filter { $0.kindName == "ToastPresentation" }
    .count
}

// MARK: - Attempt 001: active message refresh

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 001 active message follows source generations")
  func toastLifecycle001ActiveMessageFollowsSourceGenerations() throws {
    // Hypothesis: a stable toast item can retain the first declared Text payload while its source
    // keeps emitting fresh generations under the same portal entry identity.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle001"),
      size: .init(width: 58, height: 10)
    ) {
      ToastLifecycle001Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Advance Toast Message 001")
      #expect(frame.contains("toast message generation \(generation)"))
      #expect(!frame.contains("toast message generation \(generation - 1)"))
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle001Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Toast Message 001") { generation += 1 }
      Text("source generation \(generation)")
    }
    .toast(
      "toast message generation \(generation)",
      isPresented: $isPresented,
      duration: nil
    )
  }
}

// MARK: - Attempt 002: content cardinality replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 002 active content replaces its child cardinality")
  func toastLifecycle002ActiveContentReplacesItsChildCardinality() throws {
    // Hypothesis: a retained ToastContent attachment can preserve the previous one-child or
    // two-child topology even after the source emits a freshly built payload group.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle002"),
      size: .init(width: 62, height: 12)
    ) {
      ToastLifecycle002Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Replace Toast Topology 002")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("compact toast generation \(generation)"))
        #expect(!frame.contains("detail toast generation \(generation)"))
      } else {
        #expect(frame.contains("primary toast generation \(generation)"))
        #expect(frame.contains("detail toast generation \(generation)"))
        #expect(!frame.contains("compact toast generation \(generation)"))
      }
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle002Root: View {
  @State private var generation = 0
  @State private var expanded = false
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Topology 002") {
      generation += 1
      expanded.toggle()
    }
    .toast(isPresented: $isPresented, duration: nil) {
      if expanded {
        VStack(alignment: .leading, spacing: 0) {
          Text("primary toast generation \(generation)")
          Text("detail toast generation \(generation)")
        }
      } else {
        Text("compact toast generation \(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: erased style family replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 003 active toast adopts each replacement style family")
  func toastLifecycle003ActiveToastAdoptsEachReplacementStyleFamily() throws {
    // Hypothesis: AnyToastStyle can retain its first concrete box while the active item keeps the
    // same ID, leaving the toast icon and semantic chrome on the previous style family.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle003"),
      size: .init(width: 56, height: 10)
    ) {
      ToastLifecycle003Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Replace Toast Style 003")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("ℹ"))
        #expect(!frame.contains("✓"))
      } else {
        #expect(frame.contains("✓"))
        #expect(!frame.contains("ℹ"))
      }
      #expect(frame.contains("style family generation \(generation)"))
    }
  }
}

@MainActor
private struct ToastLifecycle003Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Style 003") { generation += 1 }
      .toast(
        "style family generation \(generation)",
        isPresented: $isPresented,
        style: generation.isMultiple(of: 2) ? .info : .success,
        duration: nil
      )
  }
}

// MARK: - Attempt 004: same-type style payload refresh

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 004 active toast refreshes same-type style payload")
  func toastLifecycle004ActiveToastRefreshesSameTypeStylePayload() throws {
    // Hypothesis: type-erased style storage can compare only its concrete type and leave an active
    // toast using the first same-type icon and geometry payload.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle004"),
      size: .init(width: 58, height: 10)
    ) {
      ToastLifecycle004Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Refresh Toast Chrome 004")
      let currentIcon = generation.isMultiple(of: 2) ? "E" : "O"
      let staleIcon = generation.isMultiple(of: 2) ? "O" : "E"
      #expect(frame.contains("\(currentIcon) chrome generation \(generation)"))
      #expect(!frame.contains("\(staleIcon) chrome generation \(generation)"))
    }
  }
}

private struct ToastLifecycle004Style: ToastStyle {
  let generation: Int

  var snapshotLabel: String { "ToastLifecycle004Style" }

  func resolvePresentation(for _: ToastStyleConfiguration) -> ToastStylePresentation {
    ToastStylePresentation(
      icon: generation.isMultiple(of: 2) ? "E" : "O",
      contentPadding: .init(all: 1),
      minWidth: 18,
      maxWidth: 48
    )
  }
}

@MainActor
private struct ToastLifecycle004Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    Button("Refresh Toast Chrome 004") { generation += 1 }
      .toast(
        "chrome generation \(generation)",
        isPresented: $isPresented,
        style: ToastLifecycle004Style(generation: generation),
        duration: nil
      )
  }
}

// MARK: - Attempt 005: active environment capture

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 005 active content reads the current source environment")
  func toastLifecycle005ActiveContentReadsTheCurrentSourceEnvironment() throws {
    // Hypothesis: portal payloads can retain the environment snapshot from activation and keep an
    // active toast reader isolated from later source-environment replacements.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle005"),
      size: .init(width: 60, height: 10)
    ) {
      ToastLifecycle005Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Advance Toast Environment 005")
      #expect(frame.contains("source environment value-\(generation)"))
      #expect(frame.contains("toast environment value-\(generation)"))
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

private enum ToastLifecycleEnvironmentKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var toastLifecycleValue: String {
    get { self[ToastLifecycleEnvironmentKey.self] }
    set { self[ToastLifecycleEnvironmentKey.self] = newValue }
  }
}

@MainActor
private struct ToastLifecycle005Reader: View {
  let prefix: String
  @Environment(\.toastLifecycleValue) private var value

  var body: some View {
    Text("\(prefix) environment \(value)")
  }
}

@MainActor
private struct ToastLifecycle005Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Toast Environment 005") { generation += 1 }
      ToastLifecycle005Reader(prefix: "source")
    }
    .toast(isPresented: $isPresented, duration: nil) {
      ToastLifecycle005Reader(prefix: "toast")
    }
    .environment(\.toastLifecycleValue, "value-\(generation)")
  }
}

// MARK: - Attempt 006: active timer binding retarget

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 006 active timer dismisses the current binding target")
  func toastLifecycle006ActiveTimerDismissesTheCurrentBindingTarget() async throws {
    // Hypothesis: the stable toast task can keep the Binding captured at activation even after the
    // live modifier retargets its dismissal write to a replacement owner.
    let bindingChanges = MainActorConditionSignal()
    let first = ToastLifecycleBox(true, signal: bindingChanges)
    let second = ToastLifecycleBox(true, signal: bindingChanges)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle006"),
      size: .init(width: 64, height: 10)
    ) {
      ToastLifecycle006Root(first: first, second: second)
    }
    defer { harness.shutdown() }

    let retargeted = try harness.clickText("Retarget Toast Binding 006")
    #expect(retargeted.contains("dismiss target second"))

    await bindingChanges.wait {
      !first.value || !second.value
    }
    _ = try harness.render()
    withKnownIssue("Active toast timer retains its activation binding after source retarget") {
      #expect(first.value && !second.value)
    }
  }
}

@MainActor
private final class ToastLifecycleBox<Value> {
  var value: Value {
    didSet { signal?.notify() }
  }
  private(set) var writes: [Value] = []
  private let signal: MainActorConditionSignal?

  init(_ value: Value, signal: MainActorConditionSignal? = nil) {
    self.value = value
    self.signal = signal
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      }
    )
  }
}

@MainActor
private struct ToastLifecycle006Root: View {
  let first: ToastLifecycleBox<Bool>
  let second: ToastLifecycleBox<Bool>
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget Toast Binding 006") { usesSecond = true }
      Text("dismiss target \(usesSecond ? "second" : "first")")
      Text("first \(first.value) second \(second.value)")
    }
    .toast(
      "retargeted timer toast",
      isPresented: usesSecond ? second.binding() : first.binding(),
      duration: 0.08
    )
  }
}

// MARK: - Attempt 007: reminted source timer ownership

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 007 reminted source transfers timer ownership")
  func toastLifecycle007RemintedSourceTransfersTimerOwnership() async throws {
    // Hypothesis: replacing an active toast source with a newly identified source can leave the
    // departed timer alive or fail to start the replacement source's dismissal task.
    let bindingChanges = MainActorConditionSignal()
    let first = ToastLifecycleBox(true, signal: bindingChanges)
    let second = ToastLifecycleBox(true, signal: bindingChanges)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle007"),
      size: .init(width: 66, height: 11)
    ) {
      ToastLifecycle007Root(first: first, second: second)
    }
    defer { harness.shutdown() }

    let replaced = try harness.clickText("Remint Toast Source 007")
    #expect(replaced.contains("replacement timer toast"))
    #expect(!replaced.contains("original timer toast"))

    await bindingChanges.wait {
      !first.value || !second.value
    }
    _ = try harness.render()
    #expect(first.value && !second.value)
    #expect(toastLifecycleEntryCount(in: harness) == 0)
  }
}

@MainActor
private struct ToastLifecycle007Root: View {
  let first: ToastLifecycleBox<Bool>
  let second: ToastLifecycleBox<Bool>
  @State private var usesReplacement = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remint Toast Source 007") { usesReplacement = true }
      if usesReplacement {
        Text("replacement source")
          .id("toast-lifecycle-007-replacement")
          .toast(
            "replacement timer toast",
            isPresented: second.binding(),
            duration: 0.06
          )
      } else {
        Text("original source")
          .id("toast-lifecycle-007-original")
          .toast(
            "original timer toast",
            isPresented: first.binding(),
            duration: 0.06
          )
      }
    }
  }
}

// MARK: - Attempt 008: nil-to-finite duration activation

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 008 finite duration starts after nil duration")
  func toastLifecycle008FiniteDurationStartsAfterNilDuration() async throws {
    // Hypothesis: a nil-duration toast's task completes while its descriptor remains committed, so
    // changing the active item to a finite duration may never start a new timer.
    let presented = ToastLifecycleBox(true)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle008"),
      size: .init(width: 62, height: 10)
    ) {
      ToastLifecycle008Root(presented: presented)
    }
    defer { harness.shutdown() }

    let armed = try harness.clickText("Arm Toast Timer 008")
    #expect(armed.contains("duration armed true"))
    #expect(armed.contains("nil to finite toast"))

    await AsyncEvent.firing(after: .milliseconds(140)).wait()
    _ = try harness.render()
    let dismissed = !presented.value
    withKnownIssue("Finite duration does not restart a completed nil-duration toast task") {
      #expect(dismissed && toastLifecycleEntryCount(in: harness) == 0)
    }
  }
}

@MainActor
private struct ToastLifecycle008Root: View {
  let presented: ToastLifecycleBox<Bool>
  @State private var timerArmed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Arm Toast Timer 008") { timerArmed = true }
      Text("duration armed \(timerArmed)")
    }
    .toast(
      "nil to finite toast",
      isPresented: presented.binding(),
      duration: timerArmed ? 0.05 : nil
    )
  }
}

// MARK: - Attempt 009: finite-to-nil duration cancellation

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 009 nil duration cancels the active deadline")
  func toastLifecycle009NilDurationCancelsTheActiveDeadline() async throws {
    // Hypothesis: replacing a finite duration with nil can update the item without cancelling the
    // already-running task, allowing a retired deadline to dismiss the still-active toast.
    let presented = ToastLifecycleBox(true)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle009"),
      size: .init(width: 62, height: 10)
    ) {
      ToastLifecycle009Root(presented: presented)
    }
    defer { harness.shutdown() }

    let disabled = try harness.clickText("Disable Toast Timer 009")
    #expect(disabled.contains("timer disabled true"))
    await AsyncEvent.firing(after: .milliseconds(140)).wait()
    let frame = try harness.render()

    // Intermittent: under parallel-suite load the 140ms wait can elapse
    // before the finite deadline fires, so the stale-deadline dismissal —
    // the pinned defect — does not always reproduce.
    withKnownIssue("Nil duration does not cancel the toast's active finite deadline", isIntermittent: true) {
      #expect(
        presented.value && frame.contains("finite to nil toast")
          && toastLifecycleEntryCount(in: harness) == 1
      )
    }
  }
}

@MainActor
private struct ToastLifecycle009Root: View {
  let presented: ToastLifecycleBox<Bool>
  @State private var timerDisabled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Disable Toast Timer 009") { timerDisabled = true }
      Text("timer disabled \(timerDisabled)")
    }
    .toast(
      "finite to nil toast",
      isPresented: presented.binding(),
      duration: timerDisabled ? nil : 0.08
    )
  }
}

// MARK: - Attempt 010: shorter replacement deadline

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 010 shorter duration replaces the active deadline")
  func toastLifecycle010ShorterDurationReplacesTheActiveDeadline() async throws {
    // Hypothesis: changing duration does not change the task descriptor, so a one-second timer can
    // survive after the active toast requests a near-immediate replacement deadline.
    let presented = ToastLifecycleBox(true)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle010"),
      size: .init(width: 64, height: 10)
    ) {
      ToastLifecycle010Root(presented: presented)
    }
    defer { harness.shutdown() }

    let shortened = try harness.clickText("Shorten Toast Timer 010")
    #expect(shortened.contains("timer shortened true"))
    await AsyncEvent.firing(after: .milliseconds(140)).wait()
    _ = try harness.render()
    let dismissed = !presented.value

    withKnownIssue("Shorter duration does not replace the toast's active long deadline") {
      #expect(dismissed && toastLifecycleEntryCount(in: harness) == 0)
    }
  }
}

@MainActor
private struct ToastLifecycle010Root: View {
  let presented: ToastLifecycleBox<Bool>
  @State private var timerShortened = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Shorten Toast Timer 010") { timerShortened = true }
      Text("timer shortened \(timerShortened)")
    }
    .toast(
      "long to short toast",
      isPresented: presented.binding(),
      duration: timerShortened ? 0.04 : 1.0
    )
  }
}

// MARK: - Attempt 011: longer replacement deadline

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 011 longer duration retires the earlier deadline")
  func toastLifecycle011LongerDurationRetiresTheEarlierDeadline() async throws {
    // Hypothesis: extending an active toast can update the item payload without cancelling the
    // short timer that was started by its activation generation.
    let presented = ToastLifecycleBox(true)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle011"),
      size: .init(width: 64, height: 10)
    ) {
      ToastLifecycle011Root(presented: presented)
    }
    defer { harness.shutdown() }

    let extended = try harness.clickText("Extend Toast Timer 011")
    #expect(extended.contains("timer extended true"))
    await AsyncEvent.firing(after: .milliseconds(150)).wait()
    let frame = try harness.render()

    // Under a contended executor the stale short task can be scheduled after this probe, so the
    // defect is observable but not guaranteed to reproduce in every parallel suite run.
    withKnownIssue(
      "Longer duration does not retire the toast's active short deadline",
      isIntermittent: true
    ) {
      #expect(
        presented.value && frame.contains("short to long toast")
          && toastLifecycleEntryCount(in: harness) == 1
      )
    }
  }
}

@MainActor
private struct ToastLifecycle011Root: View {
  let presented: ToastLifecycleBox<Bool>
  @State private var timerExtended = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Extend Toast Timer 011") { timerExtended = true }
      Text("timer extended \(timerExtended)")
    }
    .toast(
      "short to long toast",
      isPresented: presented.binding(),
      duration: timerExtended ? 1.0 : 0.08
    )
  }
}

// MARK: - Attempt 012: close before deadline then reopen

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 012 manual close cancels the retired deadline before reopen")
  func toastLifecycle012ManualCloseCancelsRetiredDeadlineBeforeReopen() async throws {
    // Hypothesis: closing a toast and reopening the same source can leave the first generation's
    // short deadline alive to dismiss the replacement generation prematurely.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle012"),
      size: .init(width: 66, height: 11)
    ) {
      ToastLifecycle012Root()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Close Toast 012")
    #expect(!frame.contains("close reopen toast"))
    frame = try harness.clickText("Reopen Long Toast 012")
    #expect(frame.contains("close reopen toast"))

    await AsyncEvent.firing(after: .milliseconds(150)).wait()
    frame = try harness.render()
    #expect(frame.contains("close reopen toast"))
    #expect(toastLifecycleEntryCount(in: harness) == 1)
  }
}

@MainActor
private struct ToastLifecycle012Root: View {
  @State private var isPresented = true
  @State private var usesLongDeadline = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Close Toast 012") { isPresented = false }
      Button("Reopen Long Toast 012") {
        usesLongDeadline = true
        isPresented = true
      }
    }
    .toast(
      "close reopen toast",
      isPresented: $isPresented,
      duration: usesLongDeadline ? 1.0 : 0.08
    )
  }
}

// MARK: - Attempt 013: repeated automatic dismissal

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 013 reopening a dismissed source starts a fresh timer")
  func toastLifecycle013ReopeningDismissedSourceStartsFreshTimer() async throws {
    // Hypothesis: after auto-dismiss completes and removes the portal row, reopening the same
    // declaration can reuse completed lifecycle metadata without starting another timer.
    let bindingChanges = MainActorConditionSignal()
    let presented = ToastLifecycleBox(false, signal: bindingChanges)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle013"),
      size: .init(width: 64, height: 10)
    ) {
      ToastLifecycle013Root(presented: presented)
    }
    defer { harness.shutdown() }

    for cycle in 1...3 {
      let shown = try harness.clickText("Show Timed Toast 013")
      #expect(shown.contains("reopen timer toast cycle \(cycle)"))
      await bindingChanges.wait { !presented.value }
      let dismissed = try harness.render()
      #expect(!dismissed.contains("reopen timer toast"))
      #expect(toastLifecycleEntryCount(in: harness) == 0)
    }
  }
}

@MainActor
private struct ToastLifecycle013Root: View {
  let presented: ToastLifecycleBox<Bool>
  @State private var cycle = 0

  var body: some View {
    Button("Show Timed Toast 013") {
      cycle += 1
      presented.value = true
    }
    .toast(
      "reopen timer toast cycle \(cycle)",
      isPresented: presented.binding(),
      duration: 0.04
    )
  }
}

// MARK: - Attempt 014: source subtree teardown

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 014 removing the source prunes its entry and timer")
  func toastLifecycle014RemovingSourcePrunesEntryAndTimer() throws {
    // Hypothesis: direct toast declarations can survive source-subtree removal because they have no
    // presentation trigger leaf to report the departed emitter.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle014"),
      size: .init(width: 62, height: 10)
    ) {
      ToastLifecycle014Root()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("removed source toast"))
    #expect(toastLifecycleEntryCount(in: harness) == 1)
    #expect(harness.activeTaskCount == 1)

    let removed = try harness.clickText("Remove Toast Source 014")
    #expect(removed.contains("toast source removed"))
    #expect(!removed.contains("removed source toast"))
    #expect(toastLifecycleEntryCount(in: harness) == 0)
    #expect(harness.activeTaskCount == 0)
    #expect(harness.activeTaskDescriptorCount == 0)
  }
}

@MainActor
private struct ToastLifecycle014Root: View {
  @State private var includesSource = true
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove Toast Source 014") { includesSource = false }
      if includesSource {
        Text("active toast source")
          .toast("removed source toast", isPresented: $isPresented, duration: 1.0)
      } else {
        Text("toast source removed")
      }
    }
  }
}

// MARK: - Attempt 015: sibling toast stacking order

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 015 sibling toasts stack in activation order")
  func toastLifecycle015SiblingToastsStackInActivationOrder() throws {
    // Hypothesis: coordinator reconciliation across independently invalidated sources can collapse
    // the older toast or reverse the family's activation ordering.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle015"),
      size: .init(width: 64, height: 14)
    ) {
      ToastLifecycle015Root()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Show Older Toast 015")
    let frame = try harness.clickText("Show Newer Toast 015")

    #expect(
      toastLifecycleContainsInOrder(
        ["older sibling toast", "newer sibling toast"],
        in: frame
      )
    )
    #expect(toastLifecycleEntryCount(in: harness) == 1)
  }
}

private func toastLifecycleContainsInOrder(_ tokens: [String], in frame: String) -> Bool {
  var cursor = frame.startIndex
  for token in tokens {
    guard let range = frame.range(of: token, range: cursor..<frame.endIndex) else {
      return false
    }
    cursor = range.upperBound
  }
  return true
}

@MainActor
private struct ToastLifecycle015Root: View {
  @State private var older = false
  @State private var newer = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Show Older Toast 015") { older = true }
        .toast("older sibling toast", isPresented: $older, duration: nil)
      Button("Show Newer Toast 015") { newer = true }
        .toast("newer sibling toast", isPresented: $newer, duration: nil)
    }
  }
}

// MARK: - Attempt 016: partial stack dismissal

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 016 dismissing the older toast preserves the newer item")
  func toastLifecycle016DismissingOlderToastPreservesNewerItem() throws {
    // Hypothesis: syncing one source to an empty item set can clear the whole family store instead
    // of removing only that source's tracked toast.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle016"),
      size: .init(width: 64, height: 14)
    ) {
      ToastLifecycle016Root()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("older removable toast"))
    #expect(harness.frame.contains("newer surviving toast"))
    let frame = try harness.clickText("Dismiss Older Toast 016")

    #expect(!frame.contains("older removable toast"))
    #expect(frame.contains("newer surviving toast"))
    #expect(toastLifecycleEntryCount(in: harness) == 1)
  }
}

@MainActor
private struct ToastLifecycle016Root: View {
  @State private var older = true
  @State private var newer = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Dismiss Older Toast 016") { older = false }
      Text("older source")
        .toast("older removable toast", isPresented: $older, duration: nil)
      Text("newer source")
        .toast("newer surviving toast", isPresented: $newer, duration: nil)
    }
  }
}

// MARK: - Attempt 017: source reorder identity

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 017 reordered sources preserve toast identity and order")
  func toastLifecycle017ReorderedSourcesPreserveToastIdentityAndOrder() throws {
    // Hypothesis: declarative toast storage can follow structural source order rather than ForEach
    // entity identity, duplicating items or exchanging their activation ordinals after reorder.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle017"),
      size: .init(width: 66, height: 15)
    ) {
      ToastLifecycle017Root()
    }
    defer { harness.shutdown() }

    for _ in 1...10 {
      let frame = try harness.clickText("Reverse Toast Sources 017")
      #expect(
        toastLifecycleContainsInOrder(
          ["identity toast alpha", "identity toast beta"],
          in: frame
        )
      )
      #expect(frame.components(separatedBy: "identity toast alpha").count - 1 == 1)
      #expect(frame.components(separatedBy: "identity toast beta").count - 1 == 1)
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

private struct ToastLifecycle017Item: Identifiable {
  let id: String
}

@MainActor
private struct ToastLifecycle017Root: View {
  @State private var reversed = false

  private var items: [ToastLifecycle017Item] {
    let source = ["alpha", "beta"].map(ToastLifecycle017Item.init(id:))
    return reversed ? Array(source.reversed()) : source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse Toast Sources 017") { reversed.toggle() }
      ForEach(items) { item in
        Text("source \(item.id)")
          .toast(
            "identity toast \(item.id)",
            isPresented: .constant(true),
            duration: nil
          )
      }
    }
  }
}

// MARK: - Attempt 018: simultaneous activation order

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 018 simultaneous activation has stable source order")
  func toastLifecycle018SimultaneousActivationHasStableSourceOrder() throws {
    // Hypothesis: rebuilding the family store from multiple newly active declarations can depend on
    // dictionary iteration and change the visible stacking order across activation cycles.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle018"),
      size: .init(width: 66, height: 15)
    ) {
      ToastLifecycle018Root()
    }
    defer { harness.shutdown() }

    for cycle in 1...8 {
      let frame = try harness.clickText("Open Toast Pair 018")
      #expect(
        toastLifecycleContainsInOrder(
          ["simultaneous first \(cycle)", "simultaneous second \(cycle)"],
          in: frame
        )
      )
      #expect(toastLifecycleEntryCount(in: harness) == 1)

      let closed = try harness.clickText("Close Toast Pair 018")
      #expect(!closed.contains("simultaneous first"))
      #expect(!closed.contains("simultaneous second"))
      #expect(toastLifecycleEntryCount(in: harness) == 0)
    }
  }
}

@MainActor
private struct ToastLifecycle018Root: View {
  @State private var first = false
  @State private var second = false
  @State private var cycle = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open Toast Pair 018") {
        cycle += 1
        first = true
        second = true
      }
      Button("Close Toast Pair 018") {
        first = false
        second = false
      }
      Text("first source")
        .toast("simultaneous first \(cycle)", isPresented: $first, duration: nil)
      Text("second source")
        .toast("simultaneous second \(cycle)", isPresented: $second, duration: nil)
    }
  }
}

// MARK: - Attempt 019: active source remint cardinality

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 019 reminting the active source keeps one live item")
  func toastLifecycle019RemintingActiveSourceKeepsOneLiveItem() throws {
    // Hypothesis: a newly minted source can be synchronized before the prior source is pruned,
    // leaving both generations visible or retaining the departed payload.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle019"),
      size: .init(width: 66, height: 12)
    ) {
      ToastLifecycle019Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Remint Active Toast 019")
      #expect(frame.contains("reminted toast generation \(generation)"))
      #expect(!frame.contains("reminted toast generation \(generation - 1)"))
      #expect(frame.components(separatedBy: "reminted toast generation").count - 1 == 1)
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle019Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remint Active Toast 019") { generation += 1 }
      Text("reminted source \(generation)")
        .id("toast-lifecycle-019-source-\(generation)")
        .toast(
          "reminted toast generation \(generation)",
          isPresented: .constant(true),
          duration: nil
        )
    }
  }
}

// MARK: - Attempt 020: chained modifier coexistence

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 020 chained toast modifiers keep independent items")
  func toastLifecycle020ChainedToastModifiersKeepIndependentItems() throws {
    // Hypothesis: two toast modifiers attached to one authored source can publish the same source
    // identity and portal token, causing the later declaration to overwrite the earlier item.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle020"),
      size: .init(width: 68, height: 15)
    ) {
      ToastLifecycle020Root()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      let frame = try harness.clickText("Refresh Chained Toasts 020")
      #expect(frame.contains("outer chained toast \(generation)"))
      withKnownIssue("Chained toast modifiers overwrite the inner item for one source identity") {
        #expect(
          frame.contains("inner chained toast \(generation)")
            && frame.components(separatedBy: "chained toast").count - 1 == 2
        )
      }
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle020Root: View {
  @State private var generation = 0
  @State private var inner = true
  @State private var outer = true

  var body: some View {
    Button("Refresh Chained Toasts 020") { generation += 1 }
      .toast(
        "inner chained toast \(generation)",
        isPresented: $inner,
        duration: nil
      )
      .toast(
        "outer chained toast \(generation)",
        isPresented: $outer,
        duration: nil
      )
  }
}

// MARK: - Attempt 021: nonmodal base interaction

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 021 active toast preserves base interaction routing")
  func toastLifecycle021ActiveToastPreservesBaseInteractionRouting() throws {
    // Hypothesis: repeated portal refresh can accidentally promote toast interaction gating to the
    // family overlay root and suppress actions in the underlying base tree.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle021"),
      size: .init(width: 66, height: 12)
    ) {
      ToastLifecycle021Root()
    }
    defer { harness.shutdown() }

    for count in 1...12 {
      let frame = try harness.clickText("Activate Base Under Toast 021")
      #expect(frame.contains("base activation count \(count)"))
      #expect(frame.contains("nonmodal interaction toast"))
      #expect(harness.actionRegistrationCount == 1)
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle021Root: View {
  @State private var count = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Activate Base Under Toast 021") { count += 1 }
      Text("base activation count \(count)")
    }
    .toast("nonmodal interaction toast", isPresented: $isPresented, duration: nil)
  }
}

// MARK: - Attempt 022: repeated focus neutrality

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 022 repeated activation never steals base focus")
  func toastLifecycle022RepeatedActivationNeverStealsBaseFocus() throws {
    // Hypothesis: repeated nonmodal overlay insertion can still perturb focus-region ordering or
    // push a toast attachment identity into the modal restoration path.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle022"),
      size: .init(width: 66, height: 12)
    ) {
      ToastLifecycle022Root()
    }
    defer { harness.shutdown() }

    let expectedFocus = try harness.focusIdentity(forText: "Focus Target 022")
    _ = try harness.focus(expectedFocus)
    let baselineRegions = harness.focusRegionCount

    for cycle in 1...12 {
      let frame = try harness.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == expectedFocus)
      #expect(harness.focusRegionCount == baselineRegions)
      #expect(harness.focusModalRestorationStackCount == 0)
      #expect(toastLifecycleEntryCount(in: harness) == (cycle.isMultiple(of: 2) ? 0 : 1))
      #expect(frame.contains("focus neutral toast") == !cycle.isMultiple(of: 2))
    }
  }
}

@MainActor
private struct ToastLifecycle022Root: View {
  @State private var isPresented = false

  var body: some View {
    Panel(id: "toast-lifecycle-022-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Focus Target 022") {}
        Button("Toggle Focus Toast 022") { isPresented.toggle() }
      }
    }
    .keyCommand("Toggle Focus Toast 022", key: .character("t"), modifiers: .ctrl) {
      isPresented.toggle()
    }
    .toast("focus neutral toast", isPresented: $isPresented, duration: nil)
  }
}

// MARK: - Attempt 023: content lifecycle pairing

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 023 content lifecycle pairs once per activation")
  func toastLifecycle023ContentLifecyclePairsOncePerActivation() throws {
    // Hypothesis: force-refreshing toast attachment payloads can duplicate appear handlers, miss a
    // disappear, or retain a previous activation's lifecycle closure.
    let probe = ToastLifecycleEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle023"),
      size: .init(width: 66, height: 12)
    ) {
      ToastLifecycle023Root(probe: probe)
    }
    defer { harness.shutdown() }

    for cycle in 1...10 {
      _ = try harness.clickText("Open Lifecycle Toast 023")
      #expect(probe.events.last == "appear-\(cycle)")
      #expect(harness.lifecycleRegistrationCount == 2)

      _ = try harness.clickText("Close Lifecycle Toast 023")
      #expect(probe.events.suffix(2) == ["appear-\(cycle)", "disappear-\(cycle)"])
      #expect(probe.events.count == cycle * 2)
      #expect(harness.lifecycleRegistrationCount == 0)
    }
  }
}

@MainActor
private final class ToastLifecycleEventProbe {
  var events: [String] = []
  var taskStarts = 0 {
    didSet { taskChanges.notify() }
  }
  var taskCancellations = 0 {
    didSet { taskChanges.notify() }
  }
  let taskChanges = MainActorConditionSignal()
}

@MainActor
private struct ToastLifecycle023Content: View {
  let cycle: Int
  let probe: ToastLifecycleEventProbe

  var body: some View {
    Text("lifecycle toast cycle \(cycle)")
      .onAppear { probe.events.append("appear-\(cycle)") }
      .onDisappear { probe.events.append("disappear-\(cycle)") }
  }
}

@MainActor
private struct ToastLifecycle023Root: View {
  let probe: ToastLifecycleEventProbe
  @State private var isPresented = false
  @State private var cycle = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open Lifecycle Toast 023") {
        cycle += 1
        isPresented = true
      }
      Button("Close Lifecycle Toast 023") { isPresented = false }
    }
    .toast(isPresented: $isPresented, duration: nil) {
      ToastLifecycle023Content(cycle: cycle, probe: probe)
    }
  }
}

// MARK: - Attempt 024: content task cancellation and restart

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 024 content task cancels and restarts with each item")
  func toastLifecycle024ContentTaskCancelsAndRestartsWithEachItem() async throws {
    // Hypothesis: portal row reuse can keep a toast content task alive after close or suppress the
    // next activation's task start because its descriptor matches the departed item.
    let probe = ToastLifecycleEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle024"),
      size: .init(width: 66, height: 12)
    ) {
      ToastLifecycle024Root(probe: probe)
    }
    defer { harness.shutdown() }

    for cycle in 1...6 {
      _ = try harness.clickText("Open Task Toast 024")
      await probe.taskChanges.wait {
        probe.taskStarts == cycle
      }
      _ = try harness.render()
      #expect(harness.activeTaskCount == 1)

      _ = try harness.clickText("Close Task Toast 024")
      await probe.taskChanges.wait {
        probe.taskCancellations == cycle
      }
      _ = try harness.render()
      #expect(harness.activeTaskCount == 0)
      #expect(harness.activeTaskDescriptorCount == 0)
    }
  }
}

@MainActor
private struct ToastLifecycle024Content: View {
  let cycle: Int
  let probe: ToastLifecycleEventProbe

  var body: some View {
    Text("task toast cycle \(cycle)")
      .task {
        probe.taskStarts += 1
        while !Task.isCancelled {
          await Task.yield()
        }
        probe.taskCancellations += 1
      }
  }
}

@MainActor
private struct ToastLifecycle024Root: View {
  let probe: ToastLifecycleEventProbe
  @State private var isPresented = false
  @State private var cycle = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open Task Toast 024") {
        cycle += 1
        isPresented = true
      }
      Button("Close Task Toast 024") { isPresented = false }
    }
    .toast(isPresented: $isPresented, duration: nil) {
      ToastLifecycle024Content(cycle: cycle, probe: probe)
    }
  }
}

// MARK: - Attempt 025: mixed topology teardown bounds

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 025 mixed remint and cardinality churn stays bounded")
  func toastLifecycle025MixedRemintAndCardinalityChurnStaysBounded() throws {
    // Hypothesis: alternating source remint with one-to-two toast cardinality can strand portal
    // timers or lifecycle registrations that survive the family's final teardown.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle025"),
      size: .init(width: 70, height: 16)
    ) {
      ToastLifecycle025Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Churn Toast Topology 025")
      let expectedItems = generation.isMultiple(of: 2) ? 1 : 2
      #expect(frame.contains("primary churn toast \(generation)"))
      #expect(
        frame.contains("secondary churn toast \(generation)") == !generation.isMultiple(of: 2)
      )
      #expect(toastLifecycleEntryCount(in: harness) == 1)
      #expect(harness.activeTaskCount == expectedItems)
      #expect(harness.activeTaskDescriptorCount == expectedItems)
      #expect(harness.lifecycleRegistrationCount == expectedItems * 2)
    }

    let closed = try harness.clickText("Close All Toasts 025")
    #expect(!closed.contains("churn toast"))
    #expect(toastLifecycleEntryCount(in: harness) == 0)
    #expect(harness.activeTaskCount == 0)
    #expect(harness.activeTaskDescriptorCount == 0)
    #expect(harness.lifecycleRegistrationCount == 0)
  }
}

@MainActor
private struct ToastLifecycle025Content: View {
  let label: String

  var body: some View {
    Text(label)
      .onAppear {}
      .onDisappear {}
  }
}

@MainActor
private struct ToastLifecycle025Root: View {
  @State private var generation = 0
  @State private var primary = true
  @State private var secondary = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Churn Toast Topology 025") {
        generation += 1
        secondary.toggle()
      }
      Button("Close All Toasts 025") {
        primary = false
        secondary = false
      }
      Text("primary source \(generation)")
        .id("toast-lifecycle-025-primary-\(generation % 2)")
        .toast(isPresented: $primary, duration: 10.0) {
          ToastLifecycle025Content(label: "primary churn toast \(generation)")
        }
      Text("secondary source \(generation)")
        .toast(isPresented: $secondary, duration: 10.0) {
          ToastLifecycle025Content(label: "secondary churn toast \(generation)")
        }
    }
  }
}
