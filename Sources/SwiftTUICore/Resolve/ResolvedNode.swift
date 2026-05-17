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

/// Marker for visual-only content that needs an accessibility label or hidden policy.
package struct AccessibilityVisualContent: Equatable, Sendable {
  package var kind: String

  package init(kind: String) {
    self.kind = kind
  }
}

/// Semantic and interaction metadata attached to a resolved node.
public struct SemanticMetadata: Equatable, Sendable {
  private var flags: UInt16
  package var focusScopeIdentity: Identity?
  /// When `true`, focusable descendants of this node are suppressed
  /// during semantic extraction — the node itself remains focusable
  /// (if its other metadata marks it so) but its descendants do not
  /// appear in the focus region list. Set by
  /// `Panel.focusContainment(.sealed)`.
  public var focusInteractions: FocusInteractions
  public var scrollRole: ScrollRole?
  public var sectionRole: SectionRole?
  public var accessibilityRole: AccessibilityRole?
  public var accessibilityLabel: String?
  public var accessibilityHint: String?
  public var accessibilityLiveRegion: AccessibilityPoliteness?
  package var accessibilityVisualContent: AccessibilityVisualContent?
  package var accessibilityCursorAnchor: CellPoint?
  package var textInputAccessibilityCursorAnchor: TextInputAccessibilityCursorAnchor?
  public var selectionTag: SelectionTag?
  public var tabItemLabel: TabItemLabel?
  public var explicitInteractionRect: CellRect?
  public var explicitInteractionPath: Path?
  public var namedCoordinateSpaceName: String?
  package var interactionAvailability: InteractionAvailability

  package var focusScopeBoundary: Bool {
    get { flag(Self.focusScopeBoundaryFlag) }
    set { setFlag(Self.focusScopeBoundaryFlag, to: newValue) }
  }

  package var focusSectionBoundary: Bool {
    get { flag(Self.focusSectionBoundaryFlag) }
    set { setFlag(Self.focusSectionBoundaryFlag, to: newValue) }
  }

  package var sealsFocusDescendants: Bool {
    get { flag(Self.sealsFocusDescendantsFlag) }
    set { setFlag(Self.sealsFocusDescendantsFlag, to: newValue) }
  }

  public var participatesInPointerHitTesting: Bool {
    get { flag(Self.participatesInPointerHitTestingFlag) }
    set { setFlag(Self.participatesInPointerHitTestingFlag, to: newValue) }
  }

  public var captureOnPress: Bool {
    get { flag(Self.captureOnPressFlag) }
    set { setFlag(Self.captureOnPressFlag, to: newValue) }
  }

  public var allowsHitTesting: Bool {
    get { flag(Self.allowsHitTestingFlag) }
    set { setFlag(Self.allowsHitTestingFlag, to: newValue) }
  }

  public var accessibilityHidden: Bool {
    get { flag(Self.accessibilityHiddenFlag) }
    set { setFlag(Self.accessibilityHiddenFlag, to: newValue) }
  }

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

  private var explicitFocusability: Bool? {
    get {
      guard flag(Self.explicitFocusabilityHasValueFlag) else {
        return nil
      }
      return flag(Self.explicitFocusabilityValueFlag)
    }
    set {
      guard let newValue else {
        setFlag(Self.explicitFocusabilityHasValueFlag, to: false)
        setFlag(Self.explicitFocusabilityValueFlag, to: false)
        return
      }
      setFlag(Self.explicitFocusabilityHasValueFlag, to: true)
      setFlag(Self.explicitFocusabilityValueFlag, to: newValue)
    }
  }

