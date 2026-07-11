import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI environment and style stress behavior", .serialized)
struct FrameworkStressEnvironmentStyleTests {}

private enum EnvironmentStyleStringKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var environmentStyleString: String {
    get { self[EnvironmentStyleStringKey.self] }
    set { self[EnvironmentStyleStringKey.self] = newValue }
  }
}

private enum EnvironmentStyleOptionalKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

private struct EnvironmentStyleAction: Sendable {
  let perform: @MainActor @Sendable () -> Void

  @MainActor
  func callAsFunction() {
    perform()
  }
}

private enum EnvironmentStyleActionKey: EnvironmentKey {
  static let defaultValue = EnvironmentStyleAction {}
}

extension EnvironmentValues {
  fileprivate var environmentStyleOptional: String? {
    get { self[EnvironmentStyleOptionalKey.self] }
    set { self[EnvironmentStyleOptionalKey.self] = newValue }
  }

  fileprivate var environmentStyleAction: EnvironmentStyleAction {
    get { self[EnvironmentStyleActionKey.self] }
    set { self[EnvironmentStyleActionKey.self] = newValue }
  }
}

private func environmentStyleText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: reminted nested override removal

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 001 reminted override removal restores live grandparent")
  func environmentStyle001RemintedOverrideRemovalRestoresLiveGrandparent() throws {
    // Hypothesis: removing a reminted nearest writer can leave its snapshot on a stable reader
    // instead of exposing the simultaneously updated grandparent value.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle001"),
      size: .init(width: 66, height: 7)
    ) {
      EnvironmentStyle001Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      var frame = try harness.clickText("Advance Outer 001")
      #expect(frame.contains("001 value inner-\(generation)"))

      frame = try harness.clickText("Toggle Override 001")
      #expect(frame.contains("001 value outer-\(generation)"))

      frame = try harness.clickText("Toggle Override 001")
      #expect(frame.contains("001 value inner-\(generation)"))
    }
  }
}

// MARK: - Attempt 004: closure-valued environment action freshness

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 004 stable invoker dispatches current environment action")
  func environmentStyle004StableInvokerDispatchesCurrentEnvironmentAction() throws {
    // Hypothesis: reflection-based environment snapshot comparison can treat closure-valued
    // actions as unchanged and leave a stable invoker dispatching the first closure.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle004"),
      size: .init(width: 72, height: 7)
    ) {
      EnvironmentStyle004Root()
    }
    defer { harness.shutdown() }

    var expected = 0
    for generation in 1...12 {
      _ = try harness.clickText("Advance Action 004")
      let frame = try harness.clickText("Invoke Environment Action 004")
      expected += generation
      #expect(frame.contains("004 generation \(generation) total \(expected)"))
      #expect(harness.actionRegistrationCount == 2)
    }
  }
}

private struct EnvironmentStyle004Invoker: View {
  @Environment(\.environmentStyleAction) private var action

  var body: some View {
    Button("Invoke Environment Action 004") { action() }
  }
}

private struct EnvironmentStyle004Root: View {
  @State private var generation = 0
  @State private var total = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Action 004") { generation += 1 }
      Text("004 generation \(generation) total \(total)")
      EnvironmentStyle004Invoker()
        .environment(
          \.environmentStyleAction,
          EnvironmentStyleAction { total += generation }
        )
    }
  }
}

// MARK: - Attempt 005: nested environment action teardown

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 005 removing nested action restores current outer action")
  func environmentStyle005RemovingNestedActionRestoresCurrentOuterAction() throws {
    // Hypothesis: a closure-valued nearest action can survive its modifier's removal, masking the
    // current outer action even though the stable invoker is reevaluated.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle005"),
      size: .init(width: 72, height: 7)
    ) {
      EnvironmentStyle005Root()
    }
    defer { harness.shutdown() }

    var expected = 0
    for generation in 1...10 {
      _ = try harness.clickText("Advance Action 005")
      var frame = try harness.clickText("Invoke Environment Action 005")
      expected += generation
      #expect(frame.contains("005 generation \(generation) total \(expected)"))

      _ = try harness.clickText("Toggle Inner Action 005")
      frame = try harness.clickText("Invoke Environment Action 005")
      expected += generation * 10
      #expect(frame.contains("005 generation \(generation) total \(expected)"))
      _ = try harness.clickText("Toggle Inner Action 005")
    }
  }
}

