public import SwiftTUICore

// MARK: - Toast / Transient Notification System

/// Type-erased storage for a toast style, the value a `toast(...)` declaration
/// carries.
///
/// Toasts have no style environment key, so this value travels with the
/// declaration rather than with a subtree: it is what the `style:` argument
/// takes. The four built-ins are available as statics, and
/// ``AnyToastStyle/init(_:)`` wraps a custom conformance. The built-ins compare
/// equal for retained reuse by type; a custom style compares by value when it
/// is `Equatable`.
public struct AnyToastStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyToastStyleBox

  /// Wraps `style` for storage on a toast declaration.
  ///
  /// - Parameter style: The concrete ``ToastStyle`` to erase.
  public init<S: ToastStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The informational toast: an `ℹ` icon and a border in the theme's info
  /// accent (``InfoToastStyle``). It is the default `style:` argument, and also
  /// the chrome that renders when a style resolves an invalid value.
  public static var info: Self {
    Self(InfoToastStyle())
  }

  /// The success toast: a `✓` icon and a border in the theme's success
  /// accent (``SuccessToastStyle``).
  public static var success: Self {
    Self(SuccessToastStyle())
  }

  /// The warning toast: a `⚠` icon and a border in the theme's warning
  /// accent (``WarningToastStyle``).
  public static var warning: Self {
    Self(WarningToastStyle())
  }

  /// The destructive or error toast: a `✗` icon and a border in the
  /// theme's danger accent (``DangerToastStyle``).
  public static var danger: Self {
    Self(DangerToastStyle())
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String {
    snapshotLabel
  }

  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String {
    snapshotLabel
  }

  @MainActor
  package func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnyToastStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

extension AnyToastStyle {
  /// The style's presentation for `configuration`, checked against the
  /// shared misuse rule (see `StyleMisuse`): an invalid value reports one
  /// `style.invalidPresentation` issue naming this style, and the info
  /// presentation renders for this resolve. Nothing traps on a style value.
  @MainActor
  package func validatedPresentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    let resolved = presentation(for: configuration)
    return StyleMisuse.validatedPresentation(
      resolved,
      problems: resolved.validationProblems(fitting: configuration.terminalSize),
      family: "ToastStyle",
      styleLabel: description,
      identity: nil,
      report: ImperativeRuntimeIssueQueue.record,
      fallback: { Self.info.presentation(for: configuration) }
    )
  }
}

/// Defines the chrome used for transient toast notifications.
///
/// A toast style is a presentation-value style:
/// ``ToastStyle/resolvePresentation(for:)`` returns a
/// ``ToastStylePresentation`` rather than a view body. Toasts are deliberately
/// declaration-scoped: a toast's tone is per-toast semantics, so
/// `.toast(..., style:)` stays the only styling path and no toast environment
/// key or `toastStyle(_:)` modifier exists.
///
/// Unlike the portal families the configuration hands the style no baseline to
/// transform, so a style builds a whole ``ToastStylePresentation`` and the
/// initializer's defaults stand in for the fields it does not set. What it is
/// handed instead is the shape of the visible stack:
/// ``ToastStyleConfiguration/stackIndex`` and
/// ``ToastStyleConfiguration/stackCount`` are known only after the coordinator
/// composes the stack, which is why a toast style resolves there rather than
/// where the toast is declared.
///
/// The coordinator keeps the stack's placement and spacing, the dismissal
/// deadline, and the rule that a toast neither takes focus nor blocks input;
/// the message belongs to the declaration. A style resolves chrome only.
///
/// The resolved value is validated: an invalid one reports one
/// `style.invalidPresentation` runtime issue naming this style, and the
/// ``AnyToastStyle/info`` chrome renders for that resolve. Nothing traps on a
/// style value.
///
/// Built-ins: ``AnyToastStyle/info``, ``AnyToastStyle/success``,
/// ``AnyToastStyle/warning``, and ``AnyToastStyle/danger``. Conform with a
/// `Sendable` struct or enum and pass the value as the `style:` argument.
///
/// ```swift
/// struct CountedToastStyle: ToastStyle {
///   var snapshotLabel: String { "CountedToastStyle" }
///
///   func resolvePresentation(
///     for configuration: ToastStyleConfiguration
///   ) -> ToastStylePresentation {
///     ToastStylePresentation(
///       icon: String(configuration.stackIndex + 1),
///       borderStyle: AnyShapeStyle(.terminalBorder(.info)))
///   }
/// }
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol ToastStyle: Sendable {
  /// The label reported in snapshots and diagnostics. Defaults to the reflected
  /// type name; the built-ins pin `"ToastStyle.info"`, `"ToastStyle.success"`,
  /// `"ToastStyle.warning"`, and `"ToastStyle.danger"`. It is diagnostic text,
  /// not identity.
  var snapshotLabel: String { get }

  /// Resolves the chrome this toast row renders.
  ///
  /// Called on the main actor while the toast is visible, each time the
  /// composed stack resolves, with this row's position in that stack. There is
  /// no baseline to start from: return a ``ToastStylePresentation``, whose
  /// initializer defaults supply the framework's neutral bar.
  ///
  /// - Parameter configuration: This row's place in the visible stack and the
  ///   render state.
  /// - Returns: The chrome for this resolve; an invalid value falls back to the
  ///   ``AnyToastStyle/info`` chrome after reporting.
  @MainActor
  func resolvePresentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
}

