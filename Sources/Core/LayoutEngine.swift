/// A retained cache of measured subtrees keyed by identity and proposal.
// SAFETY: Stores only Sendable data (MeasurementKey, MeasurementInput, MeasuredNode) but has
// unsynchronized mutable state (storage dict, counters). Only accessed from the layout engine
// during a single frame's layout pass on one thread. Never shared across concurrent contexts.
public final class MeasurementCache: @unchecked Sendable {
  private struct MeasurementKey: Hashable, Sendable {
    let identity: Identity
    let proposal: ProposedSize
  }

  private struct CachedMeasurement: Sendable {
    let resolved: ResolvedNode
    let node: MeasuredNode
  }

  private var storage: [MeasurementKey: CachedMeasurement] = [:]
  private var generation = 0
  private var lookups = 0
  private var hits = 0
  private var misses = 0
  private var stores = 0

  /// Creates an empty measurement cache.
  public init() {}

  /// The number of cached entries.
  public var count: Int {
    storage.count
  }

  /// Snapshot metrics describing cache usage.
  public var metrics: MeasurementCacheMetrics {
    MeasurementCacheMetrics(
      generation: generation,
      entries: storage.count,
      lookups: lookups,
      hits: hits,
      misses: misses,
      stores: stores
    )
  }

  /// Returns a cached measurement for `resolved` and `proposal` when the
  /// structural inputs still match.
  public func lookup(
    resolved: ResolvedNode,
    proposal: ProposedSize
  ) -> MeasuredNode? {
    lookups += 1
    let key = MeasurementKey(identity: resolved.identity, proposal: proposal)
    guard let cached = storage[key] else {
      misses += 1
      return nil
    }
    guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
      misses += 1
      return nil
    }
    hits += 1
    return cached.node
  }

  /// Stores `node` as the cached measurement for `resolved`.
  public func store(
    _ node: MeasuredNode,
    for resolved: ResolvedNode
  ) {
    stores += 1
    storage[MeasurementKey(identity: node.identity, proposal: node.proposal)] = CachedMeasurement(
      resolved: resolved,
      node: node
    )
  }

  /// Clears the cache and advances its generation counter.
  public func reset() {
    generation += 1
    storage.removeAll(keepingCapacity: true)
    lookups = 0
    hits = 0
    misses = 0
    stores = 0
  }
}

/// Measures and places resolved nodes under SwiftUI-style layout rules.
public struct LayoutEngine {
  public let cache: MeasurementCache?

  /// Creates a layout engine with an optional retained measurement cache.
  public init(cache: MeasurementCache? = nil) {
    self.cache = cache
  }

  /// Measures a resolved tree under `proposal`.
  public func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> MeasuredNode {
    measure(
      resolved,
      proposal: proposal,
      passContext: nil
    )
  }

  package func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    if let retained = retainedMeasurement(
      for: resolved,
      proposal: proposal,
      retainedLayout: passContext?.retainedLayout
    ) {
      passContext?.workMetrics.measuredNodesReused += countMeasuredNodes(retained)
      return retained
    }

    if let cached = cache?.lookup(resolved: resolved, proposal: proposal) {
      passContext?.workMetrics.measuredNodesReused += countMeasuredNodes(cached)
      return cached
    }

    passContext?.workMetrics.measuredNodesComputed += 1

