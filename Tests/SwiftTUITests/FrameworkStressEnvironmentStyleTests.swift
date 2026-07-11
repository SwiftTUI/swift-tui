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

private enum EnvironmentStyleIntPreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

private struct EnvironmentStyleTaggedAnchor: Sendable {
  let tag: String
  let anchor: Anchor<Rect>
}

private enum EnvironmentStyleAnchorListKey: PreferenceKey {
  static let defaultValue: [EnvironmentStyleTaggedAnchor] = []

  static func reduce(
    value: inout [EnvironmentStyleTaggedAnchor],
    nextValue: () -> [EnvironmentStyleTaggedAnchor]
  ) {
    value.append(contentsOf: nextValue())
  }
}

private enum EnvironmentStyleStringListPreferenceKey: PreferenceKey {
  static let defaultValue: [String] = []

  static func reduce(value: inout [String], nextValue: () -> [String]) {
    value.append(contentsOf: nextValue())
  }
}

@MainActor
private final class EnvironmentStyleEventProbe {
  var events: [String] = []
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

// MARK: - Attempt 011: enabled propagation through retained custom style

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 011 custom button style receives current enabled state")
  func environmentStyle011CustomButtonStyleReceivesCurrentEnabledState() throws {
    // Hypothesis: disabled transforms can invalidate the control action table without replacing
    // the retained ButtonStyleConfiguration consumed by a custom style body.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle011"),
      size: .init(width: 76, height: 7)
    ) {
      EnvironmentStyle011Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Toggle Enabled 011")
      let marker = generation.isMultiple(of: 2) ? "enabled" : "disabled"
      #expect(frame.contains("\(marker) Enabled Target 011"))
    }
  }
}

private struct EnvironmentStyle011ButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(configuration.isEnabled ? "enabled" : "disabled")
      configuration.label
    }
  }
}

private struct EnvironmentStyle011Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Enabled 011") { generation += 1 }
      Button("Enabled Target 011") {}
        .buttonStyle(EnvironmentStyle011ButtonStyle())
        .disabled(!generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 012: control prominence propagation

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 012 custom button style receives current prominence")
  func environmentStyle012CustomButtonStyleReceivesCurrentProminence() throws {
    // Hypothesis: controlProminence can update the environment snapshot without replacing the
    // configuration captured by a stable custom ButtonStyle body.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle012"),
      size: .init(width: 76, height: 7)
    ) {
      EnvironmentStyle012Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Toggle Prominence 012")
      let marker = generation.isMultiple(of: 2) ? "standard" : "increased"
      #expect(frame.contains("\(marker) Prominence Target 012"))
    }
  }
}

private struct EnvironmentStyle012ButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(configuration.controlProminence == .increased ? "increased" : "standard")
      configuration.label
    }
  }
}

private struct EnvironmentStyle012Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Prominence 012") { generation += 1 }
      Button("Prominence Target 012") {}
        .buttonStyle(EnvironmentStyle012ButtonStyle())
        .controlProminence(generation.isMultiple(of: 2) ? .standard : .increased)
    }
  }
}

// MARK: - Attempt 013: button-border-shape propagation

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 013 custom button style receives current border shape")
  func environmentStyle013CustomButtonStyleReceivesCurrentBorderShape() throws {
    // Hypothesis: buttonBorderShape can be omitted from erased-style invalidation, retaining an
    // earlier configuration after the environment writer changes in place.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle013"),
      size: .init(width: 76, height: 7)
    ) {
      EnvironmentStyle013Root()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Toggle Border Shape 013")
      let marker = generation.isMultiple(of: 2) ? "automatic" : "rounded"
      #expect(frame.contains("\(marker) Border Shape Target 013"))
    }
  }
}

private struct EnvironmentStyle013ButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(configuration.buttonBorderShape == .roundedRectangle ? "rounded" : "automatic")
      configuration.label
    }
  }
}

private struct EnvironmentStyle013Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Border Shape 013") { generation += 1 }
      Button("Border Shape Target 013") {}
        .buttonStyle(EnvironmentStyle013ButtonStyle())
        .buttonBorderShape(generation.isMultiple(of: 2) ? .automatic : .roundedRectangle)
    }
  }
}