  public init(
    isFocusable: Bool? = nil,
    focusInteractions: FocusInteractions = .automatic,
    participatesInPointerHitTesting: Bool = false,
    captureOnPress: Bool = false,
    allowsHitTesting: Bool = true,
    scrollRole: ScrollRole? = nil,
    sectionRole: SectionRole? = nil,
    accessibilityRole: AccessibilityRole? = nil,
    accessibilityLabel: String? = nil,
    accessibilityHint: String? = nil,
    accessibilityHidden: Bool = false,
    accessibilityLiveRegion: AccessibilityPoliteness? = nil,
    selectionTag: SelectionTag? = nil,
    tabItemLabel: TabItemLabel? = nil,
    explicitInteractionRect: CellRect? = nil,
    explicitInteractionPath: Path? = nil,
    namedCoordinateSpaceName: String? = nil
  ) {
    self.init(
      isFocusable: isFocusable,
      focusScopeBoundary: false,
      focusScopeIdentity: nil,
      focusSectionBoundary: false,
      sealsFocusDescendants: false,
      focusInteractions: focusInteractions,
      participatesInPointerHitTesting: participatesInPointerHitTesting,
      captureOnPress: captureOnPress,
      allowsHitTesting: allowsHitTesting,
      scrollRole: scrollRole,
      sectionRole: sectionRole,
      accessibilityRole: accessibilityRole,
      accessibilityLabel: accessibilityLabel,
      accessibilityHint: accessibilityHint,
      accessibilityHidden: accessibilityHidden,
      accessibilityLiveRegion: accessibilityLiveRegion,
      selectionTag: selectionTag,
      tabItemLabel: tabItemLabel,
      explicitInteractionRect: explicitInteractionRect,
      explicitInteractionPath: explicitInteractionPath,
      namedCoordinateSpaceName: namedCoordinateSpaceName
    )
  }

  package init(
    isFocusable: Bool? = nil,
    focusScopeBoundary: Bool = false,
    focusScopeIdentity: Identity? = nil,
    focusSectionBoundary: Bool = false,
    sealsFocusDescendants: Bool = false,
    focusInteractions: FocusInteractions = .automatic,
    participatesInPointerHitTesting: Bool = false,
    captureOnPress: Bool = false,
    allowsHitTesting: Bool = true,
    scrollRole: ScrollRole? = nil,
    sectionRole: SectionRole? = nil,
    accessibilityRole: AccessibilityRole? = nil,
    accessibilityLabel: String? = nil,
    accessibilityHint: String? = nil,
    accessibilityHidden: Bool = false,
    accessibilityLiveRegion: AccessibilityPoliteness? = nil,
    accessibilityVisualContent: AccessibilityVisualContent? = nil,
    accessibilityCursorAnchor: CellPoint? = nil,
    textInputAccessibilityCursorAnchor: TextInputAccessibilityCursorAnchor? = nil,
    selectionTag: SelectionTag? = nil,
    tabItemLabel: TabItemLabel? = nil,
    explicitInteractionRect: CellRect? = nil,
    explicitInteractionPath: Path? = nil,
    namedCoordinateSpaceName: String? = nil,
    interactionAvailability: InteractionAvailability = .enabled
  ) {
    flags = Self.makeFlags(
      isFocusable: isFocusable,
      focusScopeBoundary: focusScopeBoundary,
      focusSectionBoundary: focusSectionBoundary,
      sealsFocusDescendants: sealsFocusDescendants,
      participatesInPointerHitTesting: participatesInPointerHitTesting,
      captureOnPress: captureOnPress,
      allowsHitTesting: allowsHitTesting,
      accessibilityHidden: accessibilityHidden
    )
    self.focusScopeIdentity = focusScopeIdentity
    self.focusInteractions = focusInteractions
    self.scrollRole = scrollRole
    self.sectionRole = sectionRole
    self.accessibilityRole = accessibilityRole
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.accessibilityLiveRegion = accessibilityLiveRegion
    self.accessibilityVisualContent = accessibilityVisualContent
    self.accessibilityCursorAnchor = accessibilityCursorAnchor
    self.textInputAccessibilityCursorAnchor = textInputAccessibilityCursorAnchor
    self.selectionTag = selectionTag
    self.tabItemLabel = tabItemLabel
    self.explicitInteractionRect = explicitInteractionRect
    self.explicitInteractionPath = explicitInteractionPath
    self.namedCoordinateSpaceName = namedCoordinateSpaceName
    self.interactionAvailability = interactionAvailability
  }

