/// The layout strategy applied to a resolved node.
public enum LayoutBehavior: Sendable {
  case intrinsic
  case stack(
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  )
  case lazyStack(
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  )
  case overlay(alignment: Alignment)
  case padding(EdgeInsets)
  /// Expands child layout back into the container safe area reserved by an
  /// ancestor wrapper while leaving the wrapper's own measured size unchanged.
  case safeAreaIgnoring(EdgeInsets)
  /// Inserts a secondary child along one safe-area edge and shifts the primary
  /// child inward only when the inset content exceeds the reclaimed safe area.
  case safeAreaInset(edge: Edge, alignment: Alignment, spacing: Int, safeArea: EdgeInsets)
  /// A border that reserves layout insets for its own glyphs.
  ///
  /// For `.outset` placements the layout engine
  /// treats this like a `.padding` whose insets are derived from the
  /// border set's per-side display widths (masked by `sides`), so the
  /// child's content is never occluded by border glyphs.  For `.inset`
  /// placements the border contributes no layout space — glyphs will be
  /// painted into the view's outermost cells by the rasterizer.
  ///
  /// The styling payload (`foreground`, `background`, `blend`,
  /// `blendPhase`) passes through the layout pass untouched and is
  /// consumed later by the rasterizer.  See §4.7 of
  /// `SHAPE_AND_BORDER_APIS.md` for the full design.
  ///
  /// Marked `indirect` so the aggregate payload (BorderSet +
  /// BorderEdgeStyle + BorderBackgroundStyle + BorderBlend + sides)
  /// stays behind a single pointer inside the enum discriminant;
  /// unboxed, this case would balloon ``LayoutBehavior`` past 1.6 kB
  /// and overflow the stack during deep recursive tree traversals
  /// (see the 1024-deep ResolvedNode regression tests).
  indirect case border(
    BorderSet,
    placement: StrokeStyle.Placement,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set
  )
  case frame(width: Int?, height: Int?, alignment: Alignment)
  case offset(x: Int, y: Int)
  /// Positions the content so its center lands at `(x, y)` in the
  /// parent's coordinate space.  Unlike `.offset`, which translates
  /// the content without affecting parent layout, `.position` takes
  /// the full proposed size for its wrapper so the parent reserves
  /// space for the absolute placement area.  Matches SwiftUI's
  /// `View.position(x:y:)` semantics.
  case position(x: Int, y: Int)
  case flexibleFrame(
    minWidth: ProposedDimension?, idealWidth: ProposedDimension?, maxWidth: ProposedDimension?,
    minHeight: ProposedDimension?, idealHeight: ProposedDimension?, maxHeight: ProposedDimension?,
    alignment: Alignment
  )
  case decoration(primaryIndex: Int, alignment: Alignment)
  case viewThatFits(AxisSet)
  case custom(CustomLayoutHandle)
}

