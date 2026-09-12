public import SwiftTUICore

/// Composes a menu's trigger and inline or floating content.
///
/// This is a body-producing family: the framework hands
/// ``MenuStyle/makeBody(configuration:)`` the captured trigger label, the
/// captured commands, the presentation binding, and the menu's render state,
/// and the view it returns renders in the menu's place. The style decides what
/// the trigger looks like and whether the commands float above the layout or
/// expand inline beneath it.
///
/// ``Menu`` keeps everything that makes a menu a menu: the focus stop, the
/// expansion state and its binding, the keyboard activation, the Escape
/// dismissal while presented, the accessibility role, and the portal's
/// lifetime. A style composes around them through two route wrappers,
/// ``MenuStyleConfiguration/trigger(content:)`` for the pointer target and
/// ``MenuStyleConfiguration/portal(presentation:content:)`` for the floating
/// surface.
///
/// A presented menu must reach its commands: place the portal wrapper, or place
/// `configuration.content` inline while `isPresented` is true. A style that
/// does neither reports `style.missingRequiredRoute`, and the automatic body
/// renders for that resolve. Disabling a presented menu leaves it presented
/// with its commands and trigger disabled, and its Escape handler stays
/// installed.
///
/// The built-ins are ``AnyMenuStyle/automatic`` (a full-width trigger row with
/// the label, a spacer, and a caret, over a floating surface),
/// ``AnyMenuStyle/button`` (a bordered trigger over the same floating surface),
/// ``AnyMenuStyle/borderlessButton`` (the same trigger without the border), and
/// ``AnyMenuStyle/inline`` (the automatic trigger row with the commands
/// expanded below it in normal layout). Unlike most families, `automatic` is
/// its own treatment rather than an alias of a named built-in. Apply a style
/// with `menuStyle(_:)`, which stores it in the environment for that subtree;
/// the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform. A style
/// may store dynamic properties, which are prepared before `makeBody` runs.
///
/// ```swift
/// struct SizedMenuStyle: MenuStyle {
///   func makeBody(configuration: MenuStyleConfiguration) -> some View {
///     configuration.portal(presentation: .init(maximumWidth: 18, maximumHeight: 6)) {
///       configuration.trigger {
///         HStack(spacing: 1) {
///           configuration.label
///           Text(configuration.isPresented ? "▴" : "▾")
///         }
///       }
///     }
///   }
/// }
///
/// Menu("Actions") {
///   Button("Save") { save() }
/// }
/// .menuStyle(SizedMenuStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol MenuStyle: Sendable {
  /// The view type ``MenuStyle/makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The name this style reports in snapshots, debug bundles, and style
  /// diagnostics.
  ///
  /// The default implementation returns the reflected type name; the built-ins
  /// pin theirs, such as `"AnyMenuStyle.inline"`. It is diagnostic text and not
  /// identity, so nothing should branch on its value. The misuse issues a menu
  /// reports name the style through this label.
  var snapshotLabel: String { get }
  /// Composes the trigger and the presented commands into the menu's rendered
  /// body.
  ///
  /// The method runs on the main actor once per resolve of the styled menu,
  /// presented or not.
  ///
  /// - Parameter configuration: The captured label and commands, the
  ///   presentation binding, the render state, and the route wrappers for this
  ///   menu.
  /// - Returns: The view that renders in the menu's place.
  @ViewBuilder @MainActor
  func makeBody(configuration: MenuStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _menuStyleValueTypeWitness: Void { get }
}

extension MenuStyle {
  /// The reflected type name of the conformance, used when a style does not
  /// pin a label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }
  @_documentation(visibility: internal)
  public static var _menuStyleValueTypeWitness: Void { () }
}

extension MenuStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI styles must be value types (a struct or an enum); a class cannot conform to MenuStyle"
  )
  public static var _menuStyleValueTypeWitness: Void { () }
}

