import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI input-routing stress behavior", .serialized)
struct FrameworkStressInputRoutingTests {}

@MainActor
private final class StressInputBox<Value> {
  var value: Value
  var writeCount = 0

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writeCount += 1
      }
    )
  }
}

// MARK: - Attempt 001: consecutive self-disabling focus targets

extension FrameworkStressInputRoutingTests {
  @Test("Tab continues past two focus targets disabled by the landing transition")
  func stressInputRouting001TabContinuesPastConsecutiveDisabledTargets() throws {
    // Hypothesis: focus convergence may lose its pending traversal after the
    // first landing disables both that region and its immediate successor.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput001Root"),
      size: .init(width: 36, height: 10)
    ) {
      StressInput001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Focus A")
    _ = try harness.pressKey(KeyPress(.tab))

    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity
        == (try harness.focusIdentity(forText: "Focus D"))
    )
  }
}

// MARK: - Attempt 006: stable non-Hashable FocusedValue convergence

extension FrameworkStressInputRoutingTests {
  @Test("A stable non-Hashable FocusedValue converges under repeated renders")
  func stressInputRouting006StableNonHashableFocusedValueConverges() throws {
    // Hypothesis: conservative focused-value equality may treat an unchanged
    // non-Hashable payload as new forever and exhaust the focus-sync budget.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput006Root"),
      size: .init(width: 40, height: 8)
    ) {
      StressInput006Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Stable nonhashable focus")
    for _ in 0..<8 {
      _ = try harness.render()
      #expect(harness.focusedValueRegistrationCount == 1)
    }
  }
}

private struct StressInput006Payload: Equatable, Sendable {
  var label: String
  var revision: Int
}

private enum StressInput006FocusedKey: FocusedValueKey {
  typealias Value = StressInput006Payload
}

extension FocusedValues {
  fileprivate var stressInput006Payload: StressInput006Payload? {
    get { self[StressInput006FocusedKey.self] }
    set { self[StressInput006FocusedKey.self] = newValue }
  }
}

private struct StressInput006Fixture: View {
  static let focusIdentity = testIdentity("StressInput006", "Focus")

  var body: some View {
    Text("Stable nonhashable focus")
      .id(Self.focusIdentity)
      .focusable()
      .focusedValue(
        \.stressInput006Payload,
        StressInput006Payload(label: "stable", revision: 7)
      )
  }
}

// MARK: - Attempt 007: conditional focused-value key removal

extension FrameworkStressInputRoutingTests {
  @Test("Removing focused-value key B clears B while preserving sibling key A")
  func stressInputRouting007ConditionalFocusedValueKeyIsRemovedPrecisely() throws {
    // Hypothesis: same-identity focused-value restoration may merge a departed
    // conditional key back into the live registration that still publishes A.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput007Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressInput007Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput007Fixture.focusIdentity)
    var values = harness.runLoop.localFocusedValuesRegistry.focusedValues(
      for: StressInput007Fixture.focusIdentity
    )
    #expect(values.stressInput007A == "A")
    #expect(values.stressInput007B == "B")

    _ = try harness.clickText("Remove focused B")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput007Fixture.focusIdentity)
    _ = try harness.render()
    values = harness.runLoop.localFocusedValuesRegistry.focusedValues(
      for: StressInput007Fixture.focusIdentity
    )

    #expect(values.stressInput007A == "A")
    #expect(values.stressInput007B == nil)
  }
}

private enum StressInput007AKey: FocusedValueKey {
  typealias Value = String
}

private enum StressInput007BKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var stressInput007A: String? {
    get { self[StressInput007AKey.self] }
    set { self[StressInput007AKey.self] = newValue }
  }

  fileprivate var stressInput007B: String? {
    get { self[StressInput007BKey.self] }
    set { self[StressInput007BKey.self] = newValue }
  }
}

private struct StressInput007Fixture: View {
  static let focusIdentity = testIdentity("StressInput007", "Focus")

  @State private var includesB = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove focused B") { includesB = false }
      if includesB {
        Text("Focused A and B")
          .id(Self.focusIdentity)
          .focusable()
          .focusedValue(\.stressInput007A, "A")
          .focusedValue(\.stressInput007B, "B")
      } else {
        Text("Focused A only")
          .id(Self.focusIdentity)
          .focusable()
          .focusedValue(\.stressInput007A, "A")
      }
    }
  }
}

