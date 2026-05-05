import Testing

@testable import SwiftTUIViews

@Suite
struct ErasedViewTypeIDTests {
  @Test("same static type produces equal erased view type IDs")
  func sameStaticTypeProducesEqualIDs() {
    let first = ErasedViewTypeID(Text.self)
    let second = ErasedViewTypeID(Text.self)

    #expect(first == second)
    #expect(first.identityComponent == second.identityComponent)
    #expect(first.typeDiscriminator == second.typeDiscriminator)
  }

  @Test("different static types produce different identity components")
  func differentStaticTypesProduceDifferentIdentityComponents() {
    let textID = ErasedViewTypeID(Text.self)
    let stackID = ErasedViewTypeID(VStack<TupleView<Text, Text>>.self)

    #expect(textID.identityComponent != stackID.identityComponent)
  }

  @Test("different static types produce different type discriminators")
  func differentStaticTypesProduceDifferentTypeDiscriminators() {
    let textID = ErasedViewTypeID(Text.self)
    let stackID = ErasedViewTypeID(VStack<TupleView<Text, Text>>.self)

    #expect(textID.typeDiscriminator != stackID.typeDiscriminator)
  }

  @Test("display name is deterministic enough for readable failures")
  func displayNameIsReadableAndDeterministic() {
    let textID = ErasedViewTypeID(Text.self)

    #expect(textID.displayName == String(reflecting: Text.self))
    #expect(textID.description == textID.displayName)
    #expect(textID.displayName.contains("Text"))
  }
}
