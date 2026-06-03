import Testing

@testable import SwiftTUICore

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
    #expect(original.isEquivalentForPlacement(to: reidentified))
    // Geometry/metadata gate passes; only the runtime identity differs, so the
    // placed bounds are reusable but the metadata mirror must re-sync.
    #expect(original.placementEquivalence(to: reidentified) == .geometryReusable)
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
}
