import SwiftTUIRuntime

// The split layout for a workspace node.
//
// `TerminalWorkspaceSplitLayout` places two subviews side by side (or stacked)
// according to a `TerminalSplitAxis` and a split `fraction`, reusing
// `TerminalWorkspaceLayout.splitRects` so the live layout matches the
// workspace model's own geometry.
//
// Split out of `TerminalWorkspaceView.swift` so that file stays focused on the
// `TerminalWorkspaceView` view and its pane/tab subviews. Widened from
// `private` to file-internal so `TerminalWorkspaceNodeView` can still
// construct it across files.

struct TerminalWorkspaceSplitLayout: Layout {
  var axis: TerminalSplitAxis
  var fraction: Double

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard !subviews.isEmpty else {
      return .zero
    }

    let width =
      finiteDimension(proposal.width)
      ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
      ?? 0
    let height =
      finiteDimension(proposal.height)
      ?? subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }.max()
      ?? 0
    return LayoutSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard subviews.count >= 2 else {
      subviews.first?.place(
        at: bounds.origin,
        anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.size.width, height: bounds.size.height)
      )
      return
    }

    let split = TerminalSplit(
      axis: axis,
      fraction: fraction,
      first: .terminal(
        TerminalPaneSpec(id: "__layout-first", title: "", command: "")
      ),
      second: .terminal(
        TerminalPaneSpec(id: "__layout-second", title: "", command: "")
      )
    )
    let rects = TerminalWorkspaceLayout.splitRects(
      for: split,
      in: CellRect(origin: CellPoint(x: bounds.origin.x, y: bounds.origin.y), size: bounds.size)
    )

    subviews[0].place(
      at: rects.first.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(width: rects.first.size.width, height: rects.first.size.height)
    )
    subviews[1].place(
      at: rects.second.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(width: rects.second.size.width, height: rects.second.size.height)
    )
  }

  private func finiteDimension(_ dimension: ProposedDimension) -> Int? {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .infinity, .unspecified:
      return nil
    }
  }
}
