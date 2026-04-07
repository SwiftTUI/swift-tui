/// Structured metadata for a tab item label.
public struct TabItemLabel: Equatable, Sendable, CustomStringConvertible {
  public var title: String
  public var detail: String?
  public var badge: String?

  public init<S: StringProtocol>(
    _ title: S,
    detail: S? = nil,
    badge: S? = nil
  ) {
    self.title = String(title)
    self.detail = detail.map { String($0) }
    self.badge = badge.map { String($0) }
  }

  public var displayText: String {
    var parts: [String] = [title]
    if let detail, !detail.isEmpty {
      parts.append(detail)
    }
    if let badge, !badge.isEmpty {
      parts.append("[\(badge)]")
    }
    return parts.joined(separator: " · ")
  }

  public var description: String {
    displayText
  }
}

/// Semantic and interaction metadata attached to a resolved node.
public struct SemanticMetadata: Equatable, Sendable {
  private var explicitFocusability: Bool?
  package var focusScopeBoundary: Bool
  package var focusSectionBoundary: Bool
  public var focusInteractions: FocusInteractions
  public var participatesInPointerHitTesting: Bool
  public var allowsHitTesting: Bool
  public var scrollRole: ScrollRole?
  public var sectionRole: SectionRole?
  public var presentationRole: PresentationRole?
  public var selectionTag: SelectionTag?
  public var tabItemLabel: TabItemLabel?

  public var isFocusable: Bool {
    get { explicitFocusability ?? false }
    set { explicitFocusability = newValue }
  }

  package var focusParticipation: FocusParticipation {
    switch explicitFocusability {
    case true?:
      return .included
    case false?:
      return .excluded
    case nil:
      return .automatic
    }
  }

  public init(
    isFocusable: Bool? = nil,
    focusInteractions: FocusInteractions = .automatic,
    participatesInPointerHitTesting: Bool = false,
    allowsHitTesting: Bool = true,
    scrollRole: ScrollRole? = nil,
    sectionRole: SectionRole? = nil,
    presentationRole: PresentationRole? = nil,
    selectionTag: SelectionTag? = nil,
    tabItemLabel: TabItemLabel? = nil
  ) {
    self.init(
      isFocusable: isFocusable,
      focusScopeBoundary: false,
      focusSectionBoundary: false,
      focusInteractions: focusInteractions,
      participatesInPointerHitTesting: participatesInPointerHitTesting,
      allowsHitTesting: allowsHitTesting,
      scrollRole: scrollRole,
      sectionRole: sectionRole,
      presentationRole: presentationRole,
      selectionTag: selectionTag,
      tabItemLabel: tabItemLabel
    )
  }

  package init(
    isFocusable: Bool? = nil,
    focusScopeBoundary: Bool = false,
    focusSectionBoundary: Bool = false,
    focusInteractions: FocusInteractions = .automatic,
    participatesInPointerHitTesting: Bool = false,
    allowsHitTesting: Bool = true,
    scrollRole: ScrollRole? = nil,
    sectionRole: SectionRole? = nil,
    presentationRole: PresentationRole? = nil,
    selectionTag: SelectionTag? = nil,
    tabItemLabel: TabItemLabel? = nil
  ) {
    explicitFocusability = isFocusable
    self.focusScopeBoundary = focusScopeBoundary
    self.focusSectionBoundary = focusSectionBoundary
    self.focusInteractions = focusInteractions
    self.participatesInPointerHitTesting = participatesInPointerHitTesting
    self.allowsHitTesting = allowsHitTesting
    self.scrollRole = scrollRole
    self.sectionRole = sectionRole
    self.presentationRole = presentationRole
    self.selectionTag = selectionTag
    self.tabItemLabel = tabItemLabel
  }

