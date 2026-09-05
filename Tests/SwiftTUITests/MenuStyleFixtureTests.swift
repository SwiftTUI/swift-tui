import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

// Typechecked separately as an external consumer of the fixture SPI.
@MainActor
struct MenuStyleFixtureTests {
  @Test("menu fixture routes remain inert for every floating built-in")
  func menuFixtures() {
    let configuration = MenuStyleConfiguration(
      label: .init { Text("Commands") },
      content: .init { Text("Item") }, isPresented: .constant(true),
      isEnabled: true, isFocused: true, showsFocusEffect: false, isPressed: false,
      styleEnvironment: .init())
    let frames = [
      render(AutomaticMenuStyle().makeBody(configuration: configuration)),
      render(ButtonMenuStyle().makeBody(configuration: configuration)),
      render(BorderlessButtonMenuStyle().makeBody(configuration: configuration)),
    ]
    for frame in frames {
      let text = frame.rasterSurface.lines.joined()
      #expect(text.contains("Commands"))
      #expect(!text.contains("Item"))
      #expect(!text.contains("▌"))
      #expect(frame.semanticSnapshot.interactionRegions.isEmpty)
      #expect(frame.diagnostics.runtime.issues.isEmpty)
    }
    let inline = render(InlineMenuStyle().makeBody(configuration: configuration))
    #expect(inline.rasterSurface.lines.joined().contains("Item"))
    #expect(inline.semanticSnapshot.interactionRegions.isEmpty)
  }

  @Test("control group fixtures expose optional label and independently laid out content")
  func controlGroupFixtures() {
    var configuration = ControlGroupStyleConfiguration(
      label: .init { Text("Commands") },
      content: .init {
        Text("First")
        Text("Second")
      }, styleEnvironment: .init())
    let automatic = render(AutomaticControlGroupStyle().makeBody(configuration: configuration))
    let horizontal = render(HorizontalControlGroupStyle().makeBody(configuration: configuration))
    #expect(automatic.rasterSurface == horizontal.rasterSurface)
    #expect(horizontal.rasterSurface.lines.joined().contains("First Second"))
    let vertical = render(VerticalControlGroupStyle().makeBody(configuration: configuration))
    #expect(
      vertical.rasterSurface.lines.contains { $0.contains("First") && !$0.contains("Second") })
    configuration.label = nil
    let unlabeled = render(HorizontalControlGroupStyle().makeBody(configuration: configuration))
    #expect(!unlabeled.rasterSurface.lines.joined().contains("Commands"))
  }

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["Fixture"])),
      proposal: .init(width: 30, height: 8))
  }
}