/// Captured menu slots and primitive-owned presentation state.
///
/// The configuration has three groups of members. ``MenuStyleConfiguration/label``
/// and ``MenuStyleConfiguration/content`` are the captured authored slots,
/// which keep the authoring scope of the content the menu was declared with.
/// ``MenuStyleConfiguration/isPresented`` is the primitive's expansion binding,
/// and the remaining values (`isEnabled`, `isFocused`, `showsFocusEffect`,
/// `isPressed`, `focusActive`, `styleEnvironment`) are read-only render state.
/// ``MenuStyleConfiguration/trigger(content:)`` and
/// ``MenuStyleConfiguration/portal(presentation:content:)`` are the route
/// wrappers a style composes around the views it builds.
///
/// The content slot is retained by the declaring menu, so moving it between an
/// inline host and the floating portal keeps the commands' state and running
/// tasks. Place it once per body. The framework builds this value while it
/// resolves a ``Menu``; test targets build one directly through the fixture
/// initializer, whose route wrappers install nothing (see
/// <doc:Testing-Styles>).
public struct MenuStyleConfiguration: Sendable {
  /// The captured, authored trigger label.
  ///
  /// Placing this view in the body renders the title the menu was declared
  /// with and keeps that content's state and authoring scope. It is the label
  /// only: the caret, chrome, and pointer target around it belong to the
  /// style.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures a label for an inert style fixture (see <doc:Testing-Styles>).
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   label.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured, authored commands, as a leading-aligned column of distinct
  /// children.
  ///
  /// Place this view where the commands should appear: it is the floating body
  /// of ``MenuStyleConfiguration/portal(presentation:content:)`` automatically,
  /// and an inline style composes it directly while
  /// ``MenuStyleConfiguration/isPresented`` is true. Placing it, or the portal
  /// wrapper, is what satisfies the presented menu's route requirement.
  ///
  /// The slot is retained by the declaring menu, so hosting it inline or in the
  /// portal preserves the commands' state and running tasks. Closing the menu
  /// retains persistent state and cancels the commands' tasks; reopening
  /// restarts them. Place it once per body; composing it twice is unsupported.
  public struct Content: View, Sendable {
    package let payloads: [ScopedContentPayload]
    package var usageIdentity: Identity?
    package var retention: CapturedSubviewRetention? = nil

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payloads = withAuthoringContext(makeCapturedAuthoringContext(from: authoringContext)) {
        scopedDeclaredBuilderChildren(from: content())
      }
    }