  public func merging(_ other: Self) -> Self {
    Self(
      isFocusable: other.explicitFocusability ?? explicitFocusability,
      focusScopeBoundary: other.focusScopeBoundary || focusScopeBoundary,
      focusScopeIdentity: other.focusScopeIdentity ?? focusScopeIdentity,
      focusSectionBoundary: other.focusSectionBoundary || focusSectionBoundary,
      sealsFocusDescendants: other.sealsFocusDescendants || sealsFocusDescendants,
      focusInteractions: other.focusInteractions == .automatic
        ? focusInteractions
        : other.focusInteractions,
      participatesInPointerHitTesting: other.participatesInPointerHitTesting
        || participatesInPointerHitTesting,
      captureOnPress: other.captureOnPress || captureOnPress,
      allowsHitTesting: other.allowsHitTesting && allowsHitTesting,
      scrollRole: other.scrollRole ?? scrollRole,
      sectionRole: other.sectionRole ?? sectionRole,
      accessibilityRole: other.accessibilityRole ?? accessibilityRole,
      accessibilityLabel: other.accessibilityLabel ?? accessibilityLabel,
      accessibilityHint: other.accessibilityHint ?? accessibilityHint,
      accessibilityHidden: other.accessibilityHidden || accessibilityHidden,
      accessibilityLiveRegion: other.accessibilityLiveRegion ?? accessibilityLiveRegion,
      accessibilityVisualContent: other.accessibilityVisualContent ?? accessibilityVisualContent,
      accessibilityCursorAnchor: other.accessibilityCursorAnchor ?? accessibilityCursorAnchor,
      textInputAccessibilityCursorAnchor: other.textInputAccessibilityCursorAnchor
        ?? textInputAccessibilityCursorAnchor,
      selectionTag: other.selectionTag ?? selectionTag,
      tabItemLabel: other.tabItemLabel ?? tabItemLabel,
      explicitInteractionRect: other.explicitInteractionRect ?? explicitInteractionRect,
      explicitInteractionPath: other.explicitInteractionPath ?? explicitInteractionPath,
      namedCoordinateSpaceName: other.namedCoordinateSpaceName ?? namedCoordinateSpaceName,
      interactionAvailability: mergedInteractionAvailability(
        interactionAvailability,
        other.interactionAvailability
      )
    )
  }

  private static let explicitFocusabilityHasValueFlag: UInt16 = 1 << 0
  private static let explicitFocusabilityValueFlag: UInt16 = 1 << 1
  private static let focusScopeBoundaryFlag: UInt16 = 1 << 2
  private static let focusSectionBoundaryFlag: UInt16 = 1 << 3
  private static let sealsFocusDescendantsFlag: UInt16 = 1 << 4
  private static let participatesInPointerHitTestingFlag: UInt16 = 1 << 5
  private static let captureOnPressFlag: UInt16 = 1 << 6
  private static let allowsHitTestingFlag: UInt16 = 1 << 7
  private static let accessibilityHiddenFlag: UInt16 = 1 << 8

  private func flag(_ bit: UInt16) -> Bool {
    flags & bit != 0
  }

  private mutating func setFlag(
    _ bit: UInt16,
    to value: Bool
  ) {
    if value {
      flags |= bit
    } else {
      flags &= ~bit
    }
  }

  private static func makeFlags(
    isFocusable: Bool?,
    focusScopeBoundary: Bool,
    focusSectionBoundary: Bool,
    sealsFocusDescendants: Bool,
    participatesInPointerHitTesting: Bool,
    captureOnPress: Bool,
    allowsHitTesting: Bool,
    accessibilityHidden: Bool
  ) -> UInt16 {
    var flags: UInt16 = 0
    if let isFocusable {
      flags |= explicitFocusabilityHasValueFlag
      if isFocusable {
        flags |= explicitFocusabilityValueFlag
      }
    }
    if focusScopeBoundary {
      flags |= focusScopeBoundaryFlag
    }
    if focusSectionBoundary {
      flags |= focusSectionBoundaryFlag
    }
    if sealsFocusDescendants {
      flags |= sealsFocusDescendantsFlag
    }
    if participatesInPointerHitTesting {
      flags |= participatesInPointerHitTestingFlag
    }
    if captureOnPress {
      flags |= captureOnPressFlag
    }
    if allowsHitTesting {
      flags |= allowsHitTestingFlag
    }
    if accessibilityHidden {
      flags |= accessibilityHiddenFlag
    }
    return flags
  }
}

