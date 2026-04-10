import Testing

@testable import Core

@Suite
struct StructuralDiffTests {
  @Test("reorder emits a move operation and no removals or insertions")
  func reorderEmitsMove() {
    let a = ChildDescriptor(
      identity: testIdentity("Root", "ID[0]"),
      typeIdentity: "view:Row",
      explicitID: "ID[0]"
    )
    let b = ChildDescriptor(
      identity: testIdentity("Root", "ID[1]"),
      typeIdentity: "view:Row",
      explicitID: "ID[1]"
    )

    let operations = diffChildren(old: [a, b], new: [b, a])

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
      .init(
        identity: testIdentity("Root", "ID[0]"),
        typeIdentity: "view:Row",
        explicitID: "ID[0]"
      ),
      .init(
        identity: testIdentity("Root", "ID[1]"),
        typeIdentity: "view:Row",
        explicitID: "ID[1]"
      ),
    ]
    let new: [ChildDescriptor] = [
      .init(
        identity: testIdentity("Root", "ID[1]"),
        typeIdentity: "view:Row",
        explicitID: "ID[1]"
      ),
      .init(
        identity: testIdentity("Root", "ID[2]"),
        typeIdentity: "view:Row",
        explicitID: "ID[2]"
      ),
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
      .init(
        identity: testIdentity("Root", "ID[0]"),
        typeIdentity: "view:Row",
        explicitID: "ID[0]"
      ),
      .init(
        identity: testIdentity("Root", "ID[1]"),
        typeIdentity: "view:Row",
        explicitID: "ID[1]"
      ),
    ]

    let operations = diffChildren(old: old, new: new)

    #expect(operations.contains(.inserted(newIndex: 0)))
    #expect(operations.contains(.inserted(newIndex: 1)))
    #expect(operations.count == 2)
  }

  @Test("pure removal emits only removed operations")
  func pureRemovalEmitsOnlyRemovals() {
    let old: [ChildDescriptor] = [
      .init(
        identity: testIdentity("Root", "ID[0]"),
        typeIdentity: "view:Row",
        explicitID: "ID[0]"
      ),
      .init(
        identity: testIdentity("Root", "ID[1]"),
        typeIdentity: "view:Row",
        explicitID: "ID[1]"
      ),
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
      .init(
        identity: testIdentity("Root", "ID[0]"),
        typeIdentity: "view:Row",
        explicitID: "ID[0]"
      ),
      .init(
        identity: testIdentity("Root", "ID[1]"),
        typeIdentity: "view:Row",
        explicitID: "ID[1]"
      ),
      .init(
        identity: testIdentity("Root", "ID[2]"),
        typeIdentity: "view:Row",
        explicitID: "ID[2]"
      ),
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
}
