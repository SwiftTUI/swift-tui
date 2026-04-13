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
    focused: Bool = false,
    selection: String = "home"
  ) -> FrameArtifacts {
    var environmentValues = EnvironmentValues()
    if focused {
      environmentValues.focusedIdentity = testIdentity("Tabs")
    }

    return DefaultRenderer().render(
      TabView(selection: .constant(selection)) {
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
    )
  }

  private func renderTabView(
    style: TabViewStyle = .automatic,
    focused: Bool = false,
    selection: String = "home"
  ) -> String {
    renderTabArtifacts(style: style, focused: focused, selection: selection)
      .rasterSurface.lines.joined(separator: "\n")
  }

  private func stripBounds(
    for style: TabViewStyle
  ) -> Rect {
    Rect(
      origin: .zero,
      size: .init(
        width: 40,
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
    let focusedRoundedArtifacts = renderTabArtifacts(style: .literalTabs, focused: true)
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
      hasFillCommand(in: focusedRoundedArtifacts.drawTree, bounds: stripBounds(for: .literalTabs)))
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
    let roundedSurface = renderTabView(style: .literalTabs, focused: true)
    let powerlineSurface = renderTabView(style: .powerline, focused: true)

    #expect(!underlineSurface.contains("▌Home · 3"))
    #expect(!roundedSurface.contains("▌Home · 3"))
    #expect(!powerlineSurface.contains("▌Home · 3"))
  }

  @Test("unfocused tabs do not draw the strip-level focus wash")
  func unfocusedTabsDoNotDrawStripFocusWash() {
    let underlineArtifacts = renderTabArtifacts(style: .underline, focused: false)
    let roundedArtifacts = renderTabArtifacts(style: .literalTabs, focused: false)
    let powerlineArtifacts = renderTabArtifacts(style: .powerline, focused: false)

    #expect(!hasFillCommand(in: underlineArtifacts.drawTree, bounds: stripBounds(for: .underline)))
    #expect(!hasFillCommand(in: roundedArtifacts.drawTree, bounds: stripBounds(for: .literalTabs)))
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
          "▁▁▁▁▁▁▁▁ ▁▁▁▁▁▁▁▁▁▁▁ ▂▂▂▂▂▂ ▁▁▁▁▁▁▁▁▁▁ ▁▁▁▁▁▁",
        ]
    )
  }

  @Test("literal tabs use traditional outlined tab chrome")
  func literalTabsUseTraditionalOutline() {
    let lines = renderTabView(style: .literalTabs, focused: false, selection: "settings")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .prefix(2)
      .map(String.init)
      .map(trimTrailingSpaces)

    #expect(
      Array(lines)
        == [
          "╭──────────╮╭──────────╮╭──────╮",
          "│ Home · 3 ││ Settings ││ Logs │",
        ]
    )
  }

  @Test("powerline tabs use unicode slant separators between items")
  func powerlineTabsUseUnicodeSlants() throws {
    let firstLine = try #require(
      renderTabView(style: .powerline, focused: false, selection: "settings")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .first
        .map(String.init)
    )

    #expect(firstLine.contains("◢"))
    #expect(firstLine.contains("◤"))
    #expect(firstLine.contains("Home · 3"))
    #expect(firstLine.contains("Settings"))
    #expect(firstLine.contains("Logs"))
  }

  @Test("selected powerline tabs fill the full segment with the accent color")
  func selectedPowerlineTabsUseFullAccentFill() throws {
    let artifacts = renderTabArtifacts(
      style: .powerline,
      focused: false,
      selection: "settings"
    )
    let firstRow = try #require(artifacts.rasterSurface.cells.first)
    let expectedBackground = TerminalAppearance.fallback.tintColor
    let wedgeIndices = firstRow.enumerated().compactMap { index, cell in
      switch cell.character {
      case "◢", "◤":
        index
      default:
        nil
      }
    }

    #expect(wedgeIndices.count == 2)
    #expect(firstRow[wedgeIndices[0]].character == "◢")
    #expect(firstRow[wedgeIndices[1]].character == "◤")

    let settingsStart = try #require(firstRow.firstIndex { $0.character == "S" })
    let settingsEnd = wedgeIndices[1]

    for x in settingsStart..<settingsEnd {
      #expect(firstRow[x].style?.backgroundColor == expectedBackground)
    }

    #expect(firstRow[wedgeIndices[0]].style?.backgroundColor == nil)
    #expect(firstRow[wedgeIndices[1]].style?.backgroundColor == nil)
    #expect(firstRow[settingsStart].style?.backgroundColor == expectedBackground)
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
  case .fill(let commandBounds, _, _, _, _):
    return commandBounds == bounds
  case .clip(_, let child):
    return hasFillCommand(child, bounds: bounds)
  default:
    return false
  }
}
