import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

@MainActor
struct PaletteStyleFixtureTests {
  @Test("palette fixture routes, activation, and dismissal remain inert")
  func inertFixtures() {
    let command = PaletteStyleConfiguration.Command(id: 1, name: "Command", description: "Hint")
    let configuration = PaletteStyleConfiguration(
      title: "Commands", commands: [command], terminalSize: .init(width: 60, height: 24),
      controlProminence: .standard, styleEnvironment: .init())
    command.perform()
    configuration.dismiss()
    let snapshot = DefaultRenderer().render(
      command.route { Text(command.name) },
      context: .init(identity: Identity(components: ["PaletteFixture"])))
    #expect(snapshot.rasterSurface.lines.joined().contains("Command"))
    #expect(snapshot.semanticSnapshot.interactionRegions.isEmpty)
    #expect(snapshot.diagnostics.runtime.issues.isEmpty)
    let defaultBody = DefaultRenderer().render(
      DefaultPaletteStyle().makeBody(configuration: configuration),
      context: .init(identity: Identity(components: ["PaletteFixture"])),
      proposal: .init(width: 60, height: 24))
    #expect(defaultBody.rasterSurface.lines.joined().contains("Hint"))
    #expect(
      !defaultBody.semanticSnapshot.interactionRegions.contains {
        $0.identity.components.contains("PaletteCommand")
      })
  }
}