// MARK: - Attempt 008: pending resetFocus namespace teardown

extension FrameworkStressInputRoutingTests {
  @Test("Registry reset discards resetFocus requests owned by the departed namespace")
  func stressInputRouting008DefaultFocusResetRequestDiesWithNamespace() throws {
    // Hypothesis: LocalDefaultFocusRegistry.reset clears registrations but
    // leaves pendingResetNamespace armed, allowing a later namespace reuse to
    // receive a reset request issued by a departed scope.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput008Root"),
      size: .init(width: 20, height: 4)
    ) {
      EmptyView()
    }
    defer { harness.shutdown() }

    let namespace = MatchedGeometryNamespace(8)
    let candidate = testIdentity("StressInput008", "Candidate")
    let registry = harness.runLoop.localDefaultFocusRegistry
    registry.requestReset(in: namespace)
    registry.reset()
    registry.registerCandidate(namespace: namespace, identity: candidate)
    let region = FocusRegion(
      identity: candidate,
      rect: CellRect(
        origin: CellPoint(x: 0, y: 0),
        size: CellSize(width: 1, height: 1)
      ),
      focusInteractions: .automatic,
      scopePath: [],
      sectionIdentity: nil
    )

    withKnownIssue("A reset default-focus namespace request survives registry reset") {
      #expect(
        registry.desiredFocusRequest(
          focusRegions: [region],
          shouldApplyInitialDefault: false
        ) == .none
      )
    }
  }
}

private enum StressInput001Field: Hashable {
  case a
  case b
  case c
  case d
}

private struct StressInput001Fixture: View {
  static let aIdentity = testIdentity("StressInput001", "A")
  static let bIdentity = testIdentity("StressInput001", "B")
  static let cIdentity = testIdentity("StressInput001", "C")
  static let dIdentity = testIdentity("StressInput001", "D")

  @FocusState private var focusedField: StressInput001Field?
  @State private var disablesMiddlePair = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Focus A") {}
        .id(Self.aIdentity)
        .focused($focusedField, equals: .a)
      Button("Focus B") {}
        .id(Self.bIdentity)
        .focused($focusedField, equals: .b)
        .disabled(disablesMiddlePair)
      Button("Focus C") {}
        .id(Self.cIdentity)
        .focused($focusedField, equals: .c)
        .disabled(disablesMiddlePair)
      Button("Focus D") {}
        .id(Self.dIdentity)
        .focused($focusedField, equals: .d)
    }
    .onChange(of: focusedField) { _, next in
      if next == .b {
        disablesMiddlePair = true
      }
    }
  }
}

// MARK: - Attempt 002: reverse traversal through a self-disabling target

extension FrameworkStressInputRoutingTests {
  @Test("Shift-Tab continues backward when its landing target disables itself")
  func stressInputRouting002ReverseTraversalContinuesPastDisabledTarget() throws {
    // Hypothesis: reverse traversal may be re-seated forward when the region
    // reached by Shift-Tab removes itself during focus synchronization.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput002Root"),
      size: .init(width: 36, height: 10)
    ) {
      StressInput002Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput002Fixture.dIdentity)
    _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressInput002Fixture.aIdentity)
  }
}

private enum StressInput002Field: Hashable {
  case a
  case b
  case c
  case d
}

private struct StressInput002Fixture: View {
  static let aIdentity = testIdentity("StressInput002", "A")
  static let bIdentity = testIdentity("StressInput002", "B")
  static let cIdentity = testIdentity("StressInput002", "C")
  static let dIdentity = testIdentity("StressInput002", "D")

  @FocusState private var focusedField: StressInput002Field?
  @State private var disablesMiddlePair = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse A") {}
        .id(Self.aIdentity)
        .focused($focusedField, equals: .a)
      Button("Reverse B") {}
        .id(Self.bIdentity)
        .focused($focusedField, equals: .b)
        .disabled(disablesMiddlePair)
      Button("Reverse C") {}
        .id(Self.cIdentity)
        .focused($focusedField, equals: .c)
        .disabled(disablesMiddlePair)
      Button("Reverse D") {}
        .id(Self.dIdentity)
        .focused($focusedField, equals: .d)
    }
    .onChange(of: focusedField) { _, next in
      if next == .c {
        disablesMiddlePair = true
      }
    }
  }
}

// MARK: - Attempt 003: directional continuation after focus-region removal