  public func merging(_ other: Self) -> Self {
    Self(
      isFocusable: other.explicitFocusability ?? explicitFocusability,
      focusScopeBoundary: other.focusScopeBoundary || focusScopeBoundary,
      focusSectionBoundary: other.focusSectionBoundary || focusSectionBoundary,
      focusInteractions: other.focusInteractions == .automatic
        ? focusInteractions
        : other.focusInteractions,
      participatesInPointerHitTesting: other.participatesInPointerHitTesting
        || participatesInPointerHitTesting,
      allowsHitTesting: other.allowsHitTesting && allowsHitTesting,
      scrollRole: other.scrollRole ?? scrollRole,
      sectionRole: other.sectionRole ?? sectionRole,
      presentationRole: other.presentationRole ?? presentationRole,
      selectionTag: other.selectionTag ?? selectionTag,
      tabItemLabel: other.tabItemLabel ?? tabItemLabel
    )
  }
}

/// Lifecycle handlers and task metadata attached to a node.
public struct LifecycleMetadata: Equatable, Sendable {
  public var appearHandlerIDs: [String]
  public var disappearHandlerIDs: [String]
  public var task: TaskDescriptor?

  public init(
    appearHandlerIDs: [String] = [],
    disappearHandlerIDs: [String] = [],
    task: TaskDescriptor? = nil
  ) {
    self.appearHandlerIDs = appearHandlerIDs
    self.disappearHandlerIDs = disappearHandlerIDs
    self.task = task
  }

  public var isEmpty: Bool {
    appearHandlerIDs.isEmpty
      && disappearHandlerIDs.isEmpty
      && task == nil
  }

  public func merging(_ other: Self) -> Self {
    Self(
      appearHandlerIDs: appearHandlerIDs + other.appearHandlerIDs,
      disappearHandlerIDs: disappearHandlerIDs + other.disappearHandlerIDs,
      task: other.task ?? task
    )
  }
}

/// Indexed child access for data-backed lazy containers.
package protocol IndexedChildSource: Sendable {
  var count: Int { get }
  var identityRoot: Identity { get }
  var measurementSignature: String { get }

  func child(at index: Int) -> ResolvedNode
}

/// A node produced by the resolve phase before measurement.
public struct ResolvedNode: Equatable, Sendable {
  public var identity: Identity
  public var kind: NodeKind
  public var children: [ResolvedNode] {
    didSet {
      recomputePreferenceValues()
      recomputeSubtreeNodeCount()
      recomputeSupportsRetainedReuse()
    }
  }
  public var environmentSnapshot: EnvironmentSnapshot
  public var transactionSnapshot: TransactionSnapshot
  public var layoutBehavior: LayoutBehavior {
    didSet {
      recomputeSupportsRetainedReuse()
    }
  }
  public var layoutMetadata: LayoutMetadata
  public var drawMetadata: DrawMetadata
  public var semanticMetadata: SemanticMetadata
  public var lifecycleMetadata: LifecycleMetadata
  public var drawPayload: DrawPayload
  public var intrinsicSize: Size?
  package var indexedChildSource: (any IndexedChildSource)? {
    didSet {
      recomputeSupportsRetainedReuse()
    }
  }
  package var preferenceValues: PreferenceValues
  package private(set) var subtreeNodeCount: Int
  public var supportsRetainedReuse: Bool

  public init(
    identity: Identity,
    kind: NodeKind,
    children: [ResolvedNode] = [],
    environmentSnapshot: EnvironmentSnapshot = .init(),
    transactionSnapshot: TransactionSnapshot = .init(),
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    intrinsicSize: Size? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.children = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self.layoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self.drawMetadata = drawMetadata
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = nil
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    self.supportsRetainedReuse = true
    recomputeSubtreeNodeCount()
    recomputeSupportsRetainedReuse()
  }

  package init(
    identity: Identity,
    kind: NodeKind,
    children: [ResolvedNode] = [],
    environmentSnapshot: EnvironmentSnapshot = .init(),
    transactionSnapshot: TransactionSnapshot = .init(),
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    intrinsicSize: Size? = nil,
    indexedChildSource: (any IndexedChildSource)? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.children = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self.layoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self.drawMetadata = drawMetadata
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = indexedChildSource
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    self.supportsRetainedReuse = true
    recomputeSubtreeNodeCount()
    recomputeSupportsRetainedReuse()
  }

  private mutating func recomputePreferenceValues() {
    preferenceValues = Self.combinedPreferenceValues(for: children)
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }

