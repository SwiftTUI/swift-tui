import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
struct MenuStyleRuntimeTests {
  @Test("retaining a style binding does not retain or reactivate a departed menu owner")
  func bindingLifetime() throws {
    let probe = MenuConfigurationProbe()
    let renderer = DefaultRenderer()
    let id = testIdentity("Menu")
    let context = ResolveContext(identity: testIdentity("Root"))
    _ = renderer.render(
      Menu("Commands") { Text("Item") }
        .menuStyle(InspectMenuStyle(probe: probe)).id(id), context: context)
    weak let owner = renderer.viewGraph.nodeForIdentity(id.child(.named("MenuState")))
    #expect(owner != nil)
    let binding = try #require(probe.configuration?.$isPresented)
    binding.wrappedValue = true
    #expect(binding.wrappedValue)
    probe.configuration = nil
    _ = renderer.render(Text("Removed"), context: context)
    #expect(owner == nil)
    binding.wrappedValue = true
    #expect(!binding.wrappedValue)
    let replacement = renderer.render(Menu("Commands") { Text("Item") }.id(id), context: context)
    #expect(!replacement.rasterSurface.lines.joined().contains("Item"))
  }

  @Test(
    "menu styles preserve pointer, keyboard, dismissal, and exactly-once actions",
    arguments: 0..<5, [false, true])
  func interaction(styleIndex: Int, selective: Bool) throws {
    let styles: [AnyMenuStyle] = [
      .automatic, .button, .borderlessButton, .inline,
      .init(ConsumerMenuStyle()),
    ]
    let probe = MenuActionProbe()
    let id = testIdentity("Menu")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 40, height: 14),
      selectiveEvaluation: selective
    ) {
      Menu("Commands") { Button("Run command") { probe.activations += 1 } }
        .menuStyle(styles[styleIndex]).id(id)
    }
    defer { harness.shutdown() }
    #expect(!harness.frame.contains("Run command"))
    _ = try harness.clickText("Commands")
    #expect(harness.frame.contains("Run command"))
    _ = try harness.clickText("Run command")
    #expect(probe.activations == 1)
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(!harness.frame.contains("Run command"))
    _ = try harness.focus(id)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("Run command"))
    _ = try harness.focus(id)
    _ = try harness.pressKey(KeyPress(.space))
    #expect(!harness.frame.contains("Run command"))
    #expect(probe.activations == 1)
  }

  @Test("omitting the trigger removes pointer activation and keeps keyboard activation")
  func omittedTrigger() throws {
    let id = testIdentity("Menu")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 40, height: 12)
    ) {
      Menu("Commands") { Text("Presented child") }
        .menuStyle(ConsumerMenuStyle(omitTrigger: true)).id(id)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("Commands")
    #expect(!harness.frame.contains("Presented child"))
    _ = try harness.focus(id)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("Presented child"))
  }

  @Test("disabled menus reject primitive activation and style binding writes")
  func disabled() {
    let probe = MenuConfigurationProbe()
    let actions = LocalActionRegistry()
    let id = testIdentity("Menu")
    let renderer = DefaultRenderer()
    let view = Menu("Commands") { Text("Presented child") }
      .menuStyle(InspectMenuStyle(probe: probe)).disabled(true).id(id)
    let context = ResolveContext(
      identity: testIdentity("Root"), localActionRegistry: actions,
      applyEnvironmentValues: true)
    _ = renderer.render(view, context: context)
    #expect(!actions.dispatch(identity: id))
    probe.configuration?.isPresented = true
    #expect(probe.configuration?.isPresented == false)
    #expect(
      !renderer.render(view, context: context).rasterSurface.lines.joined().contains(
        "Presented child"))
  }

  @Test("duplicate trigger and portal wrappers report and keep their first routes")
  func duplicates() {
    let id = testIdentity("Menu")
    let frame = DefaultRenderer().render(
      Menu("Commands") { Text("Presented child") }
        .menuStyle(DuplicateMenuStyle()).id(id),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 40, height: 12))
    let issues = frame.diagnostics.runtime.issues.filter { $0.code == "style.duplicateRoute" }
    #expect(issues.count == 2)
    #expect(issues.contains { $0.message.contains("trigger") })
    #expect(issues.contains { $0.message.contains("portal") })
    #expect(menuRouteCount(frame.resolvedTree, identity: menuTriggerIdentity(for: id)) == 1)
  }

  @Test("a presented body without content or a portal falls back and reports")
  func missingRequiredContent() {
    let actions = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let id = testIdentity("Menu")
    let view = Menu("Commands") { Text("Presented child") }
      .menuStyle(MissingMenuContentStyle()).id(id)
    let context = ResolveContext(
      identity: testIdentity("Root"), localActionRegistry: actions,
      applyEnvironmentValues: true)
    _ = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
    #expect(actions.dispatch(identity: id))
    let frame = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
    #expect(frame.rasterSurface.lines.joined().contains("Presented child"))
    #expect(frame.diagnostics.runtime.issues.contains { $0.code == "style.missingRequiredRoute" })
  }

  @Test("invalid anchored sizing falls back to the automatic presentation")
  func invalidPresentation() {
    let actions = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let id = testIdentity("Menu")
    let view = Menu("Commands") { Text("Presented child") }
      .menuStyle(ConsumerMenuStyle(presentation: .init(minimumWidth: -1))).id(id)
    let context = ResolveContext(
      identity: testIdentity("Root"), localActionRegistry: actions,
      applyEnvironmentValues: true)
    let closed = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
    #expect(closed.diagnostics.runtime.issues.contains { $0.code == "style.invalidPresentation" })
    #expect(actions.dispatch(identity: id))
    let opened = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
    #expect(opened.rasterSurface.lines.joined().contains("Presented child"))
    #expect(opened.diagnostics.runtime.issues.contains { $0.code == "style.invalidPresentation" })
  }

  @Test("fixture trigger and portal wrappers are inert")
  func inertFixtures() {
    let configuration = MenuStyleConfiguration(
      label: .init { Text("Fixture anchor") }, content: .init { Text("Secret content") },
      isPresented: .constant(true), isEnabled: true, isFocused: false,
      showsFocusEffect: true, isPressed: false, styleEnvironment: .init())
    let view = configuration.portal(presentation: .init()) {
      VStack {
        configuration.trigger { configuration.label }
        configuration.trigger { Text("Repeated") }
      }
    }
    let frame = DefaultRenderer().render(view, context: .init(identity: testIdentity("Fixture")))
    #expect(frame.rasterSurface.lines.joined().contains("Fixture anchor"))
    #expect(!frame.rasterSurface.lines.joined().contains("Secret content"))
    #expect(frame.semanticSnapshot.interactionRegions.isEmpty)
    #expect(frame.diagnostics.runtime.issues.isEmpty)
  }
}

