import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct TextFigureResolutionTests {
  @Test("TextFigure resolves as a single leaf node")
  func textFigureResolvesAsSingleLeafNode() {
    let resolved = Resolver().resolve(
      AnyView(TextFigure("Hi")),
      in: .init(identity: testIdentity("Root"))
    )

    #expect(resolved.kind == .view("TextFigure"))
    #expect(resolved.children.isEmpty)

    guard case .textFigure(let payload) = resolved.drawPayload else {
      Issue.record("Expected TextFigure draw payload")
      return
    }

    #expect(payload == .init(content: "Hi", font: "standard"))
  }

  @Test("TextFigure exposes embedded font names")
  func textFigureExposesEmbeddedFontNames() {
    let fonts = TextFigure.availableFonts

    #expect(fonts.contains("standard"))
    #expect(fonts.contains("slant"))
    #expect(fonts.contains("banner"))
  }
}
