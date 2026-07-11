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

    #expect(
      registry.desiredFocusRequest(
        focusRegions: [region],
        shouldApplyInitialDefault: false
      ) == .none
    )
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

    #expect(registry.desiredFocusRequest(allowedIdentities: [live]) == .focus(live))
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

    #expect(events == [.key(KeyPress(.character("é")))])
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

    #expect(text.value == "abd")
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

    #expect(keys.value == [.character("👩‍💻")])
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
    #expect(second.value == "wxyzZ")
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

// MARK: - Attempt 020b: active drag retargeted at a stable identity

extension FrameworkStressInputRoutingTests {
  @Test("An active drag at a stable identity adopts the re-authored binding")
  func stressInputRouting020bActiveDragAdoptsReauthoredCallbacksAtStableIdentity() throws {
    // The record-refresh seam isolated from attempt 020's conditional-branch
    // identity flip: the gesture value is swapped in place, so the node
    // identity (and with it the pointer capture) is stable across the
    // retarget. The preserved mid-drag recognizer must adopt the re-authored
    // closure when the committed record is restored over it.
    let firstChanges = StressInputBox(0)
    let secondChanges = StressInputBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput020BRoot"),
      size: .init(width: 44, height: 6)
    ) {
      StressInput020BFixture(firstChanges: firstChanges, secondChanges: secondChanges)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Stable retarget"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(
      .dragged(.primary),
      at: Point(x: start.x + 3, y: start.y)
    )
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 3, y: start.y))

    #expect(firstChanges.value == 1)
    #expect(secondChanges.value >= 1)
  }
}

private struct StressInput020BFixture: View {
  let firstChanges: StressInputBox<Int>
  let secondChanges: StressInputBox<Int>
  @State private var targetsSecond = false

  var body: some View {
    Text("Stable retarget")
      .frame(width: 24, height: 1, alignment: .leading)
      .gesture(
        targetsSecond
          ? DragGesture().onChanged { _ in
            secondChanges.value += 1
          }
          : DragGesture().onChanged { _ in
            firstChanges.value += 1
            targetsSecond = true
          }
      )
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

// MARK: - Attempt 024: stationary pointer after hovered geometry moves

extension FrameworkStressInputRoutingTests {
  @Test("Hover exits when the hovered target moves away under a stationary pointer")
  func stressInputRouting024HoverExitsAfterGeometryMovesAway() throws {
    // Hypothesis: hover state stores only a route identity and never re-hit-
    // tests the last pointer location after a render changes route geometry.
    let phases = StressInputBox<[HoverPhase]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput024Root"),
      size: .init(width: 56, height: 6)
    ) {
      StressInput024Fixture(phases: phases)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Moving hover target"))
    _ = try harness.movePointer(to: point)
    _ = try harness.render()

    #expect(
      phases.value.first.map { phase in
        if case .entered = phase { return true }
        return false
      } == true)
    withKnownIssue("Stationary-pointer hover is not re-hit-tested after geometry moves") {
      #expect(phases.value.last == .exited)
    }
  }
}

private struct StressInput024Fixture: View {
  let phases: StressInputBox<[HoverPhase]>
  @State private var moved = false

  var body: some View {
    Text("Moving hover target")
      .frame(width: 22, height: 1, alignment: .leading)
      .padding(.leading, moved ? 28 : 0)
      .onPointerHover { phase in
        phases.value.append(phase)
        if case .entered = phase {
          moved = true
        }
      }
  }
}

// MARK: - Attempt 025: stacked hover phases under partial churn

extension FrameworkStressInputRoutingTests {
  @Test("Stacked hover modifiers receive balanced phases across partial owner churn")
  func stressInputRouting025StackedHoverPhasesRemainBalanced() throws {
    // Hypothesis: restoring one hover contribution after its state write may
    // replace the sibling contribution or lose one sibling's exit phase.
    let events = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput025Root"),
      size: .init(width: 52, height: 8)
    ) {
      StressInput025Fixture(events: events)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Stacked hover"))
    _ = try harness.movePointer(to: point)
    _ = try harness.movePointer(to: Point(x: 50, y: 7))

    withKnownIssue("Stacked hover dispatch drops the inner modifier's balanced phases") {
      #expect(events.value.filter { $0 == "inner-entered" }.count == 1)
      #expect(events.value.filter { $0 == "outer-entered" }.count == 1)
      #expect(events.value.filter { $0 == "inner-exited" }.count == 1)
      #expect(events.value.filter { $0 == "outer-exited" }.count == 1)
    }
  }
}

private struct StressInput025Fixture: View {
  let events: StressInputBox<[String]>
  @State private var generation = 0