extension LayoutBehavior: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.intrinsic, .intrinsic):
      return true
    case (.overlay(let lhsAlignment), .overlay(let rhsAlignment)):
      return lhsAlignment == rhsAlignment
    case (
      .stack(let lhsAxis, let lhsSpacing, let lhsHorizontalAlignment, let lhsVerticalAlignment),
      .stack(let rhsAxis, let rhsSpacing, let rhsHorizontalAlignment, let rhsVerticalAlignment)
    ):
      return lhsAxis == rhsAxis
        && lhsSpacing == rhsSpacing
        && lhsHorizontalAlignment == rhsHorizontalAlignment
        && lhsVerticalAlignment == rhsVerticalAlignment
    case (
      .lazyStack(let lhsAxis, let lhsSpacing, let lhsHorizontalAlignment, let lhsVerticalAlignment),
      .lazyStack(let rhsAxis, let rhsSpacing, let rhsHorizontalAlignment, let rhsVerticalAlignment)
    ):
      return lhsAxis == rhsAxis
        && lhsSpacing == rhsSpacing
        && lhsHorizontalAlignment == rhsHorizontalAlignment
        && lhsVerticalAlignment == rhsVerticalAlignment
    case (.padding(let lhsInsets), .padding(let rhsInsets)):
      return lhsInsets == rhsInsets
    case (.safeAreaIgnoring(let lhsInsets), .safeAreaIgnoring(let rhsInsets)):
      return lhsInsets == rhsInsets
    case (
      .safeAreaInset(
        edge: let lhsEdge,
        alignment: let lhsAlignment,
        spacing: let lhsSpacing,
        safeArea: let lhsSafeArea
      ),
      .safeAreaInset(
        edge: let rhsEdge,
        alignment: let rhsAlignment,
        spacing: let rhsSpacing,
        safeArea: let rhsSafeArea
      )
    ):
      return lhsEdge == rhsEdge
        && lhsAlignment == rhsAlignment
        && lhsSpacing == rhsSpacing
        && lhsSafeArea == rhsSafeArea
    case (
      .border(
        let lhsSet, let lhsPlacement, let lhsFg, let lhsBg,
        let lhsBlend, let lhsPhase, let lhsSides
      ),
      .border(
        let rhsSet, let rhsPlacement, let rhsFg, let rhsBg,
        let rhsBlend, let rhsPhase, let rhsSides
      )
    ):
      return lhsSet == rhsSet
        && lhsPlacement == rhsPlacement
        && lhsFg == rhsFg
        && lhsBg == rhsBg
        && lhsBlend == rhsBlend
        && lhsPhase == rhsPhase
        && lhsSides == rhsSides
    case (
      .frame(let lhsWidth, let lhsHeight, let lhsAlignment),
      .frame(let rhsWidth, let rhsHeight, let rhsAlignment)
    ):
      return lhsWidth == rhsWidth
        && lhsHeight == rhsHeight
        && lhsAlignment == rhsAlignment
    case (.offset(let lhsX, let lhsY), .offset(let rhsX, let rhsY)):
      return lhsX == rhsX && lhsY == rhsY
    case (.position(let lhsX, let lhsY), .position(let rhsX, let rhsY)):
      return lhsX == rhsX && lhsY == rhsY
    case (
      .flexibleFrame(
        let lhsMinW, let lhsIdealW, let lhsMaxW,
        let lhsMinH, let lhsIdealH, let lhsMaxH,
        let lhsAlignment
      ),
      .flexibleFrame(
        let rhsMinW, let rhsIdealW, let rhsMaxW,
        let rhsMinH, let rhsIdealH, let rhsMaxH,
        let rhsAlignment
      )
    ):
      return lhsMinW == rhsMinW && lhsIdealW == rhsIdealW && lhsMaxW == rhsMaxW
        && lhsMinH == rhsMinH && lhsIdealH == rhsIdealH && lhsMaxH == rhsMaxH
        && lhsAlignment == rhsAlignment
    case (
      .decoration(let lhsPrimaryIndex, let lhsAlignment),
      .decoration(let rhsPrimaryIndex, let rhsAlignment)
    ):
      return lhsPrimaryIndex == rhsPrimaryIndex
        && lhsAlignment == rhsAlignment
    case (.viewThatFits(let lhsAxes), .viewThatFits(let rhsAxes)):
      return lhsAxes == rhsAxes
    case (.custom(let lhsHandle), .custom(let rhsHandle)):
      return lhsHandle == rhsHandle
    default:
      return false
    }
  }
}

