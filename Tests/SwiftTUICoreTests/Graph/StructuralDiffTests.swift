import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct StructuralDiffTests {
  @Test("reorder emits a move operation and no removals or insertions")
  func reorderEmitsMove() {
    let a = keyedRow(id: 0, slot: 0)
    let b = keyedRow(id: 1, slot: 1)
    let movedA = keyedRow(id: 0, slot: 1)
    let movedB = keyedRow(id: 1, slot: 0)

    let operations = diffChildren(old: [a, b], new: [movedB, movedA])

    let moves = operations.compactMap { operation -> (Int, Int)? in
      guard case .moved(let oldIndex, let newIndex) = operation else { return nil }
      return (oldIndex, newIndex)
    }
    let matches = operations.compactMap { operation -> (Int, Int)? in
      guard case .matched(let oldIndex, let newIndex) = operation else { return nil }
      return (oldIndex, newIndex)
    }

    // Exactly one element moves; the other is matched in place at its new
    // index.  Myers is free to pick either element as the one that moved,
    // so we only assert the structural properties, not the specific pair.
    #expect(moves.count == 1)
    #expect(matches.count == 1)
    #expect(!operations.contains { if case .removed = $0 { return true } else { return false } })
    #expect(!operations.contains { if case .inserted = $0 { return true } else { return false } })

    // Whichever element moved, the move must pair an old index with a
    // different new index (i.e. it's actually a move, not a no-op).
    let move = moves[0]
    #expect(move.0 != move.1)
  }

  @Test("insertion and removal are emitted for unmatched descriptors")
  func insertionsAndRemovalsAreEmitted() {
    let old: [ChildDescriptor] = [
      keyedRow(id: 0, slot: 0),
      keyedRow(id: 1, slot: 1),
    ]
    let new: [ChildDescriptor] = [
      keyedRow(id: 1, slot: 0),
      keyedRow(id: 2, slot: 1),
    ]

    let operations = diffChildren(old: old, new: new)

    // B survives (old index 1, new index 0), A is removed, C is inserted.
    // The exact emission order depends on the stdlib; assert set membership
    // rather than list equality.
    #expect(operations.contains(.matched(oldIndex: 1, newIndex: 0)))
    #expect(operations.contains(.removed(oldIndex: 0)))
    #expect(operations.contains(.inserted(newIndex: 1)))
    #expect(operations.count == 3)
  }

  @Test("pure insertion emits only inserted operations")
  func pureInsertionEmitsOnlyInserts() {
    let old: [ChildDescriptor] = []
    let new: [ChildDescriptor] = [
      keyedRow(id: 0, slot: 0),
      keyedRow(id: 1, slot: 1),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(operations.contains(.inserted(newIndex: 0)))
    #expect(operations.contains(.inserted(newIndex: 1)))
    #expect(operations.count == 2)
  }

  @Test("pure removal emits only removed operations")
  func pureRemovalEmitsOnlyRemovals() {
    let old: [ChildDescriptor] = [
      keyedRow(id: 0, slot: 0),
      keyedRow(id: 1, slot: 1),
    ]
    let new: [ChildDescriptor] = []

    let operations = diffChildren(old: old, new: new)

    #expect(operations.contains(.removed(oldIndex: 0)))
    #expect(operations.contains(.removed(oldIndex: 1)))
    #expect(operations.count == 2)
  }

  @Test("stable ordering emits only matched operations")
  func stableOrderingEmitsOnlyMatches() {
    let descriptors: [ChildDescriptor] = [
      keyedRow(id: 0, slot: 0),
      keyedRow(id: 1, slot: 1),
      keyedRow(id: 2, slot: 2),
    ]

    let operations = diffChildren(old: descriptors, new: descriptors)

    #expect(
      operations == [
        .matched(oldIndex: 0, newIndex: 0),
        .matched(oldIndex: 1, newIndex: 1),
        .matched(oldIndex: 2, newIndex: 2),
      ]
    )
  }

  @Test("static unkeyed insertion shifts sibling identity")
  func staticUnkeyedInsertionShiftsSiblingIdentity() {
    let old: [ChildDescriptor] = [
      unkeyed(type: "view:Row", slot: 0),
      unkeyed(type: "view:Row", slot: 1),
    ]
    let new: [ChildDescriptor] = [
      unkeyed(type: "view:Inserted", slot: 0),
      unkeyed(type: "view:Row", slot: 1),
      unkeyed(type: "view:Row", slot: 2),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(operations.contains(.removed(oldIndex: 0)))
    #expect(operations.contains(.inserted(newIndex: 0)))
    #expect(operations.contains(.inserted(newIndex: 2)))
  }

  @Test("keyed insertion preserves shifted siblings")
  func keyedInsertionPreservesShiftedSiblings() {
    let old: [ChildDescriptor] = [
      keyedRow(id: 0, slot: 0),
      keyedRow(id: 1, slot: 1),
    ]
    let new: [ChildDescriptor] = [
      keyedRow(id: 2, slot: 0),
      keyedRow(id: 0, slot: 1),
      keyedRow(id: 1, slot: 2),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(operations.contains(.inserted(newIndex: 0)))
    #expect(operations.contains(.matched(oldIndex: 0, newIndex: 1)))
    #expect(operations.contains(.matched(oldIndex: 1, newIndex: 2)))
    #expect(!operations.contains { if case .removed = $0 { return true } else { return false } })
  }

  @Test("duplicate keyed ids remain deterministic with occurrence ordinals")
  func duplicateKeyedIDsUseOccurrenceOrdinals() {
    let old: [ChildDescriptor] = [
      keyedRow(id: "dup", occurrence: 0, slot: 0),
      keyedRow(id: "dup", occurrence: 1, slot: 1),
    ]
    let new: [ChildDescriptor] = [
      keyedRow(id: "dup", occurrence: 1, slot: 0),
      keyedRow(id: "dup", occurrence: 0, slot: 1),
    ]

    let operations = diffChildren(old: old, new: new)
    let removals = operations.filter {
      if case .removed = $0 { return true }
      return false
    }
    let insertions = operations.filter {
      if case .inserted = $0 { return true }
      return false
    }

    #expect(removals.isEmpty)
    #expect(insertions.isEmpty)
    #expect(operations.count == 2)
  }
}

private func keyedRow<ID: Hashable & Sendable>(
  id: ID,
  occurrence: Int = 0,
  slot: Int
) -> ChildDescriptor {
  let structuralPath = structuralSlot(slot)
  return ChildDescriptor(
    identity: testIdentity("Root", "ID[\(String(reflecting: id))]"),
    structuralPath: structuralPath,
    entityIdentity: EntityIdentity(id, occurrence: occurrence),
    entityStructuralPath: structuralPath,
    typeIdentity: "view:Row"
  )
}

private func unkeyed(
  type: String,
  slot: Int
) -> ChildDescriptor {
  ChildDescriptor(
    identity: testIdentity("Root", "Child[\(slot)]"),
    structuralPath: structuralSlot(slot),
    typeIdentity: type
  )
}

private func structuralSlot(_ slot: Int) -> StructuralPath {
  StructuralPath(components: [
    .init(rawValue: "Root"),
    .init(rawValue: "ForEachElement[\(slot)]"),
  ])
}