@MainActor private final class MenuActionProbe { var activations = 0 }
private func menuRouteCount(_ node: ResolvedNode, identity: Identity) -> Int {
  let own = node.kind == .view("PointerRoute") && node.identity == identity ? 1 : 0
  return own + node.children.reduce(0) { $0 + menuRouteCount($1, identity: identity) }
}
@MainActor private final class MenuConfigurationProbe { var configuration: MenuStyleConfiguration? }

private struct ConsumerMenuStyle: MenuStyle {
  var omitTrigger = false
  var presentation = AnchoredSurfaceStylePresentation()
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    ConsumerMenuBody(
      configuration: configuration, omitTrigger: omitTrigger, presentation: presentation)
  }
}
private struct ConsumerMenuBody: View {
  let configuration: MenuStyleConfiguration
  let omitTrigger: Bool
  let presentation: AnchoredSurfaceStylePresentation
  var body: some View {
    configuration.portal(presentation: presentation) {
      if omitTrigger { configuration.label } else { configuration.trigger { configuration.label } }
    }
  }
}
private struct InspectMenuStyle: MenuStyle {
  let probe: MenuConfigurationProbe
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    InspectMenuBody(configuration: configuration, probe: probe)
  }
}
private struct InspectMenuBody: View {
  let configuration: MenuStyleConfiguration
  let probe: MenuConfigurationProbe
  var body: some View {
    probe.configuration = configuration
    return configuration.portal(presentation: .init()) {
      configuration.trigger { configuration.label }
    }
  }
}
private struct MissingMenuContentStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    MissingMenuContentBody(configuration: configuration)
  }
}
private struct MissingMenuContentBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View { configuration.trigger { configuration.label } }
}
private struct DuplicateMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    DuplicateMenuBody(configuration: configuration)
  }
}
private struct DuplicateMenuBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    VStack {
      configuration.portal(presentation: .init()) {
        VStack {
          configuration.trigger { configuration.label }
          configuration.trigger { Text("Repeated trigger") }
        }
      }
      configuration.portal(presentation: .init()) { Text("Repeated portal") }
    }
  }
}
