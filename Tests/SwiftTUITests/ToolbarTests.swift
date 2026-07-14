import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ToolbarTests {
  @Test("DefaultTopToolbarStyle and DefaultBottomToolbarStyle conform to ToolbarStyle")
  func defaultStylesExist() {
    let top: any ToolbarStyle = DefaultTopToolbarStyle()
    let bottom: any ToolbarStyle = DefaultBottomToolbarStyle()
    #expect(top.placement == .top)
    #expect(bottom.placement == .bottom)
  }

  @Test("toolbarItem contributions accumulate up the tree via preference key")
  func toolbarItemsAccumulate() {
    let view = VStack {
      Text("A").toolbarItem(
        .init(
          title: "Item A",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        )
      )
      Text("B").toolbarItem(
        .init(
          title: "Item B",
          icon: nil,
          position: .top,
          isEnabled: true,
          action: {}
        )
      )
    }
    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.count == 2)
    #expect(items.map(\.title).contains("Item A"))
    #expect(items.map(\.title).contains("Item B"))
  }

  @Test("Builder toolbarItem variant registers its label text as the title")
  @available(*, deprecated, message: "exercises the deprecated toolbarItem(label:icon:) overload")
  func builderVariantRegisters() {
    let view = Text("X").toolbarItem(action: {}) {
      Text("Copy")
    } icon: {
      EmptyView()
    }
    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.first?.title == "Copy")
  }

  @Test("Builder toolbarItem variant extracts text from composed label views")
  @available(*, deprecated, message: "exercises the deprecated toolbarItem(label:icon:) overload")
  func builderVariantExtractsComposedLabelText() {
    let view = Text("X").toolbarItem(action: {}) {
      HStack(spacing: 1) {
        Text("Copy")
        Text("File").foregroundStyle(.muted)
      }
    } icon: {
      EmptyView()
    }
    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let items = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(items.first?.title == "Copy File")
  }

  @Test("Panel with toolbar absorbs toolbar items from its subtree")
  func toolbarAbsorbsItems() {
    let panel =
      Panel(id: "outer") {
        Text("content").toolbarItem(
          .init(
            title: "Save",
            icon: nil,
            position: .top,
            isEnabled: true,
            action: {}
          )
        )
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(panel), in: context)
    // After the toolbar modifier consumes the preference, the outer
    // preferenceValues should NOT still contain the toolbar item.
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    #expect(leakedItems.isEmpty)
  }

  @Test("Unhosted toolbar items emit runtime issues")
  func unhostedToolbarItemEmitsRuntimeIssue() {
    let view = Text("content").toolbarItem(
      .init(
        title: "Save",
        icon: nil,
        position: .top,
        isEnabled: true,
        action: {}
      )
    )

    let artifacts = DefaultRenderer().render(
      view,
      context: ResolveContext(identity: testIdentity("toolbar-unhosted-root"))
    )
    let issue = artifacts.diagnostics.runtime.issues.first
    #expect(artifacts.diagnostics.runtime.issues.count == 1)
    #expect(issue?.code == "toolbar.unhostedItems")
    #expect(issue?.severity == .warning)
    #expect(issue?.identity != nil)
  }

  @Test("Hosted toolbar items do not emit runtime issues")
  func hostedToolbarItemDoesNotEmitRuntimeIssue() {
    let panel =
      Panel(id: "outer") {
        Text("content").toolbarItem(
          .init(
            title: "Save",
            icon: nil,
            position: .top,
            isEnabled: true,
            action: {}
          )
        )
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-hosted-root"))
    )
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
  }

  @Test("Late toolbar items inside GeometryReader emit unhosted runtime issues")
  func lateToolbarItemInsideGeometryReaderEmitsRuntimeIssue() {
    let artifacts = DefaultRenderer().render(
      GeometryReader { _ in
        Text("content").toolbarItem(
          .init(
            title: "Late Save",
            icon: nil,
            position: .bottom,
            isEnabled: true,
            action: {}
          )
        )
      },
      context: .init(identity: testIdentity("toolbar-late-unhosted-root")),
      proposal: .init(width: 24, height: 4)
    )
    let issue = artifacts.diagnostics.runtime.issues.first

    #expect(artifacts.diagnostics.runtime.issues.count == 1)
    #expect(issue?.code == "toolbar.unhostedItems")
    #expect(issue?.severity == .warning)
    #expect(issue?.identity != nil)
  }

  @Test("Panel toolbar absorbs toolbar items realized inside GeometryReader")
  func toolbarAbsorbsItemsRealizedInsideGeometryReader() {
    let panel =
      Panel(id: "outer") {
        GeometryReader { proxy in
          Text("body \(proxy.size.width)x\(proxy.size.height)")
            .toolbarItem(
              .init(
                title: "Size \(proxy.size.width)x\(proxy.size.height)",
                icon: nil,
                position: .bottom,
                isEnabled: true,
                action: {}
              )
            )
        }
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 30, height: 6)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-late-hosted-root")),
      proposal: .init(width: 30, height: 6)
    )
    let lines = artifacts.rasterSurface.lines
    let bodyRow = lines.firstIndex { $0.contains("body 30x5") }
    let sizeRow = lines.firstIndex { $0.contains("Size 30x5") }

    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
    #expect(bodyRow != nil)
    #expect(sizeRow != nil)
    if let bodyRow, let sizeRow {
      #expect(bodyRow < sizeRow)
    }
    #expect(
      artifacts.semanticSnapshot.accessibilityNodes.contains { node in
        node.role == .button && node.label == "Size 30x5"
      }
    )
  }

  @Test("Late toolbar items commit their action handlers")
  func lateToolbarItemActionHandlerCommits() throws {
    let actionRegistry = LocalActionRegistry()
    var actionCount = 0
    let panel =
      Panel(id: "outer") {
        GeometryReader { proxy in
          Text("body \(proxy.size.width)x\(proxy.size.height)")
            .toolbarItem(
              .init(
                title: "Increment \(proxy.size.width)x\(proxy.size.height)",
                icon: nil,
                position: .bottom,
                isEnabled: true,
                action: {
                  actionCount += 1
                }
              )
            )
        }
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 30, height: 6)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(
        identity: testIdentity("toolbar-late-action-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 6)
    )
    let button = try #require(
      artifacts.semanticSnapshot.accessibilityNodes.first { node in
        node.role == .button && node.label == "Increment 30x5"
      }
    )

    #expect(actionRegistry.dispatch(identity: button.identity))
    #expect(actionCount == 1)
  }

  @Test("Toolbar strip reuse refreshes current action handlers")
  func toolbarStripReuseRefreshesCurrentActionHandlers() throws {
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    var dispatchedMarkers: [String] = []

    func panel(actionMarker: String) -> some View {
      let marker = actionMarker
      return Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Stable",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {
                dispatchedMarkers.append(marker)
              }
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 20, height: 5)
    }

    _ = renderer.render(
      panel(actionMarker: "first"),
      context: .init(
        identity: testIdentity("toolbar-reuse-action-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let second = renderer.render(
      panel(actionMarker: "second"),
      context: .init(
        identity: testIdentity("toolbar-reuse-action-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let button = try #require(
      second.semanticSnapshot.accessibilityNodes.first { node in
        node.role == .button && node.label == "Stable"
      }
    )

    #expect(second.diagnostics.work.resolvedNodesReused > 0)
    #expect(actionRegistry.dispatch(identity: button.identity))
    #expect(dispatchedMarkers == ["second"])
  }

  @Test("Strip reuse refresh pairs discovered identities with enabled items only")
  func toolbarStripReuseRefreshPairsEnabledItems() throws {
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    var dispatchedMarkers: [String] = []

    // Three items with the middle one disabled: a disabled Button never
    // registers an action, so the discovered refresh identities must pair
    // positionally with the ENABLED items — a whole-items zip would
    // re-point "Third"'s registration at "Second"'s (disabled) closure.
    func panel(generation: String) -> some View {
      func item(_ title: String, isEnabled: Bool = true) -> ToolbarItemConfig {
        .init(
          title: title,
          icon: nil,
          position: .top,
          isEnabled: isEnabled,
          action: { dispatchedMarkers.append("\(title)-\(generation)") }
        )
      }
      return Panel(id: "outer") {
        Text("body")
          .toolbarItem(item("First"))
          .toolbarItem(item("Second", isEnabled: false))
          .toolbarItem(item("Third"))
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 40, height: 5)
    }

    _ = renderer.render(
      panel(generation: "g1"),
      context: .init(
        identity: testIdentity("toolbar-reuse-enabled-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let second = renderer.render(
      panel(generation: "g2"),
      context: .init(
        identity: testIdentity("toolbar-reuse-enabled-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(second.diagnostics.work.resolvedNodesReused > 0)
    for title in ["First", "Third"] {
      let button = try #require(
        second.semanticSnapshot.accessibilityNodes.first { node in
          node.role == .button && node.label == title
        },
        "no button node for \(title)"
      )
      #expect(actionRegistry.dispatch(identity: button.identity))
    }
    #expect(dispatchedMarkers == ["First-g2", "Third-g2"])
  }

  @Test("Toolbar strip reuse is frame-product equivalent to fresh resolve")
  func toolbarStripReuseIsFrameProductEquivalent() {
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()

    func panel() -> some View {
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              systemHint: "S",
              action: {}
            )
          )
          .toolbarItem(
            .init(
              title: "Reset",
              icon: nil,
              position: .top,
              isEnabled: true,
              systemHint: "R",
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 30, height: 6)
    }

    let first = renderer.render(
      panel(),
      context: .init(
        identity: testIdentity("toolbar-equivalence-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let firstActionRegistrations = actionRegistrationSummary(actionRegistry)

    let second = renderer.render(
      panel(),
      context: .init(
        identity: testIdentity("toolbar-equivalence-root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let secondActionRegistrations = actionRegistrationSummary(actionRegistry)

    #expect(second.diagnostics.work.resolvedNodesReused > 0)
    #expect(second.resolvedTree == first.resolvedTree)
    #expect(second.measuredTree == first.measuredTree)
    #expect(second.placedTree == first.placedTree)
    #expect(second.semanticSnapshot == first.semanticSnapshot)
    #expect(second.drawTree == first.drawTree)
    #expect(second.rasterSurface == first.rasterSurface)
    #expect(secondActionRegistrations == firstActionRegistrations)
  }

  @Test("Unselected layout-dependent candidates do not leak toolbar items")
  func unselectedLayoutDependentCandidatesDoNotLeakToolbarItems() {
    let panel =
      Panel(id: "outer") {
        ViewThatFits {
          GeometryReader { proxy in
            Text("wide \(proxy.size.width)x\(proxy.size.height)")
              .toolbarItem(
                .init(
                  title: "Wide",
                  icon: nil,
                  position: .bottom,
                  isEnabled: true,
                  action: {}
                )
              )
          }
          .frame(width: 20, height: 1)

          Text("fit")
        }
        .frame(width: 3, height: 1)
      }
      .toolbar(style: DefaultBottomToolbarStyle())

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-unselected-candidate-root")),
      proposal: .init(width: 3, height: 1)
    )
    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
    #expect(!rendered.contains("Wide"))
    #expect(rendered.contains("fit"))
  }

  @Test("RunLoop forwards runtime issues to the host sink")
  func runLoopForwardsRuntimeIssuesToHostSink() async throws {
    let rootIdentity = testIdentity("toolbar-runloop-root")
    let receivedIssues = LockedBox<[RuntimeIssue]>([])
    let terminalSize = CellSize(width: 24, height: 4)
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: ToolbarIssueTerminalHost(size: terminalSize),
      terminalInputReader: EmptyToolbarIssueInput(),
      signalReader: EmptyToolbarIssueSignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        Text("content").toolbarItem(
          .init(
            title: "Save",
            icon: nil,
            position: .top,
            isEnabled: true,
            action: {}
          )
        )
      }
    )
    runLoop.runtimeIssueSink = RuntimeIssueSink { issue in
      receivedIssues.withLock { issues in
        issues.append(issue)
      }
    }

    let result = try await runLoop.run()
    // Filter to the toolbar issue: the soundness probe's counters are
    // process-global, so concurrently-running suites' sampled violations can
    // legitimately reach this run loop's sink too (F34 routing).
    let toolbarIssues = receivedIssues.value.filter { $0.code == "toolbar.unhostedItems" }

    #expect(result.exitReason == .inputEnded)
    #expect(toolbarIssues.count == 1)
    #expect(toolbarIssues.first?.severity == .warning)
  }

  @Test(
    "Toolbar items bubble past a non-toolbar scope and land at the next ancestor with a toolbar")
  func toolbarItemsBubblePastScopeWithoutToolbar() {
    let view =
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("content").toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
        }
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let leakedItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
    // Absorbed at outer Panel because inner Panel has no toolbar.
    #expect(leakedItems.isEmpty)
  }

  @Test("Panel with top toolbar renders item titles in a horizontal strip above the content")
  func toolbarRendersAboveContent() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-render-root"))
    )
    let lines = artifacts.rasterSurface.lines
    let saveRow = lines.firstIndex { $0.contains("Save") }
    let bodyRow = lines.firstIndex { $0.contains("body") }
    #expect(saveRow != nil)
    #expect(bodyRow != nil)
    if let saveRow, let bodyRow {
      // Top-placement: toolbar strip must appear above the content.
      #expect(saveRow < bodyRow)
    }
  }

  @Test("Top toolbar reclaims the container's top safe area")
  func topToolbarUsesTopSafeArea() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = render(
      panel,
      terminalSize: .init(width: 20, height: 6),
      safeAreaInsets: .init(top: 1, leading: 0, bottom: 0, trailing: 0)
    )
    let lines = artifacts.rasterSurface.lines
    let saveRow = lines.firstIndex { $0.contains("Save") }
    let bodyRow = lines.firstIndex { $0.contains("body") }

    #expect(saveRow != nil)
    #expect(bodyRow != nil)
    if let saveRow, let bodyRow {
      #expect(saveRow == 0)
      #expect(saveRow < bodyRow)
    }
  }

  @Test(
    "Toolbar-strip buttons inherit the Panel's scope path so commands registered at the Panel are visible from toolbar focus"
  )
  func toolbarStripInheritsPanelScope() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Save",
              icon: nil,
              position: .top,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultTopToolbarStyle())

    let context = ResolveContext(identity: testIdentity("toolbar-scope-root"))
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    // Find the Panel node and confirm the toolbar strip sits inside
    // it (not as a sibling). A toolbar whose strip is a sibling of
    // the Panel would leave toolbar-button focus outside the scope
    // boundary — palette/key commands registered at the Panel would
    // then be invisible to toolbar focus.
    guard let panelNode = findNode(in: resolved, where: { isKind($0.kind, named: "Panel") })
    else {
      Issue.record("Panel node not found in resolved tree")
      return
    }
    let hasButtonInsidePanel =
      findNode(
        in: panelNode,
        where: { isKind($0.kind, named: "Button") }
      ) != nil
    #expect(
      hasButtonInsidePanel,
      "expected a Button (toolbar-item button) somewhere inside the Panel subtree"
    )
  }

  @Test("Panel with bottom toolbar renders item titles below the content")
  func toolbarRendersBelowContent() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Close",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-render-bottom-root"))
    )
    let lines = artifacts.rasterSurface.lines
    let bodyRow = lines.firstIndex { $0.contains("body") }
    let closeRow = lines.firstIndex { $0.contains("Close") }
    #expect(bodyRow != nil)
    #expect(closeRow != nil)
    if let bodyRow, let closeRow {
      // Bottom-placement: toolbar strip must appear below the content.
      #expect(bodyRow < closeRow)
    }
  }

  @Test("Toolbar strip lays out multiple items as distinct siblings")
  func toolbarRendersMultipleItemsWithoutOverlap() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Reset counter",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
          .toolbarItem(
            .init(
              title: "⌃K Palette",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 40, height: 6)

    let artifacts = DefaultRenderer().render(
      panel,
      context: .init(identity: testIdentity("toolbar-multi-item-root"))
    )
    let lineContainingBoth = artifacts.rasterSurface.lines.first {
      $0.contains("Reset counter") && $0.contains("⌃K Palette")
    }

    #expect(lineContainingBoth != nil)
  }

  @Test("Bottom toolbar reclaims the container's bottom safe area")
  func bottomToolbarUsesBottomSafeArea() {
    let panel =
      Panel(id: "outer") {
        Text("body")
          .toolbarItem(
            .init(
              title: "Close",
              icon: nil,
              position: .bottom,
              isEnabled: true,
              action: {}
            )
          )
      }
      .toolbar(style: DefaultBottomToolbarStyle())
      .frame(width: 20, height: 5)

    let artifacts = render(
      panel,
      terminalSize: .init(width: 20, height: 6),
      safeAreaInsets: .init(top: 0, leading: 0, bottom: 1, trailing: 0)
    )
    let lines = artifacts.rasterSurface.lines
    let bodyRow = lines.firstIndex { $0.contains("body") }
    let closeRow = lines.firstIndex { $0.contains("Close") }

    #expect(closeRow != nil)
    #expect(bodyRow != nil)
    if let bodyRow, let closeRow {
      #expect(closeRow == lines.index(before: lines.endIndex))
      #expect(bodyRow < closeRow)
    }
  }
}