extension FrameworkStressInputRoutingTests {
  @Test("Right-arrow continuation remains geometric after the landing target disappears")
  func stressInputRouting003DirectionalContinuationPreservesGeometry() throws {
    // Hypothesis: removal of the first directional landing may fall back to
    // document order, selecting the below-row decoy instead of the next region
    // on the same horizontal ray.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput003Root"),
      size: .init(width: 52, height: 8)
    ) {
      StressInput003Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Geo A")
    _ = try harness.pressKey(KeyPress(.arrowRight))

    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity
        == (try harness.focusIdentity(forText: "Geo C"))
    )
  }
}

private enum StressInput003Field: Hashable {
  case a
  case b
  case c
  case decoy
}

private struct StressInput003Fixture: View {
  static let aIdentity = testIdentity("StressInput003", "A")
  static let bIdentity = testIdentity("StressInput003", "B")
  static let cIdentity = testIdentity("StressInput003", "C")
  static let decoyIdentity = testIdentity("StressInput003", "Decoy")

  @FocusState private var focusedField: StressInput003Field?
  @State private var removesLanding = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Button("Geo A") {}
        .id(Self.aIdentity)
        .focused($focusedField, equals: .a)
      Button("Geo Decoy") {}
        .id(Self.decoyIdentity)
        .focused($focusedField, equals: .decoy)
        .padding(.top, 3)
      if !removesLanding {
        Button("Geo B") {}
          .id(Self.bIdentity)
          .focused($focusedField, equals: .b)
          .padding(.leading, 14)
      }
      Button("Geo C") {}
        .id(Self.cIdentity)
        .focused($focusedField, equals: .c)
        .padding(.leading, 28)
    }
    .frame(width: 48, height: 6, alignment: .topLeading)
    .onChange(of: focusedField) { _, next in
      if next == .b {
        removesLanding = true
      }
    }
  }
}

// MARK: - Attempt 004: passive pointer mutation after keyboard traversal

extension FrameworkStressInputRoutingTests {
  @Test("Hover-driven removal does not inherit a stale keyboard traversal direction")
  func stressInputRouting004HoverMutationDoesNotResumeKeyboardTraversal() throws {
    // Hypothesis: a pending Tab record may survive a passive pointer move and
    // incorrectly advance focus when hover-driven state removes the focused B.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput004Root"),
      size: .init(width: 48, height: 10)
    ) {
      StressInput004Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Hover focus A")
    _ = try harness.pressKey(KeyPress(.tab))
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity
        == (try harness.focusIdentity(forText: "Hover focus B"))
    )

    let hoverPoint = try #require(harness.point(forText: "Hover mutation"))
    _ = try harness.movePointer(to: hoverPoint)

    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity
        == (try harness.focusIdentity(forText: "Hover focus A"))
    )
  }
}

private struct StressInput004Fixture: View {
  static let aIdentity = testIdentity("StressInput004", "A")
  static let bIdentity = testIdentity("StressInput004", "B")
  static let cIdentity = testIdentity("StressInput004", "C")

  @State private var removesB = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Hover focus A") {}
        .id(Self.aIdentity)
      if !removesB {
        Button("Hover focus B") {}
          .id(Self.bIdentity)
      }
      Button("Hover focus C") {}
        .id(Self.cIdentity)
      Text("Hover mutation")
        .frame(width: 20, height: 1, alignment: .leading)
        .onPointerHover { phase in
          if case .entered = phase {
            removesB = true
          }
        }
    }
  }
}

// MARK: - Attempt 005: stale FocusState request ahead of a live request

extension FrameworkStressInputRoutingTests {
  @Test("A stale pending FocusState request does not block a later live request")
  func stressInputRouting005StaleFocusRequestDoesNotBlockLiveRequest() throws {
    // Hypothesis: desiredFocusRequest may return early when its first pending
    // group selects a removed identity, never considering the next live group.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput005Root"),
      size: .init(width: 20, height: 4)
    ) {
      EmptyView()
    }
    defer { harness.shutdown() }

    let stale = testIdentity("StressInput005", "Stale")
    let live = testIdentity("StressInput005", "Live")
    let registry = harness.runLoop.localFocusBindingRegistry
    registry.register(
      identity: stale,
      bindingID: "stale",
      hasPendingRequest: true,
      isSelected: true,
      applyRuntimeFocus: { _ in false }
    )
    registry.register(
      identity: live,
      bindingID: "live",
      hasPendingRequest: true,
      isSelected: true,
      applyRuntimeFocus: { _ in false }
    )

