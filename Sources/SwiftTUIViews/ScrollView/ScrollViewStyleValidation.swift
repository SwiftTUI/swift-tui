import SwiftTUICore

@MainActor
func validatedScrollPresentation(
  _ proposed: ScrollViewStylePresentation,
  configuration: ScrollViewStyleConfiguration,
  styleLabel: String,
  identity: Identity
) -> ScrollViewStylePresentation {
  var result = proposed
  var problems: [String] = []
  // Each invalid field falls back on its own; the automatic presentation is
  // resolved only once a field needs it.
  var automaticPresentation: ScrollViewStylePresentation?
  var automatic: ScrollViewStylePresentation {
    if let automaticPresentation { return automaticPresentation }
    let resolved = AutomaticScrollViewStyle().resolvePresentation(for: configuration)
    automaticPresentation = resolved
    return resolved
  }
  func isCell(_ glyph: String) -> Bool {
    glyph.count == 1 && glyph.first.map { cellWidth(of: $0) == 1 } == true
      && glyph.unicodeScalars.allSatisfy {
        let category = $0.properties.generalCategory
        return category != .control && category != .lineSeparator && category != .paragraphSeparator
      }
  }
  if !isCell(result.verticalIndicatorGlyph) {
    problems.append("vertical indicator must be one terminal cell")
    result.verticalIndicatorGlyph = automatic.verticalIndicatorGlyph
  }
  if !isCell(result.horizontalIndicatorGlyph) {
    problems.append("horizontal indicator must be one terminal cell")
    result.horizontalIndicatorGlyph = automatic.horizontalIndicatorGlyph
  }
  let insets = result.contentInsets
  if [insets.top, insets.leading, insets.bottom, insets.trailing].contains(where: {
    $0 < 0 || $0 > Int.max / 4
  }) {
    problems.append("content insets must be nonnegative representable cell counts")
    result.contentInsets = automatic.contentInsets
  }
  if !result.opacity.isFinite || !(0...1).contains(result.opacity) {
    problems.append("opacity must be finite and between zero and one")
    result.opacity = automatic.opacity
  }
  if !problems.isEmpty {
    ImperativeRuntimeIssueQueue.record(
      StyleMisuse.partiallyInvalidPresentationIssue(
        family: "ScrollViewStyle", styleLabel: styleLabel, problems: problems,
        identity: identity))
  }
  return result
}
