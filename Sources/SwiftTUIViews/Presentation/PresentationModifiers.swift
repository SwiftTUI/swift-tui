public import SwiftTUICore

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
    let portalEntryID = presentationAttachment(for: node, token: spec.token)
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let item = PromptPresentationItem(
      id: portalEntryID.description,
      portalEntryID: portalEntryID,
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
    let portalEntryID = presentationAttachment(for: node, token: spec.token)
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let item = PromptPresentationItem(
      id: portalEntryID.description,
      portalEntryID: portalEntryID,
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
    let portalEntryID = presentationAttachment(for: node, token: spec.token)
    let item = PromptPresentationItem(
      id: portalEntryID.description,
      portalEntryID: portalEntryID,
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
