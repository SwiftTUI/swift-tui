package struct ChildAllocation: Equatable, Sendable {
  package var identity: Identity
  package var size: CellSize

  package init(identity: Identity, size: CellSize) {
    self.identity = identity
    self.size = size
  }
}

/// Container-specific placement information captured during measure.
package struct ContainerAllocationSnapshot: Equatable, Sendable {
  package var childSizes: [ChildAllocation]
  package var selectedChildIndex: Int?
  package var lazyStack: LazyStackAllocationSnapshot?
  package var hostedCollection: HostedCollectionAllocationSnapshot?

  package init(
    childSizes: [ChildAllocation] = [],
    selectedChildIndex: Int? = nil,
    lazyStack: LazyStackAllocationSnapshot? = nil,
    hostedCollection: HostedCollectionAllocationSnapshot? = nil
  ) {
    self.childSizes = childSizes
    self.selectedChildIndex = selectedChildIndex
    self.lazyStack = lazyStack
    self.hostedCollection = hostedCollection
  }
}

/// Realized source indices for a node-hosted List or Table measurement.
/// Child measurements are index-parallel with this bounded list.
package struct HostedCollectionAllocationSnapshot: Equatable, Sendable {
  package var sourceIndices: [Int]
  package var tableColumnWidths: [Int]?
  /// The window this measurement was taken for, when it came from an enclosing
  /// scroll layout's measure-viewport hint rather than from a finite proposal.
  /// A hint-derived product is valid only for its window, and the scroll
  /// layout's reuse signature is deliberately position-free, so the retained
  /// gate recomputes the window and denies reuse on mismatch. `nil` on the
  /// finite path, where the proposal itself already gates reuse.
  package var measuredWindow: Range<Int>?
  /// Display lines per row used to derive `measuredWindow`.
  package var estimatedRowStride: Int?
  /// The height-aware visible layout, derived ONCE here from the measured row
  /// heights and carried forward. Placement translates it into absolute
  /// coordinates and hands it to draw and semantics, so the four phases share
  /// one product instead of each re-deriving its own (register item D19).
  /// Origin-zero: placement owns the translation.
  package var listLayout: ListVisibleLayout?
  /// The table twin of ``listLayout``, on the same terms.
  package var tableLayout: TableVisibleLayout?

  package init(
    sourceIndices: [Int],
    tableColumnWidths: [Int]? = nil,
    measuredWindow: Range<Int>? = nil,
    estimatedRowStride: Int? = nil,
    listLayout: ListVisibleLayout? = nil,
    tableLayout: TableVisibleLayout? = nil
  ) {
    self.sourceIndices = sourceIndices
    self.tableColumnWidths = tableColumnWidths
    self.measuredWindow = measuredWindow
    self.estimatedRowStride = estimatedRowStride
    self.listLayout = listLayout
    self.tableLayout = tableLayout
  }
}

/// Allocation state captured for lazy stacks.
package struct LazyStackAllocationSnapshot: Equatable, Sendable {
  package var axis: Axis
  package var childMainOffsets: [Int]
  package var childMainLengths: [Int]
  /// Index-parallel child identities, captured from the already-materialized
  /// children the allocation measured. Placement uses them to publish
  /// estimated scroll targets for children outside the visible window — a
  /// `scrollTo` aimed at a never-placed lazy row has no placed frame to
  /// resolve against, but its allocation offset is exactly the frame it
  /// would get if placed.
  package var childIdentities: [Identity]
  package var contentMainLength: Int
  package var crossLeading: Int
  package var crossTrailing: Int
  /// The realized-and-measured index band when this snapshot was built under
  /// a measure-viewport hint (proposal 2026-07-13-002 Stage 2.2); `nil`
  /// means exhaustive — every entry is a real measurement. Entries outside
  /// the window are synthesized from the probe row's extent, so a windowed
  /// product is only valid for its window: the retained-measurement gate
  /// recomputes the current window and denies reuse on mismatch.
  package var measuredWindow: Range<Int>?
  /// The per-row main-axis stride (probe extent + spacing) the estimated
  /// entries were synthesized with; feeds the retained-gate recompute.
  package var estimatedRowStride: Int?

  package init(
    axis: Axis,
    childMainOffsets: [Int] = [],
    childMainLengths: [Int] = [],
    childIdentities: [Identity] = [],
    contentMainLength: Int = 0,
    crossLeading: Int = 0,
    crossTrailing: Int = 0,
    measuredWindow: Range<Int>? = nil,
    estimatedRowStride: Int? = nil
  ) {
    self.axis = axis
    self.childMainOffsets = childMainOffsets
    self.childMainLengths = childMainLengths
    self.childIdentities = childIdentities
    self.contentMainLength = contentMainLength
    self.crossLeading = crossLeading
    self.crossTrailing = crossTrailing
    self.measuredWindow = measuredWindow
    self.estimatedRowStride = estimatedRowStride
  }
}