// MARK: - Attempt 014: same-type erased text-field-style replacement

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 014 erased text field style refreshes payload and content")
  func environmentStyle014ErasedTextFieldStyleRefreshesPayloadAndContent() throws {
    // Hypothesis: AnyTextFieldStyle can preserve the first concrete style value while the field's
    // separately resolved display content continues to update, producing split-generation chrome.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle014"),
      size: .init(width: 78, height: 7)
    ) {
      EnvironmentStyle014Root()
    }
    defer { harness.shutdown() }

    for generation in 1...14 {
      let frame = try harness.clickText("Advance Field Style 014")
      #expect(frame.contains("field-style-\(generation)"))
      #expect(frame.contains("value-\(generation)"))
      #expect(!frame.contains("field-style-\(generation - 1)"))
    }
  }
}

private struct EnvironmentStyle014TextFieldStyle: TextFieldStyle {
  let marker: String

  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(marker)
      configuration.fieldContent
    }
  }
}

private struct EnvironmentStyle014Root: View {
  @State private var generation = 0
  @State private var value = "value-0"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Field Style 014") {
        generation += 1
        value = "value-\(generation)"
      }
      TextField("Field 014", text: $value)
        .textFieldStyle(EnvironmentStyle014TextFieldStyle(marker: "field-style-\(generation)"))
    }
  }
}

// MARK: - Attempt 015: cross-type erased text-field-style replacement

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 015 erased text field style replaces concrete family")
  func environmentStyle015ErasedTextFieldStyleReplacesConcreteFamily() throws {
    // Hypothesis: one AnyTextFieldStyle environment slot can keep a prior concrete box when it
    // alternates between built-in and custom style families around a stable field identity.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle015"),
      size: .init(width: 78, height: 7)
    ) {
      EnvironmentStyle015Root()
    }
    defer { harness.shutdown() }

    for generation in 1...14 {
      let frame = try harness.clickText("Toggle Field Family 015")
      #expect(frame.contains("field-value-\(generation)"))
      if generation.isMultiple(of: 2) {
        #expect(!frame.contains("custom-field-\(generation)"))
      } else {
        #expect(frame.contains("custom-field-\(generation)"))
      }
    }
  }
}

private struct EnvironmentStyle015Root: View {
  @State private var generation = 0
  @State private var value = "field-value-0"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Field Family 015") {
        generation += 1
        value = "field-value-\(generation)"
      }
      TextField("Field 015", text: $value)
        .textFieldStyle(
          generation.isMultiple(of: 2)
            ? AnyTextFieldStyle.plain
            : AnyTextFieldStyle(
              EnvironmentStyle014TextFieldStyle(marker: "custom-field-\(generation)")
            )
        )
    }
  }
}

// MARK: - Attempt 016: nested tint removal through style configuration

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 016 removing inner tint reveals current outer tint")
  func environmentStyle016RemovingInnerTintRevealsCurrentOuterTint() throws {
    // Hypothesis: StyleEnvironmentSnapshot can retain a departed nearest tint while other style
    // configuration fields refresh, masking a changed outer tint in custom controls.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle016"),
      size: .init(width: 76, height: 8)
    ) {
      EnvironmentStyle016Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      _ = try harness.clickText("Advance Tint 016")
      var frame = try harness.clickText("Toggle Inner Tint 016")
      let outer = generation.isMultiple(of: 2) ? "red" : "green"
      #expect(frame.contains("tint-\(outer) Tint Target 016"))

      frame = try harness.clickText("Toggle Inner Tint 016")
      #expect(frame.contains("tint-blue Tint Target 016"))
    }
  }
}

private struct EnvironmentStyle016ButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let marker: String
    if configuration.styleEnvironment.tintStyle == AnyShapeStyle(Color.red) {
      marker = "red"
    } else if configuration.styleEnvironment.tintStyle == AnyShapeStyle(Color.green) {
      marker = "green"
    } else if configuration.styleEnvironment.tintStyle == AnyShapeStyle(Color.blue) {
      marker = "blue"
    } else {
      marker = "none"
    }
    return HStack(spacing: 1) {
      Text("tint-\(marker)")
      configuration.label
    }
  }
}

private struct EnvironmentStyle016Root: View {
  @State private var generation = 0
  @State private var usesInner = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Tint 016") { generation += 1 }
      Button("Toggle Inner Tint 016") { usesInner.toggle() }
      Group {
        if usesInner {
          Button("Tint Target 016") {}
            .tint(Color.blue)
        } else {
          Button("Tint Target 016") {}
        }
      }
      .buttonStyle(EnvironmentStyle016ButtonStyle())
      .tint(generation.isMultiple(of: 2) ? Color.red : Color.green)
    }
  }
}