    withKnownIssue("A stale FocusState request blocks the later live request") {
      #expect(registry.desiredFocusRequest(allowedIdentities: [live]) == .focus(live))
    }
  }
}

// MARK: - Attempt 009: stacked same-key handler priority under churn

extension FrameworkStressInputRoutingTests {
  @Test("Stacked same-key handler priority survives repeated closure rebinding")
  func stressInputRouting009StackedKeyHandlerPrioritySurvivesChurn() throws {
    // Hypothesis: partial handler-bucket restoration may invert outer-before-
    // inner dispatch priority when closures are rebound at a stable identity.
    let events = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput009Root"),
      size: .init(width: 48, height: 8)
    ) {
      StressInput009Fixture(events: events)
    }
    defer { harness.shutdown() }

    for generation in 0..<6 {
      _ = harness.runLoop.focusTracker.setFocus(to: StressInput009Fixture.focusIdentity)
      _ = try harness.render()
      _ = try harness.pressKey(KeyPress(.character("k")))
      #expect(
        Array(events.value.suffix(2)) == [
          "outer-(generation)",
          "inner-(generation)",
        ]
      )
      if generation < 5 {
        _ = try harness.clickText("Rebind key owners")
      }
    }
  }
}

private struct StressInput009Fixture: View {
  static let focusIdentity = testIdentity("StressInput009", "Focus")

  let events: StressInputBox<[String]>
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebind key owners") { generation += 1 }
      Text("Stacked key target (generation)")
        .id(Self.focusIdentity)
        .focusable()
        .onKeyPress(.character("k")) { _ in
          events.value.append("inner-(generation)")
          return .handled
        }
        .onKeyPress(.character("k")) { _ in
          events.value.append("outer-(generation)")
          return .ignored
        }
    }
  }
}

// MARK: - Attempt 010: remove the top stacked key handler

extension FrameworkStressInputRoutingTests {
  @Test("Removing the top stacked key handler exposes only the live inner handler")
  func stressInputRouting010RemovingTopHandlerExposesInnerHandler() throws {
    // Hypothesis: a departed top bucket may remain restored at the stable
    // identity and continue consuming keys after its modifier disappears.
    let events = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput010Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressInput010Fixture(events: events)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput010Fixture.focusIdentity)
    _ = try harness.pressKey(KeyPress(.character("x")))
    #expect(events.value == ["outer"])

    _ = try harness.clickText("Remove outer handler")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput010Fixture.focusIdentity)
    _ = try harness.render()
    _ = try harness.pressKey(KeyPress(.character("x")))

    #expect(events.value == ["outer", "inner"])
    #expect(harness.keyPressHandlerCount == 1)
  }
}

private struct StressInput010Fixture: View {
  static let focusIdentity = testIdentity("StressInput010", "Focus")

  let events: StressInputBox<[String]>
  @State private var hasOuterHandler = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove outer handler") { hasOuterHandler = false }
      if hasOuterHandler {
        Text("Removable key target")
          .id(Self.focusIdentity)
          .focusable()
          .onKeyPress(.character("x")) { _ in
            events.value.append("inner")
            return .handled
          }
          .onKeyPress(.character("x")) { _ in
            events.value.append("outer")
            return .handled
          }
      } else {
        Text("Removable key target")
          .id(Self.focusIdentity)
          .focusable()
          .onKeyPress(.character("x")) { _ in
            events.value.append("inner")
            return .handled
          }
      }
    }
  }
}

// MARK: - Attempt 011: removed TextField interceptor

extension FrameworkStressInputRoutingTests {
  @Test("A removed custom TextField interceptor stops consuming typed input")
  func stressInputRouting011RemovedTextFieldInterceptorStopsIntercepting() throws {
    // Hypothesis: a stale outer key-handler bucket may outlive its modifier and
    // keep intercepting text before the TextField's built-in editor handler.
    let text = StressInputBox("")
    let intercepted = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput011Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressInput011Fixture(text: text, intercepted: intercepted)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput011Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.character("q")))
    #expect(text.value.isEmpty)
    #expect(intercepted.value == 1)

    _ = try harness.clickText("Remove field interceptor")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput011Fixture.fieldIdentity)
    _ = try harness.render()
    _ = try harness.pressKey(KeyPress(.character("q")))

    #expect(text.value == "q")
    #expect(intercepted.value == 1)
  }
}

