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
        height: style == .powerline ? 1 : style == .literalTabs ? 3 : 2
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
      .prefix(4)
      .map(String.init)
      .map(trimTrailingSpaces)

    #expect(
      Array(lines)
        == [
          "╭──────────╮╭──────────╮╭──────╮",
          "│ Home · 3 ││ Settings ││ Logs │",
          "┴──────────┴┘          └┴──────┴────────",
          "Settings content",
        ]
    )
  }

  @Test("selected literal tab uses foreground chrome without filling its background")
  func selectedLiteralTabUsesForegroundChromeWithoutFill() throws {
    let artifacts = renderTabArtifacts(
      style: .literalTabs,
      focused: false,
      selection: "settings"
    )
    let cells = artifacts.rasterSurface.cells
    let expectedAccent = TerminalAppearance.fallback.tintColor
    let expectedForeground = TerminalAppearance.fallback.foregroundColor

    // Rows 0-2 are the tab chrome (top edge, label, lower edges).
    // Row 3 is the content area. Find the label cells for
    // "Settings" in row 1 and confirm the selected tab keeps a
    // foreground-colored outline, an accent-colored label, and no
    // filled background on any chrome row.
    let labelRow = try #require(cells.indices.contains(1) ? cells[1] : nil)
    let settingsStart = try #require(labelRow.firstIndex { $0.character == "S" })
    // The interior of a rounded tab includes `│ ` before the label and
    // ` │` after it, so walk back to the opening vertical bar.
    let tabStart = settingsStart - 2
    // And walk forward past the label to the closing vertical bar.
    var tabEnd = settingsStart
    while tabEnd < labelRow.count, labelRow[tabEnd].character != "│" {
      tabEnd += 1
    }

    for x in tabStart...tabEnd {
      #expect(cells[0][x].style?.backgroundColor != expectedAccent)
      #expect(cells[1][x].style?.backgroundColor != expectedAccent)
      #expect(cells[2][x].style?.backgroundColor != expectedAccent)
    }
    #expect(cells[0][tabStart].style?.foregroundColor == expectedForeground)
    #expect(cells[1][tabStart].style?.foregroundColor == expectedForeground)
    #expect(cells[1][settingsStart].style?.foregroundColor == expectedAccent)
    #expect(cells[1][tabEnd].style?.foregroundColor == expectedForeground)
    #expect(cells[2][tabStart].style?.foregroundColor == expectedForeground)

    // Unselected labels stay muted, while their outline chrome and the
    // shared bottom rail use the foreground color.
    let homeStart = try #require(labelRow.firstIndex { $0.character == "H" })
    let homeTabStart = homeStart - 2
    var homeTabEnd = homeStart
    while homeTabEnd < labelRow.count, labelRow[homeTabEnd].character != "│" {
      homeTabEnd += 1
    }
    #expect(cells[1][homeStart].style?.foregroundColor != expectedAccent)
    #expect(cells[1][homeTabStart].style?.foregroundColor == expectedForeground)
    #expect(cells[1][homeTabEnd].style?.foregroundColor == expectedForeground)
    let bottomRow = try #require(cells.indices.contains(2) ? cells[2] : nil)
    #expect(bottomRow[0].character == "┴")
    #expect(bottomRow[11].character == "┴")
    #expect(bottomRow[12].character == "┘")
    #expect(bottomRow[23].character == "└")
    #expect(bottomRow[24].character == "┴")
    #expect(bottomRow[31].character == "┴")
    #expect(bottomRow[39].character == "─")
    #expect(bottomRow[0].style?.foregroundColor == expectedForeground)
    #expect(bottomRow[12].style?.foregroundColor == expectedForeground)
    #expect(bottomRow[24].style?.foregroundColor == expectedForeground)
    #expect(bottomRow[39].style?.foregroundColor == expectedForeground)

    // The content row should start immediately after the tab chrome
    // without an extra underline strip between them.
    let contentRow = try #require(cells.indices.contains(3) ? cells[3] : nil)
    #expect(String(contentRow.prefix(16).map(\.character)).contains("Settings content"))
    #expect(contentRow[tabStart].style?.backgroundColor != expectedAccent)
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
