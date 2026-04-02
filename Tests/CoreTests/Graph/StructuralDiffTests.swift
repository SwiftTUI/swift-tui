import Testing

@testable import Core

@Suite
struct StructuralDiffTests {
  @Test("reorder with stable descriptors matches without inserts or removals")
  func reorderMatchesStableDescriptors() {
    let old: [ChildDescriptor] = [
      .init(typeIdentity: "view:Row", explicitID: "ID[0]"),
      .init(typeIdentity: "view:Row", explicitID: "ID[1]"),
    ]
    let new: [ChildDescriptor] = [
      .init(typeIdentity: "view:Row", explicitID: "ID[1]"),
      .init(typeIdentity: "view:Row", explicitID: "ID[0]"),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(
      operations == [
        .matched(oldIndex: 1, newIndex: 0),
        .matched(oldIndex: 0, newIndex: 1),
      ]
    )
  }

  @Test("insertions and removals are emitted for unmatched descriptors")
  func insertionsAndRemovalsAreEmitted() {
    let old: [ChildDescriptor] = [
      .init(typeIdentity: "view:Row", explicitID: "ID[0]"),
      .init(typeIdentity: "view:Row", explicitID: "ID[1]"),
    ]
    let new: [ChildDescriptor] = [
      .init(typeIdentity: "view:Row", explicitID: "ID[1]"),
      .init(typeIdentity: "view:Row", explicitID: "ID[2]"),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(
      operations == [
        .matched(oldIndex: 1, newIndex: 0),
        .inserted(newIndex: 1),
        .removed(oldIndex: 0),
      ]
    )
  }
}
