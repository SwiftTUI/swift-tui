import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct ViewModifierAlgebraTests {
  @Test("custom ViewModifier bodies lower through ModifiedContent")
  func customModifierBodyLowersThroughModifiedContent() {
    let resolved = Resolver().resolve(
      Text("Hello").modifier(PaddingThenOffsetModifier()),
      in: .init(identity: testIdentity("ViewModifier", "Body"))
    )

    #expect(resolved.kind == .view("Offset"))
    #expect(resolved.children.count == 1)
    #expect(resolved.children[0].kind == .view("Padding"))
  }

  @Test("ViewModifier.concat composes modifier values in order")
  func concatComposesModifiersInOrder() {
    let combined = PaddingModifierBody().concat(OffsetModifierBody())
    let resolved = Resolver().resolve(
      Text("Hello").modifier(combined),
      in: .init(identity: testIdentity("ViewModifier", "Concat"))
    )

    #expect(resolved.kind == .view("Offset"))
    #expect(resolved.children.count == 1)
    #expect(resolved.children[0].kind == .view("Padding"))
  }

  @Test("id rewrites identity through modifier application")
  func idRewritesIdentityThroughModifierApplication() {
    let explicitIdentity = testIdentity("ViewModifier", "ExplicitID")
    let resolved = Resolver().resolve(
      Text("Hello")
        .padding(1)
        .id(explicitIdentity),
      in: .init(identity: testIdentity("ViewModifier", "IDRoot"))
    )

    #expect(resolved.identity == explicitIdentity)
    #expect(resolved.kind == .view("Padding"))
  }

  @Test("tab metadata peeking walks ModifiedContent chains")
  func tabMetadataPeekingWalksModifiedContentChains() {
    let child =
      Text("Body")
      .semanticMetadata(.init(tabItemLabel: .init("Label")))
      .tag(42)

    let metadata = peekTabChildMetadata(from: child)

    #expect(metadata.label == TabItemLabel("Label"))
    #expect(metadata.tag == SelectionTag(value: 42))
  }
}

@MainActor
private struct PaddingThenOffsetModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(1)
      .offset(x: 2, y: 0)
  }
}

@MainActor
private struct PaddingModifierBody: ViewModifier {
  func body(content: Content) -> some View {
    content.padding(1)
  }
}

@MainActor
private struct OffsetModifierBody: ViewModifier {
  func body(content: Content) -> some View {
    content.offset(x: 2, y: 0)
  }
}