    /// Captures menu commands for an inert style fixture (see <doc:Testing-Styles>).
    ///
    /// A multi-statement builder produces the same distinct children a live
    /// menu would hand the style, and the fixture slot carries no retention.
    ///
    /// - Parameter content: The view builder standing in for the authored
    ///   commands.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      self.init(authoringContext: currentAuthoringContext(), content: content)
    }

    /// The captured authored commands.
    public var body: some View {
      if let retention {
        contentBody.id(retention.identity.child(.named("host")))
      } else {
        contentBody
      }
    }

    private var contentBody: some View {
      VStack(alignment: .leading, spacing: 0) {
        CapturedSubviewSequenceView(payloads: payloads, retention: retention)
      }
      .background { MenuStyleUsageMarker(identity: usageIdentity) }
    }
  }

  /// The authored trigger label, ready to place in the style's body.
  public var label: Label
  /// The authored commands, ready to place in the style's body exactly once.
  public var content: Content
  /// Whether the menu is presented, projected as the primitive's own binding.
  ///
  /// Read it to draw an open or closed trigger, and write it to open or close
  /// the menu from a view the style composes. The binding cannot be replaced,
  /// and writes are dropped while the menu is disabled; the primitive still
  /// owns the expansion state, the portal, and Escape dismissal.
  @Binding public var isPresented: Bool
  /// Whether the menu accepts activation.
  ///
  /// A disabled menu that is already presented stays presented with its
  /// commands and trigger disabled, so a style should keep drawing the
  /// commands rather than assume dismissal.
  public var isEnabled: Bool
  /// Whether the menu owns keyboard focus, regardless of the focus effect.
  public var isFocused: Bool
  /// Whether the environment permits a focus treatment;
  /// `focusEffectDisabled()` clears it while the menu stays focused.
  public var showsFocusEffect: Bool
  /// Whether the pointer is currently pressing the menu's trigger.
  public var isPressed: Bool
  /// The appearance, theme, ambient paints, and cell metrics in effect where
  /// the menu was declared.
  ///
  /// The built-in triggers derive their paints from
  /// `controlChrome(isEnabled:isFocused:isPressed:)` on this snapshot.
  public var styleEnvironment: StyleEnvironmentSnapshot
  /// Whether the menu is focused and the focus effect is enabled.
  ///
  /// Read this rather than combining `isFocused` and `showsFocusEffect`
  /// yourself: a menu under `focusEffectDisabled()` still activates from the
  /// keyboard but must not draw a focus treatment.
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var controlIdentity: Identity?
  private var presentationBinding: Binding<Bool>?

  /// Constructs a style fixture. Its wrappers install no runtime routes or portals.
  ///
  /// Constructs the configuration from fixture state for a style test without a
  /// live render (see <doc:Testing-Styles>). Supply `isPresented` as a constant
  /// or write-counting binding to exercise both presentation states.
  @_spi(StyleFixtures)
  public init(
    label: Label, content: Content, isPresented: Binding<Bool>,
    isEnabled: Bool, isFocused: Bool, showsFocusEffect: Bool, isPressed: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.label = label
    self.content = content
    self._isPresented = isPresented
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.isPressed = isPressed
    self.styleEnvironment = styleEnvironment
  }

  /// Installs the primitive's pointer trigger once. Keyboard activation is
  /// available even when a style omits this wrapper.
  ///
  /// Wrap the view that should open and close the menu when clicked; the
  /// framework supplies the route's identity, and a press on it toggles
  /// ``MenuStyleConfiguration/isPresented`` while the menu is enabled.
  /// Installing the wrapper twice in one body reports `style.duplicateRoute`:
  /// the first installation stays the pointer target and the later one renders
  /// its content without one. On a fixture configuration the wrapper is inert
  /// and returns the content unchanged.
  ///
  /// - Parameter content: The trigger view to place behind the pointer target.
  /// - Returns: The trigger view, with the menu's pointer route installed
  ///   around it.
  @ViewBuilder @MainActor
  public func trigger<Trigger: View>(@ViewBuilder content: () -> Trigger) -> some View {
    styleRoute(
      target: controlIdentity.map { controlIdentity in
        StyleRouteTarget(
          identity: menuTriggerIdentity(for: controlIdentity),
          family: "MenuStyle", role: "trigger")
      }, content: content())
  }

  /// Uses `content` as the inline anchor and this configuration's captured
  /// commands as the floating body. Escape and portal lifetime stay with Menu.
  ///
  /// The closure's view stays in normal layout at the menu's site; the captured
  /// commands are hosted in a portal above the surrounding views while
  /// ``MenuStyleConfiguration/isPresented`` is true, so opening and closing
  /// does not reflow siblings. `presentation` bounds the surface's outer width
  /// and its content viewport height before insets, and supplies the insets,
  /// background, and border; an invalid value reports
  /// `style.invalidPresentation` and the automatic presentation renders for
  /// that resolve. Installing the wrapper twice in one body reports
  /// `style.duplicateRoute` and the later installation renders its anchor with
  /// no portal. On a fixture configuration the wrapper is inert and returns the
  /// anchor unchanged.
  ///
  /// - Parameters:
  ///   - presentation: The bounds, insets, and paints for the floating
  ///     surface.
  ///   - content: The inline anchor, which usually wraps the trigger.
  /// - Returns: The anchor, with the menu's portal attached to it.
  @ViewBuilder @MainActor
  public func portal<PortalContent: View>(
    presentation: AnchoredSurfaceStylePresentation,
    @ViewBuilder content: () -> PortalContent
  ) -> some View {
    if let controlIdentity, let presentationBinding {
      MenuStylePortalView(
        controlIdentity: controlIdentity, presentation: presentation,
        isPresented: presentationBinding, menuContent: self.content, anchor: content())
    } else {
      content()
    }
  }

  package mutating func bindRoutes(to identity: Identity, presentation: Binding<Bool>) {
    controlIdentity = identity
    presentationBinding = presentation
    content.usageIdentity = identity
  }
}

/// Type-erased storage for a concrete menu style, the value the environment
/// carries.
///
/// `menuStyle(_:)` stores one of these for its subtree, and every built-in is
/// available as a static on this type. The value participates in retained
/// reuse: the stateless built-ins compare equal by type, and a custom style
/// compares by value when it conforms to `Equatable`.
public struct AnyMenuStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyMenuStyleBox

  /// Erases a concrete menu style.
  ///
  /// - Parameter style: The conformance to store. Its `snapshotLabel` is
  ///   copied out for diagnostics.
  public init<S: MenuStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }
  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }
  /// A one-row trigger holding the label, a spacer, and a caret, with the
  /// commands in a floating surface.
  public static var automatic: Self {
    Self(AutomaticMenuStyle())
  }
  /// A bordered trigger of intrinsic width, with the commands in a floating
  /// surface.
  public static var button: Self {
    Self(ButtonMenuStyle())
  }
  /// The button trigger without its border or padding, with the commands in a
  /// floating surface.
  public static var borderlessButton: Self {
    Self(BorderlessButtonMenuStyle())
  }
  /// The automatic trigger row with the commands expanded below it in normal
  /// layout, which reflows the surrounding views.
  public static var inline: Self {
    Self(InlineMenuStyle())
  }

  @MainActor
  package func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyMenuStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