private struct EnvironmentStyle005Invoker: View {
  @Environment(\.environmentStyleAction) private var action

  var body: some View {
    Button("Invoke Environment Action 005") { action() }
  }
}

private struct EnvironmentStyle005Root: View {
  @State private var generation = 0
  @State private var total = 0
  @State private var usesInner = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Action 005") { generation += 1 }
      Button("Toggle Inner Action 005") { usesInner.toggle() }
      Text("005 generation \(generation) total \(total)")
      Group {
        if usesInner {
          EnvironmentStyle005Invoker()
            .environment(
              \.environmentStyleAction,
              EnvironmentStyleAction { total += generation }
            )
        } else {
          EnvironmentStyle005Invoker()
        }
      }
    }
    .environment(
      \.environmentStyleAction,
      EnvironmentStyleAction { total += generation * 10 }
    )
  }
}

// MARK: - Attempt 006: keyed environment action reorder

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 006 reordered invokers keep entity-owned environment actions")
  func environmentStyle006ReorderedInvokersKeepEntityOwnedActions() throws {
    // Hypothesis: closure-valued environment actions can be restored by structural slot when
    // keyed owners reorder, swapping otherwise-current actions between entities.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle006"),
      size: .init(width: 76, height: 9)
    ) {
      EnvironmentStyle006Root()
    }
    defer { harness.shutdown() }

    var expectedA = 0
    var expectedB = 0
    for generation in 1...10 {
      _ = try harness.clickText("Reorder Action Owners 006")
      _ = try harness.clickText("Advance Actions 006")
      _ = try harness.clickText("Invoke Action 006 A")
      let frame = try harness.clickText("Invoke Action 006 B")
      expectedA += generation
      expectedB += generation * 10
      #expect(frame.contains("006 totals A \(expectedA) B \(expectedB)"))
    }
  }
}

private struct EnvironmentStyle006Invoker: View {
  let label: String
  @Environment(\.environmentStyleAction) private var action

  var body: some View {
    Button("Invoke Action 006 \(label)") { action() }
  }
}

private struct EnvironmentStyle006Item: Identifiable {
  let id: String
}

private struct EnvironmentStyle006Root: View {
  @State private var generation = 0
  @State private var reversed = false
  @State private var totalA = 0
  @State private var totalB = 0

  private var items: [EnvironmentStyle006Item] {
    let source = [EnvironmentStyle006Item(id: "A"), EnvironmentStyle006Item(id: "B")]
    return reversed ? Array(source.reversed()) : source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Action Owners 006") { reversed.toggle() }
      Button("Advance Actions 006") { generation += 1 }
      Text("006 totals A \(totalA) B \(totalB)")
      ForEach(items) { item in
        EnvironmentStyle006Invoker(label: item.id)
          .environment(
            \.environmentStyleAction,
            EnvironmentStyleAction {
              if item.id == "A" {
                totalA += generation
              } else {
                totalB += generation * 10
              }
            }
          )
      }
    }
  }
}

// MARK: - Attempt 007: same-type erased button-style replacement

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 007 erased button style refreshes same-type payload")
  func environmentStyle007ErasedButtonStyleRefreshesSameTypePayload() throws {
    // Hypothesis: AnyButtonStyle replacement can compare only the concrete style type or snapshot
    // label, retaining the first style body's stored payload across same-type value churn.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle007"),
      size: .init(width: 72, height: 7)
    ) {
      EnvironmentStyle007Root()
    }
    defer { harness.shutdown() }

    for generation in 1...14 {
      let frame = try harness.clickText("Advance Style 007")
      #expect(frame.contains("style-\(generation) Styled Action 007"))
      #expect(!frame.contains("style-\(generation - 1) Styled Action 007"))
    }
  }
}

