import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Palette-command absorption.
///
/// These tests used to observe absorption through the `paletteSheet`
/// content builder, which A5 removed — a palette is declaration plus
/// command data plus the framework's own rendering. They now assert on the
/// rendered surface instead, which is a stronger claim: it shows the
/// absorbed commands reach the *rendering*, not merely a closure.
@MainActor
@Suite
struct PaletteSheetAbsorptionTests {
  private func surface(_ view: some View, identity: String) -> String {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity(identity)),
      proposal: .init(width: 60, height: 16)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  @Test("paletteSheet renders the palette commands absorbed from its subtree")
  func paletteSheetRendersAbsorbedCommands() {
    let rendered = surface(
      Panel(id: "inner") { EmptyView() }
        .paletteCommand(name: "Alpha", action: {})
        .paletteCommand(name: "Beta", action: {})
        .panel(id: "host")
        .paletteSheet("Palette", isPresented: Binding.constant(true)),
      identity: "absorption-root"
    )
    #expect(rendered.contains("Alpha"))
    #expect(rendered.contains("Beta"))
    // Contribution order is preserved for an empty query: Alpha's row
    // precedes Beta's in the rendered lines.
    let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false)
    let alphaLine = lines.firstIndex { $0.contains("Alpha") }
    let betaLine = lines.firstIndex { $0.contains("Beta") }
    #expect(alphaLine != nil)
    #expect(betaLine != nil)
    if let alphaLine, let betaLine {
      #expect(alphaLine < betaLine)
    }
  }

  @Test("paletteSheet still receives palette commands after toolbar composition")
  func paletteSheetReceivesCommandsAfterToolbarComposition() {
    let rendered = surface(
      Panel(id: "host") {
        Text("body")
          .toolbarItem(.init(title: "Palette", action: {}))
      }
      .paletteCommand(name: "Alpha", action: {})
      .toolbar().toolbarStyle(DefaultBottomToolbarStyle())
      .paletteSheet("Palette", isPresented: Binding.constant(true)),
      identity: "toolbar-absorption-root"
    )
    #expect(rendered.contains("Alpha"))
  }

  @Test("paletteSheet clears absorbed commands so they do not re-bubble")
  func paletteSheetClearsAbsorbedCommands() {
    let view =
      Panel(id: "inner") { EmptyView() }
      .paletteCommand(name: "Inner", action: {})
      .panel(id: "outer")
      .paletteSheet("Inner", isPresented: Binding.constant(true))

    let context = ResolveContext(identity: testIdentity("clear-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let leftover = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(leftover.isEmpty)
  }

  @Test("a dismissed palette renders no command rows")
  func dismissedPaletteRendersNothing() {
    let rendered = surface(
      Panel(id: "inner") { EmptyView() }
        .paletteCommand(name: "Alpha", action: {})
        .panel(id: "host")
        .paletteSheet("Palette", isPresented: Binding.constant(false)),
      identity: "absent-root"
    )
    #expect(!rendered.contains("Alpha"))
    #expect(!rendered.contains("Filter commands"))
  }
}