extension ToastStyle {
  /// The reflected type name, used when a conformance does not pin a label.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a toast style may consult.
///
/// `stackIndex` and `stackCount` are only known once the coordinator has
/// composed the active stack, which is why a toast's style resolves at
/// composition time rather than where it is declared. There is deliberately no
/// `defaultPresentation` and no control prominence here: a toast style builds a
/// whole ``ToastStylePresentation`` rather than transforming a baseline.
/// Nothing here is a binding or an authored view; the toast's message stays
/// with the declaration.
public struct ToastStyleConfiguration: Sendable {
  /// This toast's position in the visible stack, oldest first.
  public var stackIndex: Int
  /// How many toasts are visible in the stack.
  public var stackCount: Int
  /// The terminal's size in cells when the stack composed, for sizing relative
  /// to the terminal rather than to a fixed width. The resolved padding is also
  /// checked to leave room for content inside it.
  public var terminalSize: CellSize
  /// The `StyleEnvironmentSnapshot` where the toast was declared: the detected
  /// appearance, the active theme, the ambient paints, and the enabled state,
  /// from which a style derives its colors.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    stackIndex: Int,
    stackCount: Int,
    terminalSize: CellSize,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.stackIndex = stackIndex
    self.stackCount = stackCount
    self.terminalSize = terminalSize
    self.styleEnvironment = styleEnvironment
  }
}

/// Resolved toast chrome: the icon, paint, padding, and size bounds one
/// notification bar renders.
///
/// A ``ToastStyle`` returns this value from
/// ``ToastStyle/resolvePresentation(for:)``. Unlike the portal families a toast
/// style is handed no baseline, so it builds a whole value and the
/// initializer's defaults stand in for the rest. The field names are the toast
/// family's own rather than the shared portal chrome vocabulary, and the border
/// carries a paint but no stroke geometry, so its shape is fixed. All
/// dimensions are terminal cells.
///
/// The bar validates the value before rendering it. Negative or unrepresentable
/// padding, padding that leaves no cell of the terminal for content,
/// non-positive, misordered, or unrepresentable width or height bounds, or an
/// icon that is empty or carries a glyph no terminal cell can hold reports one
/// `style.invalidPresentation` runtime issue naming the style, and the
/// ``AnyToastStyle/info`` chrome renders for that resolve. A count larger than
/// any terminal is still valid: the size bound is representability. Nothing
/// traps on a style value.
public struct ToastStylePresentation: Sendable {
  /// A short glyph run drawn before the content in `iconStyle`. `nil` (the
  /// default) omits it. When set it must be non-empty, and every grapheme must
  /// occupy one or two terminal cells and must not be a control, line, or
  /// paragraph separator, because the icon shares one row with the content.
  public var icon: String?
  /// The paint of the icon run. Defaults to the ambient foreground; the
  /// built-ins use the theme's accent for their tone.
  public var iconStyle: AnyShapeStyle
  /// The fill behind the bar. Defaults to the theme's surface background.
  public var backgroundStyle: AnyShapeStyle
  /// The paint of the bar's border, drawn with the framework's default stroke.
  /// Defaults to the theme's separator paint; the built-ins use the theme's
  /// border in their tone.
  public var borderStyle: AnyShapeStyle
  /// Padding in cells between the border and the icon-and-content row.
  /// Defaults to one cell on every edge. Edges must be non-negative and
  /// representable, and the horizontal and vertical sums must leave at least
  /// one cell of the terminal for content.
  public var contentPadding: EdgeInsets
  /// The smallest width of the bar, in cells. Defaults to `10`.
  public var minWidth: Int
  /// The largest width of the bar, in cells. Defaults to `60`. The widths must
  /// be positive, representable, and ordered minimum then maximum.
  public var maxWidth: Int
  /// The smallest height of the bar, in cells. Defaults to `3`.
  public var minHeight: Int
  /// The height of the bar when no height is proposed, in cells. Defaults to
  /// `3`.
  public var idealHeight: Int
  /// The largest height of the bar, in cells. Defaults to `5`. The three
  /// heights must be positive, representable, and ordered minimum, ideal,
  /// maximum.
  public var maxHeight: Int

