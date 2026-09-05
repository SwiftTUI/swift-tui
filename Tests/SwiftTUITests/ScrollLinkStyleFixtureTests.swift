@_spi(StyleFixtures) import SwiftTUIViews
import Testing

@MainActor
struct ScrollLinkStyleFixtureTests {
  @Test("scroll fixtures expose automatic and minimal treatments without live state")
  func scrollBuiltIns() {
    let configuration = ScrollViewStyleConfiguration(
      axes: [.horizontal, .vertical], visibleIndicatorAxes: .vertical,
      focusedIndicatorAxes: [], allowsDirectManipulation: false, isEnabled: true,
      styleEnvironment: .init())
    let automatic = AutomaticScrollViewStyle().resolvePresentation(for: configuration)
    let minimal = MinimalScrollViewStyle().resolvePresentation(for: configuration)
    #expect(automatic.contentInsets == .zero)
    #expect(automatic.verticalIndicatorGlyph == "▐")
    #expect(automatic.horizontalIndicatorGlyph == "▂")
    #expect(automatic.reservesIndicatorSpace)
    #expect(!minimal.reservesIndicatorSpace)
    #expect(minimal.indicatorStyle == .semantic(.muted))
    #expect(minimal.backgroundStyle == nil)
    #expect(automatic.snapshotLabel != minimal.snapshotLabel)
  }

  @Test("link fixtures distinguish underline policy and retain focused backgrounds")
  func linkBuiltIns() {
    let configuration = LinkStyleConfiguration(
      isInline: true, isEnabled: true, isFocused: true, showsFocusEffect: true,
      isPressed: false, styleEnvironment: .init())
    let automatic = AutomaticLinkStyle().resolvePresentation(for: configuration)
    let underlined = UnderlinedLinkStyle().resolvePresentation(for: configuration)
    let plain = PlainLinkStyle().resolvePresentation(for: configuration)
    #expect(configuration.focusActive)
    #expect(automatic.underline == .visible(.init(pattern: .solid)))
    #expect(underlined.foregroundStyle == configuration.styleEnvironment.themeStyle(for: .link))
    #expect(underlined.underline == .visible(.init(pattern: .solid)))
    #expect(plain.foregroundStyle == nil)
    #expect(plain.underline == .hidden)
    #expect(plain.backgroundStyle == automatic.backgroundStyle)
    #expect(plain.backgroundStyle != nil)
  }
}
