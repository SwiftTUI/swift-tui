import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
struct PassiveCompositionStyleTests {
  @Test("label built-ins render distinct treatments", arguments: [0, 1, 2, 3])
  func labelTreatments(_ index: Int) {
    let styles: [AnyLabelStyle] = [.automatic, .titleAndIcon, .titleOnly, .iconOnly]
    let frame = render(Label("Title") { Text("*") }.labelStyle(styles[index]))
    let text = frame.rasterSurface.lines.joined()
    #expect(text.contains("Title") == (index != 3))
    #expect(text.contains("*") == (index != 2))
  }

  @Test("labeled content switches between baseline and stacked composition")
  func labeledContentTreatments() {
    let row = render(LabeledContent("Name", value: "Ada").labeledContentStyle(.automatic))
    let stack = render(LabeledContent("Name", value: "Ada").labeledContentStyle(.stacked))
    #expect(row.rasterSurface.lines.contains { $0.contains("Name") && $0.contains("Ada") })
    #expect(!stack.rasterSurface.lines.contains { $0.contains("Name") && $0.contains("Ada") })
    #expect(stack.rasterSurface.lines.contains { $0.contains("Name") })
    #expect(stack.rasterSurface.lines.contains { $0.contains("Ada") })
  }

  @Test("group box automatic aliases bordered, while plain removes the border")
  func groupBoxTreatments() {
    let box = GroupBox("Group") { Text("Value") }
    expectSameSurface(box.groupBoxStyle(.automatic), box.groupBoxStyle(.bordered))
    let plain = render(box.groupBoxStyle(.plain))
    let bordered = render(box.groupBoxStyle(.bordered))
    #expect(plain.rasterSurface != bordered.rasterSurface)
    #expect(plain.rasterSurface.lines.joined().contains("Value"))
    #expect(!plain.rasterSurface.lines.joined().contains("╭"))
  }