private struct StressInput011Fixture: View {
  static let fieldIdentity = testIdentity("StressInput011", "Field")

  let text: StressInputBox<String>
  let intercepted: StressInputBox<Int>
  @State private var intercepts = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove field interceptor") { intercepts = false }
      if intercepts {
        TextField("Value", text: text.binding())
          .id(Self.fieldIdentity)
          .textFieldStyle(.plain)
          .onKeyPress(.character("q")) { _ in
            intercepted.value += 1
            return .handled
          }
      } else {
        TextField("Value", text: text.binding())
          .id(Self.fieldIdentity)
          .textFieldStyle(.plain)
      }
    }
  }
}

// MARK: - Attempt 012: keyCommand isEnabled rebinding

extension FrameworkStressInputRoutingTests {
  @Test("keyCommand dispatch observes the current isEnabled value after churn")
  func stressInputRouting012KeyCommandEnabledStateRebinds() throws {
    // Hypothesis: the command table may restore a disabled descriptor over the
    // freshly enabled registration for the same scope and binding.
    let fired = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput012Root"),
      size: .init(width: 48, height: 10)
    ) {
      StressInput012Fixture(fired: fired)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput012Fixture.focusIdentity)
    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
    #expect(fired.value == 0)

    _ = try harness.clickText("Toggle command enabled")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput012Fixture.focusIdentity)
    _ = try harness.render()
    _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))

    #expect(fired.value == 1)
    #expect(harness.keyCommandRegistrationCount == 1)
  }
}

private struct StressInput012Fixture: View {
  static let focusIdentity = testIdentity("StressInput012", "Focus")

  let fired: StressInputBox<Int>
  @State private var commandEnabled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle command enabled") { commandEnabled.toggle() }
      Panel(id: "stress-input-012-panel") {
        Text("Command focus")
          .id(Self.focusIdentity)
          .focusable()
      }
      .keyCommand(
        "Stress save",
        key: .character("s"),
        modifiers: .ctrl,
        isEnabled: commandEnabled
      ) {
        fired.value += 1
      }
    }
  }
}

// MARK: - Attempt 013: duplicate keyCommand override removal

extension FrameworkStressInputRoutingTests {
  @Test("Removing a duplicate overriding command reveals the remaining command")
  func stressInputRouting013RemovingDuplicateCommandRevealsBaseCommand() throws {
    // Hypothesis: last-writer command replacement may erase the underlying
    // descriptor permanently when the overriding modifier leaves the tree.
    let events = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput013Root"),
      size: .init(width: 48, height: 10)
    ) {
      StressInput013Fixture(events: events)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput013Fixture.focusIdentity)
    _ = try harness.pressKey(KeyPress(.character("k"), modifiers: .ctrl))
    #expect(events.value == ["override"])

    _ = try harness.clickText("Remove command override")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput013Fixture.focusIdentity)
    _ = try harness.render()
    _ = try harness.pressKey(KeyPress(.character("k"), modifiers: .ctrl))

    #expect(events.value == ["override", "base"])
    #expect(harness.keyCommandRegistrationCount == 1)
  }
}

private struct StressInput013Fixture: View {
  static let focusIdentity = testIdentity("StressInput013", "Focus")

  let events: StressInputBox<[String]>
  @State private var hasOverride = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove command override") { hasOverride = false }
      if hasOverride {
        Panel(id: "stress-input-013-panel") {
          Text("Duplicate command focus")
            .id(Self.focusIdentity)
            .focusable()
        }
        .keyCommand("Base", key: .character("k"), modifiers: .ctrl) {
          events.value.append("base")
        }
        .keyCommand("Override", key: .character("k"), modifiers: .ctrl) {
          events.value.append("override")
        }
      } else {
        Panel(id: "stress-input-013-panel") {
          Text("Duplicate command focus")
            .id(Self.focusIdentity)
            .focusable()
        }
        .keyCommand("Base", key: .character("k"), modifiers: .ctrl) {
          events.value.append("base")
        }
      }
    }
  }
}

// MARK: - Attempt 014: keyCommand capture of live FocusedValue

