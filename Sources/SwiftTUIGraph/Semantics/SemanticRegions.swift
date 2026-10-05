/// A focusable region extracted from the placed tree.
/// Equality deliberately includes `package`-level bookkeeping fields (F120).
/// These types carry change detection through the frame pipeline.
/// Thus, externally identical values can compare `!=` if internal routing or bookkeeping differs.
/// Public consumers must not treat `==` as
/// visible-field equality.
public struct FocusRegion: Equatable, Sendable {
  public var identity: Identity
  public var rect: CellRect
  public var focusInteractions: FocusInteractions
  /// The graph node that produced this focus target, including synthetic rows.
  package var ownerNodeID: ViewNodeID?
  /// The producing value's identity. A fused modifier node can have a
  /// different structural identity from its List or other control payload.
  package var ownerIdentity: Identity?
  package var scopePath: [Identity]
  package var sectionIdentity: Identity?
  package var modalFocusScopePath: [Identity]?

  public init(
    identity: Identity,
    rect: CellRect,
    focusInteractions: FocusInteractions = .automatic,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil
  ) {
    self.identity = identity
    self.rect = rect
    self.focusInteractions = focusInteractions
    self.ownerNodeID = nil
    self.ownerIdentity = nil
    self.scopePath = scopePath
    self.sectionIdentity = sectionIdentity
    self.modalFocusScopePath = nil
  }

  package init(
    identity: Identity,
    rect: CellRect,
    focusInteractions: FocusInteractions = .automatic,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil,
    modalFocusScopePath: [Identity]?,
    ownerNodeID: ViewNodeID? = nil,
    ownerIdentity: Identity? = nil
  ) {
    self.identity = identity
    self.rect = rect
    self.focusInteractions = focusInteractions
    self.ownerNodeID = ownerNodeID
    self.ownerIdentity = ownerIdentity
    self.scopePath = scopePath
    self.sectionIdentity = sectionIdentity
    self.modalFocusScopePath = modalFocusScopePath
  }
}

/// Scroll metadata extracted for a scrollable node.
/// Equality deliberately includes `package`-level bookkeeping fields (F120).
/// These types carry change detection through the frame pipeline.
/// Thus, externally identical values can compare `!=` if internal routing or bookkeeping differs.
/// Public consumers must not treat `==` as
/// visible-field equality.
package struct LazyScrollAnchorCorrection: Equatable, Sendable {
  package var requestedOffset: CellPoint
  package var correctedOffset: CellPoint

  package init(requestedOffset: CellPoint, correctedOffset: CellPoint) {
    self.requestedOffset = requestedOffset
    self.correctedOffset = correctedOffset
  }
}

/// The measured collection window in cell units, separate from its row-based
/// navigation currency. Fixed chrome and overflow indicators make the last
/// legal row anchor differ from a plain `contentHeight - viewportHeight` clamp.
package struct CollectionScrollPosition: Equatable, Sendable {
  package var cellOffset: Int
  package var isAtStart: Bool
  package var isAtEnd: Bool

  package init(cellOffset: Int, isAtStart: Bool, isAtEnd: Bool) {
    self.cellOffset = cellOffset
    self.isAtStart = isAtStart
    self.isAtEnd = isAtEnd
  }
}

public struct ScrollRoute: Equatable, Sendable {
  package var collectionScrollPosition: CollectionScrollPosition? = nil

  /// Authored motion policy at this route, refreshed with each semantic frame.
  package var reducesMotion = false
  package var scrollAnchorCorrection: LazyScrollAnchorCorrection? = nil
  /// For a viewport-backed collection whose rows render taller than one cell,
  /// the largest scroll anchor row whose window still ends at the last row, as
  /// its layout drew it. The collection's scroll currency counts one line per
  /// row and clamps against this instead, so the last rows stay reachable.
  package var collectionMaximumAnchorRow: Int? = nil
  public var identity: Identity
  package var viewNodeID: ViewNodeID?
  public var viewportRect: CellRect
  public var contentBounds: CellRect
  /// The current clamped scroll offset of this region. The default is `.zero`.
  /// The web-host presentation boundary gets this value from the live scroll-position registry.
  /// It publishes the value as scroll-extent metadata.
  /// The browser host uses this metadata for scroll chaining.
  /// It captures the wheel only while the region can scroll in that direction. See
  /// `docs/proposals/EMBEDDED_WEB_SCROLL_CHAINING.md` in the coordination root.
  public var contentOffset: CellPoint
  /// Walk-parent identities recorded at each identity re-root boundary above
  /// this route in the placed tree, outermost first (empty when the route
  /// lives in its ancestors' identity space). An explicit `.id(_:)` re-roots
  /// the route's identity out of structural scopes like a `ScrollViewReader`'s;
  /// scope matching falls back to this chain when no identity-prefix route
  /// matched.
  package var structuralHostChain: [Identity]