  /// Constructs toast chrome, defaulting every field to the framework's neutral
  /// bar.
  ///
  /// Without arguments the result is an iconless bar on the theme's surface
  /// background inside a separator-colored border, one cell of padding, 10 to
  /// 60 cells wide, and 3 to 5 cells tall. A built-in tone is this value with
  /// an icon and the theme's accent and border for its tone.
  ///
  /// - Parameters:
  ///   - icon: A glyph run drawn before the content, or `nil` for none.
  ///   - iconStyle: The icon's paint.
  ///   - backgroundStyle: The fill behind the bar.
  ///   - borderStyle: The border's paint.
  ///   - contentPadding: Padding in cells inside the border.
  ///   - minWidth: The smallest width in cells.
  ///   - maxWidth: The largest width in cells.
  ///   - minHeight: The smallest height in cells.
  ///   - idealHeight: The height used when none is proposed.
  ///   - maxHeight: The largest height in cells.
  public init(
    icon: String? = nil,
    iconStyle: AnyShapeStyle = AnyShapeStyle(.foreground),
    backgroundStyle: AnyShapeStyle = AnyShapeStyle(.terminalSurfaceBackground),
    borderStyle: AnyShapeStyle = AnyShapeStyle(.separator),
    contentPadding: EdgeInsets = .init(all: 1),
    minWidth: Int = 10,
    maxWidth: Int = 60,
    minHeight: Int = 3,
    idealHeight: Int = 3,
    maxHeight: Int = 5
  ) {
    self.icon = icon
    self.iconStyle = iconStyle
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
    self.contentPadding = contentPadding
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.minHeight = minHeight
    self.idealHeight = idealHeight
    self.maxHeight = maxHeight
  }
}

extension ToastStylePresentation {
  /// Why this value cannot render as resolved, independent of the terminal:
  /// negative or unrepresentable padding; non-positive, misordered, or
  /// unrepresentable width and height bounds; or an icon that is empty or
  /// carries a glyph no terminal cell can hold. Empty when the value is valid.
  package var validationProblems: [String] {
    var problems: [String] = []
    let representable = AnchoredSurfaceStylePresentation.representableCellCount
    if paddingInsets.contains(where: { $0 < 0 }) {
      problems.append("contentPadding must not be negative")
    }
    if paddingInsets.contains(where: { $0 > representable }) {
      problems.append("contentPadding must be representable cell counts")
    }
    if minWidth <= 0 || maxWidth < minWidth || maxWidth > representable {
      problems.append("widths must be positive, representable, and ordered minimum, maximum")
    }
    if minHeight <= 0 || idealHeight < minHeight || maxHeight < idealHeight
      || maxHeight > representable
    {
      problems.append(
        "heights must be positive, representable, and ordered minimum, ideal, maximum")
    }
    if let icon, !toastIconIsRenderable(icon) {
      problems.append("icon must be one or more glyphs of one or two terminal cells")
    }
    return problems
  }

