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
  /// When set, the semantics walk mints this node's pointer route from this
  /// identity instead of the node's structural identity. Stamped by gesture
  /// attachment when the gesture keys its registration on an entity-rerooted
  /// descendant (`.id` below the chain): the region's route and the
  /// registration then share one identity, so pointer capture survives a
  /// conditional-branch re-resolve that re-mints the chain node. Region
  /// identity, rect, and focus stay structural.
  package var explicitRouteIdentity: Identity?

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

  /// Whether this node is a command/chrome-hosting region (the Role-A
  /// view-controller analogue: `Panel`, `NavigationStack`, …).
  ///
  /// A command host hoists toolbar / palette / key commands to top-level
  /// regions and is a focus *scope* (`focusScopeBoundary`), but it is **not**
  /// a focus *target*: it does not participate in top-level focus, so Tab
  /// passes through it to item leaves and it classifies structurally as a
  /// container, not a control. Its commands activate by the active/visible
  /// context (or, when a descendant is focused, the focus chain), never by
  /// focusing the host. Orthogonal to `isFocusable`/focus participation; it
  /// marks the hosting *capability* only.
  package var isCommandHost: Bool {
    get { flag(Self.isCommandHostFlag) }
    set { setFlag(Self.isCommandHostFlag, to: newValue) }
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
    isCommandHost: Bool = false,
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
      isCommandHost: isCommandHost,
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
    var merged = Self(
      isFocusable: other.explicitFocusability ?? explicitFocusability,
      focusScopeBoundary: other.focusScopeBoundary || focusScopeBoundary,
      focusScopeIdentity: other.focusScopeIdentity ?? focusScopeIdentity,
      focusSectionBoundary: other.focusSectionBoundary || focusSectionBoundary,
      sealsFocusDescendants: other.sealsFocusDescendants || sealsFocusDescendants,
      isCommandHost: other.isCommandHost || isCommandHost,
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
    merged.explicitRouteIdentity = other.explicitRouteIdentity ?? explicitRouteIdentity
    return merged
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
  private static let isCommandHostFlag: UInt16 = 1 << 9

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
    isCommandHost: Bool,
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
    if isCommandHost {
      flags |= isCommandHostFlag
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
