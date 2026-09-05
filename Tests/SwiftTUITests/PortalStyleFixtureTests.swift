@_spi(StyleFixtures) import SwiftTUIViews
import Testing

@MainActor
struct PortalStyleFixtureTests {
  @Test("automatic presentation styles preserve arbitrary modifier baselines")
  func automaticBaselines() {
    let prompt = PromptSurfaceStylePresentation(
      backdropOpacity: 0.4, headerTone: .accent, minimumWidth: 18, maximumWidth: 42,
      scrollMinimumHeight: 1, scrollIdealHeight: 3, scrollMaximumHeight: 7,
      contentInsets: .init(horizontal: 3, vertical: 2), backgroundStyle: AnyShapeStyle(.red),
      borderStroke: .single, borderStyle: AnyShapeStyle(.green))
    let promptConfiguration = PromptStyleConfiguration(
      hasMessage: true, hasActions: false, defaultPresentation: prompt,
      terminalSize: .init(width: 100, height: 30), controlProminence: .standard,
      styleEnvironment: .init())
    #expect(AutomaticPromptStyle().resolvePresentation(for: promptConfiguration) == prompt)
    #expect(promptConfiguration.hasMessage)
    #expect(!promptConfiguration.hasActions)

    let cover = FullScreenSurfaceStylePresentation(
      contentInsets: .init(horizontal: 4, vertical: 3), backgroundStyle: AnyShapeStyle(.red))
    let coverConfiguration = FullScreenCoverStyleConfiguration(
      defaultPresentation: cover, terminalSize: .init(width: 100, height: 30),
      controlProminence: .standard, styleEnvironment: .init())
    #expect(AutomaticFullScreenCoverStyle().resolvePresentation(for: coverConfiguration) == cover)

    let popover = AnchoredSurfaceStylePresentation(
      contentInsets: .init(horizontal: 3, vertical: 2), minimumWidth: 10, maximumWidth: 40,
      maximumHeight: 7, backgroundStyle: AnyShapeStyle(.red), borderStroke: .single,
      borderStyle: AnyShapeStyle(.green))
    let popoverConfiguration = PopoverStyleConfiguration(
      defaultPresentation: popover, terminalSize: .init(width: 100, height: 30),
      controlProminence: .standard, styleEnvironment: .init())
    #expect(AutomaticPopoverStyle().resolvePresentation(for: popoverConfiguration) == popover)

    _ = Text("fixture").promptStyle(.automatic)
      .fullScreenCoverStyle(.automatic).popoverStyle(.automatic)
    _ = Text("fixture").promptStyle(AnyPromptStyle.automatic)
      .fullScreenCoverStyle(AnyFullScreenCoverStyle.automatic).popoverStyle(
        AnyPopoverStyle.automatic)
  }
}
