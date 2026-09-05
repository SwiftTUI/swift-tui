import SwiftTUIViews

struct ConsumerLinkStyle: LinkStyle, Equatable {
  var underline: LinkUnderlineStyle = .inherited
  var foreground: AnyShapeStyle? = nil
  var opacity: Double? = nil
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    .init(foregroundStyle: foreground, emphasis: .italic, underline: underline, opacity: opacity)
  }
}

struct ConsumerScrollViewStyle: ScrollViewStyle, Equatable {
  var insets = EdgeInsets(all: 1)
  var reservesSpace = false
  var verticalGlyph = "|"
  var horizontalGlyph = "-"
  func resolvePresentation(for configuration: ScrollViewStyleConfiguration)
    -> ScrollViewStylePresentation
  {
    .init(
      snapshotLabel: "consumer", contentInsets: insets,
      verticalIndicatorGlyph: verticalGlyph, horizontalIndicatorGlyph: horizontalGlyph,
      indicatorStyle: .color(.red), focusedIndicatorStyle: .color(.green),
      backgroundStyle: .color(.blue), opacity: 0.75, reservesIndicatorSpace: reservesSpace)
  }
}

@MainActor
func consumerScrollLinkModifiers() -> some View {
  VStack {
    Link("Docs", destination: "https://example.com").linkStyle(ConsumerLinkStyle())
    Text("See \(Link("Docs", destination: "https://example.com"))").linkStyle(AnyLinkStyle.plain)
    ScrollView { Text("Content") }.scrollViewStyle(ConsumerScrollViewStyle())
    ScrollView { Text("Content") }.scrollViewStyle(AnyScrollViewStyle.minimal)
    Link("Plain", destination: "https://example.com").linkStyle(.plain)
    Link("Underlined", destination: "https://example.com").linkStyle(.underlined)
    ScrollView { Text("Automatic") }.scrollViewStyle(.automatic)
  }
  .linkStyle(.automatic)
  .scrollViewStyle(.minimal)
}
