/// Sizing policies for content that is authored during resolve but realized
/// only after layout has concrete geometry.
package enum LayoutDependentContentSizingPolicy: Equatable, Sendable {
  case fillsProposal(unspecifiedIdeal: CellSize)

  package func measuredSize(for proposal: ProposedSize) -> CellSize {
    switch self {
    case .fillsProposal(let unspecifiedIdeal):
      return CellSize(
        width: measuredDimension(proposal.width, ideal: unspecifiedIdeal.width),
        height: measuredDimension(proposal.height, ideal: unspecifiedIdeal.height)
      )
    }
  }

  private func measuredDimension(
    _ dimension: ProposedDimension,
    ideal: Int
  ) -> Int {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .unspecified, .infinity:
      return max(0, ideal)
    }
  }
}

/// The geometry available when layout realizes a deferred content boundary.
package struct LayoutRealizationContext: Equatable, Sendable {
  package var boundaryIdentity: Identity
  package var proposal: ProposedSize
  package var bounds: CellRect
  package var safeAreaInsets: EdgeInsets
  package var cellPixelMetrics: CellPixelMetrics
  package var pointerInputCapabilities: PointerInputCapabilities
  package var placedFrameTable: PlacedFrameTable

  package init(
    boundaryIdentity: Identity,
    proposal: ProposedSize,
    bounds: CellRect,
    safeAreaInsets: EdgeInsets,
    cellPixelMetrics: CellPixelMetrics,
    pointerInputCapabilities: PointerInputCapabilities,
    placedFrameTable: PlacedFrameTable = .init()
  ) {
    self.boundaryIdentity = boundaryIdentity
    self.proposal = proposal
    self.bounds = bounds
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
    self.pointerInputCapabilities = pointerInputCapabilities
    self.placedFrameTable = placedFrameTable
  }
}

package struct LayoutDependentContentSignature: Equatable, Sendable {
  package var boundaryIdentity: Identity
  package var proposal: ProposedSize
  package var bounds: CellRect
  package var safeAreaInsets: EdgeInsets
  package var cellPixelMetrics: CellPixelMetrics
  package var pointerInputCapabilities: PointerInputCapabilities
  package var placedFrameTable: PlacedFrameTable

  package init(_ context: LayoutRealizationContext) {
    boundaryIdentity = context.boundaryIdentity
    proposal = context.proposal
    bounds = context.bounds
    safeAreaInsets = context.safeAreaInsets
    cellPixelMetrics = context.cellPixelMetrics
    pointerInputCapabilities = context.pointerInputCapabilities
    placedFrameTable = context.placedFrameTable
  }
}

package struct LayoutDependentContentRealization: Sendable {
  package var signature: LayoutDependentContentSignature
  package var children: [ResolvedNode]

  package init(
    signature: LayoutDependentContentSignature,
    children: [ResolvedNode]
  ) {
    self.signature = signature
    self.children = children
  }
}

@MainActor
package protocol LayoutDependentContentRealizer: AnyObject, Sendable {
  var debugName: String { get }

  func realize(in context: LayoutRealizationContext) -> [ResolvedNode]
}

/// A layout-callable handle that realizes authored content once concrete
/// geometry is known.
package final class LayoutDependentContentHandle: Sendable {
  private let realizer: any LayoutDependentContentRealizer

  package init(
    _ realizer: any LayoutDependentContentRealizer
  ) {
    self.realizer = realizer
  }

  package var debugName: String {
    MainActor.assumeIsolated {
      realizer.debugName
    }
  }

  package func realize(
    in context: LayoutRealizationContext
  ) -> [ResolvedNode] {
    MainActor.assumeIsolated {
      realizer.realize(in: context)
    }
  }
}

package struct LayoutDependentContentBoundary: Sendable {
  package var identity: Identity
  package var sizingPolicy: LayoutDependentContentSizingPolicy
  package var safeAreaInsets: EdgeInsets
  package var cellPixelMetrics: CellPixelMetrics
  package var pointerInputCapabilities: PointerInputCapabilities
  package var debugName: String
  package var handle: LayoutDependentContentHandle

  package init(
    identity: Identity,
    sizingPolicy: LayoutDependentContentSizingPolicy,
    safeAreaInsets: EdgeInsets,
    cellPixelMetrics: CellPixelMetrics,
    pointerInputCapabilities: PointerInputCapabilities,
    debugName: String,
    handle: LayoutDependentContentHandle
  ) {
    self.identity = identity
    self.sizingPolicy = sizingPolicy
    self.safeAreaInsets = safeAreaInsets
    self.cellPixelMetrics = cellPixelMetrics
    self.pointerInputCapabilities = pointerInputCapabilities
    self.debugName = debugName
    self.handle = handle
  }

  package var equivalenceSignature: String {
    "\(identity.path)#\(debugName)#\(sizingPolicy)"
  }
}

extension ResolvedNode {
  package func applyingLayoutDependentRealizations(
    _ realizations: [Identity: [ResolvedNode]]
  ) -> ResolvedNode {
    var copy = self
    if copy.layoutDependentContent != nil {
      copy.children = realizations[copy.identity] ?? []
      return copy
    }
    guard copy.children.contains(where: { $0.containsLayoutDependentContent }) else {
      return copy
    }
    copy.children = copy.children.map {
      $0.applyingLayoutDependentRealizations(realizations)
    }
    return copy
  }

  private var containsLayoutDependentContent: Bool {
    if layoutDependentContent != nil {
      return true
    }
    return children.contains { $0.containsLayoutDependentContent }
  }
}
