import Foundation
import Testing

@testable import SwiftTUIGraph

/// Field-coverage totality lock for every `ResolvedNode` comparison function
/// (F96). The comparators in `ResolvedNodeEquivalence.swift` each encode a
/// deliberate per-field policy (compared, compared-by-signature, or exempt for
/// a documented reason), but nothing forced a newly added stored field to be
/// classified — `isTransient`/`matchedGeometry` shipped compared by
/// `placementEquivalence` yet invisible to `==` and the memo oracle, and the
/// divergence was only found by a manual audit. This suite derives the
/// canonical field set from the production source (same technique as
/// `ViewGraphCheckpointTotalityTests`) and requires every comparator to
/// mention or explicitly exempt every stored field, so the next added field
/// fails here until every comparator's policy is a decision, not an accident.
@MainActor
@Suite("ResolvedNode comparator totality")
struct ResolvedNodeComparatorTotalityTests {
  private static let resolvedNodePath = "Sources/SwiftTUIGraph/Resolve/ResolvedNode.swift"
  private static let equivalencePath =
    "Sources/SwiftTUIGraph/Resolve/ResolvedNodeEquivalence.swift"

  /// Stored properties whose public comparison surface goes by another name:
  /// the comparators reference the computed accessor, not the storage.
  private static let storageAliases: [String: String] = [
    "_storedChildren": "children",
    "_storedLayoutBehavior": "layoutBehavior",
    "_boxedDrawMetadata": "drawMetadata",
  ]

  /// Derived caches and runtime-stamping bookkeeping no comparator should
  /// consult: recomputed from the compared fields (comparing the source
  /// fields subsumes them) or assigned by runtime adoption after resolve.
  private static let universalExemptions: [String: String] = [
    "subtreeNodeCount": "derived cache recomputed from children — comparing children subsumes it",
    "customLayoutFallbackSummary":
      "derived cache recomputed from indexedChildSource/layoutRealizedContent didSets",
    "subtreeRuntimeNodeIDsStamped":
      "runtime stamping bookkeeping — its own doc excludes it from == alongside viewNodeID",
  ]