extension FrameworkStressInputRoutingTests {
  @Test("keyCommand reads the live FocusedValue after focus moves")
  func stressInputRouting014KeyCommandReadsLiveFocusedValue() throws {
    // Hypothesis: command restoration may retain the closure authored for the
    // previous focused-value environment after focus moves within its scope.
    let events = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput014Root"),
      size: .init(width: 48, height: 10)
    ) {
      StressInput014Fixture(events: events)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Focused command A")
    _ = try harness.pressKey(KeyPress(.character("l"), modifiers: .ctrl))
    _ = try harness.focusText("Focused command B")
    _ = try harness.pressKey(KeyPress(.character("l"), modifiers: .ctrl))

    #expect(events.value == ["A", "B"])
  }
}

private enum StressInput014FocusedKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var stressInput014Label: String? {
    get { self[StressInput014FocusedKey.self] }
    set { self[StressInput014FocusedKey.self] = newValue }
  }
}

private struct StressInput014Fixture: View {
  static let aIdentity = testIdentity("StressInput014", "A")
  static let bIdentity = testIdentity("StressInput014", "B")

  let events: StressInputBox<[String]>
  @FocusedValue(\.stressInput014Label) private var focusedLabel

  var body: some View {
    Panel(id: "stress-input-014-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Focused command A") {}
          .id(Self.aIdentity)
          .focusedValue(\.stressInput014Label, "A")
        Button("Focused command B") {}
          .id(Self.bIdentity)
          .focusedValue(\.stressInput014Label, "B")
      }
    }
    .keyCommand("Read focused label", key: .character("l"), modifiers: .ctrl) {
      events.value.append(focusedLabel ?? "nil")
    }
  }
}

// MARK: - Attempt 015: arbitrarily split UTF-8 keyboard input

extension FrameworkStressInputRoutingTests {
  @Test("Terminal input preserves a multibyte character split across reads")
  func stressInputRouting015UTF8CharacterSurvivesArbitraryByteSplits() throws {
    // Hypothesis: the incremental parser may discard non-ASCII lead and
    // continuation bytes instead of retaining an incomplete UTF-8 scalar.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput015Root"),
      size: .init(width: 20, height: 4)
    ) {
      EmptyView()
    }
    defer { harness.shutdown() }

    var parser = TerminalInputParser()
    let bytes = Array("é".utf8)
    var events = parser.feed([bytes[0]])
    events.append(contentsOf: parser.feed([bytes[1]]))

    withKnownIssue("TerminalInputParser drops a UTF-8 scalar split across feeds") {
      #expect(events == [.key(KeyPress(.character("é")))])
    }
    #expect(harness.keyPressHandlerCount == 0)
  }
}

// MARK: - Attempt 016: TextField forward-delete routing

extension FrameworkStressInputRoutingTests {
  @Test("Delete removes the character after the focused TextField caret")
  func stressInputRouting016DeletePerformsForwardDeletion() throws {
    // Hypothesis: the parser emits KeyEvent.delete but the text-input command
    // mapper may omit the forward-delete command already supported by reducer.
    let text = StressInputBox("abcd")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput016Root"),
      size: .init(width: 32, height: 6)
    ) {
      StressInput016Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("abcd")
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.delete))

    withKnownIssue("Delete has no forward-deletion mapping for focused text input") {
      #expect(text.value == "abd")
    }
  }
}

private struct StressInput016Fixture: View {
  static let fieldIdentity = testIdentity("StressInput016", "Field")

  let text: StressInputBox<String>

  var body: some View {
    TextField("Forward delete", text: text.binding())
      .id(Self.fieldIdentity)
      .textFieldStyle(.plain)
  }
}

// MARK: - Attempt 017: fallback paste preserves grapheme clusters

extension FrameworkStressInputRoutingTests {
  @Test("Fallback paste emits one key event per extended grapheme cluster")
  func stressInputRouting017FallbackPastePreservesExtendedGraphemes() throws {
    // Hypothesis: scalar-wise fallback dispatch may split a composed emoji into
    // several independently handled character events.
    let keys = StressInputBox<[KeyEvent]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput017Root"),
      size: .init(width: 36, height: 6)
    ) {
      StressInput017Fixture(keys: keys)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Grapheme paste target")
    _ = try harness.paste("👩‍💻")

    withKnownIssue("Fallback paste splits extended graphemes into Unicode scalars") {
      #expect(keys.value == [.character("👩‍💻")])
    }
  }
}