/// Modifier-driven layout metadata attached to a resolved node.
package struct LayoutMetadata: Sendable {
  package var layoutPriority: Double
  package var fixedSizeHorizontal: Bool
  package var fixedSizeVertical: Bool
  package var minimumWidth: Int?
  package var minimumHeight: Int?
  package var lineLimit: Int?
  package var textTruncationMode: TextTruncationMode?
  package var textWrappingStrategy: TextWrappingStrategy?
  package var spacing: Spacing
  package var alignmentKeys: [String]
  package var layoutValues: [String: String]
  private var layoutValueStorage: [ObjectIdentifier: any Sendable]
  private var horizontalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]
  private var verticalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int]

  package init(
    layoutPriority: Double = 0,
    fixedSizeHorizontal: Bool = false,
    fixedSizeVertical: Bool = false,
    minimumWidth: Int? = nil,
    minimumHeight: Int? = nil,
    lineLimit: Int? = nil,
    textTruncationMode: TextTruncationMode? = nil,
    textWrappingStrategy: TextWrappingStrategy? = nil,
    spacing: Spacing = .init(),
    alignmentKeys: [String] = [],
    layoutValues: [String: String] = [:],
    layoutValueStorage: [ObjectIdentifier: any Sendable] = [:],
    horizontalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int] = [:],
    verticalAlignmentGuideStorage: [ObjectIdentifier: @Sendable (ViewDimensions) -> Int] = [:]
  ) {
    self.layoutPriority = layoutPriority
    self.fixedSizeHorizontal = fixedSizeHorizontal
    self.fixedSizeVertical = fixedSizeVertical
    self.minimumWidth = minimumWidth.map { max(0, $0) }
    self.minimumHeight = minimumHeight.map { max(0, $0) }
    self.lineLimit = lineLimit
    self.textTruncationMode = textTruncationMode
    self.textWrappingStrategy = textWrappingStrategy
    self.spacing = spacing
    self.alignmentKeys = alignmentKeys
    self.layoutValues = layoutValues
    self.layoutValueStorage = layoutValueStorage
    self.horizontalAlignmentGuideStorage = horizontalAlignmentGuideStorage
    self.verticalAlignmentGuideStorage = verticalAlignmentGuideStorage
  }

  package func merging(_ other: Self) -> Self {
    var merged = self
    if other.layoutPriority != 0 {
      merged.layoutPriority = other.layoutPriority
    }
    merged.fixedSizeHorizontal = fixedSizeHorizontal || other.fixedSizeHorizontal
    merged.fixedSizeVertical = fixedSizeVertical || other.fixedSizeVertical
    merged.minimumWidth = other.minimumWidth ?? minimumWidth
    merged.minimumHeight = other.minimumHeight ?? minimumHeight
    merged.lineLimit = other.lineLimit ?? lineLimit
    merged.textTruncationMode = other.textTruncationMode ?? textTruncationMode
    merged.textWrappingStrategy = other.textWrappingStrategy ?? textWrappingStrategy
    merged.spacing = spacing.merging(other.spacing)
    for key in other.alignmentKeys where !merged.alignmentKeys.contains(key) {
      merged.alignmentKeys.append(key)
    }
    merged.layoutValues.merge(other.layoutValues) { _, new in new }
    merged.layoutValueStorage.merge(other.layoutValueStorage) { _, new in new }
    merged.horizontalAlignmentGuideStorage.merge(other.horizontalAlignmentGuideStorage) { _, new in
      new
    }
    merged.verticalAlignmentGuideStorage.merge(other.verticalAlignmentGuideStorage) { _, new in new
    }
    return merged
  }

  package func settingLayoutValue<Value: Sendable>(
    _ value: Value,
    for keyIdentifier: ObjectIdentifier,
    debugName: String,
    debugValue: String
  ) -> Self {
    var copy = self
    copy.layoutValues[debugName] = debugValue
    copy.layoutValueStorage[keyIdentifier] = value
    return copy
  }

  package func layoutValue<Value: Sendable>(
    for keyIdentifier: ObjectIdentifier,
    as _: Value.Type = Value.self
  ) -> Value? {
    layoutValueStorage[keyIdentifier] as? Value
  }

  package func settingHorizontalAlignmentGuide(
    _ alignment: HorizontalAlignment,
    debugName: String,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> Self {
    var copy = self
    if !copy.alignmentKeys.contains(debugName) {
      copy.alignmentKeys.append(debugName)
    }
    copy.horizontalAlignmentGuideStorage[alignment.key] = computeValue
    return copy
  }

  package func settingVerticalAlignmentGuide(
    _ alignment: VerticalAlignment,
    debugName: String,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> Self {
    var copy = self
    if !copy.alignmentKeys.contains(debugName) {
      copy.alignmentKeys.append(debugName)
    }
    copy.verticalAlignmentGuideStorage[alignment.key] = computeValue
    return copy
  }

  package func hasExplicitHorizontalAlignmentGuide(
    _ alignment: HorizontalAlignment
  ) -> Bool {
    horizontalAlignmentGuideStorage[alignment.key] != nil
  }

  package func hasExplicitVerticalAlignmentGuide(
    _ alignment: VerticalAlignment
  ) -> Bool {
    verticalAlignmentGuideStorage[alignment.key] != nil
  }

  package func applyingGuides(to base: ViewDimensions) -> ViewDimensions {
    let horizontalGuideStorage = horizontalAlignmentGuideStorage
    let verticalGuideStorage = verticalAlignmentGuideStorage

    return
      base
      .overridingHorizontalGuides { alignment in
        horizontalGuideStorage[alignment.key].map { computeValue in
          computeValue(base)
        }
      }
      .overridingVerticalGuides { alignment in
        verticalGuideStorage[alignment.key].map { computeValue in
          computeValue(base)
        }
      }
  }

  package func viewDimensions(for size: CellSize) -> ViewDimensions {
    applyingGuides(to: ViewDimensions(width: size.width, height: size.height))
  }
}

extension LayoutMetadata: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.layoutPriority == rhs.layoutPriority
      && lhs.fixedSizeHorizontal == rhs.fixedSizeHorizontal
      && lhs.fixedSizeVertical == rhs.fixedSizeVertical
      && lhs.minimumWidth == rhs.minimumWidth
      && lhs.minimumHeight == rhs.minimumHeight
      && lhs.lineLimit == rhs.lineLimit
      && lhs.textTruncationMode == rhs.textTruncationMode
      && lhs.textWrappingStrategy == rhs.textWrappingStrategy
      && lhs.spacing == rhs.spacing
      && lhs.alignmentKeys == rhs.alignmentKeys
      && lhs.layoutValues == rhs.layoutValues
  }
}