  private mutating func recomputeSupportsRetainedReuse() {
    supportsRetainedReuse = Self.computeSupportsRetainedReuse(
      layoutBehavior: layoutBehavior,
      children: children,
      indexedChildSource: indexedChildSource
    )
  }

  private static func combinedPreferenceValues(
    for children: [ResolvedNode]
  ) -> PreferenceValues {
    var combined = PreferenceValues()
    for child in children {
      combined.merge(child.preferenceValues)
    }
    return combined
  }

  private static func computeSupportsRetainedReuse(
    layoutBehavior: LayoutBehavior,
    children: [ResolvedNode],
    indexedChildSource: (any IndexedChildSource)?
  ) -> Bool {
    if indexedChildSource != nil {
      return false
    }

    switch layoutBehavior {
    case .viewThatFits, .custom:
      return false
    default:
      return children.allSatisfy(\.supportsRetainedReuse)
    }
  }

  package var usesIndexedChildSource: Bool {
    indexedChildSource != nil
  }

  package func descendant(
    with identity: Identity
  ) -> ResolvedNode? {
    if self.identity == identity {
      return self
    }
    for child in children {
      if let match = child.descendant(with: identity) {
        return match
      }
    }
    return nil
  }

  package func path(
    to identity: Identity
  ) -> [Identity]? {
    if self.identity == identity {
      return [self.identity]
    }
    for child in children {
      if let childPath = child.path(to: identity) {
        return [self.identity] + childPath
      }
    }
    return nil
  }

  package func collectIdentities(into identities: inout [Identity]) {
    identities.append(identity)
    for child in children {
      child.collectIdentities(into: &identities)
    }
  }

  package func collectIdentities() -> [Identity] {
    var identities: [Identity] = []
    collectIdentities(into: &identities)
    return identities
  }

  package func collectLifecycleNodes(
    into nodes: inout [LifecycleStateNode]
  ) {
    if !lifecycleMetadata.isEmpty {
      nodes.append(
        LifecycleStateNode(
          identity: identity,
          appearHandlerIDs: lifecycleMetadata.appearHandlerIDs,
          disappearHandlerIDs: lifecycleMetadata.disappearHandlerIDs,
          task: lifecycleMetadata.task
        )
      )
    }

    for child in children {
      child.collectLifecycleNodes(into: &nodes)
    }
  }

  package func collectLifecycleHandlerIDs(
    appearIDs: inout [String],
    disappearIDs: inout [String]
  ) {
    appearIDs.append(contentsOf: lifecycleMetadata.appearHandlerIDs)
    disappearIDs.append(contentsOf: lifecycleMetadata.disappearHandlerIDs)

    for child in children {
      child.collectLifecycleHandlerIDs(
        appearIDs: &appearIDs,
        disappearIDs: &disappearIDs
      )
    }
  }

  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    identity == other.identity
      && kind == other.kind
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && drawPayload.isEquivalentForMeasurement(to: other.drawPayload)
      && intrinsicSize == other.intrinsicSize
      && indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature
      && children.count == other.children.count
      && zip(children, other.children).allSatisfy { lhsChild, rhsChild in
        lhsChild.isEquivalentForMeasurement(to: rhsChild)
      }
  }

  /// Stricter equivalence check used by the retained layout placement cache.
  /// Like `isEquivalentForMeasurement` but uses full draw payload equality
  /// instead of the relaxed measurement comparison, ensuring that visual-only
  /// changes (such as a shape's stroke style changing from thick to thin) are
  /// detected even when they don't affect measurement.
  package func isEquivalentForPlacement(
    to other: Self
  ) -> Bool {
    identity == other.identity
      && kind == other.kind
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && drawPayload == other.drawPayload
      && intrinsicSize == other.intrinsicSize
      && indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature
      && children.count == other.children.count
      && zip(children, other.children).allSatisfy { lhsChild, rhsChild in
        lhsChild.isEquivalentForPlacement(to: rhsChild)
      }
  }
}

