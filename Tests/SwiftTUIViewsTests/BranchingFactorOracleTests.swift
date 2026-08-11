import Foundation
import SwiftTUICore
import Testing

@testable import SwiftTUIViews

/// Owning tests for the layout branching-factor oracle (plan 2026-08-11-004
/// Stage 0).
///
/// Two enforcement layers share these fixtures:
///
/// 1. **Shape pins** — each fixture asserts its absolute request/computation
///    counts, the derived baseline shapes: `2N` requests for a finite/finite
///    stack, `2N + R` when the cross is unspecified, `N` for the ideal-only
///    round, and `2N + A` (pre-measures plus author probes) for custom
///    layouts.
/// 2. **The ledger ratchet** — `Scripts/layout_branching_ledger.txt` pins a
///    per-fixture, per-family ceiling on the requests-per-computation ratio
///    in milli-units, with the soundness scanner's asymmetry: above the
///    ceiling fails, equal passes as "matches baseline", below warns
///    "reduce the ledger". CI never rewrites the ledger; reductions are
///    manual commits.
///
/// Counters are read from a fresh `LayoutPassContext` per pass, so every row
/// measures exactly one main-purpose measure (or measure+place) pass.
@MainActor
@Suite("Branching-factor oracle (plan 2026-08-11-004)")
struct BranchingFactorOracleTests {
  private static let finiteProposal = ProposedSize(width: 40, height: 24)

  // MARK: - Built-in stack shapes

  @Test("flat stack, finite/finite: 2N requests from one container computation")
  func flatStackFiniteFinite() throws {
    let branching = measuredBranching(
      of: flatStack(childCount: 6),
      proposal: Self.finiteProposal
    )

    // Ideal round N + allocation offers N; the specified cross skips
    // reconciliation.
    #expect(branching.builtinChildMeasureRequests == 12)
    #expect(branching.builtinContainerMeasureComputations == 1)
    #expect(branching.customContainerMeasureComputations == 0)
    #expect(branching.customChildMeasureRequests == 0)
    try assertLedger(fixture: "flat-stack", family: .builtin, branching: branching)
  }

  @Test("flat stack, warm: a whole-subtree cache serve issues zero requests")
  func flatStackWarmServe() throws {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let resolved = flatStack(childCount: 6)

    let coldContext = LayoutPassContext()
    _ = engine.measure(resolved, proposal: Self.finiteProposal, passContext: coldContext)
    let hitsBeforeWarm = cache.metrics.hits

    let warmContext = LayoutPassContext()
    _ = engine.measure(resolved, proposal: Self.finiteProposal, passContext: warmContext)
    let branching = warmContext.workMetrics.branching

    // The root serve is one exact-key hit; nothing below it re-measures, so
    // the warm pass has no shape at all. A keying regression shows up here
    // first, as either requests or extra lookups.
    #expect(branching.builtinChildMeasureRequests == 0)
    #expect(branching.builtinContainerMeasureComputations == 0)
    #expect(cache.metrics.hits == hitsBeforeWarm + 1)
    try assertLedger(fixture: "flat-stack-warm", family: .builtin, branching: branching)
  }

  @Test("ideal-only stack: the ideal measurements are the final ones (N requests)")
  func idealOnlyStack() throws {
    let branching = measuredBranching(
      of: flatStack(childCount: 6),
      proposal: .unspecified
    )

    // Unspecified main: no allocation round. Rigid leaves make the
    // unspecified-cross reconciliation a no-op, so R = 0 here.
    #expect(branching.builtinChildMeasureRequests == 6)
    #expect(branching.builtinContainerMeasureComputations == 1)
    try assertLedger(fixture: "ideal-only-stack", family: .builtin, branching: branching)
  }

  @Test("unspecified cross: 2N + R with the flexible child re-measured once")
  func crossReconciliationStack() throws {
    // Child B's subtree is width-flexible and responds narrower than the
    // widest sibling, so reconciliation re-measures exactly it: R = 1.
    let resolved = stack(
      "cross-root",
      axis: .vertical,
      children: [
        leaf("wide", size: .init(width: 10, height: 1)),
        flexibleWidthChild("flexible", size: .init(width: 4, height: 1)),
      ]
    )
    let branching = measuredBranching(
      of: resolved,
      proposal: ProposedSize(width: .unspecified, height: .finite(24))
    )

    // The stack itself issues 2N + R = 5 (ideal 2, offers 2, reconciliation
    // 1). The flexible-frame wrapper is a container too: it computes at
    // each of the three distinct proposals it receives and forwards one
    // request per computation, so the pass totals are 8 requests over 4
    // container computations.
    #expect(branching.builtinChildMeasureRequests == 8)
    #expect(branching.builtinContainerMeasureComputations == 4)
    try assertLedger(
      fixture: "cross-reconciliation-stack", family: .builtin, branching: branching)
  }