private struct ToolbarActionRegistrationSummary: Equatable {
  var identity: Identity
  var followUpInvalidationIdentity: Identity?
}

@MainActor
private func actionRegistrationSummary(
  _ registry: LocalActionRegistry
) -> [ToolbarActionRegistrationSummary] {
  registry.snapshot()
    .map { identity, registration in
      ToolbarActionRegistrationSummary(
        identity: identity,
        followUpInvalidationIdentity: registration.followUpInvalidationIdentity
      )
    }
    .sorted { lhs, rhs in lhs.identity < rhs.identity }
}

private final class ToolbarIssueTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_: RasterSurface) throws -> TerminalPresentationMetrics {
    .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

private final class EmptyToolbarIssueInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class EmptyToolbarIssueSignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

@MainActor
private func findNode(
  in root: ResolvedNode,
  where predicate: (ResolvedNode) -> Bool
) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if predicate(node) { return node }
    stack.append(contentsOf: node.children)
  }
  return nil
}

@MainActor
private func isKind(_ kind: NodeKind, named name: String) -> Bool {
  if case .view(let n) = kind, n == name { return true }
  return false
}

@MainActor
private func render<V: View>(
  _ view: V,
  terminalSize: CellSize,
  safeAreaInsets: EdgeInsets
) -> RenderSnapshot {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = terminalSize
  environmentValues.safeAreaInsets = safeAreaInsets
  return DefaultRenderer().render(
    view,
    context: .init(
      identity: testIdentity("toolbar-safe-area-root"),
      environmentValues: environmentValues
    ),
    proposal: .init(
      width: terminalSize.width,
      height: terminalSize.height
    )
  )
}