package struct TextInputAccessibilityCursorAnchor: Equatable, Sendable {
  package var ownerIdentity: Identity
  package var anchor: CellPoint

  package init(
    ownerIdentity: Identity,
    anchor: CellPoint
  ) {
    self.ownerIdentity = ownerIdentity
    self.anchor = anchor
  }
}

private func mergedInteractionAvailability(
  _ current: InteractionAvailability,
  _ next: InteractionAvailability
) -> InteractionAvailability {
  switch (current, next) {
  case (.disabled, _):
    current
  case (_, .disabled):
    next
  case (.enabled, .enabled):
    .enabled
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
  var canRunOnWorker: Bool { get }
  var workerResolvedChildren: [ResolvedNode]? { get }

  func child(at index: Int) -> ResolvedNode
}

extension IndexedChildSource {
  package var canRunOnWorker: Bool { false }
  package var workerResolvedChildren: [ResolvedNode]? { nil }
}

/// Sendable resolved-child snapshot for lazy indexed containers that have
/// already materialized their authored children on the main actor.
package struct IndexedChildSourceSnapshot: IndexedChildSource {
  package let identityRoot: Identity
  package let measurementSignature: String
  private let children: [ResolvedNode]

  package init(
    identityRoot: Identity,
    measurementSignature: String,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.measurementSignature = measurementSignature
    self.children = children
  }

  package var count: Int {
    children.count
  }

  package var canRunOnWorker: Bool {
    true
  }

  package var workerResolvedChildren: [ResolvedNode]? {
    children
  }

  package func child(at index: Int) -> ResolvedNode {
    children[index]
  }
}

/// An opaque namespace used to scope matched-geometry IDs so the
/// same string-or-hashable key can refer to unrelated views in
/// different parts of the hierarchy.
///
/// Mirrors SwiftUI's `Namespace.ID` shape but without the
/// `@Namespace` property-wrapper ceremony — call sites either use
/// ``default`` for a single global namespace or pass a distinct
/// value per namespace.
public struct MatchedGeometryNamespace: Hashable, Sendable {
  public let rawValue: UInt64
  public init(_ rawValue: UInt64) { self.rawValue = rawValue }
  public static let `default` = MatchedGeometryNamespace(0)
}

/// A fully-qualified matched-geometry identifier — the namespace
/// plus the user-provided hashable ID, erased to a string for
/// cross-frame lookup.
public struct MatchedGeometryKey: Hashable, Sendable {
  public let namespace: MatchedGeometryNamespace
  /// The erased string form of the caller's ID.  Two calls with
  /// `Hashable` values whose `String(describing:)` output matches
  /// will collide — callers needing stronger uniqueness should use
  /// distinct namespaces.
  public let id: String

  public init(namespace: MatchedGeometryNamespace, id: String) {
    self.namespace = namespace
    self.id = id
  }

  public init<ID: Hashable>(namespace: MatchedGeometryNamespace = .default, id: ID) {
    self.namespace = namespace
    self.id = String(describing: id)
  }
}

/// Per-view-instance configuration carried alongside a
/// ``MatchedGeometryKey`` on a resolved/placed node.  Currently
/// only the `isSource` flag is stored; future extensions (e.g.
/// per-property opt-outs) land here.
public struct MatchedGeometryConfig: Equatable, Sendable {
  public var key: MatchedGeometryKey
  /// Whether this view contributes its geometry as the "from"
  /// source for the match.  When multiple views share the same
  /// key in the same frame, the last depth-first walk wins as the
  /// source; views marked `isSource: false` never contribute.
  /// Matches SwiftUI's `matchedGeometryEffect(id:in:properties:anchor:isSource:)`
  /// semantics for the `isSource` parameter.
  public var isSource: Bool

  public init(key: MatchedGeometryKey, isSource: Bool = true) {
    self.key = key
    self.isSource = isSource
  }
}

/// A node produced by the resolve phase before measurement.
///
/// Resolve owns the lowered tree shape, identity, environment, transaction,
/// layout behavior, metadata, handlers, draw payloads, and authored-state
/// snapshots that later phases consume.  Fields such as `preferenceValues`,
/// `subtreeNodeCount`, and `supportsRetainedReuse` are derived cache inputs
/// maintained beside the authoritative resolved data.  Later phase products may
/// mirror subsets of this data, but every retained reuse path must refresh those
/// mirrors from the current `ResolvedNode` before semantics, draw, lifecycle, or
/// animation code observes them.
public struct ResolvedNode: Equatable, Sendable {
  public var identity: Identity
  package var kind: NodeKind
  /// Stable per-Swift-type discriminator carried alongside `kind`.
  ///
  /// `NodeKind.view(String)` is a human-readable role name (e.g. `"Text"`,
  /// `"Padding"`) that any call site can produce.  When two unrelated views
  /// happen to pick the same name — intentionally for modifier roles or by
  /// accident for primitives — the string alone cannot tell them apart, and
  /// a structural diff would fuse them.  A concrete primitive that
  /// populates this field with `ObjectIdentifier(Self.self)` refines the
  /// String identity with a type-level guarantee.
  ///
  /// Left `nil` by most call sites during the incremental migration.
  /// `ChildDescriptor` equality treats `nil` as "compatible with either
  /// side" so populated and legacy descriptors still match when their
  /// names agree, keeping the migration churn-free.
  package var typeDiscriminator: ObjectIdentifier?
  /// Backing storage for ``children``.  Direct access is
  /// package-scoped so animation tick frames can replace interpolated
  /// children in place via ``setChildrenPreservingDerivedState(_:)``
  /// without paying for preference/node-count/reuse recomputes on
  /// every frame.  All external writes must go through the public
  /// ``children`` setter, which keeps the derived state correct.
  package var _storedChildren: [ResolvedNode]
  public var children: [ResolvedNode] {
    get { _storedChildren }
    set {
      _storedChildren = newValue
      recomputePreferenceValues()
      recomputeSubtreeNodeCount()
      recomputeSupportsRetainedReuse()
    }
  }

  /// Package-only write path that skips the derived-state recomputes
  /// triggered by the normal ``children`` setter.  Intended for
  /// animation tick frames, where each child is replaced with an
  /// interpolated copy that has the same shape — so the derived
  /// subtree node count, preference aggregate, and retained-reuse bit
  /// cannot change.
  ///
  /// If the replacement changes the child count, preference set, or
  /// support-retained-reuse bit, use the normal setter instead — this
  /// method makes no correctness guarantee for structural changes.
  package mutating func setChildrenPreservingDerivedState(_ newChildren: [ResolvedNode]) {
    _storedChildren = newChildren
  }
  public var environmentSnapshot: EnvironmentSnapshot
  public var transactionSnapshot: TransactionSnapshot
  /// Backing storage for ``layoutBehavior``.  Direct access is
  /// package-scoped so animation tick frames can overwrite the
  /// layout behavior with an interpolated copy without paying for
  /// the ``recomputeSupportsRetainedReuse`` recompute, which is a
  /// no-op for animation tick frames that only change numeric
  /// dimensions within the same layout variant.
  package var _storedLayoutBehavior: LayoutBehavior
  public var layoutBehavior: LayoutBehavior {
    get { _storedLayoutBehavior }
    set {
      _storedLayoutBehavior = newValue
      recomputeSupportsRetainedReuse()
    }
  }

  /// Package-only write path that skips the
  /// ``recomputeSupportsRetainedReuse`` call fired by the normal
  /// ``layoutBehavior`` setter.  Intended for animation tick frames
  /// that mutate numeric dimensions within the same layout variant
  /// (e.g. updating `.frame(width:)` or `.padding(_:)` without
  /// changing the variant itself), where the reuse bit is stable.
  package mutating func setLayoutBehaviorPreservingDerivedState(_ newBehavior: LayoutBehavior) {
    _storedLayoutBehavior = newBehavior
  }
  package var layoutMetadata: LayoutMetadata
  package var drawMetadata: DrawMetadata {
    get { _boxedDrawMetadata.value }
    set { _boxedDrawMetadata.value = newValue }
  }
  package var _boxedDrawMetadata: Boxed<DrawMetadata>
  public var semanticMetadata: SemanticMetadata
  public var lifecycleMetadata: LifecycleMetadata
  @_spi(Testing) public var drawPayload: DrawPayload
  public var intrinsicSize: CellSize?
  package var indexedChildSource: (any IndexedChildSource)? {
    didSet {
      recomputeSupportsRetainedReuse()
    }
  }
  package var layoutDependentContent: LayoutDependentContentBoundary? {
    didSet {
      recomputeSupportsRetainedReuse()
    }
  }
  package var preferenceValues: PreferenceValues
  package private(set) var subtreeNodeCount: Int
  public var supportsRetainedReuse: Bool
  /// Matched-geometry configuration set by
  /// `View.matchedGeometryEffect(id:in:isSource:)`.  When two
  /// views in different frames (typically behind an `if`/`else`
  /// branch) share the same key, the animation controller treats
  /// the swap as a single view moving from the previous frame's
  /// placed bounds to the new frame's placed bounds and animates
  /// the translation under `withAnimation`.
  public var matchedGeometry: MatchedGeometryConfig? = nil
  /// Marks the node (and transitively any node that inherits this
  /// flag via the layout engine) as a non-semantic visual overlay.
  /// The animation controller sets this on every node in a removal
  /// overlay subtree it injects during a `.transition(...)` exit.
  ///
  /// Transient nodes flow through the draw/raster path normally, so
  /// they stay visible for the duration of the exit animation, but
  /// are skipped by the semantic extractor, focus tracker, lifecycle
  /// coordinator, and interaction hit testing.  Anything sitting on
  /// the "is the committed tree still the authoritative source for
  /// routing?" axis must filter transient nodes out.
  public var isTransient: Bool = false

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
    intrinsicSize: CellSize? = nil,
    layoutDependentContent: LayoutDependentContentBoundary? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.typeDiscriminator = nil
    // Assign the backing stores directly — the computed setters would
    // touch the derived stored properties (preferenceValues, etc.)
    // which are not yet initialized at this point.  We run the
    // derived-state computation once at the end of init.
    self._storedChildren = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self._storedLayoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = nil
    self.layoutDependentContent = layoutDependentContent
    preferenceValues = Self.combinedPreferenceValues(for: children)
    subtreeNodeCount = 1
    self.supportsRetainedReuse = true
    recomputeSubtreeNodeCount()
    recomputeSupportsRetainedReuse()
  }

  package init(
    identity: Identity,
    kind: NodeKind,
    typeDiscriminator: ObjectIdentifier? = nil,
    children: [ResolvedNode] = [],
    environmentSnapshot: EnvironmentSnapshot = .init(),
    transactionSnapshot: TransactionSnapshot = .init(),
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    drawMetadata: DrawMetadata = DrawMetadata(),
    semanticMetadata: SemanticMetadata = SemanticMetadata(),
    lifecycleMetadata: LifecycleMetadata = .init(),
    drawPayload: DrawPayload = .none,
    intrinsicSize: CellSize? = nil,
    indexedChildSource: (any IndexedChildSource)? = nil,
    layoutDependentContent: LayoutDependentContentBoundary? = nil
  ) {
    self.identity = identity
    self.kind = kind
    self.typeDiscriminator = typeDiscriminator
    self._storedChildren = children
    self.environmentSnapshot = environmentSnapshot
    self.transactionSnapshot = transactionSnapshot
    self._storedLayoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self._boxedDrawMetadata = Boxed(drawMetadata)
    self.semanticMetadata = semanticMetadata
    self.lifecycleMetadata = lifecycleMetadata
    self.drawPayload = drawPayload
    self.intrinsicSize = intrinsicSize
    self.indexedChildSource = indexedChildSource
    self.layoutDependentContent = layoutDependentContent
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
      indexedChildSource: indexedChildSource,
      layoutDependentContent: layoutDependentContent
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
    indexedChildSource: (any IndexedChildSource)?,
    layoutDependentContent: LayoutDependentContentBoundary?
  ) -> Bool {
    if indexedChildSource != nil {
      return false
    }
    if layoutDependentContent != nil {
      return false
    }

    switch layoutBehavior {
    case .viewThatFits:
      return false
    case .custom(let handle):
      return handle.measurementReuseSignature != nil
        && handle.placementReuseSignature != nil
        && children.allSatisfy(\.supportsRetainedReuse)
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
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      if node.identity == identity {
        return node
      }
      for child in node.children.reversed() {
        stack.append(child)
      }
    }
    return nil
  }

  package func path(
    to identity: Identity
  ) -> [Identity]? {
    var stack: [(node: ResolvedNode, isExiting: Bool)] = [(self, false)]
    var path: [Identity] = []

    while let frame = stack.popLast() {
      if frame.isExiting {
        path.removeLast()
        continue
      }

      path.append(frame.node.identity)
      if frame.node.identity == identity {
        return path
      }

      stack.append((frame.node, true))
      for child in frame.node.children.reversed() {
        stack.append((child, false))
      }
    }

    return nil
  }

  package func collectIdentities(into identities: inout [Identity]) {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      identities.append(node.identity)
      for child in node.children.reversed() {
        stack.append(child)
      }
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
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      if !node.lifecycleMetadata.isEmpty {
        nodes.append(
          LifecycleStateNode(
            identity: node.identity,
            appearHandlerIDs: node.lifecycleMetadata.appearHandlerIDs,
            disappearHandlerIDs: node.lifecycleMetadata.disappearHandlerIDs,
            task: node.lifecycleMetadata.task
          )
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }

  package func collectLifecycleHandlerIDs(
    appearIDs: inout [String],
    disappearIDs: inout [String]
  ) {
    var stack: [ResolvedNode] = [self]
    while let node = stack.popLast() {
      appearIDs.append(contentsOf: node.lifecycleMetadata.appearHandlerIDs)
      disappearIDs.append(contentsOf: node.lifecycleMetadata.disappearHandlerIDs)

      for child in node.children.reversed() {
        stack.append(child)
      }
    }
  }

  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    identity == other.identity
      && kind == other.kind
      && Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator)
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && layoutDependentContent?.equivalenceSignature
        == other.layoutDependentContent?.equivalenceSignature
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
      && Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator)
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForPlacement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && layoutDependentContent?.equivalenceSignature
        == other.layoutDependentContent?.equivalenceSignature
      && drawPayload == other.drawPayload
      && intrinsicSize == other.intrinsicSize
      && indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature
      && children.count == other.children.count
      && zip(children, other.children).allSatisfy { lhsChild, rhsChild in
        lhsChild.isEquivalentForPlacement(to: rhsChild)
      }
  }

  /// Two discriminators are "compatible" for equivalence purposes when
  /// either both match or at least one is `nil`.  This is the bridging
  /// rule that lets migrated and un-migrated call sites coexist — a
  /// typed descriptor still matches a legacy descriptor with the same
  /// name, so partial migrations don't cause structural churn.
  package static func typeDiscriminatorsCompatible(
    _ lhs: ObjectIdentifier?,
    _ rhs: ObjectIdentifier?
  ) -> Bool {
    switch (lhs, rhs) {
    case (let l?, let r?):
      return l == r
    default:
      return true
    }
  }
}

extension ResolvedNode {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity
      && lhs.kind == rhs.kind
      && Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator)
      && lhs.children == rhs.children
      && lhs.environmentSnapshot == rhs.environmentSnapshot
      && lhs.transactionSnapshot == rhs.transactionSnapshot
      && lhs.layoutBehavior == rhs.layoutBehavior
      && lhs.layoutMetadata == rhs.layoutMetadata
      && lhs.layoutDependentContent?.equivalenceSignature
        == rhs.layoutDependentContent?.equivalenceSignature
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