private struct EnvironmentStyle007ButtonStyle: ButtonStyle {
  let marker: String

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(marker)
      configuration.label
    }
  }
}

private struct EnvironmentStyle007Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Style 007") { generation += 1 }
      Button("Styled Action 007") {}
        .buttonStyle(EnvironmentStyle007ButtonStyle(marker: "style-\(generation)"))
    }
  }
}

// MARK: - Attempt 008: cross-type erased button-style replacement

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 008 erased button style replaces concrete family and action")
  func environmentStyle008ErasedButtonStyleReplacesConcreteFamilyAndAction() throws {
    // Hypothesis: AnyButtonStyle can retain a prior concrete box when its environment slot keeps
    // one erased static type, leaving stale chrome or dropping the current Button action.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle008"),
      size: .init(width: 76, height: 8)
    ) {
      EnvironmentStyle008Root()
    }
    defer { harness.shutdown() }

    var expectedTotal = 0
    for generation in 1...12 {
      var frame = try harness.clickText("Toggle Style Family 008")
      if generation.isMultiple(of: 2) {
        #expect(!frame.contains("custom-\(generation) Styled Target 008"))
      } else {
        #expect(frame.contains("custom-\(generation) Styled Target 008"))
      }
      frame = try harness.clickText("Styled Target 008")
      expectedTotal += generation
      #expect(frame.contains("008 generation \(generation) total \(expectedTotal)"))
    }
  }
}

private struct EnvironmentStyle008Root: View {
  @State private var generation = 0
  @State private var total = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Style Family 008") { generation += 1 }
      Text("008 generation \(generation) total \(total)")
      Button("Styled Target 008") { total += generation }
        .buttonStyle(
          generation.isMultiple(of: 2)
            ? AnyButtonStyle.plain
            : AnyButtonStyle(EnvironmentStyle007ButtonStyle(marker: "custom-\(generation)"))
        )
    }
  }
}

// MARK: - Attempt 009: nested style override removal

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 009 removing button style reveals live outer style")
  func environmentStyle009RemovingButtonStyleRevealsLiveOuterStyle() throws {
    // Hypothesis: removing a nested type-erased style writer can retain its style body instead of
    // rebuilding the control from the simultaneously changing outer style environment.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle009"),
      size: .init(width: 78, height: 8)
    ) {
      EnvironmentStyle009Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      _ = try harness.clickText("Advance Styles 009")
      var frame = try harness.clickText("Toggle Inner Style 009")
      #expect(frame.contains("outer-\(generation) Nested Styled Target 009"))

      frame = try harness.clickText("Toggle Inner Style 009")
      #expect(frame.contains("inner-\(generation) Nested Styled Target 009"))
    }
  }
}

private struct EnvironmentStyle009Root: View {
  @State private var generation = 0
  @State private var usesInner = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Styles 009") { generation += 1 }
      Button("Toggle Inner Style 009") { usesInner.toggle() }
      Group {
        if usesInner {
          Button("Nested Styled Target 009") {}
            .buttonStyle(EnvironmentStyle007ButtonStyle(marker: "inner-\(generation)"))
        } else {
          Button("Nested Styled Target 009") {}
        }
      }
      .buttonStyle(EnvironmentStyle007ButtonStyle(marker: "outer-\(generation)"))
    }
  }
}

// MARK: - Attempt 010: role propagation through retained custom style

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 010 custom button style receives current role")
  func environmentStyle010CustomButtonStyleReceivesCurrentRole() throws {
    // Hypothesis: a retained custom style body can refresh its label while preserving the first
    // ButtonStyleConfiguration role supplied to the erased style box.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle010"),
      size: .init(width: 76, height: 7)
    ) {
      EnvironmentStyle010Root()
    }
    defer { harness.shutdown() }

    let roles = ["cancel", "destructive", "close", "confirm"]
    for generation in 1...16 {
      let frame = try harness.clickText("Advance Role 010")
      #expect(frame.contains("role-\(roles[generation % roles.count]) Role Target 010"))
    }
  }
}