  var body: some View {
    Text("Stacked hover (generation)")
      .id(testIdentity("StressInput025", "Hover"))
      .frame(width: 24, height: 1, alignment: .leading)
      .onPointerHover { phase in
        switch phase {
        case .entered:
          events.value.append("inner-entered")
          generation += 1
        case .moved:
          break
        case .exited:
          events.value.append("inner-exited")
        }
      }
      .onPointerHover { phase in
        switch phase {
        case .entered:
          events.value.append("outer-entered")
        case .moved:
          break
        case .exited:
          events.value.append("outer-exited")
        }
      }
  }
}

// MARK: - Attempt 026: spatial drop overrides focus scope

extension FrameworkStressInputRoutingTests {
  @Test("A spatial drop on Panel B routes to B instead of focused Panel A")
  func stressInputRouting026SpatialDropUsesHitPanelNotFocusedPanel() throws {
    // Hypothesis: blank/interior spatial hit testing may fail to recover B's
    // action scope and fall back to the currently focused scope in Panel A.
    let destinations = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput026Root"),
      size: .init(width: 64, height: 10)
    ) {
      StressInput026Fixture(destinations: destinations)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Panel A drop zone")
    let point = try #require(harness.point(forText: "Panel B drop zone"))
    _ = try harness.drop(
      paths: [DroppedPath("/tmp/stress-input-026")],
      context: DropContext(location: point)
    )

    #expect(destinations.value == ["B"])
  }
}

private struct StressInput026Fixture: View {
  static let aIdentity = testIdentity("StressInput026", "A")
  static let bIdentity = testIdentity("StressInput026", "B")

  let destinations: StressInputBox<[String]>

  var body: some View {
    HStack(alignment: .top, spacing: 1) {
      Panel(id: "stress-input-026-a") {
        Text("Panel A drop zone")
          .id(Self.aIdentity)
          .focusable()
      }
      .dropDestination { _ in
        destinations.value.append("A")
        return true
      }
      .frame(width: 28, height: 6)

      Panel(id: "stress-input-026-b") {
        Text("Panel B drop zone")
          .id(Self.bIdentity)
          .focusable()
      }
      .dropDestination { _ in
        destinations.value.append("B")
        return true
      }
      .frame(width: 28, height: 6)
    }
  }
}

// MARK: - Attempt 027: spatial drop with a modal overlay

extension FrameworkStressInputRoutingTests {
  @Test("A spatial drop targets the topmost modal instead of the background")
  func stressInputRouting027SpatialDropPrefersTopmostModal() throws {
    // Hypothesis: drop hit testing may walk the base semantic tree before the
    // presentation portal and dispatch to an obscured background scope.
    let destinations = StressInputBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput027Root"),
      size: .init(width: 64, height: 14)
    ) {
      StressInput027Fixture(destinations: destinations)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open drop modal")
    let point = try #require(harness.point(forText: "Modal drop zone", chooseLast: true))
    _ = try harness.drop(
      paths: [DroppedPath("/tmp/stress-input-027")],
      context: DropContext(location: point)
    )

    #expect(destinations.value == ["modal"])
  }
}

private struct StressInput027Fixture: View {
  let destinations: StressInputBox<[String]>
  @State private var isPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open drop modal") { isPresented = true }
      Panel(id: "stress-input-027-background") {
        Text("Background drop zone")
          .focusable()
      }
      .dropDestination { _ in
        destinations.value.append("background")
        return true
      }
    }
    .sheet("Stress drop modal", isPresented: $isPresented) {
      Panel(id: "stress-input-027-modal") {
        Text("Modal drop zone")
          .focusable()
      }
      .dropDestination { _ in
        destinations.value.append("modal")
        return true
      }
      .frame(width: 32, height: 6)
    }
  }
}

// MARK: - Attempt 028: keyboard scrolling at the content edge

extension FrameworkStressInputRoutingTests {
  @Test("Keyboard scrolling clamps its binding at the edge and reverses immediately")
  func stressInputRouting028KeyboardScrollBindingClampsAtEdge() throws {
    // Hypothesis: arrow-key scrolling may grow the bound offset beyond geometry,
    // requiring many reverse keys before the visible viewport moves.
    let position = StressInputBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput028Root"),
      size: .init(width: 32, height: 8)
    ) {
      StressInput028Fixture(position: position)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Keyboard row 0")
    let route = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes.first {
        $0.identity == StressInput028Fixture.scrollIdentity
      }
    )
    let maximumY = max(0, route.contentBounds.size.height - route.viewportRect.size.height)

    for _ in 0..<30 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    _ = try harness.pressKey(KeyPress(.arrowUp))
    #expect(position.value.y == max(0, maximumY - 1))
  }
}

private struct StressInput028Fixture: View {
  static let scrollIdentity = testIdentity("StressInput028", "Scroll")

