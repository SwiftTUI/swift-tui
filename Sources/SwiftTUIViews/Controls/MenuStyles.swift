public import SwiftTUICore

/// Composes a menu's trigger and inline or floating content.
public protocol MenuStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }
  @ViewBuilder @MainActor
  func makeBody(configuration: MenuStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _menuStyleValueTypeWitness: Void { get }
}

extension MenuStyle {
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
public struct MenuStyleConfiguration: Sendable {
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures a label for an inert style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  public struct Content: View, Sendable {
    package let payloads: [ScopedContentPayload]
    package var usageIdentity: Identity?

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payloads = withAuthoringContext(makeCapturedAuthoringContext(from: authoringContext)) {
        scopedDeclaredBuilderChildren(from: content())
      }
    }

    /// Captures menu commands for an inert style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      self.init(authoringContext: currentAuthoringContext(), content: content)
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        CapturedSubviewSequenceView(payloads: payloads)
      }
      .background { MenuStyleUsageMarker(identity: usageIdentity) }
    }
  }

  public var label: Label
  public var content: Content
  @Binding public var isPresented: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var isPressed: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var focusActive: Bool { isFocused && showsFocusEffect }
  private var controlIdentity: Identity?
  private var presentationBinding: Binding<Bool>?

  /// Constructs a style fixture. Its wrappers install no runtime routes or portals.
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
  @ViewBuilder @MainActor
  public func trigger<Trigger: View>(@ViewBuilder content: () -> Trigger) -> some View {
    if let controlIdentity {
      StyleRouteView(
        target: .init(
          identity: menuTriggerIdentity(for: controlIdentity),
          family: "MenuStyle", role: "trigger"), content: content())
    } else {
      content()
    }
  }

  /// Uses `content` as the inline anchor and this configuration's captured
  /// commands as the floating body. Escape and portal lifetime stay with Menu.
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

/// Type-erased storage for a concrete menu style.
public struct AnyMenuStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyMenuStyleBox

  public init<S: MenuStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyMenuStyleBox(style: style)
  }
  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }
  public static var automatic: Self {
    Self(AutomaticMenuStyle())
  }
  public static var button: Self {
    Self(ButtonMenuStyle())
  }
  public static var borderlessButton: Self {
    Self(BorderlessButtonMenuStyle())
  }
  public static var inline: Self {
    Self(InlineMenuStyle())
  }

  @MainActor
  package func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
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

private protocol AnyMenuStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyMenuStyleBox) -> Bool
  @MainActor
  func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyMenuStyleBox<S: MenuStyle>: AnyMenuStyleBox {
  let style: S
  func isEqualForReuse(to other: any AnyMenuStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }
  @MainActor
  func resolveBody(configuration: MenuStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
  }
}

/// The default one-row trigger and compact floating menu.
public struct AutomaticMenuStyle: MenuStyle {
  public init() {}
  public var snapshotLabel: String { "AnyMenuStyle.automatic" }
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    AutomaticMenuStyleBody(configuration: configuration)
  }
}
extension MenuStyle where Self == AutomaticMenuStyle {
  public static var automatic: Self { .init() }
}
extension AutomaticMenuStyle: ReuseTransparentStyle {}

/// A bordered trigger with a compact floating menu.
public struct ButtonMenuStyle: MenuStyle {
  public init() {}
  public var snapshotLabel: String { "AnyMenuStyle.button" }
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    ButtonMenuStyleBody(configuration: configuration)
  }
}
extension MenuStyle where Self == ButtonMenuStyle {
  public static var button: Self { .init() }
}
extension ButtonMenuStyle: ReuseTransparentStyle {}

/// A borderless trigger with a compact floating menu.
public struct BorderlessButtonMenuStyle: MenuStyle {
  public init() {}
  public var snapshotLabel: String { "AnyMenuStyle.borderlessButton" }
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    BorderlessButtonMenuStyleBody(configuration: configuration)
  }
}
extension MenuStyle where Self == BorderlessButtonMenuStyle {
  public static var borderlessButton: Self { .init() }
}
extension BorderlessButtonMenuStyle: ReuseTransparentStyle {}

/// Expands the commands below the trigger within normal layout.
public struct InlineMenuStyle: MenuStyle {
  public init() {}
  public var snapshotLabel: String { "AnyMenuStyle.inline" }
  @MainActor public func makeBody(configuration: MenuStyleConfiguration) -> some View {
    InlineMenuStyleBody(configuration: configuration)
  }
}
extension MenuStyle where Self == InlineMenuStyle {
  public static var inline: Self { .init() }
}
extension InlineMenuStyle: ReuseTransparentStyle {}

private struct AutomaticMenuStyleBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger { MenuAutomaticTrigger(configuration: configuration) }
    }
  }
}

private struct MenuAutomaticTrigger: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    let chrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
    VStack(alignment: .leading, spacing: 0) {
      BoundControlStyleRow(
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

private struct ButtonMenuStyleBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger {
        MenuButtonTrigger(configuration: configuration)
          .padding(.horizontal, 1)
          .border(
            configuration.styleEnvironment.controlChrome(
              isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
              isPressed: configuration.isPressed
            ).borderStyle, set: .rounded, placement: .outset)
      }
    }
  }
}

private struct BorderlessButtonMenuStyleBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    configuration.portal(presentation: .init()) {
      configuration.trigger { MenuButtonTrigger(configuration: configuration) }
    }
  }
}

private struct MenuButtonTrigger: View {
  let configuration: MenuStyleConfiguration
  var body: some View {
    let chrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled, isFocused: configuration.focusActive,
      isPressed: configuration.isPressed)
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
  control.child(.named("MenuTrigger"))
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
    let portalIdentity = controlIdentity.child(.named("MenuPortal"))
    let ledger = StyleRouteInstallationLedgerStorage.current
    if let ledger, !ledger.claim(portalIdentity) {
      ImperativeRuntimeIssueQueue.record(
        StyleMisuse.duplicateRouteIssue(
          family: "MenuStyle", role: "portal", styleLabel: ledger.styleLabel,
          identity: portalIdentity))
      return [anchor.resolve(in: context)]
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
    .resolveElements(in: context)
  }
}