// MARK: - Attempt 017: Equatable boundary environment invalidation

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 017 equatable reader invalidates for environment changes")
  func environmentStyle017EquatableReaderInvalidatesForEnvironmentChanges() {
    // Hypothesis: an Equatable fast-path match can reuse a reader before its recorded environment
    // dependency is compared, serving stale output despite a changed custom key.
    struct Root: View {
      let generation: Int

      var body: some View {
        EnvironmentStyle017Reader(stableToken: 1)
          .environment(\.environmentStyleString, "environment-\(generation)")
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("EnvironmentStyle017")
    for generation in 0..<20 {
      let frame = renderer.render(
        Root(generation: generation),
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      #expect(
        environmentStyleText(frame).contains("017 token 1 value environment-\(generation)")
      )
    }
  }
}

private struct EnvironmentStyle017Reader: View {
  let stableToken: Int
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("017 token \(stableToken) value \(value)")
  }
}

extension EnvironmentStyle017Reader: @MainActor Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.stableToken == rhs.stableToken
  }
}

// MARK: - Attempt 018: AnyView environment-writer replacement

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 018 AnyView branch replacement drops departed override")
  func environmentStyle018AnyViewBranchReplacementDropsDepartedOverride() throws {
    // Hypothesis: AnyView payload replacement can reuse the erased subtree's prior environment
    // writer even after switching to a different concrete reader type without that override.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle018"),
      size: .init(width: 76, height: 8)
    ) {
      EnvironmentStyle018Root()
    }
    defer { harness.shutdown() }

    for generation in 1...14 {
      _ = try harness.clickText("Advance Erased Environment 018")
      var frame = try harness.clickText("Toggle Erased Branch 018")
      #expect(frame.contains("018 secondary outer-\(generation)"))

      frame = try harness.clickText("Toggle Erased Branch 018")
      #expect(frame.contains("018 primary inner-\(generation)"))
    }
  }
}

private struct EnvironmentStyle018Primary: View {
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    Text("018 primary \(value)")
  }
}

private struct EnvironmentStyle018Secondary: View {
  @Environment(\.environmentStyleString) private var value

  var body: some View {
    HStack(spacing: 0) {
      Text("018 secondary ")
      Text(value)
    }
  }
}

private struct EnvironmentStyle018Root: View {
  @State private var generation = 0
  @State private var showsPrimary = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Erased Environment 018") { generation += 1 }
      Button("Toggle Erased Branch 018") { showsPrimary.toggle() }
      if showsPrimary {
        AnyView(
          EnvironmentStyle018Primary()
            .environment(\.environmentStyleString, "inner-\(generation)")
        )
      } else {
        AnyView(EnvironmentStyle018Secondary())
      }
    }
    .environment(\.environmentStyleString, "outer-\(generation)")
  }
}

// MARK: - Attempt 019: composed ViewModifier environment dependency

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 019 composed modifier tracks environment dependency")
  func environmentStyle019ComposedModifierTracksEnvironmentDependency() throws {
    // Hypothesis: @Environment reads performed inside a composed ViewModifier body can be
    // attributed to its content node incorrectly, allowing the stable modifier node to be reused.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle019"),
      size: .init(width: 76, height: 7)
    ) {
      EnvironmentStyle019Root()
    }
    defer { harness.shutdown() }

    for generation in 1...18 {
      let frame = try harness.clickText("Advance Modifier Environment 019")
      #expect(frame.contains("modifier-env-\(generation) Modifier Target 019"))
    }
  }
}

private struct EnvironmentStyle019Modifier: ViewModifier {
  @Environment(\.environmentStyleString) private var value

  func body(content: Content) -> some View {
    HStack(spacing: 1) {
      Text(value)
      content
    }
  }
}

private struct EnvironmentStyle019Root: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Modifier Environment 019") { generation += 1 }
      Text("Modifier Target 019")
        .modifier(EnvironmentStyle019Modifier())
        .environment(\.environmentStyleString, "modifier-env-\(generation)")
    }
  }
}

// MARK: - Attempt 020: keyed preference-observer reorder

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 020 preference observers follow keyed owners through reorder")
  func environmentStyle020PreferenceObserversFollowKeyedOwnersThroughReorder() throws {
    // Hypothesis: same-key observer registrations can follow structural ordinals when keyed owners
    // move, dispatching a row's new value through another row's closure.
    let probe = EnvironmentStyleEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle020"),
      size: .init(width: 78, height: 9)
    ) {
      EnvironmentStyle020Root(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...14 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Reorder Preference Owners 020")
      #expect(probe.events.isEmpty)

      _ = try harness.clickText("Advance Preferences 020")
      #expect(Set(probe.events) == Set(["A:\(generation)", "B:\(generation)"]))
      #expect(probe.events.count == 2)
      #expect(harness.preferenceObservationRegistrationCount == 2)
    }
  }
}