  @Test("nested stacks: inner containers recompute per distinct proposal")
  func nestedStacks() throws {
    let resolved = stack(
      "nested-root",
      axis: .vertical,
      children: (0..<3).map { row in
        stack(
          "row-\(row)",
          axis: .horizontal,
          children: (0..<3).map { column in
            leaf("cell-\(row)-\(column)", size: .init(width: 4, height: 1))
          }
        )
      }
    )
    let branching = measuredBranching(of: resolved, proposal: Self.finiteProposal)

    // Root: 3 ideal + 3 offers. Each inner stack computes at the root's
    // ideal proposal and again at its finite offer (distinct cache keys),
    // issuing 2x3 requests per computation: 6 + 3x2x6 = 42 requests over
    // 1 + 6 computations. The inner ideal rounds repeat under the offer
    // round as exact-key cache hits — requests, not fresh computations.
    #expect(branching.builtinChildMeasureRequests == 42)
    #expect(branching.builtinContainerMeasureComputations == 7)
    try assertLedger(fixture: "nested-stacks", family: .builtin, branching: branching)
  }

  @Test("spacer deficit stack: the batch arm allocates the unbounded tail once")
  func spacerDeficitStack() throws {
    let resolved = stack(
      "deficit-root",
      axis: .vertical,
      children: [
        leaf("top", size: .init(width: 10, height: 8)),
        spacer("gap"),
        leaf("bottom", size: .init(width: 10, height: 8)),
      ]
    )
    let branching = measuredBranching(
      of: resolved,
      proposal: ProposedSize(width: 40, height: 10)
    )

    // Ideal 3 + two sequential offers + the one-member unbounded batch.
    #expect(branching.builtinChildMeasureRequests == 6)
    #expect(branching.builtinContainerMeasureComputations == 1)
    try assertLedger(fixture: "spacer-deficit-stack", family: .builtin, branching: branching)
  }

  @Test("ViewThatFits: N committed measurements plus one probe per rejected child")
  func viewThatFits() throws {
    let resolved = ResolvedNode(
      identity: testIdentity("vtf"),
      kind: .view("ViewThatFits"),
      children: [
        leaf("tall", size: .init(width: 10, height: 30)),
        leaf("medium", size: .init(width: 10, height: 20)),
        leaf("short", size: .init(width: 10, height: 5)),
      ],
      layoutBehavior: .viewThatFits(AxisSet.vertical)
    )
    let branching = measuredBranching(of: resolved, proposal: Self.finiteProposal)

    // 3 children measured at the real proposal, then fit probes: child 0
    // (30 rows, rejected) and child 1 (20 rows, selected).
    #expect(branching.builtinChildMeasureRequests == 5)
    #expect(branching.builtinContainerMeasureComputations == 1)
    try assertLedger(fixture: "view-that-fits", family: .builtin, branching: branching)
  }

  @Test("windowed lazy list: one stride probe plus the visible band")
  func windowedLazyList() throws {
    let rows = (0..<40).map { index in
      leaf("row-\(index)", size: .init(width: 20, height: 1))
    }
    let resolved = indexedLazyStack("list", axis: .vertical, children: rows)
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    passContext.pushMeasureViewportHint(
      MeasureViewportHint(
        axes: .vertical,
        contentOffset: .zero,
        viewportSize: .init(width: 20, height: 10)
      )
    )
    defer { passContext.popMeasureViewportHint() }

    _ = engine.measure(
      resolved,
      proposal: ProposedSize(width: 20, height: 10),
      passContext: passContext
    )
    let branching = passContext.workMetrics.branching

    // Element-0 stride probe (reused inside the window) plus the 11
    // remaining band children: stride 1, 10 viewport rows, one overscan row
    // each side plus the partial-row allowance, clamped at the top.
    #expect(branching.builtinChildMeasureRequests == 12)
    #expect(branching.builtinContainerMeasureComputations == 1)
    try assertLedger(fixture: "windowed-lazy-list", family: .builtin, branching: branching)
  }

  // MARK: - Custom layouts

