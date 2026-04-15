// No Core import needed — the placements and content protocol are
// pure Swift types.

/// A single item in a toolbar.
///
/// `ToolbarItem` has two construction shapes:
///
/// * **Free-form**: the author supplies a real `View` body in the
///   explicit author-placed position. No command association, no key
///   glyph rendering.
/// * **Command-bound**: the item is associated with a registered
///   ``Command`` by id. At resolution time, the host looks the command
///   up (from the view-level ``CommandPreferenceKey`` reduction or
///   the ``Scene/commands(_:)`` environment channel), and renders the
///   command's title, key glyph, and disabled state.
///
/// `ToolbarItem` does **not** carry a `key:` parameter and does **not**
/// auto-register hotkeys. Registration is the ``View/command(id:title:key:_:action:)``
/// modifier's job. A command-bound item only pulls *presentation* data
/// from the command record. See
/// ``docs/proposals/COMMAND_AND_CHROME_APIS.md`` §4.3 for the
/// rationale.
public struct ToolbarItem<Content: View>: ToolbarContent {
  public typealias Body = Never

  /// Where this item lands in the toolbar host's layout.
  public let placement: ToolbarItemPlacement

  /// If non-`nil`, the id of the registered command this item surfaces.
  /// The host pulls the command's title and key glyph from the
  /// unified command preference value at resolve time.
  public let commandID: String?

  /// The author-supplied body for a free-form item, or the optional
  /// richer label for a command-bound item. For the `Text`-specialized
  /// command-bound overload, this carries a placeholder that the host
  /// replaces with the registered command's title.
  public let content: Content

  /// True if the author supplied a body closure explicitly
  /// (free-form or command-bound with custom content). False if the
  /// body is a placeholder created by the title-only Text-specialized
  /// command-bound overload.
  ///
  /// Used at composition time to decide whether a command-bound
  /// record should render the author's custom body or the command's
  /// title.
  package let hasCustomBody: Bool

  /// Creates a free-form toolbar item.
  ///
  /// Use this to place arbitrary `View` content at a semantic
  /// placement. The content body is rendered as-is — there is no
  /// command lookup and no auto-glyph rendering.
  public init(
    placement: ToolbarItemPlacement = .automatic,
    @ViewBuilder content: () -> Content
  ) {
    self.placement = placement
    self.commandID = nil
    self.content = content()
    self.hasCustomBody = true
  }

  /// Creates a command-bound toolbar item with a custom label body.
  ///
  /// Use this when the author wants a richer label than the command's
  /// title alone. The body is rendered next to the auto-derived key
  /// glyph at composition time.
  public init(
    placement: ToolbarItemPlacement = .automatic,
    command id: String,
    @ViewBuilder content: () -> Content
  ) {
    self.placement = placement
    self.commandID = id
    self.content = content()
    self.hasCustomBody = true
  }

  /// Package initializer for the Text-specialized command-bound
  /// overload. Used by
  /// ``ToolbarItem/init(_:command:)`` where `Content == Text`.
  package init(
    placement: ToolbarItemPlacement,
    commandID: String,
    placeholderContent: Content
  ) {
    self.placement = placement
    self.commandID = commandID
    self.content = placeholderContent
    self.hasCustomBody = false
  }

  public var body: Never {
    fatalError("ToolbarItem is a primitive toolbar-content artifact.")
  }
}

extension ToolbarItem where Content == Text {
  /// Creates a command-bound toolbar item whose body is the command's
  /// title, rendered as a ``Text`` leaf.
  ///
  /// The title text the view stores is a placeholder — the host
  /// replaces it with the registered command's title at composition
  /// time. If the command id does not resolve, the item is silently
  /// omitted.
  public init(
    _ placement: ToolbarItemPlacement = .automatic,
    command id: String
  ) {
    // Placeholder — the host substitutes the registered command's
    // title at composition time. `hasCustomBody` is false so the
    // composition layer knows to render the command's title instead
    // of the placeholder.
    self.init(
      placement: placement,
      commandID: id,
      placeholderContent: Text("")
    )
  }
}

/// A collection of toolbar items sharing a single placement.
///
/// `ToolbarItemGroup` mirrors SwiftUI's placement-only shape. The
/// "labeled disclosable menu" overload is explicitly dropped — see
/// ``docs/proposals/COMMAND_AND_CHROME_APIS.md`` §4.4.
public struct ToolbarItemGroup<Content: ToolbarContent>: ToolbarContent {
  public typealias Body = Never

  public let placement: ToolbarItemPlacement
  public let content: Content

  public init(
    placement: ToolbarItemPlacement = .automatic,
    @ToolbarContentBuilder content: () -> Content
  ) {
    self.placement = placement
    self.content = content()
  }

  public var body: Never {
    fatalError("ToolbarItemGroup is a primitive toolbar-content artifact.")
  }
}

/// A flexible or fixed-width spacer in a toolbar row.
public struct ToolbarSpacer: ToolbarContent {
  public typealias Body = Never

  /// How much space the spacer claims in the bottom row.
  public enum Sizing: Hashable, Sendable {
    /// Fills any remaining horizontal space in the section.
    case flexible
    /// A fixed number of cells.
    case fixed(Int)
  }

  public let sizing: Sizing
  public let placement: ToolbarItemPlacement

  public init(
    _ sizing: Sizing = .flexible,
    placement: ToolbarItemPlacement = .automatic
  ) {
    self.sizing = sizing
    self.placement = placement
  }

  public var body: Never {
    fatalError("ToolbarSpacer is a primitive toolbar-content artifact.")
  }
}
