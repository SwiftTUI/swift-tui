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
  private func renderTabArtifacts(
    style: TabViewStyle = .automatic,
    focused: Bool = false
  ) -> FrameArtifacts {
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
      proposal: .init(width: 80, height: 4)
    )
  }

  private func renderTabView(
    style: TabViewStyle = .automatic,
    focused: Bool = false
  ) -> String {
    renderTabArtifacts(style: style, focused: focused)
      .rasterSurface.lines.joined(separator: "\n")
  }

  private func stripBounds(
    for style: TabViewStyle
  ) -> Rect {
    Rect(
      origin: .zero,
      size: .init(
        width: 80,
        height: style == .powerline ? 1 : 2
      )
    )
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

  @Test("focused tabs keep tab label text and add a strip-level focus wash")
  func focusedTabsUseStripLevelFocusWash() {
    let focusedUnderlineArtifacts = renderTabArtifacts(style: .underline, focused: true)
    let focusedRoundedArtifacts = renderTabArtifacts(style: .rounded, focused: true)
    let focusedPowerlineArtifacts = renderTabArtifacts(style: .powerline, focused: true)

    // Tab labels must still be present (underlines may change weight when focused)
    let focusedUnderlineText = normalizedVisibleText(focusedUnderlineArtifacts.rasterSurface.lines)
    let focusedRoundedText = normalizedVisibleText(focusedRoundedArtifacts.rasterSurface.lines)
    let focusedPowerlineText = normalizedVisibleText(focusedPowerlineArtifacts.rasterSurface.lines)
    #expect(focusedUnderlineText.contains("Home · 3"))
    #expect(focusedRoundedText.contains("Home · 3"))
    #expect(focusedPowerlineText.contains("Home · 3"))

    #expect(
      hasFillCommand(in: focusedUnderlineArtifacts.drawTree, bounds: stripBounds(for: .underline)))
    #expect(
      hasFillCommand(in: focusedRoundedArtifacts.drawTree, bounds: stripBounds(for: .rounded)))
    #expect(
      hasFillCommand(
        in: focusedPowerlineArtifacts.drawTree,
        bounds: stripBounds(for: .powerline)
      )
    )
  }

  @Test("tabs do not prepend a focused marker into the selected label")
  func tabsDoNotShowFocusMarker() {
    let underlineSurface = renderTabView(style: .underline, focused: true)
    let roundedSurface = renderTabView(style: .rounded, focused: true)
    let powerlineSurface = renderTabView(style: .powerline, focused: true)

    #expect(!underlineSurface.contains("▌Home · 3"))
    #expect(!roundedSurface.contains("▌Home · 3"))
    #expect(!powerlineSurface.contains("▌Home · 3"))
  }

  @Test("unfocused tabs do not draw the strip-level focus wash")
  func unfocusedTabsDoNotDrawStripFocusWash() {
    let underlineArtifacts = renderTabArtifacts(style: .underline, focused: false)
    let roundedArtifacts = renderTabArtifacts(style: .rounded, focused: false)
    let powerlineArtifacts = renderTabArtifacts(style: .powerline, focused: false)

    #expect(!hasFillCommand(in: underlineArtifacts.drawTree, bounds: stripBounds(for: .underline)))
    #expect(!hasFillCommand(in: roundedArtifacts.drawTree, bounds: stripBounds(for: .rounded)))
    #expect(!hasFillCommand(in: powerlineArtifacts.drawTree, bounds: stripBounds(for: .powerline)))
  }

  @Test("underline tabs keep their rules aligned with the label edge")
  func underlineTabsAlignRulesWithLabels() {
    let lines = DefaultRenderer().render(
      TabView(selection: .constant("layout")) {
        Text("Controls content")
          .tabItem("Controls")
          .tag("controls")

        Text("Collections content")
          .tabItem("Collections")
          .tag("collections")

        Text("Layout content")
          .tabItem("Layout")
          .tag("layout")

        Text("Appearance content")
          .tabItem("Appearance")
          .tag("appearance")

        Text("Charts content")
          .tabItem("Charts")
          .tag("charts")
      }
      .id(testIdentity("GalleryTabs")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 80, height: 4)
    )
    .rasterSurface.lines
    .prefix(2)
    .map(trimTrailingSpaces)

    #expect(
      Array(lines)
        == [
          "Controls Collections Layout Appearance Charts",
          "──────── ─────────── ━━━━━━ ────────── ──────",
        ]
    )
  }
}

private func normalizedVisibleText(
  _ lines: [String]
) -> String {
  lines.map(trimTrailingSpaces).joined(separator: "\n")
}

private func trimTrailingSpaces(
  _ line: String
) -> String {
  String(line.reversed().drop(while: { $0 == " " }).reversed())
}

private func hasFillCommand(
  in node: DrawNode,
  bounds: Rect
) -> Bool {
  if node.commands.contains(where: { hasFillCommand($0, bounds: bounds) }) {
    return true
  }

  return node.children.contains(where: { hasFillCommand(in: $0, bounds: bounds) })
}

private func hasFillCommand(
  _ command: DrawCommand,
  bounds: Rect
) -> Bool {
  switch command {
  case .group(_, let children):
    return children.contains(where: { hasFillCommand($0, bounds: bounds) })
  case .fill(let commandBounds, _, _, _):
    return commandBounds == bounds
  case .clip(_, let child):
    return hasFillCommand(child, bounds: bounds)
  default:
    return false
  }
}
