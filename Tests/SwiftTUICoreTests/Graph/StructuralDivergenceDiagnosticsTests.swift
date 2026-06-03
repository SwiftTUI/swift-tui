#if DEBUG
  import Testing

  @testable import SwiftTUICore

  @Suite
  struct StructuralDivergenceDiagnosticsTests {
    @Test("ordinary resolved trees agree between path parent and structural parent")
    func ordinaryTreeHasNoParentDivergence() {
      let root = ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(
            identity: testIdentity("Root", "VStack[0]"),
            kind: .view("Text")
          ),
          ResolvedNode(
            identity: testIdentity("Root", "VStack[1]"),
            kind: .view("Group"),
            children: [
              ResolvedNode(
                identity: testIdentity("Root", "VStack[1]", "Group[0]"),
                kind: .view("Text")
              )
            ]
          ),
        ]
      )

      let snapshot = StructuralDivergenceDiagnostics.snapshot(of: root)
      let report = StructuralDivergenceDiagnostics.report(from: [snapshot])

      #expect(report.frameCount == 1)
      #expect(report.pathVsStructuralParentMismatches.isEmpty)
      #expect(report.duplicateRuntimeIdentities.isEmpty)
    }

    @Test(".id-style runtime identity divergence is detected, not hidden")
    func explicitIDParentDivergenceIsDetected() throws {
      let root = ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(
            identity: testIdentity("Root", "VStack[0]", "ID[42]"),
            kind: .view("Text")
          )
        ]
      )

      let snapshot = StructuralDivergenceDiagnostics.snapshot(of: root)
      let report = StructuralDivergenceDiagnostics.report(from: [snapshot])

      #expect(report.pathVsStructuralParentMismatches.count == 1)
      let mismatch = report.pathVsStructuralParentMismatches[0]
      #expect(mismatch.node == testIdentity("Root", "VStack[0]", "ID[42]"))
      #expect(mismatch.pathParent == testIdentity("Root", "VStack[0]"))
      #expect(mismatch.structuralParent == testIdentity("Root"))

      let record = try #require(
        snapshot.records.first { $0.runtimeIdentity == mismatch.node }
      )
      #expect(record.explicitIDComponent == "ID[42]")
    }

    @Test("duplicate runtime identities are reported per frame with producer provenance")
    func duplicateRuntimeIdentityIsReported() {
      let duplicate = testIdentity("Root", "ForEach[0]", "ID[dup]")
      let root = ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(identity: duplicate, kind: .view("Row")),
          ResolvedNode(identity: duplicate, kind: .view("Row")),
        ]
      )

      let report = StructuralDivergenceDiagnostics.report(
        from: [StructuralDivergenceDiagnostics.snapshot(of: root)]
      )

      #expect(report.duplicateRuntimeIdentities.count == 1)
      let duplicateRecord = report.duplicateRuntimeIdentities[0]
      #expect(duplicateRecord.identity == duplicate)
      #expect(duplicateRecord.occurrences == 2)
      #expect(duplicateRecord.producers == [.view("Row"), .view("Row")])
    }

    @Test("portal placement roles are surfaced from resolved surface metadata")
    func portalPlacementRolesAreReported() {
      let entry = ResolvedNode(
        identity: testIdentity("Root", "PortalHost", "overlays", "entry:sheet"),
        kind: .view("Sheet"),
        surfaceComposition: .init(
          role: .detachedOverlayEntry,
          stableKey: "Root#sheet",
          invalidationScope: .fullSurfaceDiff
        )
      )
      let root = ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [entry]
      )

      let report = StructuralDivergenceDiagnostics.report(
        from: [StructuralDivergenceDiagnostics.snapshot(of: root)]
      )

      #expect(report.portalPlacementRoles.count == 1)
      let role = report.portalPlacementRoles[0]
      #expect(role.node == entry.identity)
      #expect(role.structuralParent == testIdentity("Root"))
      #expect(role.role == .detachedOverlayEntry)
      #expect(role.stableKey == "Root#sheet")
    }

    @Test("machine-readable summary includes stable counters")
    func machineReadableSummaryIncludesCounters() {
      let duplicate = testIdentity("Root", "ID[dup]")
      let root = ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(identity: duplicate, kind: .view("Row")),
          ResolvedNode(identity: duplicate, kind: .view("Row")),
        ]
      )

      let report = StructuralDivergenceDiagnostics.report(
        from: [StructuralDivergenceDiagnostics.snapshot(of: root)]
      )

      #expect(report.machineReadableSummary.contains("structural_divergence\tframes\t1"))
      #expect(
        report.machineReadableSummary.contains(
          "structural_divergence\tduplicate_runtime_identities\t1"
        )
      )
    }
  }
#endif