private struct StressInput017Fixture: View {
  static let focusIdentity = testIdentity("StressInput017", "Focus")

  let keys: StressInputBox<[KeyEvent]>

  var body: some View {
    Text("Grapheme paste target")
      .id(Self.focusIdentity)
      .focusable()
      .onKeyPress(.any) { keyPress in
        keys.value.append(keyPress.key)
        return .handled
      }
  }
}

// MARK: - Attempt 018: stable TextField identity retargeted to another binding

extension FrameworkStressInputRoutingTests {
  @Test("Retargeting a stable TextField does not leak the old caret into the new binding")
  func stressInputRouting018TextFieldRetargetDropsOldCaretState() throws {
    // Hypothesis: editor state keyed only by view identity may retain A's caret
    // after the same TextField identity begins editing binding B.
    let first = StressInputBox("abcd")
    let second = StressInputBox("wxyz")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput018Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressInput018Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput018Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.clickText("Retarget text binding")
    _ = harness.runLoop.focusTracker.setFocus(to: StressInput018Fixture.fieldIdentity)
    _ = try harness.render()
    _ = try harness.pressKey(KeyPress(.character("Z")))

    #expect(first.value == "abcd")
    withKnownIssue("A retargeted TextField carries the prior binding's caret position") {
      #expect(second.value == "wxyzZ")
    }
  }
}

private struct StressInput018Fixture: View {
  static let fieldIdentity = testIdentity("StressInput018", "Field")

  let first: StressInputBox<String>
  let second: StressInputBox<String>
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget text binding") { usesSecond = true }
      if usesSecond {
        TextField("Retargeted value", text: second.binding())
          .id(Self.fieldIdentity)
          .textFieldStyle(.plain)
      } else {
        TextField("Retargeted value", text: first.binding())
          .id(Self.fieldIdentity)
          .textFieldStyle(.plain)
      }
    }
  }
}

// MARK: - Attempt 019: partial double-tap across owner remint

extension FrameworkStressInputRoutingTests {
  @Test("A partial double-tap cannot complete on a departed gesture owner")
  func stressInputRouting019PartialDoubleTapDoesNotFireDepartedOwner() throws {
    // Hypothesis: the first tap may leave an active count-two recognizer that
    // survives an owner remint and fires its stale closure on the second tap.
    let departedFires = StressInputBox<[Int]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput019Root"),
      size: .init(width: 42, height: 6)
    ) {
      StressInput019Fixture(departedFires: departedFires)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Double tap remint")
    _ = try harness.clickText("Double tap remint")

    withKnownIssue("A count-two tap recognizer fires its departed owner's closure") {
      #expect(departedFires.value.isEmpty)
    }
  }
}

private struct StressInput019Fixture: View {
  let departedFires: StressInputBox<[Int]>
  @State private var generation = 0

  var body: some View {
    Text("Double tap remint")
      .id(testIdentity("StressInput019", "Owner", "(generation)"))
      .frame(width: 24, height: 1, alignment: .leading)
      .onTapGesture {
        generation += 1
      }
      .onTapGesture(count: 2) {
        departedFires.value.append(generation)
      }
  }
}

// MARK: - Attempt 020: active drag retargeted during the gesture

extension FrameworkStressInputRoutingTests {
  @Test("An active drag writes the newly targeted binding after its first change")
  func stressInputRouting020ActiveDragDoesNotKeepStaleBinding() throws {
    // Hypothesis: preserving the active recognizer across re-resolution may
    // also preserve its old mutation closure after the view retargets to B.
    let firstChanges = StressInputBox(0)
    let secondChanges = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput020Root"),
      size: .init(width: 44, height: 6)
    ) {
      StressInput020Fixture(firstChanges: firstChanges, secondChanges: secondChanges)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Retarget drag"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(
      .dragged(.primary),
      at: Point(x: start.x + 3, y: start.y)
    )
    _ = try harness.sendMouse(
      .dragged(.primary),
      at: Point(x: start.x + 6, y: start.y)
    )
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 6, y: start.y))

    #expect(firstChanges.value == 1)
    withKnownIssue("An active drag keeps writing the binding captured before retargeting") {
      #expect(secondChanges.value == 1)
    }
  }
}

private struct StressInput020Fixture: View {
  static let dragIdentity = testIdentity("StressInput020", "Drag")

  let firstChanges: StressInputBox<Int>
  let secondChanges: StressInputBox<Int>
  @State private var targetsSecond = false

