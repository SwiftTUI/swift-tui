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

extension PortalStyleValueTests {
  @Test("one oversized inset is rejected and a presented surface falls back without trapping")
  func oversizedInsets() {
    var oversized = AnchoredSurfaceStylePresentation()
    oversized.contentInsets.leading = Int.max - 1
    #expect(!oversized.validationProblems.isEmpty)
    #expect(!AnchoredSurfaceStylePresentation(minimumWidth: Int.max).validationProblems.isEmpty)
    // Larger than any terminal is still a representable count, not misuse.
    #expect(AnchoredSurfaceStylePresentation(contentInsets: .init(all: 200)).validationProblems.isEmpty)
    let frame = DefaultRenderer().render(
      Text("Base").popover(isPresented: .constant(true)) { Text("Body") }
        .popoverStyle(OversizedInsetPopoverStyle()),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 40, height: 16))
    #expect(
      frame.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }.count == 1)
    #expect(frame.rasterSurface.lines.joined().contains("Body"))
  }
}

extension PortalStyleValueTests {
  @Test("an unrepresentable sheet scroll height is rejected and the presented sheet falls back")
  func unrepresentableSheetScrollHeight() {
    #expect(!SheetSurfaceStylePresentation(scrollMaximumHeight: Int.max).validationProblems.isEmpty)
    // Taller than any terminal is still a representable count, not misuse.
    #expect(SheetSurfaceStylePresentation(scrollMaximumHeight: 500).validationProblems.isEmpty)
    let baseline = presentedSheet(UnrepresentableScrollHeightSheetStyle(invalid: false))
    let frame = presentedSheet(UnrepresentableScrollHeightSheetStyle(invalid: true))
    #expect(
      frame.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }.count == 1)
    #expect(frame.rasterSurface == baseline.rasterSurface)
    #expect(frame.rasterSurface.lines.joined().contains("Body"))
  }

  @Test("an unrepresentable prompt width is rejected and the presented alert falls back")
  func unrepresentablePromptWidth() {
    #expect(!PromptSurfaceStylePresentation(maximumWidth: Int.max).validationProblems.isEmpty)
    #expect(PromptSurfaceStylePresentation(maximumWidth: 500).validationProblems.isEmpty)
    let baseline = presentedAlert(UnrepresentableWidthPromptStyle(invalid: false))
    let frame = presentedAlert(UnrepresentableWidthPromptStyle(invalid: true))
    #expect(
      frame.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }.count == 1)
    #expect(frame.rasterSurface == baseline.rasterSurface)
    #expect(frame.rasterSurface.lines.joined().contains("Title"))
  }

  private func presentedSheet(_ style: some SheetStyle) -> RenderSnapshot {
    DefaultRenderer().render(
      Text("Base").sheet("Title", isPresented: .constant(true)) { Text("Body") }
        .sheetStyle(style),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 50, height: 20))
  }

  private func presentedAlert(_ style: some PromptStyle) -> RenderSnapshot {
    DefaultRenderer().render(
      Text("Base").alert("Title", isPresented: .constant(true)).promptStyle(style),
      context: .init(identity: testIdentity("Root")), proposal: .init(width: 50, height: 20))
  }
}

private struct UnrepresentableScrollHeightSheetStyle: SheetStyle {
  let invalid: Bool
  var snapshotLabel: String { "UnrepresentableScrollHeightSheetStyle" }
  func resolvePresentation(for configuration: SheetStyleConfiguration)
    -> SheetSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.scrollMaximumHeight = Int.max }
    return presentation
  }
}

private struct UnrepresentableWidthPromptStyle: PromptStyle {
  let invalid: Bool
  var snapshotLabel: String { "UnrepresentableWidthPromptStyle" }
  func resolvePresentation(for configuration: PromptStyleConfiguration)
    -> PromptSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    if invalid { presentation.maximumWidth = Int.max }
    return presentation
  }
}

private struct OversizedInsetPopoverStyle: PopoverStyle {
  func resolvePresentation(for configuration: PopoverStyleConfiguration)
    -> AnchoredSurfaceStylePresentation
  {
    var presentation = configuration.defaultPresentation
    presentation.contentInsets.leading = Int.max - 1
    return presentation
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