  /// `validationProblems` plus the terminal-fit rule: padding whose
  /// horizontal sum reaches `terminalSize.width`, or whose vertical sum
  /// reaches `terminalSize.height`, leaves no cell for content. The fit rule
  /// waits for a positive terminal extent, so an unsized host reports only
  /// the terminal-independent problems.
  package func validationProblems(fitting terminalSize: CellSize) -> [String] {
    var problems = validationProblems
    let representable = AnchoredSurfaceStylePresentation.representableCellCount
    // The sums are only safe to form once every inset is within the
    // representable range.
    guard paddingInsets.allSatisfy({ (0...representable).contains($0) }) else {
      return problems
    }
    if terminalSize.width > 0, contentPadding.horizontal >= terminalSize.width {
      problems.append("contentPadding must leave room for content in the terminal width")
    }
    if terminalSize.height > 0, contentPadding.vertical >= terminalSize.height {
      problems.append("contentPadding must leave room for content in the terminal height")
    }
    return problems
  }

  private var paddingInsets: [Int] {
    [contentPadding.top, contentPadding.leading, contentPadding.bottom, contentPadding.trailing]
  }
}

/// A toast icon renders as one text run beside the content, so every
/// grapheme must occupy one or two terminal cells and none may break the
/// row (a control, line, or paragraph separator).
private func toastIconIsRenderable(_ icon: String) -> Bool {
  !icon.isEmpty
    && icon.allSatisfy { (1...2).contains(cellWidth(of: $0)) }
    && icon.unicodeScalars.allSatisfy {
      let category = $0.properties.generalCategory
      return category != .control && category != .lineSeparator
        && category != .paragraphSeparator
    }
}

/// The standard informational toast style: an `ℹ` icon and a border in the
/// theme's info accent, over the theme's surface background.
public struct InfoToastStyle: ToastStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ToastStyle.info"`.
  public var snapshotLabel: String {
    "ToastStyle.info"
  }

  /// Returns the neutral toast chrome with the `ℹ` icon and the info accent
  /// painting the icon and the border. Padding and the size bounds are the
  /// defaults of ``ToastStylePresentation``, and the row's place in the stack
  /// is not consulted.
  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .info,
      icon: "ℹ"
    )
  }
}

/// The standard success toast style: a `✓` icon and a border in the
/// theme's success accent, over the theme's surface background.
public struct SuccessToastStyle: ToastStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ToastStyle.success"`.
  public var snapshotLabel: String {
    "ToastStyle.success"
  }

  /// Returns the neutral toast chrome with the `✓` icon and the success accent
  /// painting the icon and the border. Padding and the size bounds are the
  /// defaults of ``ToastStylePresentation``, and the row's place in the stack
  /// is not consulted.
  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .success,
      icon: "✓"
    )
  }
}

/// The standard warning toast style: a `⚠` icon and a border in the
/// theme's warning accent, over the theme's surface background.
public struct WarningToastStyle: ToastStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ToastStyle.warning"`.
  public var snapshotLabel: String {
    "ToastStyle.warning"
  }

  /// Returns the neutral toast chrome with the `⚠` icon and the warning accent
  /// painting the icon and the border. Padding and the size bounds are the
  /// defaults of ``ToastStylePresentation``, and the row's place in the stack
  /// is not consulted.
  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .warning,
      icon: "⚠"
    )
  }
}

/// The standard destructive or error toast style: a `✗` icon and a border in the
/// theme's danger accent, over the theme's surface background.
public struct DangerToastStyle: ToastStyle {
  /// Creates the style.
  public init() {}

  /// The label reported in snapshots and diagnostics, `"ToastStyle.danger"`.
  public var snapshotLabel: String {
    "ToastStyle.danger"
  }

  /// Returns the neutral toast chrome with the `✗` icon and the danger accent
  /// painting the icon and the border. Padding and the size bounds are the
  /// defaults of ``ToastStylePresentation``, and the row's place in the stack
  /// is not consulted.
  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .danger,
      icon: "✗"
    )
  }
}

extension InfoToastStyle: ReuseTransparentStyle {}
extension SuccessToastStyle: ReuseTransparentStyle {}
extension WarningToastStyle: ReuseTransparentStyle {}
extension DangerToastStyle: ReuseTransparentStyle {}

