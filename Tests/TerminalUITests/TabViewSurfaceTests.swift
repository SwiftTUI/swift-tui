import Testing

@testable import Core
@testable import TerminalUI
@testable import View

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if case .text(let nodeText) = drawPayload, nodeText == text {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}

@MainActor
@Suite
struct TabViewSurfaceTests {
  private func renderTabView(
    style: TabViewStyle = .automatic,
    focused: Bool = false
  ) -> String {
    var environmentValues = EnvironmentValues()
    if focused {
      environmentValues.focusedIdentity = testIdentity("Tabs")
    }

    return DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Text("Home content")
          .tabItem(TabItemLabel("Home", detail: "3"))
          .tag("home")

        Text("Settings content")
          .tabItem(TabItemLabel("Settings"))
          .tag("settings")

        Text("Logs content")
          .tabItem(TabItemLabel("Logs"))
          .tag("logs")
      }
      .tabViewStyle(style)
      .id(testIdentity("Tabs")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 40, height: 4)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  @Test("TabView resolves typed labels into semantics and strip chrome")
  func tabViewResolvesTypedLabels() throws {
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Text("Home content")
          .tabItem(TabItemLabel("Home", detail: "3"))
          .tag("home")

        Text("Settings content")
          .tabItem(TabItemLabel("Settings"))
          .tag("settings")
      }
      .id(testIdentity("Tabs")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: 4)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let homeNode = try #require(artifacts.resolvedTree.descendant(withText: "Home content"))

    #expect(surface.contains("Home · 3"))
    #expect(surface.contains("Settings"))
    #expect(homeNode.semanticMetadata.tabItemLabel == TabItemLabel("Home", detail: "3"))
    #expect(homeNode.semanticMetadata.presentationRole == nil)
    #expect(artifacts.resolvedTree.semanticMetadata.presentationRole == .tabView)
  }

  @Test("focused tabs make the selected tab visibly distinct across styles")
  func focusedTabsUseClearerFocusTreatment() {
    let underlineSurface = renderTabView(style: .underline, focused: true)
    let roundedSurface = renderTabView(style: .rounded, focused: true)
    let powerlineSurface = renderTabView(style: .powerline, focused: true)

    #expect(underlineSurface.contains("▌Home · 3 "))
    #expect(underlineSurface.contains("╺━━━━━━━━╸"))
    #expect(roundedSurface.contains("╭▌Home · 3╮"))
    #expect(roundedSurface.contains("╰═════════╯"))
    #expect(powerlineSurface.contains("▌Home · 3 "))
  }

  @Test("unfocused tabs keep the legacy strip text without the focus marker")
  func unfocusedTabsDoNotShowFocusMarker() {
    let underlineSurface = renderTabView(style: .underline, focused: false)
    let roundedSurface = renderTabView(style: .rounded, focused: false)
    let powerlineSurface = renderTabView(style: .powerline, focused: false)

    #expect(!underlineSurface.contains("▌Home · 3"))
    #expect(!roundedSurface.contains("▌Home · 3"))
    #expect(!powerlineSurface.contains("▌Home · 3"))
  }
}