  /// Per-comparator exemption manifests: stored fields the comparator
  /// deliberately does NOT consult, each with the reason. A field missing
  /// from both the comparator body and this manifest fails the totality test.
  private static let exemptions: [String: [String: String]] = [
    "==": [
      "viewNodeID": "runtime node stamp, re-assigned on adoption — not view value"
    ],
    "memoReuseEquivalent": [
      "viewNodeID": "runtime node stamp, re-assigned on adoption — not view value",
      "structuralPath": "re-stamped on reuse by the retained-reuse path (documented exemption)",
    ],
    "memoUnsoundContentDivergence": [
      "viewNodeID": "runtime node stamp, re-assigned on adoption — not view value",
      "structuralPath": "oracle-ignored: re-stamped on reuse",
      "entityIdentity": "per-resolve entity bookkeeping — histogram-only, never the alarm",
      "entityStructuralPath": "per-resolve entity bookkeeping — histogram-only, never the alarm",
    ],
    "placementEquivalence": [
      "viewNodeID": "runtime node stamp — PlacedNode does not mirror it",
      "transactionSnapshot": "not mirrored into PlacedNode (see the metadata contract comment)",
      "preferenceValues": "not mirrored into PlacedNode; reconciled by the preference phase",
      "supportsRetainedReuse": "reuse-machinery flag, not placed output",
    ],
    "isEquivalentForMeasurement": [
      "viewNodeID": "measurement cache key: node stamps cannot change measured size",
      "identity": "measurement cache key: identity cannot change measured size",
      "structuralEdgeRole": "measurement cache key: edge role cannot change measured size",
      "entityIdentity": "measurement cache key: entity routing cannot change measured size",
      "entityStructuralPath": "measurement cache key: entity routing cannot change measured size",
      "declarationOwnerEdge": "measurement cache key: owner edge cannot change measured size",
      "transactionSnapshot": "measurement cache key: transactions cannot change measured size",
      "drawMetadata": "measurement cache key: draw styling cannot change measured size",
      "drawEffects": "measurement cache key: draw effects cannot change measured size",
      "surfaceComposition": "measurement cache key: compositing cannot change measured size",
      "semanticMetadata": "measurement cache key: semantics cannot change measured size",
      "lifecycleMetadata": "measurement cache key: lifecycle cannot change measured size",
      "preferenceValues": "measurement cache key: preferences cannot change measured size",
      "supportsRetainedReuse": "measurement cache key: reuse flag cannot change measured size",
      "matchedGeometry": "measurement cache key: matched-geometry pairing is placement-phase",
      "isTransient": "measurement cache key: overlay marking cannot change measured size",
    ],
    "isEquivalentForPlacement": [
      "viewNodeID": "placement cache key: node stamps do not affect geometry",
      "identity": "placement cache key: identity does not affect geometry",
      "structuralEdgeRole": "placement cache key: edge role does not affect geometry",
      "entityIdentity": "placement cache key: entity routing does not affect geometry",
      "entityStructuralPath": "placement cache key: entity routing does not affect geometry",
      "declarationOwnerEdge": "placement cache key: owner edge does not affect geometry",
      "transactionSnapshot": "placement cache key: transactions do not affect geometry",
      "drawMetadata": "placement cache key: draw styling does not affect geometry",
      "drawEffects": "placement cache key: draw effects do not affect geometry",
      "surfaceComposition": "placement cache key: compositing does not affect geometry",
      "semanticMetadata": "placement cache key: semantics do not affect geometry",
      "lifecycleMetadata": "placement cache key: lifecycle does not affect geometry",
      "preferenceValues": "placement cache key: preferences do not affect geometry",
      "supportsRetainedReuse": "placement cache key: reuse flag does not affect geometry",
      "matchedGeometry": "placement cache key: pairing resolved by the matched-geometry pass",
      "isTransient": "placement cache key: overlay marking compared by placementEquivalence",
    ],
  ]

  private func comparableFieldNames() throws -> [String] {
    try SourceParsingTestSupport.parsedStoredVarNames(
      typeKind: "struct",
      typeName: "ResolvedNode",
      relativePath: Self.resolvedNodePath
    ).map { Self.storageAliases[$0] ?? $0 }
  }