    let effectiveProposal = proposalApplyingFixedSizeMetadata(
      resolved.layoutMetadata,
      to: proposal
    )
    let childMeasurements = measureChildren(
      for: resolved,
      parentProposal: effectiveProposal,
      passContext: passContext
    )
    let clampingProposal = clampingProposal(
      for: resolved,
      effectiveProposal: effectiveProposal
    )
    let node = MeasuredNode(
      identity: resolved.identity,
      proposal: proposal,
      measuredSize: clampedSize(
        measuredSize(
          for: resolved,
          childMeasurements: childMeasurements,
          proposal: effectiveProposal,
          passContext: passContext
        ),
        proposal: clampingProposal
      ),
      childMeasurements: childMeasurements,
      containerAllocationSnapshot: containerAllocationSnapshot(
        for: resolved,
        childMeasurements: childMeasurements,
        proposal: effectiveProposal,
        passContext: passContext
      )
    )
    cache?.store(node, for: resolved)
    return node
  }

  /// Places a measured tree at `origin`.
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: Point = .zero
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: Rect(origin: origin, size: measured.measuredSize),
      passContext: nil
    )
  }

  /// Places a measured tree inside `bounds`.
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: Point = .zero,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: Rect(origin: origin, size: measured.measuredSize),
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    if let retained = retainedPlacement(
      for: resolved,
      measured: measured,
      bounds: bounds,
      retainedLayout: passContext?.retainedLayout
    ) {
      passContext?.workMetrics.placedNodesReused += countPlacedNodes(retained)
      return retained
    }

    passContext?.workMetrics.placedNodesComputed += 1

    if resolved.children.isEmpty {
      return placedNode(
        from: resolved,
        bounds: bounds,
        children: []
      )
    }

    let placedChildren = childPlacements(
      for: resolved,
      measured: measured,
      in: bounds,
      passContext: passContext
    )

    return placedNode(
      from: resolved,
      bounds: bounds,
      children: placedChildren
    )
  }

  public func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> ViewDimensions {
    let measured = measure(resolved, proposal: proposal)
    return viewDimensions(for: resolved, measured: measured)
  }

  // MARK: - Measurement dispatch

  private func measureChildren(
    for resolved: ResolvedNode,
    parentProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    switch resolved.layoutBehavior {
    case .intrinsic, .overlay:
      return resolved.children.map { child in
        measure(child, proposal: parentProposal, passContext: passContext)
      }
    case .stack(
      let axis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      return measureStackChildren(
        for: resolved,
        parentProposal: parentProposal,
        axis: axis,
        spacing: spacing,
        passContext: passContext
      )
    case .padding(let insets):
      let childProposal = inset(parentProposal, by: insets)
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .frame(let width, let height, _):
      let childProposal = ProposedSize(
        width: width.map(ProposedDimension.finite) ?? parentProposal.width,
        height: height.map(ProposedDimension.finite) ?? parentProposal.height
      )
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let childProposal = ProposedSize(
        width: flexibleFrameChildProposalDimension(
          proposal: parentProposal.width,
          min: minW,
          ideal: idealW,
          max: maxW
        ),
        height: flexibleFrameChildProposalDimension(
          proposal: parentProposal.height,
          min: minH,
          ideal: idealH,
          max: maxH
        )
      )
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .decoration(let primaryIndex, _):
      guard resolved.children.indices.contains(primaryIndex) else {
        return resolved.children.map { child in
          measure(child, proposal: parentProposal, passContext: passContext)
        }
      }

      var measuredChildren = [MeasuredNode?](repeating: nil, count: resolved.children.count)
      let primaryMeasurement = measure(
        resolved.children[primaryIndex],
        proposal: parentProposal,
        passContext: passContext
      )
      measuredChildren[primaryIndex] = primaryMeasurement

      let decorationProposal = ProposedSize(
        width: primaryMeasurement.measuredSize.width,
        height: primaryMeasurement.measuredSize.height
      )

      for index in resolved.children.indices where index != primaryIndex {
        measuredChildren[index] = measure(
          resolved.children[index],
          proposal: decorationProposal,
          passContext: passContext
        )
      }

      return measuredChildren.compactMap { $0 }
    case .viewThatFits:
      return resolved.children.map { child in
        measure(child, proposal: parentProposal, passContext: passContext)
      }
    case .custom(let handle):
      return handle.proxy.measureChildren(
        engine: self,
        node: resolved,
        proposal: parentProposal
      )
    }
  }

  // MARK: - Size computation

  private func measuredSize(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> Size {
    switch resolved.layoutBehavior {
    case .intrinsic:
      switch resolved.drawPayload {
      case .text(let content):
        return measuredTextSize(
          for: content,
          metadata: resolved.layoutMetadata,
          proposal: proposal
        )
      case .richText(let payload):
        return measuredTextSize(
          for: payload.visibleText,
          metadata: resolved.layoutMetadata,
          proposal: proposal
        )
      case .image(let payload):
        return measuredImageSize(
          for: payload,
          proposal: proposal
        )
      case .list(let payload):
        return measuredListSize(
          for: payload,
          proposal: proposal
        )
      case .table(let payload):
        return measuredTableSize(
          for: payload,
          proposal: proposal
        )
      case .shape:
        return measuredShapeSize(for: proposal)
      case .rule:
        return measuredRuleSize(for: proposal)
      case .none:
        break
      }
      if let intrinsicSize = resolved.intrinsicSize {
        return intrinsicSize
      }
      return overlaySize(from: childMeasurements)
    case .overlay(let alignment):
      let alignmentMetrics = overlayAlignmentMetrics(
        for: resolved.children,
        childMeasurements: childMeasurements,
        alignment: alignment
      )
      return Size(
        width: alignmentMetrics.leading + alignmentMetrics.trailing,
        height: alignmentMetrics.top + alignmentMetrics.bottom
      )
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      let stackSpacings = resolvedStackSpacings(
        for: resolved.children,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: resolved.children,
        childMeasurements: childMeasurements,
        axis: .vertical,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center
      )
      let contentHeight = childMeasurements.reduce(0) { $0 + $1.measuredSize.height }
      let totalSpacing = stackSpacings.reduce(0, +)
      return Size(
        width: crossMetrics.leading + crossMetrics.trailing,
        height: contentHeight + totalSpacing
      )
    case .stack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      let stackSpacings = resolvedStackSpacings(
        for: resolved.children,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: resolved.children,
        childMeasurements: childMeasurements,
        axis: .horizontal,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment
      )
      let totalWidth = childMeasurements.reduce(0) { $0 + $1.measuredSize.width }
      let totalSpacing = stackSpacings.reduce(0, +)
      return Size(
        width: totalWidth + totalSpacing,
        height: crossMetrics.leading + crossMetrics.trailing
      )
    case .padding(let insets):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return Size(
        width: contentSize.width + insets.horizontal,
        height: contentSize.height + insets.vertical
      )
    case .frame(let width, let height, _):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return Size(
        width: width ?? contentSize.width,
        height: height ?? contentSize.height
      )
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return Size(
        width: flexibleFrameMeasuredDimension(
          proposal: proposal.width,
          child: contentSize.width,
          min: minW,
          ideal: idealW,
          max: maxW
        ),
        height: flexibleFrameMeasuredDimension(
          proposal: proposal.height,
          child: contentSize.height,
          min: minH,
          ideal: idealH,
          max: maxH
        )
      )
    case .decoration(let primaryIndex, _):
      guard childMeasurements.indices.contains(primaryIndex) else {
        return overlaySize(from: childMeasurements)
      }
      return childMeasurements[primaryIndex].measuredSize
    case .viewThatFits(let axes):
      guard
        let selectedIndex = selectedChildIndex(
          for: resolved,
          proposal: proposal,
          axes: axes,
          passContext: passContext
        ), childMeasurements.indices.contains(selectedIndex)
      else {
        return .zero
      }
      return childMeasurements[selectedIndex].measuredSize
    case .custom(let handle):
      return handle.proxy.measureContainer(
        engine: self,
        node: resolved,
        proposal: proposal
      )
    }
  }

  private func finiteValue(_ dim: ProposedDimension?) -> Int? {
    guard case .finite(let v) = dim else { return nil }
    return v
  }

  private func hasFlexibleConstraint(
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Bool {
    min != nil || ideal != nil || max != nil
  }

  private func flexibleFrameChildProposalDimension(
    proposal: ProposedDimension,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> ProposedDimension {
    guard hasFlexibleConstraint(min: min, ideal: ideal, max: max) else {
      return proposal
    }

    return .finite(
      resolveFlexibleDimension(
        proposal: proposal,
        min: min,
        ideal: ideal,
        max: max
      )
    )
  }

  private func flexibleFrameMeasuredDimension(
    proposal: ProposedDimension,
    child: Int,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Int {
    guard hasFlexibleConstraint(min: min, ideal: ideal, max: max) else {
      return child
    }

    return resolveFlexibleDimension(
      proposal: proposal,
      min: min,
      ideal: ideal,
      max: max
    )
  }

  private func resolveFlexibleDimension(
    proposal: ProposedDimension,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Int {
    let minVal = finiteValue(min)
    let idealVal = finiteValue(ideal)
    let maxVal = finiteValue(max)

    let raw: Int
    switch proposal {
    case .unspecified:
      raw = idealVal ?? minVal ?? 0
    case .finite(let n):
      raw = n
    case .infinity:
      raw = maxVal ?? idealVal ?? minVal ?? 0
    }

    var result = raw
    if let lo = minVal { result = Swift.max(lo, result) }
    if let hi = maxVal { result = Swift.min(hi, result) }
    return result
  }

  private func overlaySize(from childMeasurements: [MeasuredNode]) -> Size {
    Size(
      width: childMeasurements.map { $0.measuredSize.width }.max() ?? 0,
      height: childMeasurements.map { $0.measuredSize.height }.max() ?? 0
    )
  }

  // MARK: - Intrinsic size helpers

  private func measuredTextSize(
    for content: String,
    metadata: LayoutMetadata,
    proposal: ProposedSize
  ) -> Size {
    let wrapWidth: Int? =
      switch proposal.width {
      case .finite(let width):
        width
      case .unspecified, .infinity:
        nil
      }
    return layoutText(
      for: content,
      width: wrapWidth,
      lineLimit: metadata.lineLimit,
      truncationMode: metadata.textTruncationMode ?? .tail,
      wrappingStrategy: metadata.textWrappingStrategy ?? .wordBoundary
    ).size
  }

  private func measuredRuleSize(
    for proposal: ProposedSize
  ) -> Size {
    let proposedWidth = finiteDimension(of: proposal.width)
    let proposedHeight = finiteDimension(of: proposal.height)

    switch (proposedWidth, proposedHeight) {
    case (let width?, nil):
      return Size(width: max(0, width), height: width > 0 ? 1 : 0)
    case (nil, let height?):
      return Size(width: height > 0 ? 1 : 0, height: max(0, height))
    case (let width?, let height?):
      if width >= height {
        return Size(width: max(0, width), height: height > 0 ? 1 : 0)
      }
      return Size(width: width > 0 ? 1 : 0, height: max(0, height))
    case (nil, nil):
      return Size(width: 1, height: 1)
    }
  }

  private func measuredShapeSize(
    for proposal: ProposedSize
  ) -> Size {
    Size(
      width: finiteDimension(of: proposal.width) ?? 0,
      height: finiteDimension(of: proposal.height) ?? 0
    )
  }

  private func measuredImageSize(
    for payload: ImagePayload,
    proposal: ProposedSize
  ) -> Size {
    let intrinsicSize = payload.intrinsicCellSize
    guard payload.isResizable else {
      return intrinsicSize
    }

    let proposedWidth = finiteDimension(of: proposal.width)
    let proposedHeight = finiteDimension(of: proposal.height)

    switch payload.scalingMode {
    case .stretch:
      return Size(
        width: proposedWidth ?? intrinsicSize.width,
        height: proposedHeight ?? intrinsicSize.height
      )
    case .fit, .fill:
      guard
        let pixelSize = payload.resolvedAsset?.pixelSize,
        pixelSize.width > 0,
        pixelSize.height > 0
      else {
        return Size(
          width: proposedWidth ?? intrinsicSize.width,
          height: proposedHeight ?? intrinsicSize.height
        )
      }

      let aspectRatio = Double(pixelSize.width) / Double(pixelSize.height)

      switch (proposedWidth, proposedHeight) {
      case (let width?, let height?):
        guard width > 0, height > 0 else {
          return .zero
        }
        let widthScale = Double(width) / Double(pixelSize.width)
        let heightScale = Double(height) / Double(pixelSize.height)
        let scale =
          payload.scalingMode == .fit
          ? min(widthScale, heightScale)
          : max(widthScale, heightScale)
        return Size(
          width: max(1, Int((Double(pixelSize.width) * scale).rounded(.up))),
          height: max(1, Int((Double(pixelSize.height) * scale).rounded(.up)))
        )
      case (let width?, nil):
        guard width > 0 else {
          return .zero
        }
        return Size(
          width: width,
          height: max(1, Int((Double(width) / aspectRatio).rounded(.up)))
        )
      case (nil, let height?):
        guard height > 0 else {
          return .zero
        }
        return Size(
          width: max(1, Int((Double(height) * aspectRatio).rounded(.up))),
          height: height
        )
      case (nil, nil):
        return intrinsicSize
      }
    }
  }

  // MARK: - Retained layout

  private func retainedMeasurement(
    for resolved: ResolvedNode,
    proposal: ProposedSize,
    retainedLayout: RetainedLayoutSession?
  ) -> MeasuredNode? {
    guard let retainedLayout,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.containsInvalidatedDescendant(of: resolved.identity),
      supportsRetainedLayoutReuse(for: resolved),
      let previousResolved = retainedLayout.resolvedNode(for: resolved.identity),
      let previousMeasured = retainedLayout.measuredNode(for: resolved.identity),
      previousMeasured.proposal == proposal,
      previousResolved.isEquivalentForMeasurement(to: resolved)
    else {
      return nil
    }

    return previousMeasured
  }

  private func retainedPlacement(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    bounds: Rect,
    retainedLayout: RetainedLayoutSession?
  ) -> PlacedNode? {
    guard let retainedLayout,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.containsInvalidatedDescendant(of: resolved.identity),
      supportsRetainedLayoutReuse(for: resolved),
      let previousResolved = retainedLayout.resolvedNode(for: resolved.identity),
      let previousMeasured = retainedLayout.measuredNode(for: resolved.identity),
      let previousPlaced = retainedLayout.placedNode(for: resolved.identity),
      previousResolved.isEquivalentForMeasurement(to: resolved),
      previousMeasured == measured,
      previousPlaced.bounds == bounds
    else {
      return nil
    }

    return previousPlaced
  }

  private func supportsRetainedLayoutReuse(
    for resolved: ResolvedNode
  ) -> Bool {
    switch resolved.layoutBehavior {
    case .viewThatFits, .custom:
      return false
    default:
      return resolved.children.allSatisfy { supportsRetainedLayoutReuse(for: $0) }
    }
  }

  private func countMeasuredNodes(
    _ node: MeasuredNode
  ) -> Int {
    1 + node.childMeasurements.reduce(0) { $0 + countMeasuredNodes($1) }
  }

  private func countPlacedNodes(
    _ node: PlacedNode
  ) -> Int {
    1 + node.children.reduce(0) { $0 + countPlacedNodes($1) }
  }

  // MARK: - Inset helpers

  private func inset(
    _ proposal: ProposedSize,
    by insets: EdgeInsets
  ) -> ProposedSize {
    ProposedSize(
      width: inset(proposal.width, by: insets.horizontal),
      height: inset(proposal.height, by: insets.vertical)
    )
  }

  private func inset(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      return .unspecified
    case .infinity:
      return .infinity
    case .finite(let value):
      return .finite(max(0, value - amount))
    }
  }
}