/// Viewport information used by lazy stack placement helpers.
package typealias LazyStackViewportContext = ScrollViewportContext

/// A resolved node after the measure phase has chosen concrete sizes.
///
/// Measure owns the proposal, measured size, child measurements, and
/// container-allocation snapshots used by placement. `identity` is carried from
/// resolve only to correlate retained cache entries and child placement; this
/// type does not carry resolved metadata forward to later phases.
package struct MeasuredNode: Equatable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var proposal: ProposedSize
  package var measuredSize: CellSize
  package var childMeasurements: [MeasuredNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  package var containerAllocationSnapshot: ContainerAllocationSnapshot?
  package private(set) var subtreeNodeCount: Int

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    proposal: ProposedSize,
    measuredSize: CellSize,
    childMeasurements: [MeasuredNode] = [],
    containerAllocationSnapshot: ContainerAllocationSnapshot? = nil
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.proposal = proposal
    self.measuredSize = measuredSize
    self.childMeasurements = childMeasurements
    self.containerAllocationSnapshot = containerAllocationSnapshot
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  package init(
    identity: Identity,
    proposal: ProposedSize,
    measuredSize: CellSize,
    childMeasurements: [MeasuredNode] = [],
    containerAllocationSnapshot: ContainerAllocationSnapshot? = nil
  ) {
    self.viewNodeID = nil
    self.identity = identity
    self.proposal = proposal
    self.measuredSize = measuredSize
    self.childMeasurements = childMeasurements
    self.containerAllocationSnapshot = containerAllocationSnapshot
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + childMeasurements.reduce(0) { $0 + $1.subtreeNodeCount }
  }

  /// Explicit, iterative `==`.
  ///
  /// The synthesized conformance recursed through `childMeasurements`' array
  /// equality — invisible at the call site, and reached from the frame tail by
  /// `previousMeasured == measured` in `retainedPlacement`, on the same small
  /// worker stack that overflowed `isEquivalentForMeasurement` in production
  /// (45ffdc44). Same field set; conjunct order is not observable.
  ///
  /// `subtreeNodeCount` is compared first as an O(1) early-out the synthesized
  /// form could not have: it is maintained on every `childMeasurements` write,
  /// so unequal counts prove unequal subtrees without walking either.
  package static func == (lhs: Self, rhs: Self) -> Bool {
    var pending: [(Self, Self)] = [(lhs, rhs)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.subtreeNodeCount == rhs.subtreeNodeCount,
        lhs.viewNodeID == rhs.viewNodeID,
        lhs.identity == rhs.identity,
        lhs.proposal == rhs.proposal,
        lhs.measuredSize == rhs.measuredSize,
        lhs.containerAllocationSnapshot == rhs.containerAllocationSnapshot,
        lhs.childMeasurements.count == rhs.childMeasurements.count
      else {
        return false
      }
      for index in lhs.childMeasurements.indices.reversed() {
        pending.append((lhs.childMeasurements[index], rhs.childMeasurements[index]))
      }
    }
    return true
  }
}

/// Interface implemented by low-level custom layouts.