extension ResolvedNode {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity
      && lhs.kind == rhs.kind
      && lhs.children == rhs.children
      && lhs.environmentSnapshot == rhs.environmentSnapshot
      && lhs.transactionSnapshot == rhs.transactionSnapshot
      && lhs.layoutBehavior == rhs.layoutBehavior
      && lhs.layoutMetadata == rhs.layoutMetadata
      && lhs.drawMetadata == rhs.drawMetadata
      && lhs.semanticMetadata == rhs.semanticMetadata
      && lhs.lifecycleMetadata == rhs.lifecycleMetadata
      && lhs.drawPayload == rhs.drawPayload
      && lhs.intrinsicSize == rhs.intrinsicSize
      && lhs.indexedChildSource?.measurementSignature
        == rhs.indexedChildSource?.measurementSignature
      && lhs.preferenceValues == rhs.preferenceValues
      && lhs.supportsRetainedReuse == rhs.supportsRetainedReuse
  }
}

/// Semantic role assigned to a placed node for extraction and rendering.
public enum SemanticRole: String, Equatable, Sendable {
  case generic
  case container
  case control
  case scroll
  case overlay
}

/// A node after layout has assigned concrete bounds.
public struct PlacedNode: Equatable, Sendable {
  public var identity: Identity
  public var kind: NodeKind
  public var environmentSnapshot: EnvironmentSnapshot
  public var bounds: Rect
  public var contentBounds: Rect
  public var clipBounds: Rect?
  public var zIndex: Double
  public var children: [PlacedNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  public var semanticRole: SemanticRole
  public var layoutMetadata: LayoutMetadata
  public var drawMetadata: DrawMetadata
  public var semanticMetadata: SemanticMetadata
  public var lifecycleMetadata: LifecycleMetadata
  public var drawPayload: DrawPayload
  package private(set) var subtreeNodeCount: Int

  public init(
    identity: Identity,
    kind: NodeKind = .view("Unknown"),
    environmentSnapshot: EnvironmentSnapshot = .init(),
    bounds: Rect,
    contentBounds: Rect? = nil,
    clipBounds: Rect? = nil,
    zIndex: Double = 0,
    children: [PlacedNode] = [],
    semanticRole: SemanticRole = .generic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none
  ) {
    self.identity = identity
    self.kind = kind
    self.environmentSnapshot = environmentSnapshot
    self.bounds = bounds
    self.contentBounds = contentBounds ?? bounds
    self.clipBounds = clipBounds
    self.zIndex = zIndex
    self.children = children
    self.semanticRole = semanticRole
    self.layoutMetadata = layoutMetadata
    self.drawMetadata = drawMetadata
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }

  package func collectLifecycleNodes(
    into nodes: inout [LifecycleStateNode]
  ) {
    if !lifecycleMetadata.isEmpty {
      nodes.append(
        LifecycleStateNode(
          identity: identity,
          appearHandlerIDs: lifecycleMetadata.appearHandlerIDs,
          disappearHandlerIDs: lifecycleMetadata.disappearHandlerIDs,
          task: lifecycleMetadata.task
        )
      )
    }

    for child in children {
      child.collectLifecycleNodes(into: &nodes)
    }
  }
}

/// A rectangular hit region for keyboard or pointer interaction.
public struct InteractionRegion: Equatable, Sendable {
  public var identity: Identity
  public var rect: Rect
  public var routeID: RouteID
  public var hitTestOrder: Int

  public init(
    identity: Identity,
    rect: Rect,
    routeID: RouteID,
    hitTestOrder: Int = 0
  ) {
    self.identity = identity
    self.rect = rect
    self.routeID = routeID
    self.hitTestOrder = hitTestOrder
  }
}

/// A focusable region extracted from the placed tree.
public struct FocusRegion: Equatable, Sendable {
  public var identity: Identity
  public var rect: Rect
  public var focusInteractions: FocusInteractions
  package var scopePath: [Identity]
  package var sectionIdentity: Identity?

  public init(
    identity: Identity,
    rect: Rect,
    focusInteractions: FocusInteractions = .automatic,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil
  ) {
    self.identity = identity
    self.rect = rect
    self.focusInteractions = focusInteractions
    self.scopePath = scopePath
    self.sectionIdentity = sectionIdentity
  }
}

/// Scroll metadata extracted for a scrollable node.
public struct ScrollRoute: Equatable, Sendable {
  public var identity: Identity
  public var viewportRect: Rect
  public var contentBounds: Rect

