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

  package init(
    childSizes: [ChildAllocation] = [],
    selectedChildIndex: Int? = nil,
    lazyStack: LazyStackAllocationSnapshot? = nil
  ) {
    self.childSizes = childSizes
    self.selectedChildIndex = selectedChildIndex
    self.lazyStack = lazyStack
  }
}

/// Allocation state captured for lazy stacks.
package struct LazyStackAllocationSnapshot: Equatable, Sendable {
  package var axis: Axis
  package var childMainOffsets: [Int]
  package var childMainLengths: [Int]
  package var contentMainLength: Int
  package var crossLeading: Int
  package var crossTrailing: Int

  package init(
    axis: Axis,
    childMainOffsets: [Int] = [],
    childMainLengths: [Int] = [],
    contentMainLength: Int = 0,
    crossLeading: Int = 0,
    crossTrailing: Int = 0
  ) {
    self.axis = axis
    self.childMainOffsets = childMainOffsets
    self.childMainLengths = childMainLengths
    self.contentMainLength = contentMainLength
    self.crossLeading = crossLeading
    self.crossTrailing = crossTrailing
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
}

/// Interface implemented by low-level custom layouts.
