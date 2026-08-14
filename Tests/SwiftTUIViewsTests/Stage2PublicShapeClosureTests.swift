import Testing

@testable import SwiftTUIViews

/// Positive compile fixtures for the Stage 2 preview-cut surface. The removed
/// custom-transition declarations are pinned negatively by
/// `docs/public_api_overrides.yml` and the generated symbol baseline; these
/// fixtures prove their supported replacements remain usable.
@MainActor
@Suite("Stage 2 public-shape closure")
struct Stage2PublicShapeClosureTests {
  @Test("built-in AnyTransition effects still compose")
  func builtInTransitionsStillCompose() {
    let combined = AnyTransition.opacity.combined(with: .offset(x: 3, y: -2))
    let insertion = combined.insertionModifiers()
    let removal = combined.removalModifiers()

    #expect(insertion.opacity == 0)
    #expect(insertion.offsetX == 3)
    #expect(insertion.offsetY == -2)
    #expect(removal == insertion)

    let asymmetric = AnyTransition.asymmetric(
      insertion: .move(edge: .leading),
      removal: .move(edge: .trailing)
    )
    #expect(asymmetric.insertionModifiers().moveEdge == .leading)
    #expect(asymmetric.removalModifiers().moveEdge == .trailing)
  }

  @Test("Text string and verbatim initializers are literal aliases")
  func textInitializersAreLiteralAliases() {
    let keyLikeStrings = [
      "settings.account.title",
      "%@ completed %lld items",
      "welcome/{user}/message",
      "مرحبا بالعالم",
    ]

    for value in keyLikeStrings {
      #expect(Text(value).content == value)
      #expect(Text(verbatim: value).content == value)
      #expect(Text(value).content == Text(verbatim: value).content)
    }
  }

  @Test("border supports both the inset default and explicit outset migration path")
  func borderPlacementsCompile() {
    _ = Text("inset").border()
    _ = Text("outset").border(placement: .outset)
    _ = Text("styled").border(
      BorderEdgeStyle(Color.red),
      placement: .outset
    )
    _ = Text("blend").border(
      blend: BorderBlend([Color.red, Color.blue]),
      placement: .outset
    )
  }
}