  let position: StressInputBox<ScrollPosition>

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: position.binding()
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<12) { row in
          Text("Keyboard row \(row)")
        }
      }
    }
    .id(Self.scrollIdentity)
    .frame(width: 24, height: 4, alignment: .topLeading)
  }
}

// MARK: - Attempt 029: nested wheel scroll chaining

extension FrameworkStressInputRoutingTests {
  @Test("Wheel input chains to the outer scroll view when the inner view is at bottom")
  func stressInputRouting029NestedWheelChainsAtInnerBoundary() throws {
    // Hypothesis: spatial target selection may pick only the leaf scroll route;
    // when its handler reports an edge, dispatch never retries the ancestor.
    let outer = StressInputBox(ScrollPosition.zero)
    let inner = StressInputBox(ScrollPosition(x: 0, y: 5))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput029Root"),
      size: .init(width: 40, height: 10)
    ) {
      StressInput029Fixture(outer: outer, inner: inner)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Inner 6"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)

    #expect(inner.value.y == 5)
    withKnownIssue("Nested wheel routing does not chain to the outer view at the inner edge") {
      #expect(outer.value.y == 1)
    }
  }
}

private struct StressInput029Fixture: View {
  let outer: StressInputBox<ScrollPosition>
  let inner: StressInputBox<ScrollPosition>

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: outer.binding()
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Outer header")
        ScrollView(
          .vertical,
          showsIndicators: false,
          position: inner.binding()
        ) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<8) { row in
              Text("Inner \(row)")
            }
          }
        }
        .id(testIdentity("StressInput029", "Inner"))
        .frame(width: 24, height: 3, alignment: .topLeading)
        ForEach(0..<10) { row in
          Text("Outer tail \(row)")
        }
      }
    }
    .id(testIdentity("StressInput029", "Outer"))
    .frame(width: 28, height: 6, alignment: .topLeading)
  }
}

// MARK: - Attempt 030: stable focused identity relocated offscreen

extension FrameworkStressInputRoutingTests {
  @Test("A stable focused identity is re-revealed after relocating offscreen")
  func stressInputRouting030RelocatedFocusedIdentityIsRevealedAgain() throws {
    // Hypothesis: reveal freshness keyed only by focused identity ignores a
    // geometry relocation of that still-focused identity.
    let position = StressInputBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput030Root"),
      size: .init(width: 40, height: 9)
    ) {
      StressInput030Fixture(position: position)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput030Fixture.focusIdentity)
    #expect(position.value.y == 0)
    let frame = try harness.pressKey(KeyPress(.character("m")))

    withKnownIssue("A stable focused identity is not re-revealed after geometry relocation") {
      #expect(position.value.y > 0)
      #expect(frame.contains("Relocating focus target"))
    }
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == StressInput030Fixture.focusIdentity)
  }
}

private struct StressInput030Fixture: View {
  static let focusIdentity = testIdentity("StressInput030", "Focus")
  static let scrollIdentity = testIdentity("StressInput030", "Scroll")

  let position: StressInputBox<ScrollPosition>
  @State private var movesLow = false

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: position.binding()
    ) {
      VStack(alignment: .leading, spacing: 0) {
        if !movesLow {
          focusTarget
        }
        ForEach(0..<16) { row in
          Text("Relocation spacer (row)")
        }
        if movesLow {
          focusTarget
        }
      }
    }
    .id(Self.scrollIdentity)
    .frame(width: 30, height: 5, alignment: .topLeading)
  }

  private var focusTarget: some View {
    Text("Relocating focus target")
      .id(Self.focusIdentity)
      .focusable()
      .onKeyPress(.character("m")) { _ in
        movesLow = true
        return .handled
      }
  }
}

// MARK: - Attempt 031: momentum across same-identity route replacement

extension FrameworkStressInputRoutingTests {
  @Test("Momentum does not transfer to a replacement ScrollView route with the same identity")
  func stressInputRouting031MomentumDoesNotTransferToReplacementRoute() throws {
    // Hypothesis: momentum keyed only by route Identity may mutate a newly
    // mounted binding after the original scroll owner is replaced.
    let first = StressInputBox(ScrollPosition.zero)
    let second = StressInputBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput031Root"),
      size: .init(width: 40, height: 9)
    ) {
      StressInput031Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Momentum row 0")
    let start = MonotonicInstant.now()
    #expect(
      harness.runLoop.scrollMomentum.begin(
        identity: StressInput031Fixture.scrollIdentity,
        offsetVelocity: Vector(dx: 0, dy: 30),
        canScrollX: false,
        canScrollY: true,
        now: start
      )
    )

