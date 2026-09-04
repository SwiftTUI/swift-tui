@_spi(StyleFixtures) import SwiftTUIViews
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite("Picker style parity")
struct PickerStyleParityTests {
  @Test("every built-in picker fixture has inert routes", arguments: PickerTreatment.builtIns)
  func builtInFixturesAreInert(_ treatment: PickerTreatment) {
    let configuration = fixtureConfiguration()
    let artifacts = DefaultRenderer().render(
      treatment.fixtureBody(configuration),
      context: .init(identity: testIdentity("PickerFixture")),
      proposal: .init(width: 40, height: 8)
    )
    #expect(pointerTargets(artifacts.resolvedTree).isEmpty)
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
    #expect(artifacts.rasterSurface.lines.joined().contains("Beta"))
  }

  @Test("fixture option and trigger wrappers are inert, even with a supplied identity")
  func consumerFixtureRoutesAreInert() {
    let configuration = fixtureConfiguration()
    let artifacts = DefaultRenderer().render(
      ConsumerPickerStyle(menu: true, duplicates: true).makeBody(configuration: configuration),
      context: .init(identity: testIdentity("PickerFixture")),
      proposal: .init(width: 40, height: 8)
    )
    #expect(pointerTargets(artifacts.resolvedTree).isEmpty)
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
    #expect(configuration.options.map(\.index) == [0, 1])
    #expect(configuration.options.map(\.isSelected) == [true, false])
  }

  @Test(
    "public option routes select duplicate labels by occurrence",
    arguments: PickerTreatment.allCases)
  func pointerSelection(_ treatment: PickerTreatment) throws {
    let probe = PickerParityProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 42, height: 12)
    ) {
      PickerParityFixture(probe: probe, style: treatment.style)
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Choice")
    if treatment.isMenu {
      _ = try harness.clickText("Alpha")
    }
    _ = try harness.clickText("Duplicate", chooseLast: true)
    #expect(probe.selection == 2)
    #expect(probe.writes == 1)
  }

  @Test(
    "built-in and consumer menu triggers toggle with pointer and keyboard",
    arguments: [false, true])
  func menuTriggerToggles(_ consumer: Bool) throws {
    let probe = PickerParityProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 42, height: 12)
    ) {
      PickerParityFixture(
        probe: probe,
        style: consumer ? AnyPickerStyle(ConsumerPickerStyle(menu: true)) : .menu
      )
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Alpha")
    #expect(harness.frame.contains("Duplicate"))
    var frame = try harness.clickText("Alpha")
    #expect(!frame.contains("Duplicate"))
    frame = try harness.clickText("Alpha")
    #expect(frame.contains("Duplicate"))
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Duplicate"))
    frame = try harness.pressKey(KeyPress(.return))
    #expect(frame.contains("Duplicate"))
    frame = try harness.pressKey(KeyPress(.space))
    #expect(!frame.contains("Duplicate"))
    frame = try harness.pressKey(KeyPress(.arrowDown))
    #expect(frame.contains("Duplicate"))
    #expect(probe.selection == 1)
  }

  @Test("omitting a menu trigger preserves expansion through keyboard actions")
  func omittedMenuTriggerPreservesKeyboard() throws {
    let probe = PickerParityProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 42, height: 12)
    ) {
      PickerParityFixture(
        probe: probe,
        style: AnyPickerStyle(ConsumerPickerStyle(menu: true, omitsRoutes: true))
      )
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Choice")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(!frame.contains("Alpha"))
    frame = try harness.pressKey(KeyPress(.return))
    #expect(frame.contains("Alpha"))
    #expect(probe.selection == 1)
    #expect(probe.writes == 1)
  }

  @Test("omitting public routes preserves keyboard navigation")
  func omittedRoutesPreserveKeyboard() throws {
    let probe = PickerParityProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 42, height: 12)
    ) {
      PickerParityFixture(
        probe: probe, style: AnyPickerStyle(ConsumerPickerStyle(omitsRoutes: true)))
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Choice")
    _ = try harness.clickText("Duplicate", chooseLast: true)
    #expect(probe.selection == 0)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(probe.selection == 1)
  }

  @Test("disabled picker routes cannot change selection", arguments: PickerTreatment.allCases)
  func disabledSelection(_ treatment: PickerTreatment) throws {
    let probe = PickerParityProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 42, height: 12)
    ) {
      PickerParityFixture(probe: probe, style: treatment.style).disabled(true)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText(treatment.isMenu ? "Alpha" : "Duplicate", chooseLast: true)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(probe.selection == 0)
    #expect(probe.writes == 0)
  }

  @Test("duplicate option and trigger wrappers report and keep only the first target")
  func duplicateRoutes() {
    let identity = testIdentity("Picker")
    let probe = PickerParityProbe()
    var environment = EnvironmentValues()
    environment.focusedIdentity = identity
    let artifacts = DefaultRenderer().render(
      PickerParityFixture(
        probe: probe, style: AnyPickerStyle(ConsumerPickerStyle(menu: true, duplicates: true))),
      context: .init(
        identity: testIdentity("Root"), environmentValues: environment, applyEnvironmentValues: true
      ),
      proposal: .init(width: 60, height: 12)
    )
    let issues = artifacts.diagnostics.runtime.issues.filter { $0.code == "style.duplicateRoute" }
    #expect(issues.count == 4)
    #expect(
      issues.allSatisfy { $0.source == "PickerStyle" && $0.message.contains("ConsumerPickerStyle") }
    )
    let targets = pointerTargets(artifacts.resolvedTree)
    for issue in issues {
      #expect(targets.filter { $0 == issue.identity }.count == 1)
    }
  }

  private func fixtureConfiguration() -> PickerStyleConfiguration {
    PickerStyleConfiguration(
      controlIdentity: testIdentity("FixtureMustNotBecomeARoute"),
      label: .init { Text("Choice") },
      options: [.init(label: "Alpha"), .init(label: "Beta")],
      selectedIndex: 0,
      isFocused: true,
      isActiveNavigation: true,
      showsFocusEffect: true,
      isEnabled: true,
      styleEnvironment: .init(),
      viewportLineCount: nil,
      lineWidth: nil
    )
  }
}

