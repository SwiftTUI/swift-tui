public import SwiftTUIRuntime
import SwiftTUITerminal

/// A first-class terminal workspace surface with tabs, split panes, and retained sessions.
public struct TerminalWorkspaceView: View {
  @Binding private var workspace: TerminalWorkspaceState
  @State private var sessions: TerminalWorkspaceSessionStore
  @State private var showsCommandPalette = false
  @FocusState private var focusedPane: TerminalPaneID?

  public init(
    workspace: Binding<TerminalWorkspaceState>,
    sessions: TerminalWorkspaceSessionStore = TerminalWorkspaceSessionStore()
  ) {
    _workspace = workspace
    _sessions = State(wrappedValue: sessions)
  }

  public var body: some View {
    GeometryReader { proxy in
      workspaceSurface(size: proxy.size)
    }
  }

  private func workspaceSurface(size: CellSize) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      tabStrip
      Divider()
      paneSurface(size: size)
      Divider()
      statusStrip
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .panel(id: "terminal-workspace")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { showsCommandPalette = true }
    )
    .keyCommand(
      "Focus left",
      key: .character("h"),
      modifiers: .alt,
      action: { workspace.focus(.left, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus down",
      key: .character("j"),
      modifiers: .alt,
      action: { workspace.focus(.down, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus up",
      key: .character("k"),
      modifiers: .alt,
      action: { workspace.focus(.up, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus right",
      key: .character("l"),
      modifiers: .alt,
      action: { workspace.focus(.right, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus left",
      key: .arrowLeft,
      modifiers: .alt,
      action: { workspace.focus(.left, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus down",
      key: .arrowDown,
      modifiers: .alt,
      action: { workspace.focus(.down, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus up",
      key: .arrowUp,
      modifiers: .alt,
      action: { workspace.focus(.up, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Focus right",
      key: .arrowRight,
      modifiers: .alt,
      action: { workspace.focus(.right, within: contentSize(for: size)) }
    )
    .keyCommand(
      "Split right",
      key: .character("v"),
      modifiers: .alt,
      action: { splitFocusedPane(axis: .horizontal) }
    )
    .keyCommand(
      "Split down",
      key: .character("s"),
      modifiers: .alt,
      action: { splitFocusedPane(axis: .vertical) }
    )
    .keyCommand(
      "New shell pane",
      key: .character("n"),
      modifiers: .alt,
      action: { splitFocusedPane(axis: .horizontal) }
    )
    .keyCommand(
      "New tab",
      key: .character("t"),
      modifiers: .alt,
      action: appendShellTab
    )
    .keyCommand(
      "Zoom pane",
      key: .character("z"),
      modifiers: .alt,
      action: { workspace.toggleZoom() }
    )
    .keyCommand(
      "Close pane",
      key: .character("x"),
      modifiers: .alt,
      isEnabled: workspace.canCloseFocusedPane,
      action: closeFocusedPane
    )
    .paletteCommand(
      name: "Split pane right",
      description: "Alt+V",
      action: { splitFocusedPane(axis: .horizontal) }
    )
    .paletteCommand(
      name: "Split pane down",
      description: "Alt+S",
      action: { splitFocusedPane(axis: .vertical) }
    )
    .paletteCommand(
      name: "New shell tab",
      description: "Alt+T",
      action: appendShellTab
    )
    .paletteCommand(
      name: workspace.zoomedPaneID == nil ? "Zoom focused pane" : "Unzoom focused pane",
      description: "Alt+Z",
      action: { workspace.toggleZoom() }
    )
    .paletteCommand(
      name: "Close focused pane",
      description: "Alt+X",
      isEnabled: workspace.canCloseFocusedPane,
      action: closeFocusedPane
    )
    .paletteSheet("Workspace commands", isPresented: $showsCommandPalette) { commands in
      TerminalWorkspaceCommandPalette(
        commands: commands,
        dismiss: { showsCommandPalette = false }
      )
    }
    .onAppear {
      workspace.normalizeFocus()
      focusedPane = workspace.focusedPaneID
    }
    .onChange(of: workspace.focusedPaneID) { _, newValue in
      focusedPane = newValue
    }
    .onChange(of: focusedPane) { _, newValue in
      if let newValue {
        workspace.focusPane(newValue)
      }
    }
    .onChange(of: workspace.allPaneIDs) {
      sessions.removeSessions(except: workspace.allPaneIDs)
    }
  }

  private var tabStrip: some View {
    HStack(spacing: 1) {
      ForEach(workspace.tabs, id: \.id) { tab in
        Button {
          workspace.selectTab(tab.id)
        } label: {
          Text(tab.id == workspace.activeTab?.id ? "[\(tab.title)]" : " \(tab.title) ")
            .foregroundStyle(tab.id == workspace.activeTab?.id ? .tint : .muted)
        }
      }
      Spacer(minLength: 1)
      Text(workspace.zoomedPaneID == nil ? "workspace" : "zoom")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func paneSurface(size: CellSize) -> some View {
    if let tab = workspace.activeTab {
      if let zoomedPaneID = workspace.zoomedPaneID,
        let zoomedPane = tab.root.pane(id: zoomedPaneID)
      {
        paneView(for: zoomedPane)
      } else {
        TerminalWorkspaceNodeView(
          node: tab.root,
          workspace: $workspace,
          sessions: sessions,
          focusedPane: $focusedPane
        )
      }
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("No workspace tabs").foregroundStyle(.muted)
        Text("Use the host app to create a tab.").foregroundStyle(.separator)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
  }

  private func paneView(for pane: TerminalPaneSpec) -> some View {
    TerminalWorkspacePaneView(
      pane: pane,
      session: sessions.session(for: pane),
      isFocused: workspace.focusedPaneID == pane.id,
      isZoomed: workspace.zoomedPaneID == pane.id,
      focusedPane: $focusedPane
    )
  }

  private var statusStrip: some View {
    HStack(spacing: 2) {
      Text(workspace.focusedPane?.title ?? "no pane")
        .foregroundStyle(.tint)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 1)
      Text("^K commands")
        .foregroundStyle(.separator)
      Text("Alt+HJKL focus")
        .foregroundStyle(.separator)
      Text("Alt+V/S split")
        .foregroundStyle(.separator)
      Text("Alt+Z zoom")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func contentSize(for outerSize: CellSize) -> CellSize {
    CellSize(width: outerSize.width, height: max(0, outerSize.height - 4))
  }

  private func splitFocusedPane(axis: TerminalSplitAxis) {
    let id = workspace.nextAvailablePaneID(prefix: "shell")
    workspace.splitFocusedPane(
      axis: axis,
      newPane: .shell(
        id: id,
        title: id.rawValue,
        workingDirectory: workspace.focusedPane?.workingDirectory
      )
    )
  }

  private func appendShellTab() {
    let tabID = workspace.nextAvailableTabID(prefix: "tab")
    let paneID = TerminalPaneID("\(tabID.rawValue)-shell")
    workspace.appendTab(
      TerminalWorkspaceTab(
        id: tabID,
        title: tabID.rawValue,
        root: .terminal(.shell(id: paneID, title: "shell"))
      )
    )
  }

  private func closeFocusedPane() {
    if let removed = workspace.closeFocusedPane() {
      sessions.removeSession(for: removed)
    }
  }
}

private struct TerminalWorkspaceNodeView: View {
  var node: TerminalWorkspaceNode
  @Binding var workspace: TerminalWorkspaceState
  var sessions: TerminalWorkspaceSessionStore
  var focusedPane: FocusState<TerminalPaneID?>.Binding

  var body: some View {
    switch node {
    case .terminal(let pane):
      TerminalWorkspacePaneView(
        pane: pane,
        session: sessions.session(for: pane),
        isFocused: workspace.focusedPaneID == pane.id,
        isZoomed: workspace.zoomedPaneID == pane.id,
        focusedPane: focusedPane
      )
    case .split(let split):
      TerminalWorkspaceSplitLayout(
        axis: split.axis,
        fraction: split.fraction
      ) {
        TerminalWorkspaceNodeView(
          node: split.first,
          workspace: $workspace,
          sessions: sessions,
          focusedPane: focusedPane
        )
        TerminalWorkspaceNodeView(
          node: split.second,
          workspace: $workspace,
          sessions: sessions,
          focusedPane: focusedPane
        )
      }
    }
  }
}

private struct TerminalWorkspacePaneView: View {
  var pane: TerminalPaneSpec
  var session: TerminalProcessSession
  var isFocused: Bool
  var isZoomed: Bool
  var focusedPane: FocusState<TerminalPaneID?>.Binding

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text(isFocused ? "*" : "o")
          .foregroundStyle(isFocused ? .tint : .separator)
        Text(pane.title)
          .foregroundStyle(isFocused ? .foreground : .muted)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 1)
        if isZoomed {
          Text("zoom").foregroundStyle(.separator)
        }
      }
      .padding(.horizontal, 1)
      TerminalView(session: session)
        .focused(focusedPane, equals: pane.id)
        .defaultFocus(focusedPane, pane.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .border(isFocused ? .tint : .separator)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TerminalWorkspaceSplitLayout: Layout {
  var axis: TerminalSplitAxis
  var fraction: Double

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard !subviews.isEmpty else {
      return .zero
    }

    let width =
      finiteDimension(proposal.width)
      ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
      ?? 0
    let height =
      finiteDimension(proposal.height)
      ?? subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }.max()
      ?? 0
    return LayoutSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard subviews.count >= 2 else {
      subviews.first?.place(
        at: bounds.origin,
        anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.size.width, height: bounds.size.height)
      )
      return
    }

    let split = TerminalSplit(
      axis: axis,
      fraction: fraction,
      first: .terminal(
        TerminalPaneSpec(id: "__layout-first", title: "", command: "")
      ),
      second: .terminal(
        TerminalPaneSpec(id: "__layout-second", title: "", command: "")
      )
    )
    let rects = TerminalWorkspaceLayout.splitRects(
      for: split,
      in: CellRect(origin: CellPoint(x: bounds.origin.x, y: bounds.origin.y), size: bounds.size)
    )

    subviews[0].place(
      at: rects.first.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(width: rects.first.size.width, height: rects.first.size.height)
    )
    subviews[1].place(
      at: rects.second.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(width: rects.second.size.width, height: rects.second.size.height)
    )
  }

  private func finiteDimension(_ dimension: ProposedDimension) -> Int? {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .infinity, .unspecified:
      return nil
    }
  }
}

private struct TerminalWorkspaceCommandPalette: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  @State private var query = ""
  @FocusState private var isQueryFocused: Bool

  private var matches: [ActivePaletteCommand] {
    guard !query.isEmpty else {
      return commands
    }
    return commands.filter { command in
      command.name.lowercased().contains(query.lowercased())
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 2) {
        Text("Workspace commands").bold()
        Spacer()
        Text("Enter to run").foregroundStyle(.separator)
      }
      Divider()
      TextField("Filter commands", text: $query)
        .focused($isQueryFocused)
      Divider()
      if matches.isEmpty {
        Text("No matches").foregroundStyle(.separator)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(matches.indices, id: \.self) { index in
            Button {
              matches[index].action()
              dismiss()
            } label: {
              HStack(spacing: 2) {
                Text(matches[index].name)
                Spacer(minLength: 1)
                if let description = matches[index].description {
                  Text(description).foregroundStyle(.separator)
                }
              }
            }
            .disabled(!matches[index].isEnabled)
          }
        }
      }
      Divider()
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
      }
    }
    .padding(1)
    .frame(minWidth: 52, alignment: .leading)
    .onAppear {
      query = ""
      isQueryFocused = true
    }
  }
}
