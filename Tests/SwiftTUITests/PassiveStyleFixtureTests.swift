import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

// No @testable import, package API, or test helpers: the whole file also
// typechecks outside this package with only the documented fixture SPI.
@MainActor
struct PassiveStyleFixtureTests {
  @Test("label fixtures expose both slots through every built-in")
  func labelFixtures() {
    let configuration = LabelStyleConfiguration(
      title: .init { Text("Title") }, icon: .init { Text("*") },
      styleEnvironment: .init())
    #expect(text(AutomaticLabelStyle().makeBody(configuration: configuration)).contains("* Title"))
    #expect(
      text(TitleAndIconLabelStyle().makeBody(configuration: configuration)).contains("* Title"))
    let title = text(TitleOnlyLabelStyle().makeBody(configuration: configuration))
    #expect(title.contains("Title") && !title.contains("*"))
    let icon = text(IconOnlyLabelStyle().makeBody(configuration: configuration))
    #expect(icon.contains("*") && !icon.contains("Title"))
  }

  @Test("labeled-content fixtures expose label and content")
  func labeledContentFixtures() {
    let configuration = LabeledContentStyleConfiguration(
      label: .init { Text("Name") }, content: .init { Text("Ada") },
      styleEnvironment: .init())
    let automatic = text(AutomaticLabeledContentStyle().makeBody(configuration: configuration))
    let stacked = text(StackedLabeledContentStyle().makeBody(configuration: configuration))
    #expect(automatic.contains("Name") && automatic.contains("Ada"))
    #expect(stacked.contains("Name") && stacked.contains("Ada"))
    #expect(automatic != stacked)
  }

  @Test("group-box fixtures distinguish an absent label from an empty authored label")
  func groupBoxFixtures() {
    var configuration = GroupBoxStyleConfiguration(
      label: .init { Text("Group") }, content: .init { Text("Value") },
      controlProminence: .increased, styleEnvironment: .init())
    let automatic = text(AutomaticGroupBoxStyle().makeBody(configuration: configuration))
    let bordered = text(BorderedGroupBoxStyle().makeBody(configuration: configuration))
    let plain = text(PlainGroupBoxStyle().makeBody(configuration: configuration))
    #expect(automatic == bordered)
    #expect(plain != bordered)
    #expect(plain.contains("Group") && plain.contains("Value"))
    configuration.label = nil
    let unlabeled = text(BorderedGroupBoxStyle().makeBody(configuration: configuration))
    #expect(!unlabeled.contains("Group") && unlabeled.contains("Value"))
    configuration.label = .init { EmptyView() }
    #expect(configuration.label != nil)
    #expect(text(BorderedGroupBoxStyle().makeBody(configuration: configuration)).contains("Value"))
  }

  private func text<V: View>(_ view: V) -> String {
    DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["Fixture"])),
      proposal: .init(width: 24, height: 8)
    ).rasterSurface.lines.joined(separator: "\n")
  }
}