  @Test("custom grid: 2N + A measure requests, N placement re-measures")
  func customGrid() throws {
    let resolved = customGridNode(childCount: 4)
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()

    let measured = engine.measure(
      resolved,
      proposal: Self.finiteProposal,
      passContext: passContext
    )
    let measureBranching = passContext.workMetrics.branching

    // N pre-measures at the container proposal plus A = N author probes
    // from the grid's sizeThatFits.
    #expect(measureBranching.customChildMeasureRequests == 8)
    #expect(measureBranching.customContainerMeasureComputations == 1)
    #expect(measureBranching.customPlacementChildMeasureRequests == 0)
    #expect(measureBranching.builtinContainerMeasureComputations == 0)
    try assertLedger(fixture: "custom-grid", family: .custom, branching: measureBranching)

    _ = engine.place(
      resolved,
      measured: measured,
      in: .init(origin: .zero, size: measured.measuredSize),
      passContext: passContext
    )
    let placeBranching = passContext.workMetrics.branching
    #expect(placeBranching.customPlacementChildMeasureRequests == 4)
  }

  @Test("the ledger and this suite cover exactly the same rows")
  func ledgerRowsMatchSuiteCoverage() throws {
    let ledger = try BranchingLedger.load()
    let measured = Set(Self.coveredRows.map(\.key))
    let pinned = Set(ledger.rows.keys)

    for orphan in pinned.subtracting(measured).sorted() {
      Issue.record(
        """
        ledger row '\(orphan)' has no owning fixture in \
        BranchingFactorOracleTests; remove the row or add the fixture. See \
        Scripts/layout_branching_ledger.txt and docs/SOUNDNESS-ORACLES.md.
        """
      )
    }
    for uncovered in measured.subtracting(pinned).sorted() {
      Issue.record(
        """
        fixture '\(uncovered)' has no ledger row; seed one in \
        Scripts/layout_branching_ledger.txt.
        """
      )
    }
  }

  // MARK: - Harness

  private enum BranchingFamily: String {
    case builtin
    case custom
  }

  /// Every `(fixture, family)` row this suite measures, the coverage side of
  /// the two-way drift check against the ledger.
  private static let coveredRows: [(key: String, family: BranchingFamily)] = [
    ("flat-stack builtin", .builtin),
    ("flat-stack-warm builtin", .builtin),
    ("ideal-only-stack builtin", .builtin),
    ("cross-reconciliation-stack builtin", .builtin),
    ("nested-stacks builtin", .builtin),
    ("spacer-deficit-stack builtin", .builtin),
    ("view-that-fits builtin", .builtin),
    ("windowed-lazy-list builtin", .builtin),
    ("custom-grid custom", .custom),
  ]

  private func measuredBranching(
    of resolved: ResolvedNode,
    proposal: ProposedSize
  ) -> LayoutBranchingMetrics {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    _ = engine.measure(resolved, proposal: proposal, passContext: passContext)
    return passContext.workMetrics.branching
  }

  /// The ratchet with the soundness scanner's asymmetry: above the ceiling
  /// fails, equal passes as a baseline match, below passes with a
  /// reduce-the-ledger notice on stderr.
  private func assertLedger(
    fixture: String,
    family: BranchingFamily,
    branching: LayoutBranchingMetrics
  ) throws {
    let ledger = try BranchingLedger.load()
    let key = "\(fixture) \(family.rawValue)"
    guard let ceilingMilli = ledger.rows[key] else {
      Issue.record(
        """
        fixture '\(key)' has no ledger row; seed one in \
        Scripts/layout_branching_ledger.txt.
        """
      )
      return
    }
    let measuredMilli =
      switch family {
      case .builtin: branching.builtinBranchingFactorMilli
      case .custom: branching.customBranchingFactorMilli
      }
    if measuredMilli > ceilingMilli {
      Issue.record(
        """
        FAIL: \(fixture) \(family.rawValue) branching factor \(measuredMilli) milli \
        exceeds ceiling-milli=\(ceilingMilli); a container issues more child measure \
        requests per computation than the pinned shape. See \
        Scripts/layout_branching_ledger.txt and docs/SOUNDNESS-ORACLES.md.
        """
      )
    } else if measuredMilli < ceilingMilli {
      FileHandle.standardError.write(
        Data(
          """
          warning: \(fixture) \(family.rawValue) branching factor \(measuredMilli) milli \
          is below ceiling-milli=\(ceilingMilli); reduce the ledger\n
          """.utf8
        )
      )
    }
  }

  private struct BranchingLedger {
    var rows: [String: Int]

