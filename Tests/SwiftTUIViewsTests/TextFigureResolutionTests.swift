import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextFigureResolutionTests {
  @Test("TextFigure resolves as a single leaf node")
  func textFigureResolvesAsSingleLeafNode() throws {
    let wrapper = Resolver().resolve(
      AnyView(TextFigure("Hi")),
      in: .init(identity: testIdentity("Root"))
    )
    let resolved = try #require(wrapper.anyViewPayloadContent)

    #expect(resolved.kind == .view("TextFigure"))
    #expect(resolved.children.isEmpty)

    guard case .textFigure(let payload) = resolved.drawPayload else {
      Issue.record("Expected TextFigure draw payload")
      return
    }

    #expect(payload.content == "Hi")
    #expect(payload.font.rawValue == "standard")
  }

  @Test("TextFigure exposes embedded font names")
  func textFigureExposesEmbeddedFontNames() {
    let fonts = TextFigure.availableFonts
    let fontNames = Set(fonts.map(\.rawValue))

    #expect(fontNames.contains("standard"))
    #expect(fontNames.contains("slant"))
    #expect(fontNames.contains("ansi-shadow"))
  }
}

extension ResolvedNode {
  fileprivate var anyViewPayloadContent: ResolvedNode? {
    guard kind == .view("AnyView"),
      children.count == 1,
      children[0].kind == .view("AnyViewPayload"),
      children[0].children.count == 1
    else {
      return nil
    }
    return children[0].children[0]
  }
}
