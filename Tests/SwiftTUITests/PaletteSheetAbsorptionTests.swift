import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteSheetAbsorptionTests {
  @Test("paletteSheet content receives palette commands contributed by its subtree")
  func paletteSheetReceivesSubtreeContributions() {
    let capture = PaletteSheetCaptureBox()

    let view =
      Panel(id: "inner") { EmptyView() }
        .paletteCommand(name: "Alpha", action: {})
        .paletteCommand(name: "Beta", action: {})
        .panel(id: "host")
        .paletteSheet("Palette", isPresented: Binding.constant(true)) { commands in
          capture.commandNames = commands.map(\.name)
          return Text("placeholder")
        }

    let context = ResolveContext(identity: testIdentity("absorption-root"))
    _ = Resolver().resolve(AnyView(view), in: context)

    #expect(capture.commandNames == ["Alpha", "Beta"])
  }

  @Test("paletteSheet clears absorbed commands so they do not re-bubble")
  func paletteSheetClearsAbsorbedCommands() {
    let view =
      Panel(id: "inner") { EmptyView() }
        .paletteCommand(name: "Inner", action: {})
        .panel(id: "outer")
        .paletteSheet("Inner", isPresented: Binding.constant(true)) { _ in Text("") }

    let context = ResolveContext(identity: testIdentity("clear-root"))
    let resolved = Resolver().resolve(AnyView(view), in: context)
    let leftover = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(leftover.isEmpty)
  }

  @Test("paletteSheet content builder is not invoked when isPresented is false")
  func paletteSheetSkipsBuilderWhenNotPresented() {
    let capture = PaletteSheetCaptureBox()

    let view =
      Panel(id: "inner") { EmptyView() }
        .paletteCommand(name: "Alpha", action: {})
        .panel(id: "host")
        .paletteSheet("Palette", isPresented: Binding.constant(false)) { commands in
          capture.commandNames = commands.map(\.name)
          return Text("placeholder")
        }

    let context = ResolveContext(identity: testIdentity("absent-root"))
    _ = Resolver().resolve(AnyView(view), in: context)

    #expect(capture.commandNames.isEmpty)
  }
}

@MainActor
final class PaletteSheetCaptureBox {
  var commandNames: [String] = []
}