    static func load() throws -> BranchingLedger {
      let url = try ledgerURL()
      let contents = try String(contentsOf: url, encoding: .utf8)
      var rows: [String: Int] = [:]
      for line in contents.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
          continue
        }
        let parts = trimmed.split(separator: " ")
        guard parts.count == 3,
          parts[2].hasPrefix("ceiling-milli="),
          let ceiling = Int(parts[2].dropFirst("ceiling-milli=".count))
        else {
          throw LedgerError.malformedRow(String(trimmed))
        }
        rows["\(parts[0]) \(parts[1])"] = ceiling
      }
      return BranchingLedger(rows: rows)
    }

    private static func ledgerURL() throws -> URL {
      var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      for _ in 0..<10 {
        let packageManifest = directory.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageManifest.path) {
          return
            directory
            .appendingPathComponent("Scripts")
            .appendingPathComponent("layout_branching_ledger.txt")
        }
        directory = directory.deletingLastPathComponent()
      }
      throw LedgerError.repositoryRootNotFound
    }
  }

  private enum LedgerError: Error {
    case malformedRow(String)
    case repositoryRootNotFound
  }

  // MARK: - Fixtures

  private func flatStack(childCount: Int) -> ResolvedNode {
    stack(
      "flat-root",
      axis: .vertical,
      children: (0..<childCount).map { index in
        leaf("leaf-\(index)", size: .init(width: 10, height: 2))
      }
    )
  }

  private func customGridNode(childCount: Int) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity("grid"),
      kind: .view("TwoColumnGridLayout"),
      children: (0..<childCount).map { index in
        leaf("cell-\(index)", size: .init(width: 6, height: 2))
      },
      layoutBehavior: AnyLayout(TwoColumnGridLayout()).resolvedBehavior
    )
  }
}

/// A minimal author `Layout`: probes every subview once during measurement
/// (`A = N`) and places from arithmetic alone, so the placement counter pins
/// exactly the framework's own per-child placement re-measure.
private struct TwoColumnGridLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    var columnWidths = [0, 0]
    var height = 0
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(
        .init(width: .unspecified, height: .unspecified)
      )
      columnWidths[index % 2] = max(columnWidths[index % 2], size.width)
      if index % 2 == 0 {
        height += size.height
      }
    }
    return .init(width: columnWidths[0] + columnWidths[1], height: height)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let columnWidth = max(1, bounds.size.width / 2)
    let rowHeight = 2
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: .init(
          x: bounds.origin.x + (index % 2) * columnWidth,
          y: bounds.origin.y + (index / 2) * rowHeight
        ),
        proposal: .init(width: .finite(columnWidth), height: .finite(rowHeight))
      )
    }
  }
}

/// A deterministic `ViewNodeID` per fixture name (FNV-1a), so the warm-path
/// rows exercise the measurement cache — its lookup and store are keyed on
/// the node id and skip nodes without one.
private func fixtureViewNodeID(_ name: String) -> ViewNodeID {
  var hash: UInt64 = 14_695_981_039_346_656_037
  for byte in name.utf8 {
    hash ^= UInt64(byte)
    hash &*= 1_099_511_628_211
  }
  return ViewNodeID(rawValue: hash)
}

private func leaf(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
    identity: testIdentity(name),
    kind: .view("Test"),
    intrinsicSize: size
  )
}

private func spacer(_ name: String) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
    identity: testIdentity(name),
    kind: .view("Spacer"),
    intrinsicSize: .zero
  )
}

private func stack(
  _ name: String,
  axis: SwiftTUICore.Axis,
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    viewNodeID: fixtureViewNodeID(name),
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "HStack" : "VStack"),
    children: children,
    layoutBehavior: .stack(
      axis: axis,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    )
  )
}

/// A width-flexible subtree that responds narrower than its siblings at the
/// ideal round, so an unspecified-cross stack re-measures exactly it.
private func flexibleWidthChild(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("FlexibleFrame"),
    children: [leaf("\(name)-content", size: size)],
    layoutBehavior: .flexibleFrame(
      minWidth: nil,
      idealWidth: nil,
      maxWidth: .infinity,
      minHeight: nil,
      idealHeight: nil,
      maxHeight: nil,
      alignment: .topLeading
    )
  )
}

private func indexedLazyStack(
  _ name: String,
  axis: SwiftTUICore.Axis,
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "LazyHStack" : "LazyVStack"),
    layoutBehavior: .lazyStack(
      axis: axis,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    ),
    indexedChildSource: BranchingTestIndexedChildSource(
      identityRoot: testIdentity(name),
      children: children
    )
  )
}

private struct BranchingTestIndexedChildSource: IndexedChildSource {
  let identityRoot: Identity
  let measurementSignature: IndexedChildMeasurementSignature
  private let children: [ResolvedNode]

  init(
    identityRoot: Identity,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.children = children
    measurementSignature = .init(elementPaths: children.map(\.identity.path))
  }

  var count: Int {
    children.count
  }

  func child(at index: Int) -> ResolvedNode {
    children[index]
  }

  func elementIdentity(at index: Int) -> Identity {
    children[index].identity
  }
}