private protocol AnyMenuStyleBox: AnyStyleBox {
  @MainActor
  func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyMenuStyleBox where S: MenuStyle {
  @MainActor
  func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

/// The default one-row trigger and compact floating menu.
///
/// The trigger fills the width it is given: a focus rail cell, the label, a
/// spacer, and a caret that reads `▾` while closed and `▴` while presented,
/// painted from the snapshot's control chrome. The commands render in the
/// configuration's portal with the default
/// ``AnchoredSurfaceStylePresentation``, so opening the menu does not reflow
/// the surrounding views.
public struct AutomaticMenuStyle: MenuStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyMenuStyle.automatic" }
  /// Renders the full-width trigger row inside the menu's pointer route, with
  /// the commands attached as a floating surface.
  ///
  /// - Parameter configuration: The captured slots, render state, and route
  ///   wrappers for this menu.
  /// - Returns: The anchored trigger that renders in the menu's place.
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    FloatingMenuStyleBody(configuration: configuration) {
      MenuAutomaticTrigger(configuration: configuration)
    }
  }
}
extension MenuStyle where Self == AutomaticMenuStyle {
  /// A one-row trigger holding the label, a spacer, and a caret, with the
  /// commands in a floating surface.
  public static var automatic: Self { .init() }
}
extension AutomaticMenuStyle: ReuseTransparentStyle {}

/// A bordered trigger with a compact floating menu.
///
/// The trigger is the label and its caret at intrinsic width, padded one cell
/// horizontally and framed by a rounded outset border in the chrome's border
/// paint. The commands render in the configuration's portal.
public struct ButtonMenuStyle: MenuStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyMenuStyle.button" }
  /// Renders the bordered trigger inside the menu's pointer route, with the
  /// commands attached as a floating surface.
  ///
  /// - Parameter configuration: The captured slots, render state, and route
  ///   wrappers for this menu.
  /// - Returns: The anchored trigger that renders in the menu's place.
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    FloatingMenuStyleBody(configuration: configuration) {
      MenuButtonTrigger(configuration: configuration)
        .padding(.horizontal, 1)
        .border(
          menuTriggerChrome(for: configuration).borderStyle, set: .rounded, placement: .outset)
    }
  }
}
extension MenuStyle where Self == ButtonMenuStyle {
  /// A bordered trigger of intrinsic width, with the commands in a floating
  /// surface.
  public static var button: Self { .init() }
}
extension ButtonMenuStyle: ReuseTransparentStyle {}

/// A borderless trigger with a compact floating menu.
///
/// The trigger is the label and its caret at intrinsic width, with the focused
/// or pressed fill but no border or padding. The commands render in the
/// configuration's portal.
public struct BorderlessButtonMenuStyle: MenuStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyMenuStyle.borderlessButton" }
  /// Renders the borderless trigger inside the menu's pointer route, with the
  /// commands attached as a floating surface.
  ///
  /// - Parameter configuration: The captured slots, render state, and route
  ///   wrappers for this menu.
  /// - Returns: The anchored trigger that renders in the menu's place.
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    FloatingMenuStyleBody(configuration: configuration) {
      MenuButtonTrigger(configuration: configuration)
    }
  }
}
extension MenuStyle where Self == BorderlessButtonMenuStyle {
  /// The button trigger without its border or padding, with the commands in a
  /// floating surface.
  public static var borderlessButton: Self { .init() }
}
extension BorderlessButtonMenuStyle: ReuseTransparentStyle {}

/// Expands the commands below the trigger within normal layout.
///
/// The trigger is the automatic one-row treatment. Because the commands sit in
/// the same column rather than a portal, opening and closing the menu reflows
/// the surrounding views. This is the built-in that satisfies the presented
/// menu's route requirement through inline content instead of a portal.
public struct InlineMenuStyle: MenuStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyMenuStyle.inline" }
  /// Renders the trigger row inside the menu's pointer route and, while the
  /// menu is presented, the commands directly beneath it.
  ///
  /// - Parameter configuration: The captured slots, render state, and route
  ///   wrappers for this menu.
  /// - Returns: The column that renders in the menu's place.
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    InlineMenuStyleBody(configuration: configuration)
  }
}
extension MenuStyle where Self == InlineMenuStyle {
  /// The automatic trigger row with the commands expanded below it in normal
  /// layout.
  public static var inline: Self { .init() }
}
extension InlineMenuStyle: ReuseTransparentStyle {}

