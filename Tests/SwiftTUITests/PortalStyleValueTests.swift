import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct PortalStyleValueTests {
  @Test("a shared prompt style receives each declaration's baseline and content presence")
  func promptBaselines() throws {
    let probe = PortalConfigurationProbe()
    _ = DefaultRenderer().render(
      Text("Base")
        .alert(
          "Alert", isPresented: .constant(true), actions: { EmptyView() },
          message: { Text("Message") }
        )
        .confirmationDialog(
          "Confirm", isPresented: .constant(true), actions: { Button("Accept") {} },
          message: { EmptyView() }
        )
        .promptStyle(InspectPromptStyle(probe: probe))
        .environment(\.terminalSize, .init(width: 79, height: 33)),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 79, height: 33))
    let alert = try #require(probe.prompts.first { $0.defaultPresentation.minimumWidth == 24 })
    let confirmation = try #require(
      probe.prompts.first { $0.defaultPresentation.minimumWidth == 20 })
    #expect(alert.hasMessage)
    #expect(!alert.hasActions)
    #expect(!confirmation.hasMessage)
    #expect(confirmation.hasActions)
    #expect(alert.defaultPresentation.maximumWidth == 48)
    #expect(confirmation.defaultPresentation.maximumWidth == nil)
    #expect(alert.defaultPresentation.headerTone == .neutral)
    #expect(confirmation.defaultPresentation.headerTone == .accent)
    #expect(alert.terminalSize == .init(width: 79, height: 33))
    #expect(confirmation.terminalSize == alert.terminalSize)
  }

  @Test(
    "a styled cover applies insets and paint while filling the host independently of SheetStyle")
  func coverInsetsAndPaint() {
    let probe = PortalConfigurationProbe()
    let frame = DefaultRenderer().render(
      Text("Base").fullScreenCover(isPresented: .constant(true)) { Text("Cover") }
        .fullScreenCoverStyle(ConsumerFullScreenCoverStyle(inset: 3))
        .sheetStyle(InspectUnusedSheetStyle(probe: probe)),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 40, height: 16))
    #expect(probe.sheetCalls == 0)
    #expect(frame.rasterSurface.size == .init(width: 40, height: 16))
    #expect(frame.rasterSurface.lines[3].hasPrefix("   Cover"))
    #expect(frame.rasterSurface.cells[0][0].style?.backgroundColor == Color.blue)
    #expect(frame.rasterSurface.cells[15][39].style?.backgroundColor == Color.blue)
    #expect(!frame.rasterSurface.lines.joined().contains("×"))
  }
}

@MainActor
private final class PortalConfigurationProbe {
  var prompts: [PromptStyleConfiguration] = []
  var sheetCalls = 0
}

private struct InspectPromptStyle: PromptStyle {
  let probe: PortalConfigurationProbe
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    probe.prompts.append(configuration)
    return configuration.defaultPresentation
  }
}

private struct InspectUnusedSheetStyle: SheetStyle {
  let probe: PortalConfigurationProbe
  func resolvePresentation(for configuration: SheetStyleConfiguration)
    -> SheetSurfaceStylePresentation
  {
    probe.sheetCalls += 1
    return configuration.defaultPresentation
  }
}
