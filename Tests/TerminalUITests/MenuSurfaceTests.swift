import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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
}

@MainActor
struct MenuSurfaceTests {
  @Test("Plain Text stays non-focusable by default")
  func plainTextStaysNonFocusableByDefault() {
    let text = Text("Hello")
    let explicitText = Text("Hello", semanticMetadata: SemanticMetadata())
    #expect(SemanticMetadata().presentationRole == nil)
    #expect(text.semanticMetadata.presentationRole == nil)
    #expect(explicitText.semanticMetadata.presentationRole == nil)
    let artifacts = DefaultRenderer().render(
      text,
      context: .init(identity: testIdentity("TextRoot"))
    )

    #expect(artifacts.resolvedTree.semanticMetadata.presentationRole == nil)
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
    #expect(menuNode?.semanticMetadata.presentationRole == .menu)
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("Menu")
      ]
    )
  }

  @Test("Menu toggles open and renders authored commands")
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

    let renderer = DefaultRenderer()
    let collapsedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(!collapsedArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Save"))
    #expect(actionRegistry.dispatch(identity: testIdentity("Menu")))

    let expandedArtifacts = renderer.render(
      menu,
      context: .init(
        identity: testIdentity("Root"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
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
    #expect(
      expandedArtifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("Menu")
      ]
    )
  }
}
