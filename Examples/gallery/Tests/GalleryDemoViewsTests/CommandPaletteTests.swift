import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct CommandPaletteTests {
  @Test("command palette resolves through a declared child identity")
  func commandPaletteResolvesThroughDeclaredChildBoundary() {
    let rootIdentity = Identity(components: ["CommandPaletteRoot"])
    var environment = EnvironmentValues()
    environment.terminalSize = .init(width: 80, height: 24)

    let artifacts = DefaultRenderer().render(
      CommandPaletteList(
        commands: [],
        dismiss: {}
      ),
      context: .init(
        identity: rootIdentity,
        environmentValues: environment
      ),
      proposal: .init(width: 44, height: 12)
    )

    #expect(artifacts.resolvedTree.identity == rootIdentity.child("Group[0]"))
  }
}
