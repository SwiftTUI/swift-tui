import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct StyledControlAccessibilityTests {
  @Test("counter button title survives built-in styles and shortcut chrome")
  func counterButton() {
    for style in [AnyButtonStyle.automatic, .plain, .bordered, .borderedProminent] {
      let snapshot = render(Button("Increment") {}.systemHint("Ctrl+I").buttonStyle(style))
      #expect(snapshot.accessibilityNodes.first { $0.role == .button }?.label == "Increment")
      #expect(LinearAccessibilityRenderer().render(snapshot).contains("button: Increment"))
      #expect(!LinearAccessibilityRenderer().render(snapshot).contains("Ctrl+I"))
    }
  }

  @Test("generic labels use authored order, overrides, and hidden policy without style chrome")
  func genericLabel() {
    let snapshot = render(
      Button {
      } label: {
        HStack {
          Text("Save")
          Text("decorative").accessibilityHidden()
          Text("disk glyph").accessibilityLabel("document")
        }
      }.buttonStyle(DecoratedButtonStyle())
    )
    #expect(snapshot.accessibilityNodes.first { $0.role == .button }?.label == "Save document")
    #expect(snapshot.accessibilityNodes.allSatisfy { !$0.hidden })
  }

  @Test("Label contributes its title without its icon, including icon-only presentation")
  func composedLabel() {
    let snapshot = render(
      VStack {
        Button {
        } label: {
          Label("Open") { Text("icon") }
        }
        Button {
        } label: {
          Label("Close") { Text("icon") }.labelStyle(.iconOnly)
        }
      }
    )
    #expect(
      snapshot.accessibilityNodes.filter { $0.role == .button }.map(\.label) == ["Open", "Close"])
  }

  @Test("a label with multiple top-level elements contributes every element once")
  func multipleLabelElements() {
    let snapshot = render(
      Button {
      } label: {
        Text("decoration").accessibilityHidden()
        Text("Save")
        Text("document")
      }.buttonStyle(DecoratedButtonStyle())
    )
    #expect(snapshot.accessibilityNodes.first { $0.role == .button }?.label == "Save document")
  }

  @Test("label-owned state updates the name without an outer control state change")
  func labelOwnedState() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LabelOwnedState"), size: .init(width: 40, height: 8)
    ) {
      Button {
      } label: {
        LocalStateLabel()
      }
    }
    defer { harness.shutdown() }
    for generation in 1...3 {
      _ = try harness.clickText("Local \(generation - 1)")
      #expect(
        harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.role == .button }?
          .label
          == "Local \(generation)")
    }
  }

  @Test("explicit control labels win and an empty override stays empty")
  func explicitOverrides() {
    let snapshot = render(
      VStack {
        Button("Increment") {}.accessibilityLabel("Add one")
        Button("Increment") {}.accessibilityLabel("")
        Button("Secret") {}.accessibilityHidden()
        Button("Omitted title") {}.buttonStyle(OmittedButtonStyle())
      }
    )
    #expect(
      snapshot.accessibilityNodes.filter { $0.role == .button }.map(\.label)
        == ["Add one", "", "Omitted title"])
  }

  @Test("value controls use their authored labels rather than values or glyphs")
  func valueControls() {
    let snapshot = render(
      VStack {
        Toggle("Enabled", isOn: .constant(true))
        Slider("Volume", value: .constant(3), in: 0...10)
        Stepper("Count", value: .constant(2), in: 0...10)
        Picker("Choice", selection: .constant(1)) { Text("First").tag(1) }
        TextField(text: .constant("entered value")) { Text("Account") }
        TextField("Search", text: .constant("query"))
        SecureField(text: .constant("private-password")) { Text("Password") }
        DisclosureGroup(isExpanded: .constant(true)) {
          Text("Expanded content")
        } label: {
          Text("Details")
        }
        ProgressView("Download", value: 0.5)
      }
    )
    let names = snapshot.accessibilityNodes.filter {
      [.toggle, .slider, .stepper, .picker, .textField, .secureField, .disclosureGroup, .status]
        .contains($0.role)
    }.map(\.label)
    #expect(
      names == [
        "Enabled", "Volume", "Count", "Choice", "Account", "Search", "Password", "Details",
        "Download",
      ])
    #expect(!String(describing: snapshot.accessibilityNodes).contains("private-password"))
  }

  @Test("stateful generic label refreshes through the real input and retained graph path")
  func statefulLabel() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AuthoredLabel"), size: .init(width: 40, height: 8)
    ) { StatefulLabelFixture() }
    defer { harness.shutdown() }
    for generation in 1...3 {
      _ = try harness.clickText("Advance")
      #expect(
        harness.runLoop.latestSemanticSnapshot.accessibilityNodes.last { $0.role == .button }?.label
          == "Generation \(generation)")
    }
  }

  private func render<V: View>(_ view: V) -> SemanticSnapshot {
    DefaultRenderer().render(
      view, context: ResolveContext(identity: testIdentity("StyledControl")),
      proposal: .init(width: 80, height: 30)
    ).semanticSnapshot
  }
}

private struct DecoratedButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack {
      Text("prefix chrome")
      configuration.label
      configuration.label
      Text("suffix chrome")
    }
  }
}

private struct OmittedButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View { Text("chrome only") }
}

private struct StatefulLabelFixture: View {
  @State private var generation = 0
  var body: some View {
    VStack {
      Button("Advance") { generation += 1 }
      Button {
      } label: {
        HStack {
          Text("Generation")
          Text("\(generation)")
        }
      }.buttonStyle(DecoratedButtonStyle())
    }
  }
}

private struct LocalStateLabel: View {
  @State private var generation = 0
  var body: some View {
    Text("Local \(generation)").onTapGesture { generation += 1 }
  }
}