private protocol AnyToastStyleBox: AnyStyleBox {
  @MainActor
  func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
}

extension ConcreteStyleBox: AnyToastStyleBox where S: ToastStyle {

  @MainActor
  func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    style.resolvePresentation(for: configuration)
  }

}

private func semanticToastStylePresentation(
  tone: TerminalTone,
  icon: String
) -> ToastStylePresentation {
  ToastStylePresentation(
    icon: icon,
    iconStyle: AnyShapeStyle(.terminalAccent(tone)),
    backgroundStyle: AnyShapeStyle(.terminalSurfaceBackground),
    borderStyle: AnyShapeStyle(.terminalBorder(tone))
  )
}

extension View {
  /// Presents `message` as a transient notification bar over the base content.
  ///
  /// The bar appears while `isPresented` is `true`, stacked with any other
  /// visible toasts at the terminal's bottom leading corner. It never takes
  /// focus and never blocks input, so it does not interrupt what the base
  /// content is doing. After `duration` seconds the toast dismisses itself,
  /// setting `isPresented` back to `false` and then calling `onDismiss`.
  /// Passing `nil`, or a duration that is not positive, arms no deadline, so
  /// the toast stays visible until the binding is cleared (see
  /// <doc:Dismissal-Is-Data>).
  ///
  /// `style` is the only styling path for a toast: there is no toast
  /// environment key and no `toastStyle(_:)` modifier, because a toast's tone
  /// is per-notification semantics. See ``ToastStyle``.
  ///
  /// - Parameters:
  ///   - message: The text the bar renders.
  ///   - isPresented: Whether the toast is visible. The framework clears it
  ///     when the toast dismisses itself.
  ///   - style: The chrome to render: ``AnyToastStyle/info`` (the default),
  ///     ``AnyToastStyle/success``, ``AnyToastStyle/warning``,
  ///     ``AnyToastStyle/danger``, or a custom ``ToastStyle`` wrapped in
  ///     ``AnyToastStyle``.
  ///   - duration: How many seconds the toast stays visible, or `nil` to stay
  ///     until dismissed. Defaults to three seconds.
  ///   - onDismiss: Called after the toast leaves the screen.
  public func toast<S: StringProtocol>(
    _ message: S,
    isPresented: Binding<Bool>,
    style: AnyToastStyle = .info,
    duration: Double? = 3.0,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: Text(String(message)),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents `message` as a transient notification bar in a custom style.
  ///
  /// Equivalent to wrapping `style` in ``AnyToastStyle``. The bar behaves
  /// exactly as it does for the erased overload.
  ///
  /// - Parameters:
  ///   - message: The text the bar renders.
  ///   - isPresented: Whether the toast is visible. The framework clears it
  ///     when the toast dismisses itself.
  ///   - style: A custom ``ToastStyle`` value.
  ///   - duration: How many seconds the toast stays visible, or `nil` to stay
  ///     until dismissed. Defaults to three seconds.
  ///   - onDismiss: Called after the toast leaves the screen.
  public func toast<S: StringProtocol, Style: ToastStyle>(
    _ message: S,
    isPresented: Binding<Bool>,
    style: Style,
    duration: Double? = 3.0,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    toast(
      message,
      isPresented: isPresented,
      style: AnyToastStyle(style),
      duration: duration,
      onDismiss: onDismiss
    )
  }

  /// Presents authored content as a transient notification bar over the base
  /// content.
  ///
  /// The content builder replaces the message text; everything else matches the
  /// text form. The bar appears while `isPresented` is `true`, stacked at the
  /// terminal's bottom leading corner, takes no focus, and blocks no input.
  /// After `duration` seconds it dismisses itself, clearing `isPresented` and
  /// then calling `onDismiss`; `nil`, or a duration that is not positive, arms
  /// no deadline, so the toast stays until the binding is cleared. The content
  /// keeps the state and scope it was authored in.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the toast is visible. The framework clears it
  ///     when the toast dismisses itself.
  ///   - style: The chrome to render: ``AnyToastStyle/info`` (the default),
  ///     ``AnyToastStyle/success``, ``AnyToastStyle/warning``,
  ///     ``AnyToastStyle/danger``, or a custom ``ToastStyle`` wrapped in
  ///     ``AnyToastStyle``.
  ///   - duration: How many seconds the toast stays visible, or `nil` to stay
  ///     until dismissed. Defaults to three seconds.
  ///   - onDismiss: Called after the toast leaves the screen.
  ///   - toastContent: The content the bar renders beside the style's icon.
  public func toast<ToastContent: View>(
    isPresented: Binding<Bool>,
    style: AnyToastStyle = .info,
    duration: Double? = 3.0,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: toastContent(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents authored content as a transient notification bar in a custom
  /// style.
  ///
  /// Equivalent to wrapping `style` in ``AnyToastStyle``. The bar behaves
  /// exactly as it does for the erased overload.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the toast is visible. The framework clears it
  ///     when the toast dismisses itself.
  ///   - style: A custom ``ToastStyle`` value.
  ///   - duration: How many seconds the toast stays visible, or `nil` to stay
  ///     until dismissed. Defaults to three seconds.
  ///   - onDismiss: Called after the toast leaves the screen.
  ///   - toastContent: The content the bar renders beside the style's icon.
  public func toast<ToastContent: View, Style: ToastStyle>(
    isPresented: Binding<Bool>,
    style: Style,
    duration: Double? = 3.0,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    toast(
      isPresented: isPresented,
      style: AnyToastStyle(style),
      duration: duration,
      onDismiss: onDismiss,
      content: toastContent
    )
  }
}

/// The modifier the `toast(...)` methods install, carrying one toast
/// declaration; apps call those methods rather than naming this type, which has
/// no public initializer.
public struct ToastModifier<ToastContent: View>: IterativePrimitiveViewModifier {
  var isPresented: Binding<Bool>
  var style: AnyToastStyle
  var duration: Double?
  var toastContent: ToastContent
  var dismissAuthoringContext: AuthoringContext? = makePortalAttachmentAuthoringContext()
  var onDismiss: (@MainActor @Sendable () -> Void)? = nil
  var onDismissAuthoringContext: AuthoringContext? = makePortalAttachmentAuthoringContext()

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveWork(in: context).map { completed in
      var node = completed
      // Toasts emit their declaration directly (no trigger leaf), so they
      // report the activation observation here — the frame head's portal
      // reconcile escalation depends on seeing every emitter's resolve.
      let active = isPresented.wrappedValue
      context.presentationTriggerObserver?.record(
        sourceIdentity: node.identity,
        isActive: active,
        emitterIdentity: node.identity
      )
      guard active else {
        return [node]
      }

      let sourceIdentity = node.identity
      // Chained `.toast` modifiers collapse onto one chain node and share its
      // source identity; the inner modifier's declaration is already merged on
      // the flowing node when the outer resolves, so counting same-source
      // declarations claims the next attachment ordinal — distinct portal
      // tokens ("toast", "toast[1]", …) keep chained items from overwriting
      // each other in the family store. The ordinal counts *active* inner
      // declarations only, so an inner toggle can shift an outer token; the
      // re-minted entry then re-arms its dismissal deadline, which is
      // acceptable for transient toasts.
      let attachmentOrdinal = node.preferenceValues[
        PresentationCoordinatorDeclarationPreferenceKey.self
      ].declarations.count { $0.sourceIdentity == sourceIdentity }
      let token = attachmentOrdinal == 0 ? "toast" : "toast[\(attachmentOrdinal)]"
      let portalEntryID = presentationAttachment(for: node, token: token)
      let dismissInvalidator = context.invalidationProxy?.invalidator
      let onDismiss = presentationDismissObserver(
        onDismiss,
        authoringContext: onDismissAuthoringContext
      )
      let item = ToastPresentationItem(
        id: portalEntryID.description,
        portalEntryID: portalEntryID,
        contentPayloads: portalAttachmentDeclaredBuilderChildren(
          from: toastContent,
          portalEntryID: portalEntryID,
          modalPolicy: .nonModal
        ),
        style: style,
        duration: duration,
        sourceEnvironmentValues: context.environmentValues,
        dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
          withAuthoringContext(dismissAuthoringContext) {
            isPresented.wrappedValue = false
          }
          dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
        },
        onDismiss: onDismiss
      )

      var declaration = PresentationCoordinatorDeclaration(
        sourceIdentity: sourceIdentity
      ) { registry in
        registry.toast.sync(
          sourceIdentity: sourceIdentity,
          items: [item]
        )
      }
      // Toasts declare directly (no trigger leaf), so they stamp the captured
      // presenter environment themselves — mirrors `resolvePresentationModifier`.
      declaration.sourceEnvironmentValues = context.environmentValues
      node.preferenceValues.merge(
        PresentationCoordinatorDeclarationPreferenceKey.self,
        value: .init(declarations: [declaration])
      )
      return [node]

    }
  }
}

package struct ToastCoordinatorBodyView: View {
  package var items: [ToastPresentationItem]

  package init(
    items: [ToastPresentationItem]
  ) {
    self.items = items
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 1) {
        // The stack's shape is known here and nowhere earlier, so each
        // row resolves its own style against its position in it.
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          ToastSourceEnvironmentView(item: item, stackIndex: index, stackCount: items.count)
        }
      }
      .padding(.bottom, 1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .allowsHitTesting(false)
  }
}

