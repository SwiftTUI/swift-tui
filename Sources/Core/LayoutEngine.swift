import DequeModule
import Synchronization

/// A retained cache of measured subtrees keyed by identity and proposal.
public final class MeasurementCache: Sendable {
  private struct CachedMeasurement: Sendable {
    let resolved: ResolvedNode
    let node: MeasuredNode
    let generation: UInt64
  }

  private struct AccessRecord: Sendable {
    let proposal: ProposedSize
    let generation: UInt64
  }

  private struct IdentityStorage {
    var entries: [ProposedSize: CachedMeasurement] = [:]
    var order: Deque<AccessRecord> = []
  }

  private static let maxProposalVariantsPerIdentity = 4

  private struct Storage {
    var entriesByIdentity: [Identity: IdentityStorage] = [:]
    var entryCount = 0
    var epochGeneration = 0
    var accessGeneration: UInt64 = 0
    var lookups = 0
    var hits = 0
    var misses = 0
    var invalidations = 0
    var stores = 0
  }

  private let storage: Mutex<Storage> = .init(.init())

  /// Creates an empty measurement cache.
  public init() {}

  /// The number of cached entries.
  public var count: Int {
    storage.withLock { $0.entryCount }
  }

  /// Snapshot metrics describing cache usage.
  public var metrics: MeasurementCacheMetrics {
    storage.withLock { storage in
      MeasurementCacheMetrics(
        generation: storage.epochGeneration,
        entries: storage.entryCount,
        lookups: storage.lookups,
        hits: storage.hits,
        misses: storage.misses,
        invalidations: storage.invalidations,
        stores: storage.stores
      )
    }
  }

  /// Returns a cached measurement for `resolved` and `proposal` when the
  /// structural inputs still match.
  public func lookup(
    resolved: ResolvedNode,
    proposal: ProposedSize
  ) -> MeasuredNode? {
    storage.withLock { storage in
      storage.lookups += 1
      guard var identityStorage = storage.entriesByIdentity[resolved.identity] else {
        storage.misses += 1
        return nil
      }

      guard let cached = identityStorage.entries[proposal] else {
        storage.entriesByIdentity[resolved.identity] = identityStorage
        storage.misses += 1
        return nil
      }

      // Verify equivalence before touching LRU bookkeeping.  If the cached
      // entry is stale we evict it here so subsequent lookups don't keep
      // re-fetching and re-rejecting the same mismatching cache line.
      guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
        identityStorage.entries.removeValue(forKey: proposal)
        storage.entryCount -= 1
        if identityStorage.entries.isEmpty {
          storage.entriesByIdentity.removeValue(forKey: resolved.identity)
        } else {
          storage.entriesByIdentity[resolved.identity] = identityStorage
        }
        storage.invalidations += 1
        return nil
      }

      let generation = nextGeneration(in: &storage)
      identityStorage.entries[proposal] = .init(
        resolved: cached.resolved,
        node: cached.node,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)
      storage.entriesByIdentity[resolved.identity] = identityStorage
      storage.hits += 1
      return cached.node
    }
  }

  /// Stores `node` as the cached measurement for `resolved`.
  public func store(
    _ node: MeasuredNode,
    for resolved: ResolvedNode
  ) {
    storage.withLock { storage in
      storage.stores += 1
      var identityStorage = storage.entriesByIdentity[node.identity] ?? .init()
      let generation = nextGeneration(in: &storage)

      if identityStorage.entries[node.proposal] == nil {
        storage.entryCount += 1
      }

      identityStorage.entries[node.proposal] = CachedMeasurement(
        resolved: resolved,
        node: node,
        generation: generation
      )
      identityStorage.order.append(.init(proposal: node.proposal, generation: generation))
      compactOrderIfNeeded(in: &identityStorage)
      let shouldKeepIdentity = evictIfNeeded(
        for: node.identity,
        in: &identityStorage,
        storage: &storage
      )
      if shouldKeepIdentity {
        storage.entriesByIdentity[node.identity] = identityStorage
      }
    }
  }

  package func prune(
    keeping identities: Set<Identity>
  ) {
    storage.withLock { storage in
      let retained = storage.entriesByIdentity.filter { identities.contains($0.key) }
      storage.entriesByIdentity = retained
      storage.entryCount = retained.reduce(0) { $0 + $1.value.entries.count }
    }
  }

  /// Clears the cache and advances its generation counter.
  public func reset() {
    storage.withLock { storage in
      storage.epochGeneration += 1
      storage.accessGeneration = 0
      storage.entriesByIdentity.removeAll(keepingCapacity: true)
      storage.entryCount = 0
      storage.lookups = 0
      storage.hits = 0
      storage.misses = 0
      storage.invalidations = 0
      storage.stores = 0
    }
  }

  private func nextGeneration(
    in storage: inout Storage
  ) -> UInt64 {
    storage.accessGeneration &+= 1
    return storage.accessGeneration
  }

  private func evictIfNeeded(
    for identity: Identity,
    in identityStorage: inout IdentityStorage,
    storage: inout Storage
  ) -> Bool {
    guard identityStorage.entries.count > Self.maxProposalVariantsPerIdentity else {
      return true
    }

    while identityStorage.entries.count > Self.maxProposalVariantsPerIdentity {
      guard let victim = identityStorage.order.popFirst() else {
        break
      }
      guard let cached = identityStorage.entries[victim.proposal] else {
        continue
      }
      guard cached.generation == victim.generation else {
        continue
      }

      identityStorage.entries.removeValue(forKey: victim.proposal)
      storage.entryCount -= 1
    }

    if identityStorage.entries.isEmpty {
      storage.entriesByIdentity.removeValue(forKey: identity)
      return false
    }

    return true
  }

  private func compactOrderIfNeeded(
    in identityStorage: inout IdentityStorage
  ) {
    guard !identityStorage.entries.isEmpty else {
      identityStorage.order.removeAll(keepingCapacity: true)
      return
    }

    let threshold = max(16, identityStorage.entries.count * 8)
    guard identityStorage.order.count > threshold else {
      return
    }

    var compacted: Deque<AccessRecord> = []
    let liveEntries = identityStorage.entries.sorted { lhs, rhs in
      lhs.value.generation < rhs.value.generation
    }
    for (proposal, entry) in liveEntries {
      compacted.append(.init(proposal: proposal, generation: entry.generation))
    }
    identityStorage.order = compacted
  }
}

