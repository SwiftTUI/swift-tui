import SwiftTUICore

/// Menu owns source-relative placement independently of the sheet host.
package struct HostedMenuPresentation: View {
  package var item: PromptPresentationItem

  package var body: some View {
    MenuPlacementLayout(sourceIdentity: item.portalEntryID.sourceIdentity) {
      PortalSurfaceRoot(item: item)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct MenuPlacementLayout: Layout {
  var sourceIdentity: Identity

  func sizeThatFits(
    proposal: ProposedViewSize, subviews _: LayoutSubviews, cache _: inout Void
  ) -> LayoutSize {
    LayoutSize(
      width: menuHostLength(proposal.width),
      height: menuHostLength(proposal.height))
  }

  func placeSubviews(
    in bounds: LayoutRect, proposal _: ProposedViewSize,
    subviews: LayoutSubviews, cache _: inout Void
  ) {
    guard let surface = subviews.first else { return }
    let ideal = surface.sizeThatFits(.unspecified)
    let size = LayoutSize(
      width: min(ideal.width, max(0, bounds.size.width)),
      height: min(ideal.height, max(0, bounds.size.height)))
    // Placement runs after the source and deliberately has no reuse signature:
    // retained menu content must follow a moved or scrolled trigger immediately.
    let source =
      surface.renderedFrame(for: sourceIdentity)
      ?? CellRect(origin: bounds.origin, size: .init(width: 0, height: 0))
    let below = source.origin.y + source.size.height
    let above = source.origin.y - size.height
    let preferredY =
      below + size.height <= bounds.origin.y + bounds.size.height
      ? below : above
    let origin = LayoutPoint(
      x: min(
        max(source.origin.x, bounds.origin.x),
        bounds.origin.x + max(0, bounds.size.width - size.width)),
      y: min(
        max(preferredY, bounds.origin.y),
        bounds.origin.y + max(0, bounds.size.height - size.height)))
    surface.place(
      at: origin, anchor: .topLeading,
      proposal: .init(width: size.width, height: size.height))
  }
}

private func menuHostLength(_ dimension: ProposedDimension) -> Int {
  switch dimension {
  case .finite(let value): max(0, value)
  case .infinity, .unspecified: 10
  }
}