private struct EnvironmentStyle010ButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let marker: String
    switch configuration.role {
    case .cancel: marker = "cancel"
    case .destructive: marker = "destructive"
    case .close: marker = "close"
    case .confirm: marker = "confirm"
    case nil: marker = "none"
    }
    return HStack(spacing: 1) {
      Text("role-\(marker)")
      configuration.label
    }
  }
}

private struct EnvironmentStyle010Root: View {
  @State private var generation = 0

  private var role: ButtonRole {
    switch generation % 4 {
    case 0: .cancel
    case 1: .destructive
    case 2: .close
    default: .confirm
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Role 010") { generation += 1 }
      Button("Role Target 010", role: role) {}
        .buttonStyle(EnvironmentStyle010ButtonStyle())
    }
  }
}

private struct EnvironmentStyle001Reader: View {
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("001 value \(value)")
  }
}

private struct EnvironmentStyle001Root: View {
  @State private var generation = 0
  @State private var hasOverride = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Outer 001") { generation += 1 }
      Button("Toggle Override 001") { hasOverride.toggle() }
      if hasOverride {
        EnvironmentStyle001Reader()
          .environment(\.environmentStyleString, "inner-\(generation)")
          .id("environment-style-001-inner-\(generation)")
      } else {
        EnvironmentStyle001Reader()
          .id("environment-style-001-reader")
      }
    }
    .environment(\.environmentStyleString, "outer-\(generation)")
  }
}

// MARK: - Attempt 002: keyed writer reorder

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 002 keyed writer reorder preserves entity snapshots")
  func environmentStyle002KeyedWriterReorderPreservesEntitySnapshots() throws {
    // Hypothesis: environment snapshots can follow structural indices when keyed children move,
    // making a row inherit the override previously authored at its new position.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle002"),
      size: .init(width: 68, height: 8)
    ) {
      EnvironmentStyle002Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      _ = try harness.clickText("Reorder Writers 002")
      let frame = try harness.clickText("Advance Writers 002")
      #expect(frame.contains("002 row A value A-\(generation)"))
      #expect(frame.contains("002 row B value B-\(generation)"))
      #expect(frame.contains("002 row C value C-\(generation)"))
    }
  }
}

private struct EnvironmentStyle002Item: Identifiable {
  let id: String
}

private struct EnvironmentStyle002Reader: View {
  let id: String
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("002 row \(id) value \(value)")
  }
}

private struct EnvironmentStyle002Root: View {
  @State private var generation = 0
  @State private var reversed = false

  private var items: [EnvironmentStyle002Item] {
    let source = ["A", "B", "C"].map(EnvironmentStyle002Item.init(id:))
    return reversed ? Array(source.reversed()) : source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Writers 002") { reversed.toggle() }
      Button("Advance Writers 002") { generation += 1 }
      ForEach(items) { item in
        EnvironmentStyle002Reader(id: item.id)
          .environment(\.environmentStyleString, "\(item.id)-\(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: optional writer absence versus explicit nil

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 003 removing explicit nil reveals optional outer value")
  func environmentStyle003RemovingExplicitNilRevealsOptionalOuterValue() {
    // Hypothesis: snapshot equality can collapse an absent Optional writer with an explicit nil
    // writer, preventing removal from exposing the live outer Optional value.
    struct Reader: View {
      @Environment(\.environmentStyleOptional) private var value

      var body: some View {
        Text("003 value \(value ?? "nil")")
      }
    }

    struct Root: View {
      let generation: Int
      let masksOuter: Bool

      var body: some View {
        Group {
          if masksOuter {
            Reader().environment(\.environmentStyleOptional, nil)
          } else {
            Reader()
          }
        }
        .environment(\.environmentStyleOptional, "outer-\(generation)")
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("EnvironmentStyle003")
    for generation in 0..<18 {
      let masksOuter = generation.isMultiple(of: 2)
      let frame = renderer.render(
        Root(generation: generation, masksOuter: masksOuter),
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      #expect(
        environmentStyleText(frame).contains(
          masksOuter ? "003 value nil" : "003 value outer-\(generation)"
        )
      )
    }
  }
}