/// The floating treatments: the configuration's portal around its pointer
/// trigger, differing only in the trigger they compose.
private struct FloatingMenuStyleBody<Trigger: View>: View {
  let configuration: MenuStyleConfiguration
  let trigger: Trigger

  init(configuration: MenuStyleConfiguration, @ViewBuilder trigger: () -> Trigger) {
    self.configuration = configuration
    self.trigger = trigger()
  }

  var body: some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger { trigger }
    }
  }
}

/// The control chrome every built-in trigger derives from its configuration.
private func menuTriggerChrome(for configuration: MenuStyleConfiguration) -> ControlChrome {
  configuration.styleEnvironment.controlChrome(
    isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
    isPressed: configuration.isPressed)
}

private struct MenuAutomaticTrigger: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    let chrome = menuTriggerChrome(for: configuration)
    VStack(alignment: .leading, spacing: 0) {
      ControlStyleRow(
        chrome: chrome, focusActive: configuration.focusActive,
        isHighlighted: configuration.focusActive || configuration.isPressed
      ) {
        configuration.label
        Spacer()
        Text(configuration.isPresented ? "▴" : "▾")
      }
    }
  }
}

private struct MenuButtonTrigger: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    let chrome = menuTriggerChrome(for: configuration)
    HStack(spacing: 1) {
      configuration.label
      Text(configuration.isPresented ? "▴" : "▾")
    }
    .foregroundStyle(chrome.foregroundStyle)
    .background {
      if configuration.focusActive || configuration.isPressed {
        Rectangle().fill(chrome.backgroundStyle)
      }
    }
    .opacity(chrome.opacity)
  }
}

private struct InlineMenuStyleBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { MenuAutomaticTrigger(configuration: configuration) }
      if configuration.isPresented { configuration.content }
    }
  }
}

package func menuTriggerIdentity(for control: Identity) -> Identity {
  // The dedicated state host records this handler. Keep the route beneath
  // that owner so scoped publication withdraws it when the owner departs or
  // stops recording the enabled trigger.
  control.child(.named("MenuState")).child(.named("MenuTrigger"))
}

package enum MenuStyleUsagePreferenceKey: PreferenceKey {
  package static let defaultValue: Set<Identity> = []
  package static func reduce(value: inout Set<Identity>, nextValue: () -> Set<Identity>) {
    value.formUnion(nextValue())
  }
}

private struct MenuStyleUsageMarker: View {
  let identity: Identity?
  var body: some View {
    Text("").preference(
      key: MenuStyleUsagePreferenceKey.self,
      value: identity.map { Set([$0]) } ?? [])
  }
}

private struct MenuStylePortalView<Anchor: View>: PrimitiveView, ResolvableView {
  let controlIdentity: Identity
  let presentation: AnchoredSurfaceStylePresentation
  let isPresented: Binding<Bool>
  let menuContent: MenuStyleConfiguration.Content
  let anchor: Anchor

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    makeResolveWork(in: context).run()
  }

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let portalIdentity = controlIdentity.child(.named("MenuPortal"))
    let ledger = StyleRouteInstallationLedgerStorage.current
    if let ledger, !ledger.claim(portalIdentity) {
      ImperativeRuntimeIssueQueue.record(
        StyleMisuse.duplicateRouteIssue(
          family: "MenuStyle", role: "portal", styleLabel: ledger.styleLabel,
          identity: portalIdentity))
      return anchor.resolveWork(in: context).map { [$0] }
    }
    let presentation = StyleMisuse.validatedPresentation(
      presentation, problems: presentation.validationProblems, family: "MenuStyle",
      styleLabel: ledger?.styleLabel ?? "MenuStyle", identity: controlIdentity,
      report: ImperativeRuntimeIssueQueue.record, fallback: { .init() })
    return anchor.modifier(
      MenuStylePresentationModifier(
        isPresented: isPresented, menuContent: menuContent,
        menuContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        presentation: presentation)
    )
    .background { MenuStyleUsageMarker(identity: controlIdentity) }
    .resolveElementsWork(in: context)
  }
}
