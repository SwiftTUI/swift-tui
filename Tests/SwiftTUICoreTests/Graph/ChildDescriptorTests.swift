import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct ChildDescriptorTests {
  private struct TestViewA {}
  private struct TestViewB {}

  @Test("descriptors with matching fields and no discriminators are equal")
  func legacyMatchingDescriptorsAreEqual() {
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Text"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Text"
    )

    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  @Test("descriptors with same type discriminator are equal")
  func sameTypeDiscriminatorIsEqual() {
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:TestViewA",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:TestViewA",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )

    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  @Test("same name but different type discriminators are unequal")
  func differentTypeDiscriminatorsAreUnequal() {
    // The core value of Item 4: two views that accidentally share a kind
    // name must be distinguishable by their real Swift type.  Without a
    // discriminator the greedy-or-LCS diff would reuse one in place of the
    // other, silently preserving stale state.
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Collision",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Collision",
      typeDiscriminator: ObjectIdentifier(TestViewB.self)
    )

    #expect(lhs != rhs)
  }

  @Test("legacy nil discriminator matches typed discriminator with same name")
  func legacyAndTypedDescriptorsBridgeDuringMigration() {
    // During incremental migration, some call sites will populate the
    // discriminator and others won't.  The fallback is: if either side is
    // nil, compare by typeIdentity String.  This keeps in-progress
    // migrations from producing spurious inequality churn.
    let legacy = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:TestViewA"
    )
    let typed = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:TestViewA",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )

    #expect(legacy == typed)
    #expect(typed == legacy)
    // Hash must also match for Set/Dictionary membership to work.
    #expect(legacy.hashValue == typed.hashValue)
  }

  @Test("legacy nil discriminator does not match typed descriptor with different name")
  func legacyAndTypedDescriptorsDoNotBridgeAcrossNames() {
    // Bridging only applies when the String names agree.  Different names
    // mean different identities regardless of discriminator state.
    let legacy = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Alpha"
    )
    let typed = ChildDescriptor(
      identity: testIdentity("Root", "Child"),
      typeIdentity: "view:Beta",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )

    #expect(legacy != typed)
  }

  @Test("different identity never matches regardless of discriminator")
  func differentStructuralPathNeverMatchesWithoutEntity() {
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "ChildA"),
      structuralPath: StructuralPath(components: [
        .init(rawValue: "Root"),
        .init(rawValue: "ChildA"),
      ]),
      typeIdentity: "view:TestViewA",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "ChildB"),
      structuralPath: StructuralPath(components: [
        .init(rawValue: "Root"),
        .init(rawValue: "ChildB"),
      ]),
      typeIdentity: "view:TestViewA",
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )

    #expect(lhs != rhs)
  }

  @Test("same runtime identity in different structural slots does not match")
  func structuralPathDistinguishesRuntimeIdentityCollisions() {
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[dup]"),
      structuralPath: StructuralPath(components: [
        .init(rawValue: "Root"),
        .init(rawValue: "ForEachElement[0]"),
      ]),
      typeIdentity: "view:Row"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[dup]"),
      structuralPath: StructuralPath(components: [
        .init(rawValue: "Root"),
        .init(rawValue: "ForEachElement[1]"),
      ]),
      typeIdentity: "view:Row"
    )

    #expect(lhs != rhs)
  }

  @Test("entity identity matches across positional shifts within the same sibling scope")
  func entityIdentityMatchesAcrossPositionalShifts() {
    let entity = EntityIdentity("row-a")
    let oldEntityPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "ForEachElement[0]"),
    ])
    let newEntityPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "ForEachElement[2]"),
    ])
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"row-a\"]"),
      structuralPath: oldEntityPath,
      entityIdentity: entity,
      entityStructuralPath: oldEntityPath,
      typeIdentity: "view:Row"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"row-a\"]"),
      structuralPath: newEntityPath,
      entityIdentity: entity,
      entityStructuralPath: newEntityPath,
      typeIdentity: "view:Row"
    )

    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  @Test("entity-scoped descendants keep their relative structural suffix")
  func entityScopedDescendantsKeepRelativeStructuralSuffix() {
    let entity = EntityIdentity("row-a")
    let oldEntityPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "ForEachElement[0]"),
    ])
    let newEntityPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "ForEachElement[2]"),
    ])
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"row-a\"]", "TupleView[0]"),
      structuralPath: oldEntityPath.appending(.init(rawValue: "TupleView[0]")),
      entityIdentity: entity,
      entityStructuralPath: oldEntityPath,
      typeIdentity: "view:Text"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"row-a\"]", "TupleView[1]"),
      structuralPath: newEntityPath.appending(.init(rawValue: "TupleView[1]")),
      entityIdentity: entity,
      entityStructuralPath: newEntityPath,
      typeIdentity: "view:Text"
    )

    #expect(lhs != rhs)
  }

  @Test("duplicate entity occurrence disambiguates equal user ids")
  func duplicateEntityOccurrenceDisambiguatesEqualUserIDs() {
    let entityPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "ForEachElement[0]"),
    ])
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"dup\"]"),
      structuralPath: entityPath,
      entityIdentity: EntityIdentity("dup", occurrence: 0),
      entityStructuralPath: entityPath,
      typeIdentity: "view:Row"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "ID[\"dup\"]"),
      structuralPath: entityPath,
      entityIdentity: EntityIdentity("dup", occurrence: 1),
      entityStructuralPath: entityPath,
      typeIdentity: "view:Row"
    )

    #expect(lhs != rhs)
  }

  @Test("runtime identity rewrite keeps the same positional descriptor")
  func structuralPathIsThePositionalDescriptor() {
    let structuralPath = StructuralPath(components: [
      .init(rawValue: "Root"),
      .init(rawValue: "VStack[0]"),
    ])
    let lhs = ChildDescriptor(
      identity: testIdentity("Root", "Before"),
      structuralPath: structuralPath,
      typeIdentity: "view:Text"
    )
    let rhs = ChildDescriptor(
      identity: testIdentity("Root", "After"),
      structuralPath: structuralPath,
      typeIdentity: "view:Text"
    )

    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  @Test("descriptor built from ResolvedNode picks up the node's type discriminator")
  func resolvedNodeInitPropagatesDiscriminator() {
    var resolved = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .view("TestViewA"),
      typeDiscriminator: ObjectIdentifier(TestViewA.self)
    )
    resolved.attachingEntityIdentity(
      EntityIdentity("entity"),
      at: resolved.structuralPath
    )

    let descriptor = ChildDescriptor(resolvedNode: resolved)

    #expect(descriptor.typeDiscriminator == ObjectIdentifier(TestViewA.self))
    #expect(descriptor.typeIdentity == "view:TestViewA")
    #expect(descriptor.entityIdentity == EntityIdentity("entity"))
    #expect(descriptor.entityStructuralPath == resolved.structuralPath)
  }
}
