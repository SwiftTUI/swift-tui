import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

extension ResolvedNode {
  fileprivate func descendant(withIdentity identity: Identity) -> ResolvedNode? {
    if self.identity == identity {
      return self
    }

    for child in children {
      if let match = child.descendant(withIdentity: identity) {
        return match
      }
    }

    return nil
  }

  fileprivate func contains(predicate: (ResolvedNode) -> Bool) -> Bool {
    if predicate(self) { return true }
    return children.contains { $0.contains(predicate: predicate) }
  }
}

@MainActor
struct MenuSurfaceTests {
  @Test("Plain Text stays non-focusable by default")
  func plainTextStaysNonFocusableByDefault() {
    let text = Text("Hello")
    let explicitText = Text("Hello", semanticMetadata: SemanticMetadata())
    #expect(SemanticMetadata().accessibilityRole == nil)
    #expect(text.semanticMetadata.accessibilityRole == nil)
    #expect(explicitText.semanticMetadata.accessibilityRole == nil)
    let artifacts = DefaultRenderer().render(
      text,
      context: .init(identity: testIdentity("TextRoot"))
    )

    #expect(artifacts.resolvedTree.semanticMetadata.accessibilityRole == nil)
    #expect(artifacts.semanticSnapshot.focusRegions.isEmpty)
  }

  @Test("Menu is focusable and starts collapsed")
  func menuIsFocusableAndStartsCollapsed() {
    let artifacts = DefaultRenderer().render(
      Menu("Actions") {
        Button("Open") {}
        Divider().id(testIdentity("MenuDivider"))
        Group {
          Button("Save") {}
          ForEach([1, 2], id: \.self) { index in
            Button("Item \(index)") {}
          }
        }
      }
      .id(testIdentity("Menu")),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let menuNode = artifacts.resolvedTree.descendant(withIdentity: testIdentity("Menu"))

    #expect(surface.contains("Actions"))
    #expect(surface.contains("▾"))
    #expect(!surface.contains("Open"))
    #expect(menuNode?.semanticMetadata.accessibilityRole == .menu)
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("Menu")
      ]
    )
  }

  @Test("Menu trigger row stays a single cell tall regardless of expansion state")
  func menuTriggerHeightDoesNotGrowWhenExpanded() {
    // The whole point of overlay rendering: opening a menu must NOT
    // reflow surrounding layout. Stack the menu above a Text — with
    // a tall spacer between them so the menu's overlay (which lives
    // in the same screen region as the trigger's top-leading anchor)
    // cannot visually cover the "BELOW" sentinel — and measure the
    // Text's row before and after expansion. If the menu were
    // inline-expanding, the Text would slide down by N rows.
    let actionRegistry = LocalActionRegistry()
    let menu =
      VStack(alignment: .leading, spacing: 0) {
        Menu("Actions") {
          Button("Open") {}
          Button("Save") {}
          Button("Quit") {}
        }
        .id(testIdentity("Menu"))
        Spacer().frame(height: 14)
        Text("BELOW").id(testIdentity("Below"))
      }

    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 30, height: 24)
    let renderer = DefaultRenderer()

    let collapsedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 24)
    )
    let collapsedLines = collapsedArtifacts.rasterSurface.lines
    let belowRowCollapsed = collapsedLines.firstIndex(where: { $0.contains("BELOW") })

    #expect(actionRegistry.dispatch(identity: testIdentity("Menu")))

    let expandedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 24)
    )
    let expandedLines = expandedArtifacts.rasterSurface.lines
    let belowRowExpanded = expandedLines.firstIndex(where: { $0.contains("BELOW") })

    // The exact row index depends on layout, but it must not change
    // when the menu opens — that's the no-pushdown invariant.
    #expect(belowRowCollapsed != nil)
    #expect(belowRowExpanded != nil)
    #expect(belowRowCollapsed == belowRowExpanded)
  }

  @Test("Menu toggles open and renders authored commands as an overlay")
  func menuTogglesOpenAndRendersAuthoredCommands() {
    let actionRegistry = LocalActionRegistry()
    let menu = Menu("Actions") {
      Button("Open") {}
      Divider().id(testIdentity("MenuDivider"))
      Group {
        Button("Save") {}
        ForEach([1, 2], id: \.self) { index in
          Button("Item \(index)") {}
        }
      }
    }
    .id(testIdentity("Menu"))

    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 30, height: 20)
    let renderer = DefaultRenderer()

    let collapsedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 20)
    )

    #expect(!collapsedArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Save"))
    #expect(actionRegistry.dispatch(identity: testIdentity("Menu")))

    let expandedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 30, height: 20)
    )
    let surface = expandedArtifacts.rasterSurface.lines.joined(separator: "\n")
    let dividerNode = expandedArtifacts.resolvedTree.descendant(
      withIdentity: testIdentity("MenuDivider")
    )

    #expect(surface.contains("Open"))
    #expect(surface.contains("Save"))
    #expect(surface.contains("Item 1"))
    #expect(surface.contains("Item 2"))
    #expect(dividerNode?.kind == .view("Divider"))
    #expect(surface.contains("────"))
    // Menu items render as part of the portal overlay's focus scope, while
    // the base trigger remains focusable because menus are non-modal.
    let focusIdentities = expandedArtifacts.semanticSnapshot.focusRegions.map(\.identity)
    let hasOverlayItem = focusIdentities.contains {
      $0.path.contains("PortalHost/overlays")
    }
    #expect(!focusIdentities.isEmpty)
    #expect(focusIdentities.contains(testIdentity("Menu")))
    #expect(hasOverlayItem)
  }

  @Test("Menu overlay measures intrinsically even when rows contain shortcut hint spacers")
  func menuOverlayMeasuresIntrinsicallyWithShortcutHintSpacers() {
    let actionRegistry = LocalActionRegistry()
    let menu = Menu("Actions") {
      Button("Save") {}
        .systemHint("Ctrl+S")
      Button("Save As") {}
        .systemHint("Alt+S")
    }
    .id(testIdentity("Menu"))

    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 40, height: 12)
    let renderer = DefaultRenderer()

    _ = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 12)
    )

    #expect(actionRegistry.dispatch(identity: testIdentity("Menu")))

    let expandedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 12)
    )
    let saveLine = expandedArtifacts.rasterSurface.lines.first {
      $0.contains("Save") && $0.contains("Ctrl+S")
    }

    guard let saveLine,
      let labelRange = saveLine.range(of: "Save"),
      let hintRange = saveLine.range(of: "Ctrl+S")
    else {
      Issue.record("expected menu row to render both the label and shortcut hint")
      return
    }

    let labelEnd = saveLine.distance(from: saveLine.startIndex, to: labelRange.upperBound)
    let hintStart = saveLine.distance(from: saveLine.startIndex, to: hintRange.lowerBound)

    #expect(hintStart - labelEnd <= 3)
  }
}