  @Test(
    "every stored field is compared or explicitly exempted, per comparator",
    arguments: [
      "==", "memoReuseEquivalent", "memoUnsoundContentDivergence",
      "placementEquivalence", "isEquivalentForMeasurement", "isEquivalentForPlacement",
    ])
  func comparatorIsFieldTotal(comparator: String) throws {
    let fields = try comparableFieldNames()
    #expect(Set(fields).count == fields.count)
    #expect(fields.count >= 25, "parser found implausibly few stored fields: \(fields)")

    let source = try SourceParsingTestSupport.sourceText(relativePath: Self.equivalencePath)
    let body = SourceParsingTestSupport.functionBodyText(named: comparator, in: source)
    #expect(!body.isEmpty, "could not locate \(comparator) in ResolvedNodeEquivalence.swift")

    let exempt = (Self.exemptions[comparator] ?? [:])
      .merging(Self.universalExemptions) { specific, _ in specific }
    for field in fields {
      let mentioned = body.contains(field)
      let isExempt = exempt[field] != nil
      #expect(
        mentioned || isExempt,
        "\(comparator) neither consults nor exempts ResolvedNode.\(field) — classify the field: compare it in the body, or add it to this suite's exemption manifest with a reason."
      )
      #expect(
        !(mentioned && isExempt),
        "\(comparator) both consults and exempts ResolvedNode.\(field) — the manifest has drifted from the body; remove the stale exemption."
      )
    }
  }

  @Test("exemption manifests only name real stored fields (no stale entries)")
  func exemptionManifestsNameRealFields() throws {
    let fields = Set(try comparableFieldNames())
    for (comparator, exempt) in Self.exemptions {
      for field in exempt.keys {
        #expect(
          fields.contains(field),
          "\(comparator) exempts '\(field)', which is not a stored ResolvedNode field — remove or rename the manifest entry."
        )
      }
    }
    for field in Self.universalExemptions.keys {
      #expect(
        fields.contains(field),
        "universal exemption '\(field)' is not a stored ResolvedNode field — remove or rename the entry."
      )
    }
  }

  @Test("totality guard has teeth: an unclassified field fails the check")
  func totalityGuardCatchesUnclassifiedField() throws {
    let fields = try comparableFieldNames()
    let source = try SourceParsingTestSupport.sourceText(relativePath: Self.equivalencePath)
    let body = SourceParsingTestSupport.functionBodyText(named: "==", in: source)
    let exempt = Self.exemptions["=="] ?? [:]
    // Simulate the next added field: no comparator body mentions it and no
    // manifest exempts it — the positive test's predicate must reject it.
    let phantom = "phantomNewField"
    #expect(!fields.contains(phantom))
    #expect(!(body.contains(phantom) || exempt[phantom] != nil))
  }

  // MARK: - Value-level teeth for the memo oracle's documented exemptions

  private func leafPair() -> (ResolvedNode, ResolvedNode) {
    let node = ResolvedNode(identity: testIdentity("Root"), kind: .view("Leaf"))
    return (node, node)
  }

  @Test("memo oracle ignores a structuralPath re-stamp (documented exemption)")
  func memoOracleIgnoresStructuralPathRestamp() {
    var (current, committed) = leafPair()
    committed.structuralPath = StructuralPath(components: [
      .init(rawValue: "Relocated"), .init(rawValue: "Leaf"),
    ])
    #expect(current.structuralPath != committed.structuralPath)
    #expect(current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == nil)
  }

  @Test("memo oracle and == flip on a matchedGeometry config change (F96)")
  func comparatorsFlipOnMatchedGeometryChange() {
    var (current, committed) = leafPair()
    committed.matchedGeometry = MatchedGeometryConfig(
      key: MatchedGeometryKey(id: "hero"), isSource: true
    )
    #expect(!current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == "matchedGeometry")
    #expect(current != committed)

    // isSource alone is a config change too — a stale flip would pair the
    // wrong geometry source.
    current.matchedGeometry = MatchedGeometryConfig(
      key: MatchedGeometryKey(id: "hero"), isSource: false
    )
    #expect(!current.memoReuseEquivalent(to: committed))
  }

  @Test("memo oracle and == flip on the transient overlay marking (F96)")
  func comparatorsFlipOnTransientMarking() {
    var (current, committed) = leafPair()
    committed.isTransient = true
    #expect(!current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == "isTransient")
    #expect(current != committed)
  }

  @Test("memo oracle recurses: a grandchild content diff defeats reuse")
  func memoOracleRecursesIntoChildren() {
    let grandchild = ResolvedNode(
      identity: testIdentity("Root", "Child", "Leaf"), kind: .view("Leaf")
    )
    var changedGrandchild = grandchild
    changedGrandchild.kind = .view("Renamed")
    let child = ResolvedNode(
      identity: testIdentity("Root", "Child"), kind: .view("Child"), children: [grandchild]
    )
    var changedChild = child
    changedChild._storedChildren = [changedGrandchild]
    let current = ResolvedNode(
      identity: testIdentity("Root"), kind: .root, children: [child]
    )
    var committed = current
    committed._storedChildren = [changedChild]

    #expect(!current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == "child.child.kind")
  }

  @Test("memo oracle flips on a children count mismatch")
  func memoOracleFlipsOnChildCountMismatch() {
    let child = ResolvedNode(identity: testIdentity("Root", "Leaf"), kind: .view("Leaf"))
    let current = ResolvedNode(identity: testIdentity("Root"), kind: .root, children: [child])
    let committed = ResolvedNode(identity: testIdentity("Root"), kind: .root, children: [])
    #expect(!current.memoReuseEquivalent(to: committed))
    #expect(current.memoUnsoundContentDivergence(from: committed) == "children.count")
  }
}
