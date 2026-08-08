import SwiftTUICore

// The retained-measurement seeding seam for custom layouts (scroll-latency
// R1.3, plan 2026-08-08-001).
//
// `LayoutWorkerProxy` consults this protocol before driving a custom layout's
// `sizeThatFits`/`placeSubviews`: when the pass carries a retained layout
// session that holds this container's previous-frame measured product under
// the SAME proposal, the proxy hands the layout that product's inputs. The
// layout may derive whatever convergence state it wants from them — the
// contract is that the derived state is an OPTIMIZATION SEED only: the
// layout must verify it against fresh measurement and fall back to its
// unseeded path when the seed does not confirm, so a stale or wrong retained
// product can cost at most one extra measurement and can never change what
// the layout computes from scratch.

/// A custom layout that can seed internal convergence state from the previous
/// frame's retained measurement of the same container.
protocol RetainedMeasurementSeedableLayout {
  /// Applies the previous frame's retained container measurement as an
  /// optimization seed.
  ///
  /// - Parameters:
  ///   - previousProposal: The proposal the retained product was measured
  ///     under. The proxy only seeds when it equals the current proposal, so
  ///     implementations may treat it as the current proposal.
  ///   - previousChildSize: The retained measured size of the container's
  ///     single child (the proxy only seeds single-child containers).
  mutating func applyRetainedMeasurementSeed(
    previousProposal: ProposedViewSize,
    previousChildSize: LayoutSize
  )
}