  var body: some View {
    if targetsSecond {
      Text("Retarget drag")
        .id(Self.dragIdentity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          DragGesture().onChanged { _ in
            secondChanges.value += 1
          }
        )
    } else {
      Text("Retarget drag")
        .id(Self.dragIdentity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          DragGesture().onChanged { _ in
            firstChanges.value += 1
            targetsSecond = true
          }
        )
    }
  }
}

// MARK: - Attempt 021: stacked updating gestures

extension FrameworkStressInputRoutingTests {
  @Test("Stacked updating gestures keep both GestureState cells coherent and bounded")
  func stressInputRouting021StackedGestureStatesUpdateAndResetTogether() throws {
    // Hypothesis: stacking updating decorators at one identity may register
    // only one state cell, leaving the other stale or unreset after release.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput021Root"),
      size: .init(width: 52, height: 6)
    ) {
      StressInput021Fixture()
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "first 0 second 0"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    let activeFrame = try harness.sendMouse(
      .dragged(.primary),
      at: Point(x: start.x + 4, y: start.y)
    )

    #expect(activeFrame.contains("first 4 second 4"))
    #expect(harness.gestureStateBindingCount == 2)

    let endedFrame = try harness.sendMouse(
      .up(.primary),
      at: Point(x: start.x + 4, y: start.y)
    )
    #expect(endedFrame.contains("first 0 second 0"))
    #expect(harness.gestureStateBindingCount == 2)
  }
}

private struct StressInput021Fixture: View {
  @GestureState private var first = Vector.zero
  @GestureState private var second = Vector.zero

  var body: some View {
    Text("first \(Int(first.dx)) second \(Int(second.dx))")
      .frame(width: 32, height: 1, alignment: .leading)
      .gesture(
        DragGesture()
          .updating($first) { value, state, _ in
            state = value.translation
          }
      )
      .gesture(
        DragGesture()
          .updating($second) { value, state, _ in
            state = value.translation
          }
      )
  }
}

// MARK: - Attempt 022: add a stacked gesture while another is active

extension FrameworkStressInputRoutingTests {
  @Test("A gesture added during an active drag remains installed after the drag ends")
  func stressInputRouting022GestureAddedDuringActiveGesturePersists() throws {
    // Hypothesis: registerStacked may discard a newly authored recognizer when
    // the current-pass recognizer is active and never publish it after release.
    let taps = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput022Root"),
      size: .init(width: 44, height: 6)
    ) {
      StressInput022Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Dynamic gesture"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(
      .dragged(.primary),
      at: Point(x: start.x + 4, y: start.y)
    )
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 4, y: start.y))
    _ = try harness.clickText("Dynamic gesture")

    withKnownIssue("A gesture added while a drag is active is discarded after release") {
      #expect(taps.value == 1)
    }
  }
}

private struct StressInput022Fixture: View {
  static let gestureIdentity = testIdentity("StressInput022", "Gesture")

  let taps: StressInputBox<Int>
  @State private var installsTap = false

  var body: some View {
    if installsTap {
      Text("Dynamic gesture")
        .id(Self.gestureIdentity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          DragGesture().onChanged { _ in }
        )
        .onTapGesture {
          taps.value += 1
        }
    } else {
      Text("Dynamic gesture")
        .id(Self.gestureIdentity)
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          DragGesture().onChanged { _ in
            installsTap = true
          }
        )
    }
  }
}

// MARK: - Attempt 023: allowsHitTesting(false) under an outer gesture

extension FrameworkStressInputRoutingTests {
  @Test("An outer gesture does not re-enable hit testing disabled by its content")
  func stressInputRouting023OuterGesturePreservesDisabledHitTesting() throws {
    // Hypothesis: GestureViewModifier's semantic merge may overwrite an inner
    // allowsHitTesting(false) value with its own participation metadata.
    let taps = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput023Root"),
      size: .init(width: 40, height: 6)
    ) {
      StressInput023Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("No hit testing")

    #expect(taps.value == 0)
  }
}

private struct StressInput023Fixture: View {
  let taps: StressInputBox<Int>

  var body: some View {
    Text("No hit testing")
      .frame(width: 24, height: 1, alignment: .leading)
      .allowsHitTesting(false)
      .gesture(
        TapGesture().onEnded {
          taps.value += 1
        }
      )
  }
}
