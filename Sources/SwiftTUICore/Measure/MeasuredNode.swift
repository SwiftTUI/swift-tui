public struct ChildAllocation: Equatable, Sendable {
  public var identity: Identity
  public var size: CellSize

  public init(identity: Identity, size: CellSize) {
    self.identity = identity
    self.size = size
  }
}

/// Container-specific placement information captured during measure.
public struct ContainerAllocationSnapshot: Equatable, Sendable {
  public var childSizes: [ChildAllocation]
  public var selectedChildIndex: Int?
  public var lazyStack: LazyStackAllocationSnapshot?

  public init(
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
public struct LazyStackAllocationSnapshot: Equatable, Sendable {
  public var axis: Axis
  public var childMainOffsets: [Int]
  public var childMainLengths: [Int]
  public var contentMainLength: Int
  public var crossLeading: Int
  public var crossTrailing: Int

  public init(
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
public struct MeasuredNode: Equatable, Sendable {
  public var identity: Identity
  public var proposal: ProposedSize
  public var measuredSize: CellSize
  public var childMeasurements: [MeasuredNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  public var containerAllocationSnapshot: ContainerAllocationSnapshot?
  package private(set) var subtreeNodeCount: Int

  public init(
    identity: Identity,
    proposal: ProposedSize,
    measuredSize: CellSize,
    childMeasurements: [MeasuredNode] = [],
    containerAllocationSnapshot: ContainerAllocationSnapshot? = nil
  ) {
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