/// The measured size assigned to a child during container layout.
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
public protocol CustomLayoutProxy: AnyObject, Sendable {
  var debugName: String { get }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> CellSize

  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> [MeasuredNode]

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode]
}

extension CustomLayoutProxy {
  public func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> [MeasuredNode] {
    node.children.map { child in
      engine.measure(child, proposal: proposal)
    }
  }
}

/// Execution mode advertised by a custom layout handle.
package enum CustomLayoutExecutionCapability: Equatable, Sendable {
  case mainActorOnly
  case worker
}

/// Interface implemented by custom layouts that can execute on the frame-tail
/// worker without crossing a main-actor-isolated proxy.
package protocol WorkerCustomLayoutProxy: Sendable {
  var debugName: String { get }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize

  func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode]

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode]
}

extension WorkerCustomLayoutProxy {
  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    node.children.map { child in
      engine.measure(child, proposal: proposal, passContext: passContext)
    }
  }
}

/// Sendable closure-backed snapshot for custom layouts that can execute on the
/// frame-tail worker.
package struct WorkerCustomLayoutSnapshot: WorkerCustomLayoutProxy {
  package typealias MeasureContainerHandler =
    @Sendable (LayoutEngine, ResolvedNode, ProposedSize, LayoutPassContext?) -> CellSize
  package typealias MeasureChildrenHandler =
    @Sendable (LayoutEngine, ResolvedNode, ProposedSize, LayoutPassContext?) -> [MeasuredNode]
  package typealias PlaceSubviewsHandler =
    @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
    [PlacedNode]

  package var debugName: String
  private let measureContainerHandler: MeasureContainerHandler
  private let measureChildrenHandler: MeasureChildrenHandler?
  private let placeSubviewsHandler: PlaceSubviewsHandler

  package init(
    debugName: String,
    measureChildren: MeasureChildrenHandler? = nil,
    measureContainer: @escaping MeasureContainerHandler,
    placeSubviews: @escaping PlaceSubviewsHandler
  ) {
    self.debugName = debugName
    measureChildrenHandler = measureChildren
    measureContainerHandler = measureContainer
    placeSubviewsHandler = placeSubviews
  }

  package func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    measureContainerHandler(engine, node, proposal, passContext)
  }

  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    if let measureChildrenHandler {
      return measureChildrenHandler(engine, node, proposal, passContext)
    }
    return node.children.map { child in
      engine.measure(child, proposal: proposal, passContext: passContext)
    }
  }

  package func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    placeSubviewsHandler(engine, node, measured, bounds, passContext)
  }
}

/// Reference wrapper used to carry a custom layout through the pipeline.
public final class CustomLayoutHandle: Sendable {
  public let proxy: any CustomLayoutProxy
  package let workerProxy: (any WorkerCustomLayoutProxy)?
  package let measurementReuseSignature: String?
  package let placementReuseSignature: String?
  package let placementHandler:
    (
      @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
        [PlacedNode]
    )?

  public init(
    _ proxy: some CustomLayoutProxy,
    measurementReuseSignature: String? = nil,
    placementReuseSignature: String? = nil
  ) {
    self.proxy = proxy
    workerProxy = nil
    self.measurementReuseSignature = measurementReuseSignature
    self.placementReuseSignature = placementReuseSignature
    placementHandler = nil
  }