private struct EnvironmentStyle020Item: Identifiable {
  let id: String
}

private struct EnvironmentStyle020Source: View {
  let item: EnvironmentStyle020Item
  let generation: Int
  let probe: EnvironmentStyleEventProbe

  var body: some View {
    Text("020 source \(item.id) \(generation)")
      .preference(key: EnvironmentStyleIntPreferenceKey.self, value: generation)
      .onPreferenceChange(EnvironmentStyleIntPreferenceKey.self) { value in
        probe.events.append("\(item.id):\(value)")
      }
  }
}

private struct EnvironmentStyle020Root: View {
  let probe: EnvironmentStyleEventProbe
  @State private var generation = 0
  @State private var reversed = false

  private var items: [EnvironmentStyle020Item] {
    let source = [EnvironmentStyle020Item(id: "A"), EnvironmentStyle020Item(id: "B")]
    return reversed ? Array(source.reversed()) : source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Preference Owners 020") { reversed.toggle() }
      Button("Advance Preferences 020") { generation += 1 }
      ForEach(items) { item in
        EnvironmentStyle020Source(item: item, generation: generation, probe: probe)
      }
    }
  }
}

// MARK: - Attempt 021: preference callback environment freshness

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 021 preference callback reads current environment")
  func environmentStyle021PreferenceCallbackReadsCurrentEnvironment() throws {
    // Hypothesis: a stable preference observer can refresh its baseline while retaining the first
    // environment snapshot captured by its registration action.
    let probe = EnvironmentStyleEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle021"),
      size: .init(width: 78, height: 7)
    ) {
      EnvironmentStyle021Root(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Advance Observed Environment 021")
      #expect(probe.events == ["observer-env-\(generation):\(generation)"])
      #expect(harness.preferenceObservationRegistrationCount == 1)
    }
  }
}

private struct EnvironmentStyle021Observer: View {
  let generation: Int
  let probe: EnvironmentStyleEventProbe
  @Environment(\.environmentStyleString) private var environmentValue

  var body: some View {
    Text("021 observed \(generation)")
      .preference(key: EnvironmentStyleIntPreferenceKey.self, value: generation)
      .onPreferenceChange(EnvironmentStyleIntPreferenceKey.self) { value in
        probe.events.append("\(environmentValue):\(value)")
      }
  }
}

private struct EnvironmentStyle021Root: View {
  let probe: EnvironmentStyleEventProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Observed Environment 021") { generation += 1 }
      EnvironmentStyle021Observer(generation: generation, probe: probe)
        .environment(\.environmentStyleString, "observer-env-\(generation)")
    }
  }
}

// MARK: - Attempt 022: surviving anchor after leading-source removal

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 022 anchor reduction drops removed leading source")
  func environmentStyle022AnchorReductionDropsRemovedLeadingSource() throws {
    // Hypothesis: removing the first source in an anchor reduction can leave its opaque token in
    // the reduced list or make the surviving token resolve against the departed source node.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle022"),
      size: .init(width: 78, height: 8)
    ) {
      EnvironmentStyle022Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      _ = try harness.clickText("Advance Anchors 022")
      var frame = try harness.clickText("Toggle Leading Anchor 022")
      let expectedB = generation.isMultiple(of: 2) ? 8 : 12
      #expect(frame.contains("022 B=\(expectedB)"))
      #expect(!frame.contains("022 A="))

      frame = try harness.clickText("Toggle Leading Anchor 022")
      #expect(frame.contains("022 A=6"))
      #expect(frame.contains("B=\(expectedB)"))
    }
  }
}

