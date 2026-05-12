public import SwiftTUICore

package struct PromptPresentationSpec: Sendable {
  package var token: String
  package var descriptor: PromptPresentationDescriptor
  package var reconcile:
    @MainActor @Sendable (
      PresentationCoordinatorRegistry,
      Identity,
      PromptPresentationItem
    ) -> Void

  package init(
    token: String,
    descriptor: PromptPresentationDescriptor,
    reconcile:
      @escaping @MainActor @Sendable (
        PresentationCoordinatorRegistry,
        Identity,
        PromptPresentationItem
      ) -> Void
  ) {
    self.token = token
    self.descriptor = descriptor
    self.reconcile = reconcile
  }
}

package func alertPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "alert",
    descriptor: .init(
      alignment: .center,
      accessibilityRole: .alert,
      backdropOpacity: 0,
      defaultDismissTitle: "Dismiss",
      headerTone: .neutral,
      minWidth: 24,
      maxWidth: 48,
      scrollMinHeight: 2,
      scrollIdealHeight: 6,
      scrollMaxHeight: 10,
      bodyMode: .messageAndActions
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.alert.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

package func confirmationDialogPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "confirmationDialog",
    descriptor: .init(
      alignment: .bottomLeading,
      accessibilityRole: .confirmationDialog,
      backdropOpacity: 0,
      defaultDismissTitle: "Cancel",
      headerTone: .accent,
      minWidth: 20,
      scrollMinHeight: 3,
      scrollIdealHeight: 4,
      scrollMaxHeight: 6,
      bodyMode: .messageAndActions
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.confirmationDialog.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

/// Spec for `Menu`'s expanded content. Menus use a dedicated non-modal
/// portal entry with a unique `"menu"` token (so menu attachment IDs never
/// collide with sheet attachment IDs on the same source identity) and `.menu`
/// chrome (so the rendering surface is a compact, intrinsic-width bordered box
/// with no header).
package func menuPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "menu",
    descriptor: .init(
      alignment: .topLeading,
      accessibilityRole: .menu,
      backdropOpacity: 0,
      defaultDismissTitle: "Close",
      headerTone: .accent,
      minWidth: 0,
      // Menus auto-size to content; the scroll bounds below act only as
      // a safety cap if a menu's content grows past the visible area.
      scrollMinHeight: 1,
      scrollIdealHeight: 8,
      scrollMaxHeight: 32,
      bodyMode: .contentOnly,
      chrome: .menu,
      contentSizing: .intrinsic
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.menu.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

package func sheetPromptPresentationSpec(
  backdropOpacity: Double = 0,
  chrome: PresentationChrome = .surface
) -> PromptPresentationSpec {
  // Dropdown-chromed sheets want to land flush against the window
  // edge (top, full width) rather than floating centered; override
  // the layout defaults so callers don't have to restate them.
  let alignment: Alignment =
    switch chrome {
    case .surface: .center
    case .dropdown: .topLeading
    // .menu is dispatched through `menuPromptPresentationSpec()`; if a
    // caller manually plumbs it through this sheet builder, fall back
    // to the dropdown-flavored top-leading anchoring.
    case .menu: .topLeading
    }
  let minWidth: Int =
    switch chrome {
    case .surface: 20
    case .dropdown: 0
    case .menu: 0
    }
  return PromptPresentationSpec(
    token: "sheet",
    descriptor: .init(
      alignment: alignment,
      accessibilityRole: .sheet,
      backdropOpacity: backdropOpacity,
      defaultDismissTitle: "Close",
      headerTone: .accent,
      minWidth: minWidth,
      scrollMinHeight: 4,
      scrollIdealHeight: 12,
      scrollMaxHeight: 20,
      bodyMode: .contentOnly,
      chrome: chrome
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.sheet.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

extension View {
  public func alert<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    let spec = alertPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.descriptor.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makeDeferredAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func alert<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: alertPromptPresentationSpec(),
        actions: actions(),
        message: message(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func confirmationDialog<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    let spec = confirmationDialogPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.descriptor.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makeDeferredAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: confirmationDialogPromptPresentationSpec(),
        actions: actions(),
        message: message(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func sheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: "",
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func sheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

}

@MainActor
private func defaultPresentationActions(
  defaultDismissTitle: String,
  isPresented: Binding<Bool>,
  dismissAuthoringContext: AuthoringContext?
) -> Button<Text> {
  Button(
    defaultDismissTitle,
    action: {
      withAuthoringContext(dismissAuthoringContext) {
        isPresented.wrappedValue = false
      }
    }
  )
}

public struct BuiltinPromptPresentationModifier<Actions: View, Message: View>:
  PrimitiveViewModifier
{
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var actions: Actions
  var message: Message
  var actionsAuthoringContext: AuthoringContext?
  var messageAuthoringContext: AuthoringContext?
  var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: withAuthoringContext(actionsAuthoringContext) {
        portalDeclaredBuilderChildren(from: actions)
      },
      messagePayloads: withAuthoringContext(messageAuthoringContext) {
        portalDeclaredBuilderChildren(from: message)
      },
      contentPayloads: [],
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

public struct BuiltinSheetPresentationModifier<SheetContent: View>: PrimitiveViewModifier {
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var sheetContent: SheetContent
  var sheetContentAuthoringContext: AuthoringContext?
  var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: [],
      messagePayloads: [],
      contentPayloads: withAuthoringContext(sheetContentAuthoringContext) {
        portalDeclaredBuilderChildren(from: sheetContent)
      },
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

/// Sheet variant that absorbs `paletteCommand` contributions from the
/// enclosing scope's subtree via `PaletteCommandsPreferenceKey` and
/// passes the snapshot into the sheet content closure. Mirrors the
/// `.toolbar(style:)` absorption pattern.
public struct BuiltinPaletteSheetPresentationModifier<SheetContent: View>: PrimitiveViewModifier {
  package let title: String
  package let isPresented: Binding<Bool>
  package let sheetContentBuilder: ([ActivePaletteCommand]) -> SheetContent
  package let sheetContentAuthoringContext: AuthoringContext?
  package let dismissAuthoringContext: AuthoringContext?

  package init(
    title: String,
    isPresented: Binding<Bool>,
    sheetContentBuilder: @escaping ([ActivePaletteCommand]) -> SheetContent,
    sheetContentAuthoringContext: AuthoringContext?,
    dismissAuthoringContext: AuthoringContext?
  ) {
    self.title = title
    self.isPresented = isPresented
    self.sheetContentBuilder = sheetContentBuilder
    self.sheetContentAuthoringContext = sheetContentAuthoringContext
    self.dismissAuthoringContext = dismissAuthoringContext
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)

    let absorbed = node.preferenceValues[PaletteCommandsPreferenceKey.self]
    node.preferenceValues[PaletteCommandsPreferenceKey.self] = []

    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let spec = sheetPromptPresentationSpec(chrome: .dropdown)
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: [],
      messagePayloads: [],
      contentPayloads: withAuthoringContext(sheetContentAuthoringContext) {
        portalDeclaredBuilderChildren(from: sheetContentBuilder(absorbed))
      },
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

extension ActionScope where Self: View {
  /// Presents a palette sheet whose content closure receives all
  /// `paletteCommand(...)` contributions absorbed from this scope's
  /// subtree. The snapshot is recomputed each resolve, so an open
  /// palette stays in sync with subtree changes.
  ///
  /// Mirrors `.toolbar(style:)` ↔ `.toolbarItem(...)`.
  @MainActor
  public func paletteSheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping @MainActor ([ActivePaletteCommand]) -> SheetContent
  ) -> some View & ActionScope {
    modifier(
      BuiltinPaletteSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        sheetContentBuilder: content,
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }
}

package struct HostedPromptPresentation: View {
  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  package var body: some View {
    ZStack(alignment: .topLeading) {
      if item.descriptor.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(item.descriptor.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      sizedSurface
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: item.descriptor.alignment
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var sizedSurface: some View {
    let surface = PromptPresentationSurface(item: item)
      .padding(insetEdges)

    switch item.descriptor.contentSizing {
    case .fillAvailable:
      surface
    case .intrinsic:
      surface.fixedSize(horizontal: true, vertical: true)
    }
  }

  // Dropdown chrome lands flush against the window edges; surface
  // chrome floats with a 1-cell inset so the stroked box never kisses
  // the terminal edge.
  private var insetEdges: EdgeInsets {
    switch item.descriptor.chrome {
    case .surface:
      .init(top: 1, leading: 1, bottom: 1, trailing: 1)
    case .dropdown:
      .init(top: 0, leading: 0, bottom: 0, trailing: 0)
    // Menu chrome supplies its own padding around its bordered box;
    // the host applies a small leading/top inset so the box doesn't
    // kiss the terminal edge when the menu opens at top-leading.
    case .menu:
      .init(top: 0, leading: 1, bottom: 0, trailing: 0)
    }
  }
}

/// The root view of a presented sheet/alert/confirmation-dialog
/// subtree.
///
/// `PromptPresentationSurface` is the presented content root: when a
/// `.sheet(...)`, `.alert(...)`, or `.confirmationDialog(...)` is
/// active, this view appears as the root of that presentation's
/// subtree in the rendered tree, wrapped in the presentation host
/// overlay. Its resolved node carries `focusScopeBoundary: true` via
/// the `.focusScope()` modifier applied in its body, so every focus
/// region emitted underneath a presentation carries the
/// presentation's identity on its `scopePath`.
///
/// Conforming to `ActionScope` makes the presentation a first-class
/// scope in the `ActionScope` world: commands scoped to the
/// presentation become active exactly when the presentation's scope
/// identity is on the focus chain.
package struct PromptPresentationSurface: View, ActionScope {
  package typealias ID = String

  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  /// The presentation's identity is the item's attachment id — a
  /// stable `String` derived from the source identity and the
  /// presentation token (see `presentationAttachmentID`).
  package nonisolated var id: String {
    item.id
  }

  package var body: some View {

    let content = VStack(alignment: .leading, spacing: 0) {
      presentationHeader
      switch item.descriptor.bodyMode {
      case .contentOnly:
        contentBody
      case .messageAndActions:
        messageAndActionBody
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))

    switch item.descriptor.chrome {
    case .surface:
      content
        .background {
          RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(.terminalSurfaceBackground)
        }
        .overlay {
          // .outset: chrome reserves layout space (frame grows). The rasterizer's
          // interior-fill sampling for presentation chrome is a separate
          // glyph-identity check, not a placement check.
          RoundedRectangle(cornerRadius: 1).strokeBorder(
            .terminalBorder(.accent),
            style: StrokeStyle(borderSet: .innerHalfBlock, placement: .outset)
          )
        }
        .frame(
          minWidth: .finite(item.descriptor.minWidth),
          maxWidth: maximumWidth,
          alignment: .leading
        )
        .focusScope()
        .semanticMetadata(
          .init(
            accessibilityRole: item.descriptor.accessibilityRole
          )
        )
    case .menu:
      // Menu chrome: compact, intrinsic-width bordered box. No header
      // row (the trigger that opened it stays in place behind the
      // overlay), no close button (Escape dismisses), no max-width cap
      // (the menu sizes to its longest item).
      menuContentBody
        .padding(.init(horizontal: 1, vertical: 1))
        .background {
          Rectangle().fill(.terminalSurfaceBackground)
        }
        .overlay {
          Rectangle().strokeBorder(
            .terminalBorder(.accent),
            style: StrokeStyle(borderSet: .innerHalfBlock, placement: .outset)
          )
        }
        .focusScope()
        .semanticMetadata(
          .init(
            accessibilityRole: item.descriptor.accessibilityRole
          )
        )
    case .dropdown:
      // Full-width, top-aligned strip. No side or top border — a single
      // soft bottom divider reads as a shadow under the content.
      content
        .frame(
          maxWidth: .infinity,
          alignment: .topLeading
        )
        .background {
          Rectangle().fill(.terminalSurfaceBackground)
        }
        .overlay(alignment: .bottom) {
          Divider()
            .foregroundStyle(.separator)
            .drawMetadata(.init(opacity: 0.6))
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .focusScope()
        .semanticMetadata(
          .init(
            accessibilityRole: item.descriptor.accessibilityRole
          )
        )
    }
  }

  private var maximumWidth: ProposedDimension {
    if let maxWidth = item.descriptor.maxWidth {
      return .finite(maxWidth)
    }
    return .infinity
  }

  private var presentationHeader: some View {
    HStack(alignment: .center, spacing: 1) {
      if !item.title.isEmpty {
        Text(item.title)
          .bold()
      }
      Spacer(minLength: 0)
      Button("×", role: .close, action: item.dismiss)
        .buttonStyle(.borderedProminent)
    }
    .frame(height: 1, alignment: .leading)
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(item.descriptor.headerTone, isSelected: true))
  }

  private var messageAndActionBody: some View {
    Group {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if !item.messagePayloads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              PortalPayloadGroupView(
                kindName: "PresentationMessage",
                payloads: item.messagePayloads
              )
            }
            .padding(.init(horizontal: 1, vertical: 1))
          }
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(item.descriptor.scrollMinHeight),
        idealHeight: .finite(item.descriptor.scrollIdealHeight),
        maxHeight: .finite(item.descriptor.scrollMaxHeight),
        alignment: .topLeading
      )
      presentationActions
    }
  }

  private var contentBody: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        PortalPayloadGroupView(
          kindName: "PresentationContent",
          payloads: item.contentPayloads
        )
      }
      .padding(.init(horizontal: 1, vertical: 1))
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(item.descriptor.scrollMinHeight),
      idealHeight: .finite(item.descriptor.scrollIdealHeight),
      maxHeight: .finite(item.descriptor.scrollMaxHeight),
      alignment: .topLeading
    )
  }

  /// Menu rendering body — intrinsic-sized VStack of items with no
  /// scrolling chrome. The menu sizes to its longest item; the
  /// `scrollMaxHeight` from the descriptor is ignored intentionally so
  /// short menus don't reserve extra empty rows below their last item.
  ///
  /// Iterates payloads via `ForEach` + per-item `PortalPayloadView`
  /// rather than `PortalPayloadGroupView`. The group view returns a
  /// single intrinsic-layout node when there are multiple payloads,
  /// which would let menu items overlap in one row. Iterating gives
  /// the VStack its own children to lay out vertically.
  private var menuContentBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(item.contentPayloads.indices, id: \.self) { index in
        PortalPayloadView(payload: item.contentPayloads[index])
      }
    }
  }

  private var presentationActions: some View {
    HStack(spacing: 1) {
      ForEach(item.actionPayloads.indices, id: \.self) { index in
        PortalPayloadView(payload: item.actionPayloads[index])
          .fixedSize()
      }
    }
    .fixedSize()
    .padding(.init(horizontal: 1, vertical: 0))
  }

}

// MARK: - Toast / Transient Notification System

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

  package func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation {
    box.presentation(for: configuration)
  }
}

public protocol ToastStyle: Sendable {
  var snapshotLabel: String { get }

  func resolvePresentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
}

extension ToastStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

public struct ToastStyleConfiguration: Sendable {
  public init() {}
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

private protocol AnyToastStyleBox: Sendable {
  func presentation(
    for configuration: ToastStyleConfiguration
  ) -> ToastStylePresentation
}

private struct ConcreteAnyToastStyleBox<S: ToastStyle>: AnyToastStyleBox {
  let style: S

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
  /// Displays a transient notification bar that auto-dismisses.
  public func toast<S: StringProtocol>(
    _ message: S,
    isPresented: Binding<Bool>,
    style: AnyToastStyle = .info,
    duration: Double? = 3.0
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: Text(String(message))
      )
    )
  }

  /// Displays a transient notification bar that auto-dismisses.
  public func toast<S: StringProtocol, Style: ToastStyle>(
    _ message: S,
    isPresented: Binding<Bool>,
    style: Style,
    duration: Double? = 3.0
  ) -> some View {
    toast(
      message,
      isPresented: isPresented,
      style: AnyToastStyle(style),
      duration: duration
    )
  }

  /// Displays a transient notification with custom content that auto-dismisses.
  public func toast<ToastContent: View>(
    isPresented: Binding<Bool>,
    style: AnyToastStyle = .info,
    duration: Double? = 3.0,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: toastContent()
      )
    )
  }

  /// Displays a transient notification with custom content that auto-dismisses.
  public func toast<ToastContent: View, Style: ToastStyle>(
    isPresented: Binding<Bool>,
    style: Style,
    duration: Double? = 3.0,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    toast(
      isPresented: isPresented,
      style: AnyToastStyle(style),
      duration: duration,
      content: toastContent
    )
  }
}

public struct ToastModifier<ToastContent: View>: PrimitiveViewModifier {
  var isPresented: Binding<Bool>
  var style: AnyToastStyle
  var duration: Double?
  var toastContent: ToastContent
  var dismissAuthoringContext: AuthoringContext? = makeDeferredAuthoringContext()

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let item = ToastPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: "toast"
      ),
      contentPayloads: portalDeclaredBuilderChildren(from: toastContent),
      presentation: style.presentation(for: ToastStyleConfiguration()),
      duration: duration,
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            registry.toast.sync(
              sourceIdentity: sourceIdentity,
              items: [item]
            )
          }
        ]
      )
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
        ForEach(items) { item in
          ToastPresentationView(item: item)
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

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      if let icon = item.presentation.icon {
        Text(icon)
          .foregroundStyle(item.presentation.iconStyle)
      }
      VStack {
        PortalPayloadGroupView(
          kindName: "ToastContent",
          payloads: item.contentPayloads
        )
      }
    }
    .padding(item.presentation.contentPadding)
    .background {
      Rectangle().fill(item.presentation.backgroundStyle)
    }
    .overlay {
      Rectangle().strokeBorder(
        item.presentation.borderStyle
      )
    }
    .frame(
      minWidth: .finite(item.presentation.minWidth),
      maxWidth: .finite(item.presentation.maxWidth),
      minHeight: .finite(item.presentation.minHeight),
      idealHeight: .finite(item.presentation.idealHeight),
      maxHeight: .finite(item.presentation.maxHeight),
      alignment: .leading
    )
    .task {
      guard let duration = item.duration, duration > 0 else {
        return
      }
      try? await Task.sleep(for: .seconds(duration))
      guard !Task.isCancelled else {
        return
      }
      item.dismiss()
    }
  }
}
