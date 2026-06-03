/// A rectangular hit region for keyboard or pointer interaction.
public struct InteractionRegion: Equatable, Sendable {
  public var identity: Identity
  public var rect: CellRect
  public var routeID: RouteID
  public var hitTestOrder: Int
  public var captureOnPress: Bool
  public var contentShape: Path?

  public init(
    identity: Identity,
    rect: CellRect,
    routeID: RouteID,
    hitTestOrder: Int = 0,
    captureOnPress: Bool = false,
    contentShape: Path? = nil
  ) {
    self.identity = identity
    self.rect = rect
    self.routeID = routeID
    self.hitTestOrder = hitTestOrder
    self.captureOnPress = captureOnPress
    self.contentShape = contentShape
  }

  public func contains(_ location: PointerLocation) -> Bool {
    guard rect.contains(location.location) else {
      return false
    }
    return contentShape?.contains(location.location) ?? true
  }
}

/// A focusable region extracted from the placed tree.
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
  }

  package init(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    viewportRect: CellRect,
    contentBounds: CellRect
  ) {
    self.identity = identity
    self.viewNodeID = viewNodeID
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
    self.contentOffset = contentOffset
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

/// Accessibility metadata extracted for assistive-technology consumers.
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

/// An app-triggered accessibility announcement for assistive-technology consumers.
public struct AccessibilityAnnouncement: Equatable, Sendable {
  public var message: String
  public var politeness: AccessibilityPoliteness

  /// Creates an accessibility announcement.
  public init(
    message: String,
    politeness: AccessibilityPoliteness = .polite
  ) {
    self.message = message
    self.politeness = politeness
  }
}

/// A visual-only accessibility policy warning emitted during semantic extraction.
package struct AccessibilityWarning: Equatable, Sendable {
  package var identity: Identity
  package var kind: String
  package var message: String

  package init(
    identity: Identity,
    kind: String,
    message: String
  ) {
    self.identity = identity
    self.kind = kind
    self.message = message
  }
}

/// The complete semantic extraction result for a frame.
/// Derived routing and accessibility output for a placed tree.
///
/// `SemanticSnapshot` is not a metadata carrier. It owns the runtime products
/// generated by semantic extraction: focus, interaction, scroll, selection,
/// navigation, named-coordinate-space, accessibility, and announcement records.
/// Freshness is proven by extracting from the current placed tree after any
/// retained placement metadata synchronization.
public struct SemanticSnapshot: Equatable, Sendable {
  public var interactionRegions: [InteractionRegion]
  public var focusRegions: [FocusRegion]
  public var navigationRoutes: [NavigationRoute]
  public var scrollRoutes: [ScrollRoute]
  package var scrollTargets: [ScrollTarget]
  public var selectionRoutes: [SelectionRoute]
  public var namedCoordinateSpaces: [String: CellRect]
  public var accessibilityNodes: [AccessibilityNode]
  public var accessibilityAnnouncements: [AccessibilityAnnouncement]
  package var accessibilityWarnings: [AccessibilityWarning]

  public init(
    interactionRegions: [InteractionRegion] = [],
    focusRegions: [FocusRegion] = [],
    navigationRoutes: [NavigationRoute] = [],
    scrollRoutes: [ScrollRoute] = [],
    selectionRoutes: [SelectionRoute] = [],
    namedCoordinateSpaces: [String: CellRect] = [:],
    accessibilityNodes: [AccessibilityNode] = [],
    accessibilityAnnouncements: [AccessibilityAnnouncement] = []
  ) {
    self.interactionRegions = interactionRegions
    self.focusRegions = focusRegions
    self.navigationRoutes = navigationRoutes
    self.scrollRoutes = scrollRoutes
    self.scrollTargets = []
    self.selectionRoutes = selectionRoutes
    self.namedCoordinateSpaces = namedCoordinateSpaces
    self.accessibilityNodes = accessibilityNodes
    self.accessibilityAnnouncements = accessibilityAnnouncements
    self.accessibilityWarnings = []
  }

  package init(
    interactionRegions: [InteractionRegion] = [],
    focusRegions: [FocusRegion] = [],
    navigationRoutes: [NavigationRoute] = [],
    scrollRoutes: [ScrollRoute] = [],
    scrollTargets: [ScrollTarget] = [],
    selectionRoutes: [SelectionRoute] = [],
    namedCoordinateSpaces: [String: CellRect] = [:],
    accessibilityNodes: [AccessibilityNode] = [],
    accessibilityAnnouncements: [AccessibilityAnnouncement] = [],
    accessibilityWarnings: [AccessibilityWarning]
  ) {
    self.interactionRegions = interactionRegions
    self.focusRegions = focusRegions
    self.navigationRoutes = navigationRoutes
    self.scrollRoutes = scrollRoutes
    self.scrollTargets = scrollTargets
    self.selectionRoutes = selectionRoutes
    self.namedCoordinateSpaces = namedCoordinateSpaces
    self.accessibilityNodes = accessibilityNodes
    self.accessibilityAnnouncements = accessibilityAnnouncements
    self.accessibilityWarnings = accessibilityWarnings
  }
}