private struct EnvironmentStyle022Root: View {
  @State private var generation = 0
  @State private var showsLeading = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Anchors 022") { generation += 1 }
      Button("Toggle Leading Anchor 022") { showsLeading.toggle() }
      Group {
        if showsLeading {
          Text("anchor-a")
            .frame(width: 6, height: 1)
            .offset(x: 2)
            .id("environment-style-022-a")
            .anchorPreference(key: EnvironmentStyleAnchorListKey.self, value: .bounds) {
              [EnvironmentStyleTaggedAnchor(tag: "A", anchor: $0)]
            }
        }
        Text("anchor-b")
          .frame(width: generation.isMultiple(of: 2) ? 8 : 12, height: 1)
          .id("environment-style-022-b")
          .anchorPreference(key: EnvironmentStyleAnchorListKey.self, value: .bounds) {
            [EnvironmentStyleTaggedAnchor(tag: "B", anchor: $0)]
          }
      }
      .frame(width: 70, height: 3, alignment: .topLeading)
      .overlayPreferenceValue(EnvironmentStyleAnchorListKey.self, alignment: .bottomLeading) {
        anchors in
        GeometryReader { proxy in
          let markers = anchors.map { entry in
            "\(entry.tag)=\(Int(proxy[entry.anchor].size.width))"
          }
          Text("022 \(markers.joined(separator: " "))")
        }
      }
    }
  }
}

// MARK: - Attempt 023: stacked preference-derived layers

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 023 stacked preference layers read current reduction")
  func environmentStyle023StackedPreferenceLayersReadCurrentReduction() throws {
    // Hypothesis: background and overlay readers for one key can share retained preference state,
    // causing one layer to see the prior source order after keyed children move.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EnvironmentStyle023"),
      size: .init(width: 82, height: 10)
    ) {
      EnvironmentStyle023Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      _ = try harness.clickText("Reorder Layer Sources 023")
      let frame = try harness.clickText("Advance Layer Values 023")
      let values = generation.isMultiple(of: 2) ? "A-\(generation),B-\(generation)" : "B-\(generation),A-\(generation)"
      #expect(frame.contains("023 overlay \(values)"))
      #expect(frame.contains("023 background \(values)"))
    }
  }
}

private struct EnvironmentStyle023Root: View {
  @State private var generation = 0
  @State private var reversed = false

  private var labels: [String] {
    reversed ? ["B", "A"] : ["A", "B"]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Layer Sources 023") { reversed.toggle() }
      Button("Advance Layer Values 023") { generation += 1 }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(labels, id: \.self) { label in
          Text("source \(label)")
            .preference(
              key: EnvironmentStyleStringListPreferenceKey.self,
              value: ["\(label)-\(generation)"]
            )
        }
      }
      .frame(width: 78, height: 5, alignment: .center)
      .backgroundPreferenceValue(
        EnvironmentStyleStringListPreferenceKey.self,
        alignment: .bottomLeading
      ) { values in
        Text("023 background \(values.joined(separator: ","))")
      }
      .overlayPreferenceValue(
        EnvironmentStyleStringListPreferenceKey.self,
        alignment: .topLeading
      ) { values in
        Text("023 overlay \(values.joined(separator: ","))")
      }
    }
  }
}

// MARK: - Attempt 024: stacked transaction modifier order churn

extension FrameworkStressEnvironmentStyleTests {
  @Test("stress environment style 024 stacked transaction order follows current branch")
  func environmentStyle024StackedTransactionOrderFollowsCurrentBranch() throws {
    // Hypothesis: structurally stable TransactionModifier nodes can reuse closures by ordinal when
    // two opposing transforms reverse authored order, preserving the prior winner.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("024 transaction \(generation)")
            .transaction { $0.disablesAnimations = true }
            .transaction { $0.disablesAnimations = false }
        } else {
          Text("024 transaction \(generation)")
            .transaction { $0.disablesAnimations = false }
            .transaction { $0.disablesAnimations = true }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("EnvironmentStyle024")
    for generation in 0..<20 {
      let retained = renderer.render(
        Root(generation: generation),
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      let fresh = DefaultRenderer().render(
        Root(generation: generation),
        context: .init(identity: identity)
      )
      let retainedNode = try #require(
        environmentStyleDescendant(
          retained.resolvedTree,
          text: "024 transaction \(generation)"
        )
      )
      let freshNode = try #require(
        environmentStyleDescendant(fresh.resolvedTree, text: "024 transaction \(generation)")
      )
      let expected: AnimationRequest = generation.isMultiple(of: 2) ? .disabled : .inherit
      #expect(retainedNode.transactionSnapshot.animationRequest == expected)
      #expect(retainedNode.transactionSnapshot == freshNode.transactionSnapshot)
    }
  }
}

private func environmentStyleDescendant(_ node: ResolvedNode, text: String) -> ResolvedNode? {
  if case .text(let value) = node.drawPayload, value == text {
    return node
  }
  for child in node.children {
    if let match = environmentStyleDescendant(child, text: text) {
      return match
    }
  }
  return nil
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
