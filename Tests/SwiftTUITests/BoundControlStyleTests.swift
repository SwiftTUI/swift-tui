import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
struct BoundControlStyleTests {
  @Test("style binding projections retain the source token and stored transaction")
  func projectedBindingMetadata() {
    let value = BoundStyleValue(false)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    let binding = value.binding.transaction(transaction).withBindingSource("original")
    let capture = BoundStyleCapture()
    _ = render(Toggle("Switch", isOn: binding).toggleStyle(CapturingToggleStyle(capture: capture)))
    _ = render(
      DisclosureGroup("Details", isExpanded: binding) { Text("Child") }
        .disclosureGroupStyle(CapturingDisclosureStyle(capture: capture)))
    #expect(capture.toggle?.$isOn.transaction.disablesAnimations == true)
    #expect(capture.disclosure?.$isExpanded.transaction.disablesAnimations == true)
    #expect(capture.toggle?.$isOn.bindingSourceID == binding.bindingSourceID)
    #expect(capture.disclosure?.$isExpanded.bindingSourceID == binding.bindingSourceID)
  }

  @Test(
    "toggle styles keep primitive-owned pointer and keyboard activation", arguments: [0, 1, 2, 3])
  func toggleActivation(_ index: Int) throws {
    let value = BoundStyleValue(false)
    let styles: [AnyToggleStyle] = [.automatic, .checkbox, .button, .init(ConsumerToggleStyle())]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 28, height: 5)
    ) {
      Toggle("Switch", isOn: value.binding).toggleStyle(styles[index])
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Switch")
    #expect(value.value && value.writes == 1)
    _ = try harness.pressKey(KeyPress(.space))
    #expect(!value.value && value.writes == 2)
  }

  @Test(
    "disclosure styles keep expansion and children under primitive ownership", arguments: [0, 1, 2])
  func disclosureActivation(_ index: Int) throws {
    let value = BoundStyleValue(false)
    let styles: [AnyDisclosureGroupStyle] = [
      .automatic, .compact, .init(ConsumerDisclosureGroupStyle()),
    ]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 28, height: 7)
    ) {
      DisclosureGroup("Details", isExpanded: value.binding) { Text("Secret child") }
        .disclosureGroupStyle(styles[index])
    }
    defer { harness.shutdown() }
    let opened = try harness.clickText("Details")
    #expect(opened.contains("Secret child"))
    #expect(value.value && value.writes == 1)
    let closed = try harness.pressKey(KeyPress(.space))
    #expect(!closed.contains("Secret child"))
    #expect(!value.value && value.writes == 2)
  }

  @Test(
    "custom styles receive write-through bindings guarded by enablement", arguments: [false, true])
  func bindingOwnership(_ enabled: Bool) {
    let value = BoundStyleValue(false)
    let capture = BoundStyleCapture()
    _ = render(
      Toggle("Switch", isOn: value.binding)
        .toggleStyle(CapturingToggleStyle(capture: capture)).disabled(!enabled))
    capture.toggle?.isOn = true
    #expect(value.value == enabled)
    #expect(value.writes == (enabled ? 1 : 0))
    _ = render(
      DisclosureGroup("Details", isExpanded: value.binding) { Text("Secret child") }
        .disclosureGroupStyle(CapturingDisclosureStyle(capture: capture)).disabled(!enabled))
    capture.disclosure?.isExpanded = false
    #expect(value.value == false)
    #expect(value.writes == (enabled ? 2 : 0))
  }

  @Test("a custom disclosure cannot display collapsed authored content")
  func collapsedSlotIsProtected() {
    let frame = render(
      DisclosureGroup("Details", isExpanded: .constant(false)) { Text("Secret child") }
        .disclosureGroupStyle(UnconditionalDisclosureContentStyle()))
    #expect(!frame.rasterSurface.lines.joined().contains("Secret child"))
  }

  @Test("default and public consumer styles have equal raster output", arguments: [false, true])
  func consumerParity(_ enabled: Bool) {
    for isOn in [false, true] {
      let control = Toggle("Switch", isOn: .constant(isOn)).disabled(!enabled)
      same(control, control.toggleStyle(ConsumerToggleStyle()))
      let group = DisclosureGroup("Details", isExpanded: .constant(isOn)) { Text("Child") }
        .disabled(!enabled)
      same(group, group.disclosureGroupStyle(ConsumerDisclosureGroupStyle()))
    }
    let editor = TextEditor(text: .constant("First\nSecond")).disabled(!enabled)
    same(editor, editor.textEditorStyle(ConsumerTextEditorStyle()))
    same(editor, editor.textEditorStyle(.roundedBorder))
    let progress = ProgressView(value: 0.5, barWidth: 8)
    same(progress, progress.progressViewStyle(ConsumerProgressViewStyle()))
    let indeterminate = ProgressView("Working", barWidth: 8)
    same(indeterminate, indeterminate.progressViewStyle(ConsumerProgressViewStyle()))
  }

  @Test("text editor navigation follows its styled viewport", arguments: [0, 1, 2, 3])
  func editorWrap(_ index: Int) throws {
    let value = BoundStyleValue("ABCDEFGHIJKL")
    let styles: [AnyTextEditorStyle] = [
      .automatic, .plain, .roundedBorder, .init(PaddedConsumerEditorStyle()),
    ]
    let widths = [7, 5, 7, 9]
    let editorID = testIdentity("Editor")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 12, height: 7)
    ) {
      TextEditor(text: value.binding).textEditorStyle(styles[index]).id(editorID)
        .frame(width: widths[index], height: 5, alignment: .topLeading)
    }
    defer { harness.shutdown() }
    _ = try harness.focus(editorID)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    _ = try harness.pressKey(KeyPress(.character("!")))
    #expect(value.value == "ABCDEFGHI!JKL")
    #expect(value.writes == 1)
  }

  @Test("circular progress inherits spinner style and suppresses tasks under reduced motion")
  func circularSpinnerPolicy() {
    let tasks = LocalTaskRegistry()
    var environment = EnvironmentValues()
    environment.accessibilityReduceMotion = false
    let context = ResolveContext(
      identity: testIdentity("Root"), environmentValues: environment,
      localTaskRegistry: tasks, applyEnvironmentValues: true)
    let normal = DefaultRenderer().render(
      ProgressView("Working").progressViewStyle(.circular).spinnerStyle(.lineCompass),
      context: context, proposal: .init(width: 24, height: 8))
    #expect(normal.rasterSurface.lines.joined().contains("Working"))
    #expect(!tasks.snapshot().isEmpty)
    let reducedTasks = LocalTaskRegistry()
    environment.accessibilityReduceMotion = true
    let reduced = DefaultRenderer().render(
      ProgressView("Working").progressViewStyle(.circular),
      context: .init(
        identity: testIdentity("Root"), environmentValues: environment,
        localTaskRegistry: reducedTasks, applyEnvironmentValues: true),
      proposal: .init(width: 24, height: 8))
    #expect(reduced.rasterSurface.lines.joined().contains("Working"))
    #expect(reducedTasks.snapshot().isEmpty)
  }

  private func same<A: View, B: View>(_ actual: A, _ expected: B) {
    let a = render(actual).rasterSurface
    let b = render(expected).rasterSurface
    let matches = a == b
    #expect(matches, "actual: \(a.lines) expected: \(b.lines)")
  }

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 28, height: 8))
  }
}

@MainActor
private final class BoundStyleValue<Value: Sendable> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}

@MainActor
private final class BoundStyleCapture {
  var toggle: ToggleStyleConfiguration?
  var disclosure: DisclosureGroupStyleConfiguration?
}

private struct CapturingToggleStyle: ToggleStyle {
  let capture: BoundStyleCapture
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    capture.toggle = configuration
    return configuration.label
  }
}

private struct CapturingDisclosureStyle: DisclosureGroupStyle {
  let capture: BoundStyleCapture
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    capture.disclosure = configuration
    return configuration.label
  }
}

private struct UnconditionalDisclosureContentStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack {
      configuration.label
      configuration.content
    }
  }
}