    _ = try harness.pressKey(KeyPress(.character("r")))
    let ticks = harness.runLoop.scrollMomentum.step(
      to: start.advanced(by: .milliseconds(100))
    )
    for tick in ticks {
      _ = harness.runLoop.localScrollPositionRegistry.scrollBy(
        x: tick.deltaX,
        y: tick.deltaY,
        scopeIdentity: tick.identity
      )
    }

    withKnownIssue("Momentum continues mutating the retired binding after route replacement") {
      #expect(first.value == .zero)
      #expect(second.value == .zero)
    }
  }
}

private struct StressInput031Fixture: View {
  static let scrollIdentity = testIdentity("StressInput031", "Scroll")

  let first: StressInputBox<ScrollPosition>
  let second: StressInputBox<ScrollPosition>
  @State private var targetsSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(targetsSecond ? "Binding B" : "Binding A")
      ScrollView(
        .vertical,
        showsIndicators: false,
        position: targetsSecond ? second.binding() : first.binding()
      ) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<40) { row in
            Text("Momentum row \(row)")
          }
        }
      }
      .id(Self.scrollIdentity)
      .frame(width: 28, height: 5, alignment: .topLeading)
      .onKeyPress(.character("r")) { _ in
        targetsSecond = true
        return .handled
      }
    }
  }
}

// MARK: - Attempt 032: stable ScrollView identity rebinds position storage

extension FrameworkStressInputRoutingTests {
  @Test("A stable ScrollView routes wheel writes only to its current position binding")
  func stressInputRouting032ScrollViewRebindsCurrentPositionBinding() throws {
    // Hypothesis: restored pointer or position registrations may retain binding
    // A after the stable ScrollView is re-authored with binding B.
    let first = StressInputBox(ScrollPosition.zero)
    let second = StressInputBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput032Root"),
      size: .init(width: 40, height: 9)
    ) {
      StressInput032Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Rebind row 0")
    _ = try harness.pressKey(KeyPress(.character("r")))
    let point = try #require(harness.point(forText: "Rebind row 1"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)

    withKnownIssue("A stable ScrollView retains its previous position binding") {
      #expect(first.value == .zero)
      #expect(second.value == ScrollPosition(x: 0, y: 1))
    }
  }
}

private struct StressInput032Fixture: View {
  static let scrollIdentity = testIdentity("StressInput032", "Scroll")

  let first: StressInputBox<ScrollPosition>
  let second: StressInputBox<ScrollPosition>
  @State private var targetsSecond = false

  var body: some View {
    ScrollView(
      .vertical,
      showsIndicators: false,
      position: targetsSecond ? second.binding() : first.binding()
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<18) { row in
          Text("Rebind row \(row)")
        }
      }
    }
    .id(Self.scrollIdentity)
    .frame(width: 28, height: 5, alignment: .topLeading)
    .onKeyPress(.character("r")) { _ in
      targetsSecond = true
      return .handled
    }
  }
}

// MARK: - Attempt 033: ScrollView axes replacement

extension FrameworkStressInputRoutingTests {
  @Test("Changing ScrollView axes replaces every old-axis input contract")
  func stressInputRouting033ChangingAxesDropsOldScrollHandlers() throws {
    // Hypothesis: a restored body handler from the vertical configuration may
    // coexist with the new horizontal handler at the stable route identity.
    let position = StressInputBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput033Root"),
      size: .init(width: 42, height: 9)
    ) {
      StressInput033Fixture(position: position)
    }
    defer { harness.shutdown() }

    let scrollFocus = try #require(harness.runLoop.focusTracker.focusRegions.first)
    _ = try harness.focus(scrollFocus.identity)
    _ = try harness.pressKey(KeyPress(.character("r")))
    let point = Point(x: 1, y: 1)
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    _ = try harness.scrollPointer(at: point, deltaX: 1, deltaY: 0)
    withKnownIssue("Changing ScrollView axes leaves the old vertical handler installed") {
      #expect(position.value == ScrollPosition(x: 1, y: 0))
    }
  }
}

private struct StressInput033Fixture: View {
  static let scrollIdentity = testIdentity("StressInput033", "Scroll")

  let position: StressInputBox<ScrollPosition>
  @State private var usesHorizontalAxis = false

  var body: some View {
    ScrollView(
      usesHorizontalAxis ? .horizontal : .vertical,
      showsIndicators: false,
      position: position.binding()
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<12) { row in
          HStack(spacing: 0) {
            ForEach(0..<12) { column in
              Text("G\(row)-\(column) ")
            }
          }
        }
      }
    }
    .id(Self.scrollIdentity)
    .frame(width: 20, height: 5, alignment: .topLeading)
    .onKeyPress(.character("r")) { _ in
      usesHorizontalAxis = true
      return .handled
    }
  }
}