  package init(
    _ proxy: some CustomLayoutProxy,
    measurementReuseSignature: String? = nil,
    placementReuseSignature: String? = nil,
    workerProxy: (any WorkerCustomLayoutProxy)? = nil,
    placementHandler:
      (
        @Sendable (LayoutEngine, ResolvedNode, MeasuredNode, CellRect, LayoutPassContext?) ->
          [PlacedNode]
      )? = nil
  ) {
    self.proxy = proxy
    self.measurementReuseSignature = measurementReuseSignature
    self.placementReuseSignature = placementReuseSignature
    self.workerProxy = workerProxy
    self.placementHandler = placementHandler
  }

  public var debugName: String {
    if let workerProxy {
      return workerProxy.debugName
    }
    return proxy.debugName
  }

  package var executionCapability: CustomLayoutExecutionCapability {
    workerProxy == nil ? .mainActorOnly : .worker
  }

  package var canRunOnWorker: Bool {
    workerProxy != nil
  }

  package func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    if let workerProxy {
      return workerProxy.measureContainer(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    return proxy.measureContainer(
      engine: engine,
      node: node,
      proposal: proposal
    )
  }

  package func measureChildren(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    if let workerProxy {
      return workerProxy.measureChildren(
        engine: engine,
        node: node,
        proposal: proposal,
        passContext: passContext
      )
    }
    return proxy.measureChildren(
      engine: engine,
      node: node,
      proposal: proposal
    )
  }

  package func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    if let workerProxy {
      return workerProxy.placeSubviews(
        engine: engine,
        node: node,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }
    if let placementHandler {
      return placementHandler(engine, node, measured, bounds, passContext)
    }
    return proxy.placeSubviews(
      engine: engine,
      node: node,
      measured: measured,
      in: bounds
    )
  }
}

extension CustomLayoutHandle: Equatable {
  public static func == (lhs: CustomLayoutHandle, rhs: CustomLayoutHandle) -> Bool {
    lhs === rhs
  }
}

extension LayoutBehavior {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    if self == other {
      return true
    }

    // `.border` measurement depends on the chosen ``BorderSet``,
    // the ``Placement``, and the active ``Edge.Set`` — all three feed
    // ``borderLayoutInsets``, the single function the layout engine
    // consults at lines 489 and 733 of ``LayoutEngine``.
    // Specifically: `.inset` placement returns zero ``EdgeInsets()``,
    // while `.outset` returns non-zero insets, so two borders with
    // identical set and sides but different placement produce different
    // measured sizes and must not be treated as equivalent.
    // The other payload fields (foreground colour, background colour,
    // blend, blendPhase) are draw-time concerns: the rasterizer reads
    // them when painting glyphs, but they never change a node's measured
    // size or its child proposal.
    //
    // Treating two borders that differ only in those cosmetic fields as
    // measurement-equivalent lets the layout cache reuse measurements
    // across animation ticks that interpolate ``blendPhase``: each
    // tick mutates the phase on the resolved tree, and without this
    // carve-out the cache (and the retained-layout cache, which routes
    // through this same predicate via
    // ``ResolvedNode.isEquivalentForPlacement``) would invalidate on
    // every frame.  That cascades up the ancestor chain because each
    // ancestor's ``isEquivalentForMeasurement`` walks its children.
    if case .border(let lhsSet, let lhsPlacement, _, _, _, _, let lhsSides) = self,
      case .border(let rhsSet, let rhsPlacement, _, _, _, _, let rhsSides) = other
    {
      return lhsSet == rhsSet && lhsPlacement == rhsPlacement && lhsSides == rhsSides
    }

    guard case .custom(let lhsHandle) = self,
      case .custom(let rhsHandle) = other,
      let lhsSignature = lhsHandle.measurementReuseSignature,
      let rhsSignature = rhsHandle.measurementReuseSignature
    else {
      return false
    }

    return lhsSignature == rhsSignature
  }

  package func isEquivalentForPlacement(
    to other: Self
  ) -> Bool {
    if self == other {
      return true
    }

    if case .border(let lhsSet, let lhsPlacement, _, _, _, _, let lhsSides) = self,
      case .border(let rhsSet, let rhsPlacement, _, _, _, _, let rhsSides) = other
    {
      return lhsSet == rhsSet && lhsPlacement == rhsPlacement && lhsSides == rhsSides
    }

    guard case .custom(let lhsHandle) = self,
      case .custom(let rhsHandle) = other,
      let lhsSignature = lhsHandle.placementReuseSignature,
      let rhsSignature = rhsHandle.placementReuseSignature
    else {
      return false
    }

    return lhsSignature == rhsSignature
  }
}