  @Test("nearest style overrides its ancestor and does not leak to siblings")
  func nearestStyleWins() {
    let frame = render(
      VStack(alignment: .leading, spacing: 0) {
        Label("Visible") { Text("first-icon") }.labelStyle(.titleOnly)
        Label("Hidden") { Text("second-icon") }
        LabeledContent("Row", value: "One").labeledContentStyle(.automatic)
        LabeledContent("Stack", value: "Two")
        GroupBox("Plain") { Text("Three") }.groupBoxStyle(.plain)
        GroupBox("Bordered") { Text("Four") }
      }
      .labelStyle(.iconOnly)
      .labeledContentStyle(.stacked)
      .groupBoxStyle(.bordered), height: 18)
    let text = frame.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("Visible"))
    #expect(!text.contains("first-icon"))
    #expect(!text.contains("Hidden"))
    #expect(text.contains("second-icon"))
    #expect(frame.rasterSurface.lines.contains { $0.contains("Row") && $0.contains("One") })
    #expect(!frame.rasterSurface.lines.contains { $0.contains("Stack") && $0.contains("Two") })
    #expect(text.filter { $0 == "╭" }.count == 1)
  }

  @Test("public consumer styles reproduce the default compositions")
  func thirdPartyParity() {
    let label = Label("Title") { Text("*") }
    expectSameSurface(label, label.labelStyle(ConsumerLabelStyle()))
    let row = LabeledContent("Name", value: "Ada")
    expectSameSurface(row, row.labeledContentStyle(ConsumerLabeledContentStyle()))
    let box = GroupBox("Group") { Text("Value") }.controlProminence(.increased)
    expectSameSurface(box, box.groupBoxStyle(ConsumerGroupBoxStyle()))
    let unlabeled = GroupBox { Text("Value") }
    expectSameSurface(unlabeled, unlabeled.groupBoxStyle(ConsumerGroupBoxStyle()))
  }

  @Test("each primitive supplies its current style environment once")
  func configurationEnvironment() {
    let probe = PassiveStyleEnvironmentProbe()
    var environment = EnvironmentValues()
    environment.isEnabled = false
    environment.controlProminence = .increased
    environment.foregroundStyle = AnyShapeStyle(.red)
    environment.tintStyle = AnyShapeStyle(.green)
    var appearance = TerminalAppearance.fallback
    appearance.colorSchemeContrast = .increased
    environment.terminalAppearance = appearance
    let expected = environment.styleEnvironmentSnapshot
    _ = DefaultRenderer().render(
      VStack {
        Label("Title") { Text("*") }.labelStyle(InspectingLabelStyle(probe: probe))
        LabeledContent("Name", value: "Ada")
          .labeledContentStyle(InspectingLabeledContentStyle(probe: probe))
        GroupBox { Text("Value") }.groupBoxStyle(InspectingGroupBoxStyle(probe: probe))
      },
      context: .init(
        identity: testIdentity("Root"), environmentValues: environment, applyEnvironmentValues: true
      ), proposal: .init(width: 32, height: 12))
    #expect(probe.label == [expected])
    #expect(probe.labeledContent == [expected])
    #expect(probe.groupBox == [expected])
    #expect(probe.prominence == [.increased])
    #expect(probe.hasLabel == [false])
  }

  @Test("style changes preserve authored actions and unrelated retained state")
  func liveStyleChanges() throws {
    let probe = PassiveStyleLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 44, height: 22)
    ) {
      PassiveStyleSwitchFixture(probe: probe)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Slot 0")
    _ = try harness.clickText("Sibling 0")
    let frame = try harness.clickText("Change Styles")
    #expect(frame.contains("NewLabel"))
    #expect(frame.contains("NewRow"))
    #expect(frame.contains("NewBox"))
    #expect(frame.contains("Slot 1"))
    #expect(frame.contains("Sibling 1"))
    #expect(probe.appearances == 1)
    let updated = try harness.clickText("Slot 1")
    #expect(updated.contains("Slot 2"))
  }

  @Test("default label preserves its title-and-icon layout", arguments: [6, 24])
  func defaultLabel(width: Int) {
    expectSameSurface(
      Label("Title") { Text("*") },
      HStack(alignment: .center, spacing: 1) {
        Text("*")
        Text("Title")
      }, width: width)
  }

  @Test("default labeled content preserves its baseline row", arguments: [8, 24])
  func defaultLabeledContent(width: Int) {
    expectSameSurface(
      LabeledContent("Name", value: "Ada"),
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text("Name").foregroundStyle(.separator)
        Spacer()
        Text("Ada")
      }, width: width)
  }

  @Test("default group box preserves its chrome", arguments: [false, true], [false, true])
  func defaultGroupBox(showsLabel: Bool, prominent: Bool) {
    let prominence: ControlProminence = prominent ? .increased : .standard
    let oldBody = EnvironmentReader(\.styleEnvironmentSnapshot) { environment in
      let chrome = environment.groupBoxChrome(prominence: prominence)
      VStack(alignment: .leading, spacing: 0) {
        if showsLabel {
          Text("Group").foregroundStyle(.separator)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("First")
          Text("Second")
        }
        .padding(.init(horizontal: 1, vertical: 1))
        .overlay {
          RoundedRectangle(cornerRadius: 1).strokeBorder(chrome.borderStyle)
        }
        .foregroundStyle(chrome.foregroundStyle)
      }
      .layoutMetadata(.init(minimumHeight: (showsLabel ? 1 : 0) + 3))
    }
    if showsLabel {
      expectSameSurface(
        GroupBox("Group") {
          Text("First")
          Text("Second")
        }.controlProminence(prominence), oldBody)
    } else {
      expectSameSurface(
        GroupBox {
          Text("First")
          Text("Second")
        }.controlProminence(prominence), oldBody)
    }
  }

  @Test(
    "empty group boxes preserve their minimum height and label position", arguments: [false, true])
  func emptyGroupBox(showsLabel: Bool) {
    let oldBody = EnvironmentReader(\.styleEnvironmentSnapshot) { environment in
      let chrome = environment.groupBoxChrome()
      VStack(alignment: .leading, spacing: 0) {
        if showsLabel { Text("Group").foregroundStyle(.separator) }
        VStack(alignment: .leading, spacing: 0) { EmptyView() }
          .padding(.init(horizontal: 1, vertical: 1))
          .overlay {
            RoundedRectangle(cornerRadius: 1).strokeBorder(chrome.borderStyle)
          }
          .foregroundStyle(chrome.foregroundStyle)
      }
      .layoutMetadata(.init(minimumHeight: (showsLabel ? 1 : 0) + 3))
    }
    if showsLabel {
      expectSameSurface(GroupBox("Group") { EmptyView() }, oldBody)
    } else {
      expectSameSurface(GroupBox { EmptyView() }, oldBody)
    }
  }

  private func expectSameSurface<A: View, B: View>(
    _ actual: A, _ expected: B, width: Int = 24
  ) {
    let context = ResolveContext(identity: testIdentity("Root"))
    let proposal = ProposedSize(width: width, height: 8)
    let actualFrame = DefaultRenderer().render(actual, context: context, proposal: proposal)
    let expectedFrame = DefaultRenderer().render(expected, context: context, proposal: proposal)
    #expect(
      actualFrame.rasterSurface == expectedFrame.rasterSurface,
      "actual: \(actualFrame.rasterSurface.lines) expected: \(expectedFrame.rasterSurface.lines)")
  }

  private func render<V: View>(_ view: V, height: Int = 8) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: height))
  }

}

