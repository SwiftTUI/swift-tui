/// A focusable region extracted from the placed tree.
/// Equality deliberately includes `package`-level bookkeeping fields (F120):
/// these types are the frame pipeline's change-detection currency, so two
/// externally identical values may compare `!=` when internal routing or
/// bookkeeping differs. Public consumers must not treat `==` as
/// visible-field equality.
public struct FocusRegion: Equatable, Sendable {
  public var identity: Identity
  public var rect: CellRect
  public var focusInteractions: FocusInteractions
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
    modalFocusScopePath: [Identity]?
  ) {
    self.identity = identity
    self.rect = rect
    self.focusInteractions = focusInteractions
    self.scopePath = scopePath
    self.sectionIdentity = sectionIdentity
    self.modalFocusScopePath = modalFocusScopePath
  }
}

/// Scroll metadata extracted for a scrollable node.
/// Equality deliberately includes `package`-level bookkeeping fields (F120):
/// these types are the frame pipeline's change-detection currency, so two
/// externally identical values may compare `!=` when internal routing or
/// bookkeeping differs. Public consumers must not treat `==` as
/// visible-field equality.
public struct ScrollRoute: Equatable, Sendable {
  public var identity: Identity
  package var viewNodeID: ViewNodeID?
  public var viewportRect: CellRect
  public var contentBounds: CellRect
  /// Current clamped scroll offset of this region. Defaults to `.zero`; it is
  /// populated from the live scroll-position registry only at the web-host
  /// presentation boundary, where it is published as scroll-extent metadata so
  /// the browser host can implement scroll-chaining (capture the wheel only
  /// while the region can still scroll in that direction). See
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
/// Equality deliberately includes `package`-level bookkeeping fields (F120):
/// these types are the frame pipeline's change-detection currency, so two
/// externally identical values may compare `!=` when internal routing or
/// bookkeeping differs. Public consumers must not treat `==` as
/// visible-field equality.
public struct AccessibilityNode: Equatable, Sendable {
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