  public init(
    identity: Identity,
    viewportRect: Rect,
    contentBounds: Rect
  ) {
    self.identity = identity
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
  }
}

/// Selection metadata extracted for list-like controls.
public struct SelectionRoute: Equatable, Sendable {
  public var identity: Identity
  public var role: ScrollRole

  public init(identity: Identity, role: ScrollRole) {
    self.identity = identity
    self.role = role
  }
}

/// Navigation metadata extracted for focus and scene movement.
public struct NavigationRoute: Equatable, Sendable {
  public var identity: Identity

  public init(identity: Identity) {
    self.identity = identity
  }
}

/// The complete semantic extraction result for a frame.
public struct SemanticSnapshot: Equatable, Sendable {
  public var interactionRegions: [InteractionRegion]
  public var focusRegions: [FocusRegion]
  public var navigationRoutes: [NavigationRoute]
  public var scrollRoutes: [ScrollRoute]
  public var selectionRoutes: [SelectionRoute]

  public init(
    interactionRegions: [InteractionRegion] = [],
    focusRegions: [FocusRegion] = [],
    navigationRoutes: [NavigationRoute] = [],
    scrollRoutes: [ScrollRoute] = [],
    selectionRoutes: [SelectionRoute] = []
  ) {
    self.interactionRegions = interactionRegions
    self.focusRegions = focusRegions
    self.navigationRoutes = navigationRoutes
    self.scrollRoutes = scrollRoutes
    self.selectionRoutes = selectionRoutes
  }
}

public indirect enum DrawCommand: Equatable, Sendable {
  case group(bounds: Rect, children: [DrawCommand])
  case text(
    bounds: Rect,
    content: String,
    style: TextStyle,
    lineLimit: Int?,
    truncationMode: TextTruncationMode,
    wrappingStrategy: TextWrappingStrategy
  )
  case richText(
    bounds: Rect,
    payload: RichTextPayload,
    lineLimit: Int?,
    truncationMode: TextTruncationMode,
    wrappingStrategy: TextWrappingStrategy
  )
  case image(bounds: Rect, identity: Identity, payload: ImagePayload)
  case fill(
    bounds: Rect,
    geometry: ShapeGeometry,
    style: AnyShapeStyle,
    mode: ShapeFillMode
  )
  case stroke(
    bounds: Rect,
    geometry: ShapeGeometry,
    style: AnyShapeStyle,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle? = nil
  )
  case rule(bounds: Rect, style: AnyShapeStyle, strokeStyle: StrokeStyle, stackAxis: Axis?)
  case clip(bounds: Rect, child: DrawCommand)
}

/// A node in the draw tree emitted before rasterization.
public struct DrawNode: Equatable, Sendable {
  public var identity: Identity
  public var environmentSnapshot: EnvironmentSnapshot
  public var bounds: Rect
  public var clipBounds: Rect?
  public var metadata: DrawMetadata
  public var commands: [DrawCommand]
  public var children: [DrawNode] {
    didSet {
      recomputeSubtreeNodeCount()
    }
  }
  package private(set) var subtreeNodeCount: Int

  public init(
    identity: Identity,
    environmentSnapshot: EnvironmentSnapshot = .init(),
    bounds: Rect,
    clipBounds: Rect? = nil,
    metadata: DrawMetadata = .init(),
    commands: [DrawCommand] = [],
    children: [DrawNode] = []
  ) {
    self.identity = identity
    self.environmentSnapshot = environmentSnapshot
    self.bounds = bounds
    self.clipBounds = clipBounds
    self.metadata = metadata
    self.commands = commands
    self.children = children
    subtreeNodeCount = 1
    recomputeSubtreeNodeCount()
  }

  private mutating func recomputeSubtreeNodeCount() {
    subtreeNodeCount = 1 + children.reduce(0) { $0 + $1.subtreeNodeCount }
  }
}
