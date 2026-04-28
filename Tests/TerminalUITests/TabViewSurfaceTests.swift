import Testing

@_spi(Testing) @testable import Core
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
    style: AnyTabViewStyle = .automatic,
    focused: Bool = false,
    selection: String = "home"
  ) -> FrameArtifacts {
    var environmentValues = EnvironmentValues()
    if focused {
      environmentValues.focusedIdentity = testIdentity("Tabs")
    }

    return DefaultRenderer().render(
      TabView(selection: .constant(selection)) {
        Tab("Home", detail: "3", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }

        Tab("Logs", value: "logs") {
          Text("Logs content")
        }
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
    style: AnyTabViewStyle = .automatic,
    focused: Bool = false,
    selection: String = "home"
  ) -> String {
    renderTabArtifacts(style: style, focused: focused, selection: selection)
      .rasterSurface.lines.joined(separator: "\n")
  }

  private func overflowTabView(
    selection: Binding<String>
  ) -> some View {
    TabView(selection: selection) {
      Tab("One", value: "one") {
        Text("One content")
      }

      Tab("Two", value: "two") {
        Text("Two content")
      }

      Tab("Three", value: "three") {
        Text("Three content")
      }

      Tab("Four", value: "four") {
        Text("Four content")
      }
    }
    .tabViewStyle(.literalTabs)
    .id(testIdentity("Tabs"))
  }

  private func renderOverflowTabArtifacts(
    selection: Binding<String>,
    focused: Bool = false,
    terminalWidth: Int = 24,
    proposalWidth: Int = 24
  ) -> FrameArtifacts {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: terminalWidth, height: 8)
    if focused {
      environmentValues.focusedIdentity = testIdentity("Tabs")
    }

    return DefaultRenderer().render(
      overflowTabView(selection: selection),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: proposalWidth, height: 8)
    )
  }

  private func stripBounds(
    for style: AnyTabViewStyle
  ) -> Rect {
    let height: Int =
      switch style.debugDescription {
      case "AnyTabViewStyle.powerline":
        1
      case "AnyTabViewStyle.literalTabs":
        3
      default:
        2
      }

    return Rect(
      origin: .zero,
      size: .init(
        width: 40,
        height: height
      )
    )
  }

  @Test("TabView resolves typed labels into semantics and strip chrome")
  func tabViewResolvesTypedLabels() throws {
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Tab("Home", detail: "3", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }
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

  @Test("TabView badge initializer preserves badge text in chrome and semantics")
  func tabViewBadgeInitializerPreservesBadgeText() throws {
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("inbox")) {
        Tab("Inbox", badge: "7", value: "inbox") {
          Text("Inbox content")
        }

        Tab("Archive", value: "archive") {
          Text("Archive content")
        }
      }
      .id(testIdentity("Tabs")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: 4)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let inboxNode = try #require(artifacts.resolvedTree.descendant(withText: "Inbox content"))

    #expect(surface.contains("Inbox · [7]"))
    #expect(inboxNode.semanticMetadata.tabItemLabel == TabItemLabel("Inbox", badge: "7"))
  }

  @Test("TabView arrow navigation preserves selection until activation")
  func tabViewArrowNavigationPreservesSelectionUntilActivation() {
    let keyRegistry = LocalKeyHandlerRegistry()
    let actionRegistry = LocalActionRegistry()

    final class SelectionBox {
      var value = "home"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("Tabs")

    _ = DefaultRenderer().render(
      TabView(selection: selection) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }
      }
      .id(testIdentity("Tabs")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 32, height: 4)
    )

    #expect(keyRegistry.hasHandler(identity: testIdentity("Tabs")))
    #expect(actionRegistry.hasHandler(identity: testIdentity("Tabs")))
    #expect(keyRegistry.dispatch(identity: testIdentity("Tabs"), keyPress: KeyPress(.arrowRight)))
    #expect(selectionBox.value == "home")
    #expect(actionRegistry.dispatch(identity: testIdentity("Tabs")))
    #expect(selectionBox.value == "settings")
  }

  @Test("TabView focused tab survives a rerender before activation")
  func tabViewFocusedTabSurvivesRerenderBeforeActivation() {
    let keyRegistry = LocalKeyHandlerRegistry()
    let actionRegistry = LocalActionRegistry()
    let invalidator = RecordingInvalidator()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)
    let renderer = DefaultRenderer()

    final class SelectionBox {
      var value = "home"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("Tabs")

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      localActionRegistry: actionRegistry,
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    context.invalidationProxy = invalidationProxy

    _ = renderer.render(
      TabView(selection: selection) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }
      }
      .id(testIdentity("Tabs")),
      context: context,
      proposal: .init(width: 32, height: 4)
    )

    #expect(keyRegistry.dispatch(identity: testIdentity("Tabs"), keyPress: KeyPress(.arrowRight)))
    let invalidatedIdentities = invalidator.requests.reduce(into: Set<Identity>()) {
      partial, request in
      partial.formUnion(request)
    }
    #expect(invalidatedIdentities.contains(testIdentity("Tabs")))

    var updatedContext = context
    updatedContext.invalidatedIdentities = invalidatedIdentities
    _ = renderer.render(
      TabView(selection: selection) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }
      }
      .id(testIdentity("Tabs")),
      context: updatedContext,
      proposal: .init(width: 32, height: 4)
    )

    #expect(actionRegistry.dispatch(identity: testIdentity("Tabs")))
    #expect(selectionBox.value == "settings")
  }

  @Test("focused tabs keep tab label text without a strip-level focus wash")
  func focusedTabsDoNotUseStripLevelFocusWash() {
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
      !hasFillCommand(in: focusedUnderlineArtifacts.drawTree, bounds: stripBounds(for: .underline)))
    #expect(
      !hasFillCommand(in: focusedRoundedArtifacts.drawTree, bounds: stripBounds(for: .literalTabs)))
    #expect(
      !hasFillCommand(
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

  @Test("TabView focus background only follows the focused tab")
  func tabViewFocusBackgroundOnlyFollowsFocusedTab() throws {
    let keyRegistry = LocalKeyHandlerRegistry()
    let actionRegistry = LocalActionRegistry()
    let invalidator = RecordingInvalidator()
    let invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)
    let renderer = DefaultRenderer()

    final class SelectionBox {
      var value = "home"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("Tabs")

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      localActionRegistry: actionRegistry,
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    context.invalidationProxy = invalidationProxy

    func makeView() -> some View {
      TabView(selection: selection) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
        }

        Tab("Logs", value: "logs") {
          Text("Logs content")
        }
      }
      .tabViewStyle(.underline)
      .id(testIdentity("Tabs"))
    }

    _ = renderer.render(
      makeView(),
      context: context,
      proposal: .init(width: 40, height: 4)
    )

    #expect(keyRegistry.dispatch(identity: testIdentity("Tabs"), keyPress: KeyPress(.arrowRight)))
    #expect(selectionBox.value == "home")

    var updatedContext = context
    updatedContext.invalidatedIdentities = invalidator.requests.reduce(into: Set<Identity>()) {
      partial, request in
      partial.formUnion(request)
    }
    let updatedArtifacts = renderer.render(
      makeView(),
      context: updatedContext,
      proposal: .init(width: 40, height: 4)
    )

    let firstRow = try #require(updatedArtifacts.rasterSurface.cells.first)
    let homeIndex = try #require(firstRow.firstIndex { $0.character == "H" })
    let settingsIndex = try #require(firstRow.firstIndex { $0.character == "S" })
    let logsIndex = try #require(firstRow.firstIndex { $0.character == "L" })

    #expect(firstRow[homeIndex].style?.backgroundColor == nil)
    #expect(firstRow[settingsIndex].style?.backgroundColor != nil)
    #expect(firstRow[logsIndex].style?.backgroundColor == nil)
    #expect(
      !hasFillCommand(in: updatedArtifacts.drawTree, bounds: stripBounds(for: .underline))
    )
    #expect(normalizedVisibleText(updatedArtifacts.rasterSurface.lines).contains("Home content"))
  }

  @Test("underline tabs keep their rules aligned with the label edge")
  func underlineTabsAlignRulesWithLabels() {
    let lines = DefaultRenderer().render(
      TabView(selection: .constant("layout")) {
        Tab("Controls", value: "controls") {
          Text("Controls content")
        }

        Tab("Collections", value: "collections") {
          Text("Collections content")
        }

        Tab("Layout", value: "layout") {
          Text("Layout content")
        }

        Tab("Appearance", value: "appearance") {
          Text("Appearance content")
        }

        Tab("Charts", value: "charts") {
          Text("Charts content")
        }
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

  @Test("literal tabs replace overflowing trailing tabs with a dropdown trigger")
  func literalTabsCollapseOverflowIntoDropdownTrigger() {
    let lines = renderOverflowTabArtifacts(
      selection: .constant("one")
    )
    .rasterSurface.lines
    .prefix(4)
    .map(trimTrailingSpaces)

    #expect(
      Array(lines)
        == [
          "╭─────╮╭─────╮╭───╮",
          "│ One ││ Two ││ ▾ │",
          "┘     └┴─────┴┴───┴─────",
          "One content",
        ]
    )
  }

  @Test(
    "literal tabs collapse against the current frame proposal instead of a stale terminal width")
  func literalTabsCollapseAgainstCurrentFrameProposal() {
    let surface = renderOverflowTabArtifacts(
      selection: .constant("one"),
      terminalWidth: 80,
      proposalWidth: 24
    )
    .rasterSurface.lines
    .prefix(4)
    .map(trimTrailingSpaces)

    #expect(
      Array(surface)
        == [
          "╭─────╮╭─────╮╭───╮",
          "│ One ││ Two ││ ▾ │",
          "┘     └┴─────┴┴───┴─────",
          "One content",
        ]
    )
    #expect(surface.joined(separator: "\n").contains("…") == false)
  }

  @Test("literal tabs recompute overflow when the proposal changes under selective evaluation")
  func literalTabsRecomputeOverflowWhenProposalChangesUnderSelectiveEvaluation() {
    let renderer = DefaultRenderer()
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 80, height: 8)
    let context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues
    )

    let wideSurface = renderer.render(
      overflowTabView(selection: .constant("one")),
      context: context,
      proposal: .init(width: 40, height: 8)
    )
    .rasterSurface.lines
    .prefix(3)
    .map(trimTrailingSpaces)
    .joined(separator: "\n")

    renderer.enableSelectiveEvaluation()

    let narrowSurface = renderer.render(
      overflowTabView(selection: .constant("one")),
      context: context,
      proposal: .init(width: 24, height: 8)
    )
    .rasterSurface.lines
    .prefix(3)
    .map(trimTrailingSpaces)
    .joined(separator: "\n")

    #expect(wideSurface.contains("▾") == false)
    #expect(narrowSurface.contains("▾"))
    #expect(narrowSurface.contains("…") == false)
  }

  @Test("literal tab overflow trigger expands and adopts the selected-hidden state")
  func literalTabOverflowTriggerSelectsHiddenTabs() {
    final class SelectionBox {
      var value = "one"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 24, height: 8)

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues
    )
    context.localPointerHandlerRegistry = pointerRegistry

    _ = renderer.render(
      overflowTabView(selection: selection),
      context: context,
      proposal: .init(width: 24, height: 8)
    )

    let triggerRouteID = primaryRouteID(
      for: testIdentity("Tabs").child(.named("TabOverflowTrigger"))
    )
    #expect(pointerRegistry.hasHandler(routeID: triggerRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: triggerRouteID,
        event: .init(kind: .down(.primary), location: .zero, targetRect: .zero)
      )
    )

    let expandedSurface = renderer.render(
      overflowTabView(selection: selection),
      context: context,
      proposal: .init(width: 24, height: 8)
    ).rasterSurface.lines.joined(separator: "\n")

    #expect(expandedSurface.contains("Three"))
    #expect(expandedSurface.contains("Four"))

    let hiddenRouteID = primaryRouteID(
      for: testIdentity("Tabs").child(.indexed("TabOverflowItem", index: 3))
    )
    #expect(pointerRegistry.hasHandler(routeID: hiddenRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: hiddenRouteID,
        event: .init(kind: .down(.primary), location: .zero, targetRect: .zero)
      )
    )
    #expect(selectionBox.value == "four")

    let lines = renderer.render(
      overflowTabView(selection: selection),
      context: context,
      proposal: .init(width: 24, height: 8)
    )
    .rasterSurface.lines
    .prefix(4)
    .map(trimTrailingSpaces)

    #expect(
      Array(lines)
        == [
          "╭─────╮╭─────╮╭───╮",
          "│ One ││ Two ││ ▼ │",
          "┴─────┴┴─────┴┘   └─────",
          "Four content",
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

private final class RecordingInvalidator: Invalidating {
  var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}
