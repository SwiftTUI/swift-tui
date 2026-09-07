import Testing

@testable import SwiftTUIGraph

/// Locks the Stage-2 reuse win: layout/placement equivalence is gated on the
/// *structural* path, not the runtime `Identity`. A pure `.id` change (same
/// structural slot, different runtime identity) must stay layout-reusable, and a
/// structural move (same identity, different slot) must diverge. Without this
/// lock, a future refactor that re-couples the equivalence gate to `Identity`
/// would silently defeat reuse across `.id` churn and pass the rest of the suite
/// (which compares identical identities on both sides).
@Suite("Structural equivalence lock")
struct StructuralEquivalenceLockTests {
  private func slot(_ components: String...) -> StructuralPath {
    StructuralPath(components: components.map { .init(rawValue: $0) })
  }

  @Test("a pure .id change at the same structural slot stays layout-reusable")
  func pureIdentityChangeStaysReusable() {
    let path = slot("Root", "VStack[2]")
    let original = ResolvedNode(
      identity: testIdentity("Root", "VStack[2]"),
      structuralPath: path,
      kind: .view("Text")
    )
    let reidentified = ResolvedNode(
      identity: testIdentity("Root", "VStack[2]", "ID[changed]"),
      structuralPath: path,
      kind: .view("Text")
    )

    #expect(original.isEquivalentForMeasurement(to: reidentified))
    #expect(original.measurementEquivalence(to: reidentified).canRefreshWitness)
    #expect(original.isEquivalentForPlacement(to: reidentified))
    // Geometry/metadata gate passes; only the runtime identity differs, so the
    // placed bounds are reusable but the metadata mirror must re-sync.
    #expect(original.placementEquivalence(to: reidentified) == .geometryReusable)
  }

  @Test("measurement witness refresh requires exact type discriminators")
  func witnessRefreshRequiresExactDiscriminators() {
    typealias Pair = (
      left: ObjectIdentifier?, right: ObjectIdentifier?, compatible: Bool, refresh: Bool
    )
    let typedA = ObjectIdentifier(Int.self)
    let typedB = ObjectIdentifier(String.self)
    let pairs: [Pair] = [
      (typedA, typedA, true, true),
      (nil, nil, true, true),
      (typedA, nil, true, false),
      (nil, typedA, true, false),
      (typedA, typedB, false, false),
    ]

    for pair in pairs {
      let left = ResolvedNode(
        identity: testIdentity("Root"), kind: .view("Legacy"), typeDiscriminator: pair.left)
      var right = left
      right.typeDiscriminator = pair.right

      let equivalence = left.measurementEquivalence(to: right)
      #expect(equivalence.isCompatible == pair.compatible)
      #expect(equivalence.canRefreshWitness == pair.refresh)
      #expect(left.isEquivalentForMeasurement(to: right) == pair.compatible)
    }
  }

  @Test("a nested wildcard denies witness refresh without denying measurement reuse")
  func nestedWildcardDeniesWitnessRefresh() {
    let original = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .view("Container"),
      typeDiscriminator: ObjectIdentifier(String.self),
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Child"),
          kind: .view("Legacy"),
          typeDiscriminator: ObjectIdentifier(Int.self)
        )
      ]
    )
    var wildcard = original
    wildcard.children[0].typeDiscriminator = nil

    let equivalence = original.measurementEquivalence(to: wildcard)
    #expect(equivalence.isCompatible)
    #expect(!equivalence.canRefreshWitness)
  }

  @Test("a structural-slot move with the same identity is divergent")
  func structuralMoveIsDivergent() {
    let original = ResolvedNode(
      identity: testIdentity("Root", "Item"),
      structuralPath: slot("Root", "VStack[1]"),
      kind: .view("Text")
    )
    let moved = ResolvedNode(
      identity: testIdentity("Root", "Item"),
      structuralPath: slot("Root", "VStack[2]"),
      kind: .view("Text")
    )

    #expect(!original.isEquivalentForMeasurement(to: moved))
    #expect(!original.isEquivalentForPlacement(to: moved))
    #expect(original.placementEquivalence(to: moved) == .divergent)
  }

  @Test("measurement equivalence is stack-safe for node-hosted row depth")
  func measurementEquivalenceIsStackSafeForNodeHostedRows() {
    func nestedTree() -> ResolvedNode {
      var node = ResolvedNode(
        identity: testIdentity("Leaf"),
        structuralPath: slot("Leaf"),
        kind: .view("Text")
      )
      for depth in (0..<256).reversed() {
        node = ResolvedNode(
          identity: testIdentity("HostedRow", "\(depth)"),
          structuralPath: slot("HostedRow", "\(depth)"),
          kind: .view("HostedRow"),
          children: [node]
        )
      }
      return node
    }

    let original = nestedTree()
    let repeated = nestedTree()
    #expect(original.isEquivalentForMeasurement(to: repeated))
    #expect(original.measurementEquivalence(to: repeated).canRefreshWitness)
  }
}
