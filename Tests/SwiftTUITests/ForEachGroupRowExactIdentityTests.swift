import SwiftTUICore
import Testing

@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Plan 2026-08-25-003 P3 part 2: a nested exact `.id` inside a *multi-statement*
/// `ForEach` row (the segmented picker's `segment` + conditional `Divider`) used
/// to lose its own entity to the row entity.
///
/// `ForEach` attaches its row entity after the row resolves, and a multi-statement
/// row builder mints a `Group` that `consumeDeclaredChild` splices away — so the
/// row entity is pushed onto the `Group`'s children instead of the `Group` value.
/// That stamp used to overwrite a child that had already claimed its own entity
/// through `.id(exact)`, which dropped the exact entity from the resolved tree
/// (releasing its route at the frame barrier) and left the child's committed
/// value holding the row entity — an occupant that routes to the row's own node.
/// The next frame's `nodeForIdentity` then evicted the subtree and minted a fresh
/// node, on every single frame.
///
/// The visible symptom was a wrapper-level shape flip: `ExactIdentityModifier`
/// reads `ViewGraph.entityOccupant` to decide whether to mint an
/// `ExplicitIdentityHost`, and a node minted this frame answers from the route
/// table (its own entity, so no host) where a surviving node answers from its
/// committed value (the row entity, so a host). The DEBUG skip oracle
/// (`AnimationController.noteSkippedResolvedTreeProcessing`) reported those two
/// shapes as an identity divergence between a reused and a processed tree.
@MainActor
@Suite(.serialized)
struct ForEachGroupRowExactIdentityTests {
  @Test("a multi-statement ForEach row's exact .id keeps its own entity and node")
  func multiStatementRowExactIdentityKeepsItsEntityAndNode() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GroupRowRoot"),
      size: .init(width: 40, height: 6)
    ) {
      GroupRowFixture(appearances: AppearanceLedger())
    }
    defer { harness.shutdown() }

    var shapes: [String] = []
    for _ in 0..<4 {
      _ = try harness.renderAfterExternalMutation()
      shapes.append(try groupRowShape(harness))
    }

    // Every frame resolves the same wrapper level, the same node, and the same
    // entity: no `ExplicitIdentityHost` appearing or disappearing, and no churn.
    #expect(
      Set(shapes).count == 1,
      "the row's resolved shape flipped across frames:\n\(shapes.joined(separator: "\n"))"
    )
    let shape = try #require(shapes.first)
    #expect(
      shape.contains("entity=GroupRowOption/0"),
      "the row entity overwrote the exact `.id`'s own entity: \(shape)"
    )
  }

  @Test("a multi-statement ForEach row's exact .id is not re-minted every frame")
  func multiStatementRowExactIdentityIsNotReMintedEveryFrame() throws {
    let appearances = AppearanceLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GroupRowRoot"),
      size: .init(width: 40, height: 6)
    ) {
      GroupRowFixture(appearances: appearances)
    }
    defer { harness.shutdown() }

    for _ in 0..<4 {
      _ = try harness.renderAfterExternalMutation()
    }

    // An evicted-and-re-minted node re-publishes its lifecycle registrations, so
    // a row whose identity churns fires `.onAppear` once per frame.
    #expect(
      appearances.count == 1,
      "the row's node was re-minted: `.onAppear` fired \(appearances.count) times"
    )
  }
}

// MARK: - Support

@MainActor
private final class AppearanceLedger {
  var count = 0
}

@MainActor
private func groupRowShape<V: View>(_ harness: StressRuntimeHarness<V>) throws -> String {
  let root = try #require(
    harness.runLoop.renderer
      .debugRuntimeSubsystemSnapshot()
      .animationController
      .previousTreeRoot
  )
  var lines: [String] = []
  func visit(_ node: ResolvedNode, hosted: Bool) {
    let isRowZero = node.identity.path.contains("GroupRowOption/0")
    if isRowZero, !hosted {
      lines.append(
        "\(node.kind)@\(node.identity.path)"
          + " entity=\(node.entityIdentity.map { String(describing: $0) } ?? "nil")"
          + " node=\(node.viewNodeID.map { "\($0.rawValue)" } ?? "nil")"
      )
      return
    }
    if node.kind == .view("ExplicitIdentityHost") {
      lines.append("ExplicitIdentityHost@\(node.identity.path)")
    }
    for child in node.children {
      visit(child, hosted: false)
    }
  }
  visit(root, hosted: false)
  return lines.joined(separator: " | ")
}

@MainActor
private struct GroupRowFixture: View {
  let appearances: AppearanceLedger

  var body: some View {
    HStack(spacing: 1) {
      ForEach(0..<3) { index in
        // The segmented picker's row shape: a segment carrying a nested exact
        // `.id`, plus a conditional separator. Two statements, so the row
        // builder mints the `Group` whose children take the row entity.
        Text("o\(index)")
          .onAppear {
            if index == 0 {
              appearances.count += 1
            }
          }
          .id(testIdentity("GroupRowOption", "\(index)"))
        if index < 2 {
          Divider()
        }
      }
    }
  }
}