enum PickerTreatment: CaseIterable, Sendable {
  case automatic, inline, segmented, radio, menu, consumer, consumerMenu

  static let builtIns: [Self] = [.automatic, .inline, .segmented, .radio, .menu]

  var isMenu: Bool { self == .menu || self == .consumerMenu }

  var style: AnyPickerStyle {
    switch self {
    case .automatic: .automatic
    case .inline: .inline
    case .segmented: .segmented
    case .radio: .radioGroup
    case .menu: .menu
    case .consumer: AnyPickerStyle(ConsumerPickerStyle())
    case .consumerMenu: AnyPickerStyle(ConsumerPickerStyle(menu: true))
    }
  }

  @MainActor @ViewBuilder
  func fixtureBody(_ configuration: PickerStyleConfiguration) -> some View {
    switch self {
    case .automatic: AutomaticPickerStyle().makeBody(configuration: configuration)
    case .inline: InlinePickerStyle().makeBody(configuration: configuration)
    case .segmented: SegmentedPickerStyle().makeBody(configuration: configuration)
    case .radio: RadioGroupPickerStyle().makeBody(configuration: configuration)
    case .menu: MenuPickerStyle().makeBody(configuration: configuration)
    case .consumer: ConsumerPickerStyle().makeBody(configuration: configuration)
    case .consumerMenu: ConsumerPickerStyle(menu: true).makeBody(configuration: configuration)
    }
  }
}

@MainActor
private final class PickerParityProbe {
  var selection = 0
  var writes = 0

  var binding: Binding<Int> {
    Binding(
      get: { self.selection },
      set: {
        self.selection = $0
        self.writes += 1
      })
  }
}

@MainActor
private struct PickerParityFixture: View {
  let probe: PickerParityProbe
  let style: AnyPickerStyle

  var body: some View {
    Picker("Choice", selection: probe.binding) {
      Text("Alpha").tag(0)
      Text("Duplicate").tag(1)
      Text("Duplicate").tag(2)
    }
    .pickerStyle(style)
    .id(testIdentity("Picker"))
  }
}

private func pointerTargets(_ node: ResolvedNode) -> [Identity] {
  (node.semanticMetadata.participatesInPointerHitTesting ? [node.identity] : [])
    + node.children.flatMap(pointerTargets)
}
