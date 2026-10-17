import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

@Test
func hosted_surface_initial_sizing_probes_parent_without_showing_warmup_grid() {
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: HostLengthSize(width: 8, height: 16),
    preferredGridSize: nil,
    renderedGridSize: nil
  )

  let negotiated = negotiator.negotiate(
    proposedWidth: 960,
    proposedHeight: 640
  )

  #expect(negotiated.size == HostLengthSize(width: 8, height: 16))
  #expect(negotiated.probeGridSize == CellSize(width: 120, height: 40))
}

@Test
func hosted_surface_sizing_prefers_measured_grid_over_available_space() {
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: HostLengthSize(width: 8, height: 16),
    preferredGridSize: CellSize(width: 12, height: 3),
    renderedGridSize: CellSize(width: 80, height: 24)
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: 640,
    proposedHeight: 384
  )

  #expect(negotiated == HostLengthSize(width: 96, height: 48))
}

@Test
func hosted_surface_sizing_snaps_finite_proposals_to_cell_blocks() {
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: HostLengthSize(width: 8, height: 16),
    preferredGridSize: CellSize(width: 12, height: 3),
    renderedGridSize: CellSize(width: 80, height: 24)
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: 46,
    proposedHeight: nil
  )

  #expect(negotiated == HostLengthSize(width: 40, height: 48))
}

@Test
func hosted_surface_sizing_probes_growth_without_returning_full_parent_proposal() {
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: HostLengthSize(width: 8, height: 16),
    preferredGridSize: CellSize(width: 5, height: 3),
    renderedGridSize: CellSize(width: 5, height: 3)
  )

  let negotiated = negotiator.negotiate(
    proposedWidth: 96,
    proposedHeight: 96
  )

  #expect(negotiated.size == HostLengthSize(width: 40, height: 48))
  #expect(negotiated.probeGridSize == CellSize(width: 12, height: 6))
}

@Test
func hosted_surface_sizing_remembers_confirmed_slack_after_growth_probe() {
  var confirmedSlack = HostedSurfaceConfirmedSlack()
  confirmedSlack.update(
    preferredGridSize: CellSize(width: 7, height: 1),
    renderedGridSize: CellSize(width: 12, height: 6)
  )
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: HostLengthSize(width: 8, height: 16),
    preferredGridSize: CellSize(width: 7, height: 1),
    renderedGridSize: CellSize(width: 7, height: 1),
    confirmedSlack: confirmedSlack
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: 96,
    proposedHeight: 96
  )

  #expect(negotiated == HostLengthSize(width: 56, height: 16))
}

@Test func hosted_surface_size_boundaries_are_finite_without_oversized_probes() {
  let cells = HostLengthSize(width: 1e-200, height: 2)
  let negotiator = HostedSurfaceSizeNegotiator(
    cellSize: cells, preferredGridSize: .init(width: 4, height: 3))
  let extreme = negotiator.negotiate(proposedWidth: 1e200, proposedHeight: 8)
  #expect(extreme.size == HostLengthSize(width: 4e-200, height: 6))
  #expect(extreme.probeGridSize == nil)
  for proposal in [-Double.greatestFiniteMagnitude, -1, 0] {
    let minimum = HostedSurfaceSizeNegotiator(cellSize: cells).negotiate(
      proposedWidth: proposal, proposedHeight: proposal)
    #expect(minimum.size == cells)
    #expect(minimum.probeGridSize == nil)
  }
  for pitch in [Double.nan, Double.infinity, -1, 0, Double.greatestFiniteMagnitude] {
    let invalid = HostedSurfaceSizeNegotiator(
      cellSize: .init(width: pitch, height: pitch), preferredGridSize: .init(width: 4, height: 3))
    let size = invalid.sizeThatFits(proposedWidth: nil, proposedHeight: nil)
    #expect(size.width.isFinite && size.width > 0)
    #expect(size.height.isFinite && size.height > 0)
    let intrinsic = invalid.intrinsicContentSize(noIntrinsicMetric: -1)
    #expect(intrinsic.width.isFinite && intrinsic.height.isFinite)
  }
}
