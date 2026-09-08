import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct DynamicStylePropertyTests {
  @Test("stored style wrappers update the concrete body and escaped action copy")
  func workingCopy() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DynamicStyle"), size: .init(width: 50, height: 16)
    ) {
      VStack {
        Label("First") { Text("*") }
        Label("Second") { Text("*") }
      }.labelStyle(UpdatingLabelStyle())
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("Updated 1"))
    #expect(!harness.frame.contains("Updated 0"))
    _ = try harness.clickText("Style count 0")
    #expect(harness.frame.contains("Style count 1"))
    #expect(harness.frame.contains("Style count 0"))
    _ = try harness.clickText("Style count 1")
    #expect(harness.frame.contains("Style count 2"))
  }

  @Test("button style wrappers receive current environment and update before makeBody")
  func buttonEnvironment() {
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("DynamicButton"))
    for disabled in [false, true, false] {
      let frame = renderer.render(
        Button("Action") {}.buttonStyle(UpdatingButtonStyle()).disabled(disabled),
        context: context, proposal: .init(width: 40, height: 10))
      #expect(frame.rasterSurface.lines.joined().contains("Updated 1 enabled \(!disabled)"))
    }
  }
}

@propertyWrapper @MainActor
private struct StyleTick: DynamicProperty {
  var wrappedValue = 0
  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    wrappedValue += 1
    return .changed
  }
}

private struct UpdatingLabelStyle: LabelStyle {
  @StyleTick private var tick: Int
  @State private var count = 0

  @MainActor init() {}

  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack {
      configuration.title
      Text("Updated \(tick)")
      Button("Style count \(count)") { count += tick }
    }
  }
}

private struct UpdatingButtonStyle: ButtonStyle {
  @StyleTick private var tick: Int
  @Environment(\.isEnabled) private var enabled

  @MainActor init() {}

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Text("Updated \(tick) enabled \(enabled)")
  }
}
