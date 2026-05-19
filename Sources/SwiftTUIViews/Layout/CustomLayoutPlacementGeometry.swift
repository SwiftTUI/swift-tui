import SwiftTUICore

// Placement geometry for custom layouts.
//
// `LayoutSubviewPlacementRecord` captures one subview placement (position,
// anchor, proposal, optional viewport context); `LayoutSubviewPlacementRecorder`
// collects them keyed by identity during a layout pass. `defaultPlacement`
// centers a subview in its bounds; `placedOrigin` converts an anchored
// placement into a top-left origin.
//
// Split out of `CustomLayout.swift`. The four declarations are widened from
// `private` to file-internal so the layout proxies (`SendableLayoutWorkerProxy`,
// `LayoutProxyBox`) and `LayoutSubview.place` can reach them across files.
// `internal` (not `package`) is the minimal level — this machinery is entirely
// SwiftTUIViews-internal.

struct LayoutSubviewPlacementRecord {
  var position: LayoutPoint
  var anchor: Alignment
  var proposal: ProposedViewSize
  var viewportContext: ScrollViewportContext?
}

final class LayoutSubviewPlacementRecorder {
  private var placements: [Identity: LayoutSubviewPlacementRecord] = [:]

  func record(identity: Identity, placement: LayoutSubviewPlacementRecord) {
    placements[identity] = placement
  }

  func placement(for identity: Identity) -> LayoutSubviewPlacementRecord? {
    placements[identity]
  }
}

func defaultPlacement(
  in bounds: LayoutRect,
  proposal: ProposedViewSize
) -> LayoutSubviewPlacementRecord {
  LayoutSubviewPlacementRecord(
    position: LayoutPoint(
      x: bounds.origin.x + (bounds.size.width / 2),
      y: bounds.origin.y + (bounds.size.height / 2)
    ),
    anchor: .center,
    proposal: proposal
  )
}

func placedOrigin(
  for childSize: LayoutSize,
  at position: LayoutPoint,
  anchor: Alignment
) -> LayoutPoint {
  let dimensions = ViewDimensions(width: childSize.width, height: childSize.height)
  let xOffset =
    if anchor.horizontal == .center {
      (childSize.width + 1) / 2
    } else {
      dimensions[anchor.horizontal]
    }
  let yOffset =
    if anchor.vertical == .center {
      (childSize.height + 1) / 2
    } else {
      dimensions[anchor.vertical]
    }

  return LayoutPoint(
    x: position.x - xOffset,
    y: position.y - yOffset
  )
}
