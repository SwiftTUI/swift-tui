public import SwiftTUICore

// MARK: - Toast / Transient Notification System

/// Type-erased storage for a concrete toast style.
public struct AnyToastStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyToastStyleBox

  public init<S: ToastStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyToastStyleBox(style: style)
  }

  public static var info: Self {
    Self(InfoToastStyle())
  }

  public static var success: Self {
    Self(SuccessToastStyle())
  }

  public static var warning: Self {
    Self(WarningToastStyle())
  }

  public static var danger: Self {
    Self(DangerToastStyle())
  }

  public var description: String {
    snapshotLabel
  }

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

/// Defines the chrome used for transient toast notifications.
///
/// Toasts are deliberately declaration-scoped: a toast's tone is per-toast
/// semantics, so `.toast(..., style:)` stays the only styling path and no
/// toast environment key or `toastStyle(_:)` modifier exists.
public protocol ToastStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
}

extension ToastStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a toast style may consult.
///
/// `stackIndex` and `stackCount` are only known once the coordinator has
/// composed the active stack, which is why a toast's style resolves at
/// composition time rather than where it is declared.
public struct ToastStyleConfiguration: Sendable {
  /// This toast's position in the visible stack, oldest first.
  public var stackIndex: Int
  /// How many toasts are visible in the stack.
  public var stackCount: Int
  public var terminalSize: CellSize
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

public struct ToastStylePresentation: Sendable {
  public var icon: String?
  public var iconStyle: AnyShapeStyle
  public var backgroundStyle: AnyShapeStyle
  public var borderStyle: AnyShapeStyle
  public var contentPadding: EdgeInsets
  public var minWidth: Int
  public var maxWidth: Int
  public var minHeight: Int
  public var idealHeight: Int
  public var maxHeight: Int

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

/// The standard informational toast style.
public struct InfoToastStyle: ToastStyle {
  public init() {}

  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .info,
      icon: "ℹ"
    )
  }
}

/// The standard success toast style.
public struct SuccessToastStyle: ToastStyle {
  public init() {}

  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .success,
      icon: "✓"
    )
  }
}

/// The standard warning toast style.
public struct WarningToastStyle: ToastStyle {
  public init() {}

  public func resolvePresentation(
    for _: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    semanticToastStylePresentation(
      tone: .warning,
      icon: "⚠"
    )
  }
}

/// The standard destructive or error toast style.
public struct DangerToastStyle: ToastStyle {
  public init() {}

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

private protocol AnyToastStyleBox: Sendable {
  @MainActor
  func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
  func isEqualForReuse(to other: any AnyToastStyleBox) -> Bool
}

private struct ConcreteAnyToastStyleBox<S: ToastStyle>: AnyToastStyleBox {
  let style: S

  @MainActor
  func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnyToastStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
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
  /// Displays a transient notification bar that auto-dismisses.
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

  /// Displays a transient notification bar that auto-dismisses.
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

  /// Displays a transient notification with custom content that auto-dismisses.
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

  /// Displays a transient notification with custom content that auto-dismisses.
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

public struct ToastModifier<ToastContent: View>: PrimitiveViewModifier {
  var isPresented: Binding<Bool>
  var style: AnyToastStyle
  var duration: Double?
  var toastContent: ToastContent
  var dismissAuthoringContext: AuthoringContext? = makePortalAttachmentAuthoringContext()
  var onDismiss: (@MainActor @Sendable () -> Void)? = nil
  var onDismissAuthoringContext: AuthoringContext? = makePortalAttachmentAuthoringContext()

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
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
          ToastPresentationView(
            item: item,
            stackIndex: index,
            stackCount: items.count
          )
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
    let presentation = item.style.presentation(
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