/// Measures and places resolved nodes under SwiftUI-style layout rules.
public struct LayoutEngine: Sendable {
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
    let hasInvalidatedIndexedDescendant = hasInvalidatedIndexedDescendant(
      for: resolved,
      passContext: passContext
    )

    if let retained = retainedMeasurement(
      for: resolved,
      proposal: proposal,
      retainedLayout: passContext?.retainedLayout,
      hasInvalidatedIndexedDescendant: hasInvalidatedIndexedDescendant
    ) {
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += retained.subtreeNodeCount
      }
      return retained
    }

    if !hasInvalidatedIndexedDescendant,
      let cached = cache?.lookup(resolved: resolved, proposal: proposal)
    {
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += cached.subtreeNodeCount
      }
      return cached
    }

    passContext?.updateWorkMetrics {
      $0.measuredNodesComputed += 1
    }

    let effectiveProposal = proposalApplyingFixedSizeMetadata(
      resolved.layoutMetadata,
      to: proposal
    )
    let childMeasurements = measureChildren(
      for: resolved,
      parentProposal: effectiveProposal,
      passContext: passContext
    )
    let storedChildMeasurements = storedChildMeasurements(
      for: resolved,
      measuredChildren: childMeasurements
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
      childMeasurements: storedChildMeasurements,
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
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext? = nil
  ) -> PlacedNode {
    if let retained = retainedPlacement(
      for: resolved,
      measured: measured,
      bounds: bounds,
      viewportContext: viewportContext,
      retainedLayout: passContext?.retainedLayout
    ) {
      passContext?.updateWorkMetrics {
        $0.placedNodesReused += retained.subtreeNodeCount
      }
      return retained
    }

    passContext?.updateWorkMetrics {
      $0.placedNodesComputed += 1
    }

    let hasChildren =
      if let source = resolved.indexedChildSource {
        source.count > 0
      } else {
        !resolved.children.isEmpty
      }

    if !hasChildren {
      return placedNode(
        from: resolved,
        bounds: bounds,
        measured: measured,
        children: []
      )
    }

    let placedChildren = childPlacements(
      for: resolved,
      measured: measured,
      in: bounds,
      viewportContext: viewportContext,
      passContext: passContext
    )

    return placedNode(
      from: resolved,
      bounds: bounds,
      measured: measured,
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
    case .intrinsic, .overlay, .offset, .position:
      return resolved.children.map { child in
        measure(child, proposal: parentProposal, passContext: passContext)
      }
    case .stack(
      let axis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      return measureStackChildren(
        for: stackChildren(for: resolved),
        parentProposal: parentProposal,
        axis: axis,
        spacing: spacing,
        passContext: passContext
      )
    case .lazyStack(
      let axis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      return measureStackChildren(
        for: stackChildren(for: resolved),
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
    case .safeAreaIgnoring(let insets):
      let childProposal = outset(parentProposal, by: insets)
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      guard resolved.children.count >= 2 else {
        return resolved.children.map { child in
          measure(child, proposal: parentProposal, passContext: passContext)
        }
      }

      let insetProposal = safeAreaInsetAdornmentProposal(
        parentProposal,
        edge: edge
      )
      let insetMeasurement = measure(
        resolved.children[1],
        proposal: insetProposal,
        passContext: passContext
      )
      let consumedInsets = safeAreaInsetConsumedInsets(
        edge: edge,
        contentSize: insetMeasurement.measuredSize,
        spacing: spacing,
        safeArea: safeArea
      )
      let baseProposal = inset(parentProposal, by: consumedInsets)
      let baseMeasurement = measure(
        resolved.children[0],
        proposal: baseProposal,
        passContext: passContext
      )
      return [baseMeasurement, insetMeasurement]
    case .border(let set, _, _, _, _, let sides):
      let insets = borderLayoutInsets(set: set, sides: sides)
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
      case .textFigure(let payload):
        return measuredTextFigureSize(
          for: payload,
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
      case .canvas:
        // Canvas fills any proposed size, the same as a raw shape
        // primitive: the drawing is always resolved to the final cell
        // frame at paint time, so there's no intrinsic size.
        return measuredShapeSize(for: proposal)
      case .rule:
        return measuredRuleSize(
          for: proposal,
          stackAxis: resolved.drawMetadata.ruleStackAxis
        )
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
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
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
    case .lazyStack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
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
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
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
    case .lazyStack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
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
    case .safeAreaIgnoring:
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return Size(
        width: measuredDimension(
          proposal.width,
          fallback: contentSize.width
        ),
        height: measuredDimension(
          proposal.height,
          fallback: contentSize.height
        )
      )
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      let baseSize = childMeasurements.first?.measuredSize ?? .zero
      let insetSize = childMeasurements.dropFirst().first?.measuredSize ?? .zero
      let consumed = safeAreaInsetConsumedAmount(
        edge: edge,
        contentSize: insetSize,
        spacing: spacing,
        safeArea: safeArea
      )
      switch edge {
      case .top, .bottom:
        return Size(
          width: max(baseSize.width, insetSize.width),
          height: baseSize.height + consumed
        )
      case .leading, .trailing:
        return Size(
          width: baseSize.width + consumed,
          height: max(baseSize.height, insetSize.height)
        )
      }
    case .border(let set, _, _, _, _, let sides):
      let insets = borderLayoutInsets(set: set, sides: sides)
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
    case .offset:
      return childMeasurements.first?.measuredSize ?? .zero
    case .position:
      // `.position` fills the proposed space so the parent reserves
      // room for the absolute placement area.  Unspecified
      // dimensions fall back to the child's measured size.
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      let width: Int =
        switch proposal.width {
        case .finite(let w): w
        case .infinity: max(contentSize.width, 0)
        case .unspecified: contentSize.width
        }
      let height: Int =
        switch proposal.height {
        case .finite(let h): h
        case .infinity: max(contentSize.height, 0)
        case .unspecified: contentSize.height
        }
      return Size(width: width, height: height)
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

  private func hasFiniteFlexibleConstraint(
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Bool {
    finiteValue(min) != nil || finiteValue(ideal) != nil || finiteValue(max) != nil
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

    guard hasFiniteFlexibleConstraint(min: min, ideal: ideal, max: max) else {
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

    if hasFiniteFlexibleConstraint(min: min, ideal: ideal, max: max) {
      switch proposal {
      case .unspecified:
        let minVal = finiteValue(min)
        let idealVal = finiteValue(ideal)
        let maxVal = finiteValue(max)
        var result = idealVal ?? child
        if let lo = minVal { result = Swift.max(lo, result) }
        if let hi = maxVal { result = Swift.min(hi, result) }
        return result
      case .finite, .infinity:
        return resolveFlexibleDimension(
          proposal: proposal,
          min: min,
          ideal: ideal,
          max: max
        )
      }
    }

    switch proposal {
    case .finite(let value):
      return value
    case .unspecified, .infinity:
      return child
    }
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

  private func measuredTextFigureSize(
    for payload: TextFigurePayload,
    proposal: ProposedSize
  ) -> Size {
    TextFigureSupport.measuredSize(
      for: payload,
      proposal: proposal
    )
  }

  private func measuredRuleSize(
    for proposal: ProposedSize,
    stackAxis: Axis?
  ) -> Size {
    let proposedWidth = finiteDimension(of: proposal.width)
    let proposedHeight = finiteDimension(of: proposal.height)

    if let stackAxis {
      switch stackAxis {
      case .vertical:
        let width = max(0, proposedWidth ?? 1)
        return Size(width: width, height: width > 0 ? 1 : 0)
      case .horizontal:
        let height = max(0, proposedHeight ?? 1)
        return Size(width: height > 0 ? 1 : 0, height: height)
      }
    }

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
        let resolvedAsset = payload.resolvedAsset,
        resolvedAsset.pixelSize.width > 0,
        resolvedAsset.pixelSize.height > 0,
        resolvedAsset.cellPixelSize.width > 0,
        resolvedAsset.cellPixelSize.height > 0
      else {
        return Size(
          width: proposedWidth ?? intrinsicSize.width,
          height: proposedHeight ?? intrinsicSize.height
        )
      }

      // Aspect math has to happen in pixel space: the parent proposes a
      // frame in terminal cells, but terminal cells are rarely square
      // (typically 8x16 pixels), so a naïve `cells / pixels` scale factor
      // mixes units and distorts the image. Convert the proposed frame
      // into pixels, fit/fill against the source's pixel dimensions, and
      // then convert the result back to cells.
      let pixelSize = resolvedAsset.pixelSize
      let cellPixelWidth = Double(resolvedAsset.cellPixelSize.width)
      let cellPixelHeight = Double(resolvedAsset.cellPixelSize.height)
      let pixelAspect = Double(pixelSize.width) / Double(pixelSize.height)
      // Cell aspect of the source is what the frame proposer thinks the
      // image "looks like" — it folds the non-square cell ratio into the
      // aspect. Used for single-axis proposals.
      let cellAspect = pixelAspect * cellPixelHeight / cellPixelWidth

      // Fit rounds DOWN so the image fits strictly inside the frame;
      // fill rounds UP so the image fully covers it.
      let rounding: FloatingPointRoundingRule =
        payload.scalingMode == .fit ? .down : .up
      func cellsFromPixels(_ value: Double, per cellPixel: Double) -> Int {
        max(1, Int((value / cellPixel).rounded(rounding)))
      }

      switch (proposedWidth, proposedHeight) {
      case (let width?, let height?):
        guard width > 0, height > 0 else {
          return .zero
        }
        let framePixelWidth = Double(width) * cellPixelWidth
        let framePixelHeight = Double(height) * cellPixelHeight
        let widthScale = framePixelWidth / Double(pixelSize.width)
        let heightScale = framePixelHeight / Double(pixelSize.height)
        let scale =
          payload.scalingMode == .fit
          ? min(widthScale, heightScale)
          : max(widthScale, heightScale)
        let targetPixelWidth = Double(pixelSize.width) * scale
        let targetPixelHeight = Double(pixelSize.height) * scale
        return Size(
          width: cellsFromPixels(targetPixelWidth, per: cellPixelWidth),
          height: cellsFromPixels(targetPixelHeight, per: cellPixelHeight)
        )
      case (let width?, nil):
        guard width > 0 else {
          return .zero
        }
        return Size(
          width: width,
          height: max(1, Int((Double(width) / cellAspect).rounded(rounding)))
        )
      case (nil, let height?):
        guard height > 0 else {
          return .zero
        }
        return Size(
          width: max(1, Int((Double(height) * cellAspect).rounded(rounding))),
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
    retainedLayout: RetainedLayoutSession?,
    hasInvalidatedIndexedDescendant: Bool
  ) -> MeasuredNode? {
    guard let retainedLayout,
      !hasInvalidatedIndexedDescendant,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.hasSyntheticInvalidatedAncestor(resolved.identity),
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
    viewportContext: LazyStackViewportContext?,
    retainedLayout: RetainedLayoutSession?
  ) -> PlacedNode? {
    if viewportContext != nil, case .lazyStack = resolved.layoutBehavior {
      return nil
    }

    guard
      let retainedLayout,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.hasSyntheticInvalidatedAncestor(resolved.identity),
      !retainedLayout.containsInvalidatedDescendant(of: resolved.identity),
      supportsRetainedLayoutReuse(for: resolved),
      let previousResolved = retainedLayout.resolvedNode(for: resolved.identity),
      let previousMeasured = retainedLayout.measuredNode(for: resolved.identity),
      let previousPlaced = retainedLayout.placedNode(for: resolved.identity),
      previousResolved.isEquivalentForPlacement(to: resolved)
    else {
      return nil
    }

    let measurementMatches = previousMeasured == measured
    let translationMeasurementMatches = isEquivalentForViewportTranslation(
      previousMeasured, measured)

    if previousPlaced.bounds == bounds {
      guard measurementMatches else {
        return nil
      }
      // `isEquivalentForPlacement` deliberately ignores `drawMetadata`
      // so that visual-only mutations — animation controller color
      // interpolation in particular — don't invalidate layout reuse.
      // But that means the cached `previousPlaced` carries the
      // PREVIOUS frame's drawMetadata, which is wrong for any tick
      // frame where the controller mutated colors/opacity/padding
      // on the resolved tree.  Refresh the visual metadata from the
      // current resolved tree while preserving the cached bounds.
      return refreshDrawMetadata(placed: previousPlaced, from: resolved)
    }

    guard
      viewportContext != nil,
      previousPlaced.bounds.size == bounds.size,
      measurementMatches || translationMeasurementMatches
    else {
      return nil
    }

    let delta = Point(
      x: bounds.origin.x - previousPlaced.bounds.origin.x,
      y: bounds.origin.y - previousPlaced.bounds.origin.y
    )
    if delta == .zero {
      return refreshDrawMetadata(placed: previousPlaced, from: resolved)
    }

    return refreshDrawMetadata(
      placed: translatedPlacement(previousPlaced, by: delta),
      from: resolved
    )
  }

  /// Walks a reused placed subtree in parallel with the current
  /// resolved subtree and copies visual metadata (drawMetadata,
  /// semanticMetadata, lifecycleMetadata, environmentSnapshot,
  /// isTransient) from the current resolved node onto the cached
  /// placed node.  The trees are guaranteed structurally identical
  /// by `isEquivalentForPlacement`, so we can zip them safely.
  ///
  /// This lets the layout engine reuse cached placement (bounds,
  /// sizes) while still picking up tick-frame visual mutations from
  /// the animation controller.
  private func refreshDrawMetadata(
    placed: PlacedNode,
    from resolved: ResolvedNode
  ) -> PlacedNode {
    var node = placed
    node.drawMetadata = resolved.drawMetadata
    node.semanticMetadata = resolved.semanticMetadata
    node.lifecycleMetadata = resolved.lifecycleMetadata
    node.environmentSnapshot = resolved.environmentSnapshot
    node.layoutBehavior = resolved.layoutBehavior
    node.isTransient = resolved.isTransient
    node.matchedGeometry = resolved.matchedGeometry

    guard node.children.count == resolved.children.count else {
      // Structural mismatch — should not happen because
      // isEquivalentForPlacement gated on children.count, but play
      // it safe and return the node without recursing further.
      return node
    }
    let refreshedChildren = zip(node.children, resolved.children).map {
      (placedChild, resolvedChild) in
      refreshDrawMetadata(placed: placedChild, from: resolvedChild)
    }
    node.children = refreshedChildren
    return node
  }

  private func isEquivalentForViewportTranslation(
    _ lhs: MeasuredNode,
    _ rhs: MeasuredNode
  ) -> Bool {
    lhs.identity == rhs.identity
      && lhs.measuredSize == rhs.measuredSize
      && lhs.childMeasurements.count == rhs.childMeasurements.count
      && zip(lhs.childMeasurements, rhs.childMeasurements).allSatisfy {
        isEquivalentForViewportTranslation($0, $1)
      }
  }

  private func hasInvalidatedIndexedDescendant(
    for resolved: ResolvedNode,
    passContext: LayoutPassContext?
  ) -> Bool {
    guard let source = resolved.indexedChildSource else {
      return false
    }

    guard let retainedLayout = passContext?.retainedLayout else {
      return false
    }

    return retainedLayout.affectsIndexedChildSource(root: source.identityRoot)
  }

  private func supportsRetainedLayoutReuse(
    for resolved: ResolvedNode
  ) -> Bool {
    resolved.supportsRetainedReuse
  }

  private func storedChildMeasurements(
    for resolved: ResolvedNode,
    measuredChildren: [MeasuredNode]
  ) -> [MeasuredNode] {
    guard resolved.usesIndexedChildSource, case .lazyStack = resolved.layoutBehavior else {
      return measuredChildren
    }

    return []
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

  private func outset(
    _ proposal: ProposedSize,
    by insets: EdgeInsets
  ) -> ProposedSize {
    ProposedSize(
      width: outset(proposal.width, by: insets.horizontal),
      height: outset(proposal.height, by: insets.vertical)
    )
  }

  private func outset(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      return .unspecified
    case .infinity:
      return .infinity
    case .finite(let value):
      return .finite(max(0, value + amount))
    }
  }

  private func measuredDimension(
    _ proposal: ProposedDimension,
    fallback: Int
  ) -> Int {
    switch proposal {
    case .finite(let value):
      max(0, value)
    case .unspecified, .infinity:
      fallback
    }
  }

  private func safeAreaInsetAdornmentProposal(
    _ parentProposal: ProposedSize,
    edge: Edge
  ) -> ProposedSize {
    switch edge {
    case .top, .bottom:
      return ProposedSize(
        width: parentProposal.width,
        height: .unspecified
      )
    case .leading, .trailing:
      return ProposedSize(
        width: .unspecified,
        height: parentProposal.height
      )
    }
  }

  private func safeAreaInsetConsumedAmount(
    edge: Edge,
    contentSize: Size,
    spacing: Int,
    safeArea: EdgeInsets
  ) -> Int {
    let contentLength =
      switch edge {
      case .top, .bottom:
        contentSize.height
      case .leading, .trailing:
        contentSize.width
      }
    return max(0, contentLength + max(0, spacing) - safeArea.value(for: edge))
  }

  private func safeAreaInsetConsumedInsets(
    edge: Edge,
    contentSize: Size,
    spacing: Int,
    safeArea: EdgeInsets
  ) -> EdgeInsets {
    let consumed = safeAreaInsetConsumedAmount(
      edge: edge,
      contentSize: contentSize,
      spacing: spacing,
      safeArea: safeArea
    )
    switch edge {
    case .top:
      return EdgeInsets(top: consumed)
    case .leading:
      return EdgeInsets(leading: consumed)
    case .bottom:
      return EdgeInsets(bottom: consumed)
    case .trailing:
      return EdgeInsets(trailing: consumed)
    }
  }

  /// The per-side layout insets a border contributes to its owner's frame.
  ///
  /// For `.inset` placements the border occupies the content's own
  /// outermost rows and columns and therefore adds zero layout insets;
  /// the rasterizer will draw border glyphs into those existing cells.
  /// For `.outset` (and `.decorative`) placements the insets reserve
  /// frame cells around the content so no glyph ever lands on the
  /// child's drawable area.  `sides` masks the result so callers can
  /// request borders on a subset of edges (e.g. top only).
  package func borderLayoutInsets(
    set: BorderSet,
    sides: Edge.Set
  ) -> EdgeInsets {
    guard set.placement != .inset else { return EdgeInsets() }
    return EdgeInsets(
      top: sides.contains(.top) ? set.topDisplayWidth : 0,
      leading: sides.contains(.leading) ? set.leftDisplayWidth : 0,
      bottom: sides.contains(.bottom) ? set.bottomDisplayWidth : 0,
      trailing: sides.contains(.trailing) ? set.rightDisplayWidth : 0
    )
  }
}
