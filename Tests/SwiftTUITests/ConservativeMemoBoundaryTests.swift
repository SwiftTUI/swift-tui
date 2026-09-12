import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Conservative opaque memo boundaries")
struct ConservativeMemoBoundaryTests {
  @Test("closure captures are reevaluated even when the closure value is retained")
  func closureCapture() {
    let model = LabelModel()
    let view = ClosureLabel { model.label }
    #expect(!MemoComparisonPlanCache.hasPlan(for: ClosureLabel.self))
    let renderer = DefaultRenderer()
    assertText("before", view, renderer: renderer)
    assertText("before", view, renderer: renderer)
    model.label = "after"
    assertText("after", view, renderer: renderer)
  }

  @Test("erased view replacements preserve the current content")
  func erasedView() {
    #expect(!MemoComparisonPlanCache.hasPlan(for: ErasedLabel.self))
    let renderer = DefaultRenderer()
    assertText("before", ErasedLabel(content: AnyView(Text("before"))), renderer: renderer)
    assertText("before", ErasedLabel(content: AnyView(Text("before"))), renderer: renderer)
    assertText("after", ErasedLabel(content: AnyView(Text("after"))), renderer: renderer)
  }

  @Test("opaque existential payloads are never treated as equal by their container")
  func existential() {
    #expect(!MemoComparisonPlanCache.hasPlan(for: ExistentialLabel.self))
    let renderer = DefaultRenderer()
    assertText("before", ExistentialLabel(value: LabelValue(label: "before")), renderer: renderer)
    assertText("before", ExistentialLabel(value: LabelValue(label: "before")), renderer: renderer)
    assertText("after", ExistentialLabel(value: LabelValue(label: "after")), renderer: renderer)
  }

  @Test("non-POD non-Equatable enum payload and case changes remain visible")
  func enumPayload() {
    #expect(!MemoComparisonPlanCache.hasPlan(for: EnumLabel.self))
    let renderer = DefaultRenderer()
    assertText("before", EnumLabel(value: .label("before")), renderer: renderer)
    assertText("before", EnumLabel(value: .label("before")), renderer: renderer)
    assertText("after", EnumLabel(value: .label("after")), renderer: renderer)
    assertText("empty", EnumLabel(value: .empty), renderer: renderer)
  }

  private func assertText(_ expected: String, _ view: some View, renderer: DefaultRenderer) {
    let frame = renderer.render(view, proposal: .init(width: 20, height: 2))
    #expect(frame.rasterSurface.lines.joined().contains(expected))
  }
}

@MainActor
private final class LabelModel { var label = "before" }

private struct ClosureLabel: View {
  let value: () -> String
  var body: some View { Text(value()) }
}

private struct ErasedLabel: View {
  // AnyView policy: this fixture qualifies the public type-erasure boundary.
  let content: AnyView
  var body: some View { content }
}

private protocol LabelProviding { var label: String { get } }
private struct LabelValue: LabelProviding { let label: String }
private struct ExistentialLabel: View {
  let value: any LabelProviding
  var body: some View { Text(value.label) }
}

private enum LabelChoice {
  case empty
  case label(String)
}
private struct EnumLabel: View {
  let value: LabelChoice
  var body: some View {
    switch value {
    case .empty: Text("empty")
    case .label(let label): Text(label)
    }
  }
}