@MainActor
private final class PassiveStyleLifecycleProbe {
  var appearances = 0
}

private struct PassiveStyleSwitchFixture: View {
  let probe: PassiveStyleLifecycleProbe
  @State private var changed = false
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Change Styles") { changed.toggle() }
      Label("Title") { Text("*") }
      LabeledContent("Name", value: "Ada")
      GroupBox("Group") {
        Button("Slot \(count)") { count += 1 }
      }
      PassiveStyleSibling(probe: probe)
    }
    .labelStyle(ConsumerLabelStyle(prefix: changed ? "NewLabel" : "OldLabel"))
    .labeledContentStyle(ConsumerLabeledContentStyle(prefix: changed ? "NewRow" : "OldRow"))
    .groupBoxStyle(ConsumerGroupBoxStyle(prefix: changed ? "NewBox" : "OldBox"))
  }
}

private struct PassiveStyleSibling: View {
  let probe: PassiveStyleLifecycleProbe
  @State private var count = 0

  var body: some View {
    Button("Sibling \(count)") { count += 1 }
      .onAppear { probe.appearances += 1 }
  }
}

@MainActor
private final class PassiveStyleEnvironmentProbe {
  var label: [StyleEnvironmentSnapshot] = []
  var labeledContent: [StyleEnvironmentSnapshot] = []
  var groupBox: [StyleEnvironmentSnapshot] = []
  var prominence: [ControlProminence] = []
  var hasLabel: [Bool] = []
}

private struct InspectingLabelStyle: LabelStyle {
  let probe: PassiveStyleEnvironmentProbe

  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    probe.label.append(configuration.styleEnvironment)
    return configuration.title
  }
}

private struct InspectingLabeledContentStyle: LabeledContentStyle {
  let probe: PassiveStyleEnvironmentProbe

  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    probe.labeledContent.append(configuration.styleEnvironment)
    return configuration.content
  }
}

private struct InspectingGroupBoxStyle: GroupBoxStyle {
  let probe: PassiveStyleEnvironmentProbe

  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    probe.groupBox.append(configuration.styleEnvironment)
    probe.prominence.append(configuration.controlProminence)
    probe.hasLabel.append(configuration.label != nil)
    return configuration.content
  }
}
