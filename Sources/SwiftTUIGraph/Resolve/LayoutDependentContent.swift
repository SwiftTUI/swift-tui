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

/// The geometry available when layout realizes a layout-realized content boundary.
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
    withCheckedMainActorAccess("LayoutDependentContentHandle.debugName") {
      realizer.debugName
    }
  }

  package func realize(
    in context: LayoutRealizationContext
  ) -> [ResolvedNode] {
    withCheckedMainActorAccess("LayoutDependentContentHandle.realize(in:)") {
      realizer.realize(in: context)
    }
  }
}

package struct LayoutRealizedContentBoundary: Sendable {
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

package typealias LayoutRealizationGeometry = LayoutRealizationContext

extension ResolvedNode {
  package func applyingLayoutDependentRealizations(
    _ realizations: [Identity: [ResolvedNode]]
  ) -> ResolvedNode {
    realizationApplication(realizations).node
  }

  /// The realized tree, and the preference keys the rewrite re-folded on the
  /// way up: those the replaced and the realized children carry.
  private func realizationApplication(
    _ realizations: [Identity: [ResolvedNode]]
  ) -> (node: ResolvedNode, refoldedKeys: Set<ObjectIdentifier>) {
    var copy = self
    if copy.layoutRealizedContent != nil {
      let realized = realizations[copy.identity] ?? []
      let keys = Self.preferenceKeys(of: copy.children).union(Self.preferenceKeys(of: realized))
      copy.replaceChildren(realized, refoldingPreferenceKeys: keys)
      return (copy, keys)
    }
    guard copy.children.contains(where: { $0.containsLayoutRealizedContent }) else {
      return (copy, [])
    }
    var keys: Set<ObjectIdentifier> = []
    let children = copy.children.map { child in
      let applied = child.realizationApplication(realizations)
      keys.formUnion(applied.refoldedKeys)
      return applied.node
    }
    copy.replaceChildren(children, refoldingPreferenceKeys: keys)
    return (copy, keys)
  }

  package func layoutRealizationWorkerSnapshot(
    using realizations: [Identity: [ResolvedNode]]
  ) -> ResolvedNode? {
    let snapshot = layoutRealizationWorkerSnapshotResult(using: realizations)
    return snapshot.changed ? snapshot.node : nil
  }

  private func layoutRealizationWorkerSnapshotResult(
    using realizations: [Identity: [ResolvedNode]]
  ) -> (node: ResolvedNode, changed: Bool, refoldedKeys: Set<ObjectIdentifier>) {
    var copy = self

    if let boundary = copy.layoutRealizedContent,
      let realizedChildren = realizations[copy.identity],
      realizedChildren.count == 1
    {
      let snapshotChildren = realizedChildren.map {
        $0.layoutRealizationWorkerSnapshotResult(using: realizations).node
      }
      let keys = Self.preferenceKeys(of: copy.children).union(
        Self.preferenceKeys(of: snapshotChildren))
      copy.layoutRealizedContent = nil
      copy.layoutBehavior = boundary.sizingPolicy.workerSnapshotLayoutBehavior
      copy.replaceChildren(snapshotChildren, refoldingPreferenceKeys: keys)
      return (copy, true, keys)
    }

    var changed = false
    var keys: Set<ObjectIdentifier> = []
    let snapshotChildren = copy.children.map { child in
      let snapshot = child.layoutRealizationWorkerSnapshotResult(using: realizations)
      changed = changed || snapshot.changed
      keys.formUnion(snapshot.refoldedKeys)
      return snapshot.node
    }
    if changed {
      copy.replaceChildren(snapshotChildren, refoldingPreferenceKeys: keys)
    }
    return (copy, changed, keys)
  }

  /// Replaces `children` with a frame-tail rewrite of them (a realization or
  /// its worker snapshot) and re-folds only `refoldedKeys`.
  ///
  /// `preferenceValues` is the fold of the children plus this node's own
  /// declarations: a `.preference` modifier's value, or a `TabView`'s
  /// departing-tab archive refresh request. The `children` setter re-derives
  /// every key from the children alone, which drops those declarations
  /// (STUI-1237: the arriving tab's `GeometryReader` cost the departing tab its
  /// archive refresh). For a key no rewritten child carries, before or after,
  /// the fold below is unchanged, so the resolved value stays exact. A key the
  /// rewritten children carry is re-folded from them as before.
  private mutating func replaceChildren(
    _ newChildren: [ResolvedNode],
    refoldingPreferenceKeys refoldedKeys: Set<ObjectIdentifier>
  ) {
    let resolvedPreferences = preferenceValues
    children = newChildren
    preferenceValues = resolvedPreferences.replacingEntries(
      for: refoldedKeys, from: preferenceValues)
  }

  private static func preferenceKeys(of nodes: [ResolvedNode]) -> Set<ObjectIdentifier> {
    nodes.reduce(into: Set<ObjectIdentifier>()) { $0.formUnion($1.preferenceValues.keyIdentifiers) }
  }

  private var containsLayoutRealizedContent: Bool {
    if layoutRealizedContent != nil {
      return true
    }
    return children.contains { $0.containsLayoutRealizedContent }
  }
}

extension LayoutDependentContentSizingPolicy {
  fileprivate var workerSnapshotLayoutBehavior: LayoutBehavior {
    switch self {
    case .fillsProposal(let unspecifiedIdeal):
      return .flexibleFrame(
        minWidth: nil,
        idealWidth: .finite(unspecifiedIdeal.width),
        maxWidth: .infinity,
        minHeight: nil,
        idealHeight: .finite(unspecifiedIdeal.height),
        maxHeight: .infinity,
        alignment: .topLeading
      )
    }
  }
}