private struct ToastPresentationView: View {
  var item: ToastPresentationItem
  var stackIndex: Int
  var stackCount: Int
  @Environment(\.toastPresentationCoordinator) private var coordinatorHandle
  @Environment(\.terminalSize) private var terminalSize
  @Environment(\.styleEnvironmentSnapshot) private var styleEnvironment

  var body: some View {
    // Read during body evaluation: environment storage is ambient only while
    // resolving, so the task closure must capture the handle value, not the
    // property (an in-task read would see defaults).
    let handle = coordinatorHandle
    // Validated here, the one seam where the composition-time configuration
    // exists: an invalid value reports once and the info presentation renders.
    let presentation = item.style.validatedPresentation(
      for: ToastStyleConfiguration(
        stackIndex: stackIndex,
        stackCount: stackCount,
        terminalSize: terminalSize,
        styleEnvironment: styleEnvironment
      )
    )
    let toastBody = HStack(alignment: .center, spacing: 1) {
      if let icon = presentation.icon {
        Text(icon)
          .foregroundStyle(presentation.iconStyle)
      }
      VStack {
        PortalAttachmentGroupView(
          kindName: "ToastContent",
          payloads: item.contentPayloads
        )
      }
    }
    .padding(presentation.contentPadding)
    .background {
      Rectangle().fill(presentation.backgroundStyle)
    }
    .overlay {
      Rectangle().strokeBorder(
        presentation.borderStyle
      )
    }
    .frame(
      minWidth: .finite(presentation.minWidth),
      maxWidth: .finite(presentation.maxWidth),
      minHeight: .finite(presentation.minHeight),
      idealHeight: .finite(presentation.idealHeight),
      maxHeight: .finite(presentation.maxHeight),
      alignment: .leading
    )
    // Keyed on duration so replacing the active deadline (nil<->finite,
    // shorter/longer) cancels the running sleep and arms the current one.
    .task(id: item.duration) {
      guard let duration = item.duration, duration > 0 else {
        return
      }
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else {
        return
      }
      // Fire-time lookup through the live portal state: a re-synced item
      // (same id, retargeted binding) must dismiss through its current
      // closure, not the one captured when this deadline was armed.
      let activeItem = handle.activeItem(id: item.id)
      (activeItem ?? item).dismiss()
    }
    if let onDismiss = item.onDismiss {
      toastBody.onDisappear(perform: onDismiss)
    } else {
      toastBody
    }
  }
}

/// Aggregate stack placement stays coordinator-owned; each row restores its
/// own declaration's environment before resolving chrome and authored content.
private struct ToastSourceEnvironmentView: PrimitiveView, IterativeResolvableView {
  var item: ToastPresentationItem
  var stackIndex: Int
  var stackCount: Int

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let rowContext = item.sourceEnvironmentValues.map(context.replacingEnvironmentValues) ?? context
    return resolveViewWork(
      ToastPresentationView(item: item, stackIndex: stackIndex, stackCount: stackCount),
      in: rowContext
    ).map { [$0] }
  }
}