  public init(
    identity: Identity,
    viewportRect: CellRect,
    contentBounds: CellRect,
    contentOffset: CellPoint = .zero
  ) {
    self.identity = identity
    viewNodeID = nil
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
    self.contentOffset = contentOffset
    structuralHostChain = []
  }

  package init(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    viewportRect: CellRect,
    contentBounds: CellRect,
    contentOffset: CellPoint = .zero,
    structuralHostChain: [Identity] = []
  ) {
    self.identity = identity
    self.viewNodeID = viewNodeID
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
    self.contentOffset = contentOffset
    self.structuralHostChain = structuralHostChain
  }
}

package enum ScrollTargetRole: Equatable, Sendable {
  case view
}

package struct ScrollTarget: Equatable, Sendable {
  package var isEstimated: Bool = false
  package var identity: Identity
  package var scrollIdentity: Identity
  package var rect: CellRect
  package var role: ScrollTargetRole

  package init(
    identity: Identity,
    scrollIdentity: Identity,
    rect: CellRect,
    role: ScrollTargetRole = .view
  ) {
    self.identity = identity
    self.scrollIdentity = scrollIdentity
    self.rect = rect
    self.role = role
  }
}

package struct ScrollTargetQuery: Equatable, Sendable {
  package var identity: Identity?
  package var explicitIDComponent: String?

  package init(
    identity: Identity? = nil,
    explicitIDComponent: String? = nil
  ) {
    self.identity = identity
    self.explicitIDComponent = explicitIDComponent
  }
}

/// Accessibility metadata extracted for assistive-technology consumers.
/// Equality deliberately includes `package`-level bookkeeping fields (F120).
/// These types carry change detection through the frame pipeline.
/// Thus, externally identical values can compare `!=` if internal routing or bookkeeping differs.
/// Public consumers must not treat `==` as
/// visible-field equality.
public struct AccessibilityNode: Equatable, Sendable {
  /// Opaque live-node token. Never synthesize this from the authored identity.
  public var actionTarget: String? = nil
  public var properties: AccessibilityProperties? = nil
  public var control: AccessibilityControlState? = nil
  /// Placed option routes, keyed by the control's opaque selection tokens.
  package var selectionOptionRects: [String: CellRect] = [:]
  public var isEnabled: Bool = true
  /// Assistive semantic focus, independent of keyboard focus.
  public var isAccessibilityFocused: Bool = false
  /// Authored named navigation groups, in addition to native role navigation.
  public var navigationCategories: [String] = []
  package var actionIdentity: Identity? = nil
  /// Combined descendants retain their own committed routing and lifetime checks.
  package var combinedActions: [String: AccessibilityCombinedAction] = [:]
  package var viewNodeID: ViewNodeID?
  public var identity: Identity
  public var parentIdentity: Identity?
  public var rect: CellRect
  public var role: AccessibilityRole
  public var label: String?
  public var hint: String?
  public var hidden: Bool
  public var liveRegion: AccessibilityPoliteness?
  public var cursorAnchor: CellPoint?
  /// Native text reading and selection metadata. Absent for secure inputs.
  public var textInput: AccessibilityTextInput? = nil

  public init(
    identity: Identity,
    parentIdentity: Identity? = nil,
    rect: CellRect,
    role: AccessibilityRole,
    label: String? = nil,
    hint: String? = nil,
    hidden: Bool = false,
    liveRegion: AccessibilityPoliteness? = nil,
    cursorAnchor: CellPoint? = nil
  ) {
    viewNodeID = nil
    self.identity = identity
    self.parentIdentity = parentIdentity
    self.rect = rect
    self.role = role
    self.label = label
    self.hint = hint
    self.hidden = hidden
    self.liveRegion = liveRegion
    self.cursorAnchor = cursorAnchor
  }

  package init(
    viewNodeID: ViewNodeID?,
    identity: Identity,
    parentIdentity: Identity? = nil,
    rect: CellRect,
    role: AccessibilityRole,
    label: String? = nil,
    hint: String? = nil,
    hidden: Bool = false,
    liveRegion: AccessibilityPoliteness? = nil,
    cursorAnchor: CellPoint? = nil
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.parentIdentity = parentIdentity
    self.rect = rect
    self.role = role
    self.label = label
    self.hint = hint
    self.hidden = hidden
    self.liveRegion = liveRegion
    self.cursorAnchor = cursorAnchor
  }
}

package struct AccessibilityCombinedAction: Equatable, Sendable {
  package let identity: Identity
  package let owner: ViewNodeID
  package let action: AccessibilityAction
  package let enabled: Bool
  package let readOnly: Bool
  package init(
    identity: Identity, owner: ViewNodeID, action: AccessibilityAction,
    enabled: Bool, readOnly: Bool
  ) {
    self.identity = identity
    self.owner = owner
    self.action = action
    self.enabled = enabled
    self.readOnly = readOnly
  }
}
