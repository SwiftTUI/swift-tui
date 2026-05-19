package import SwiftTUICore

// MARK: - View Update Guard

@MainActor
package enum ViewUpdateGuard {
  private static var depth = 0

  package static var isUpdating: Bool {
    depth > 0
  }

  package static func withViewUpdate<Result>(
    _ apply: () -> Result
  ) -> Result {
    depth += 1
    defer {
      depth -= 1
    }
    return apply()
  }
}

@MainActor
package enum PresentationMutationGuard {
  package static var onInvalidMutation: (@MainActor (String) -> Void)?

  package static func allowMutation(
    _ message: String
  ) -> Bool {
    guard !ViewUpdateGuard.isUpdating else {
      if let onInvalidMutation {
        onInvalidMutation(message)
        return false
      }
      assertionFailure(message)
      return false
    }
    return true
  }
}

// MARK: - Public Coordinator Interface

package struct PresentationCoordinatorHandle<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  package let snapshotLabel: String
  package let isAvailable: Bool
  private let presentHandler: @MainActor @Sendable (Item) -> Void
  private let dismissHandler: @MainActor @Sendable (Item.ID) -> Void

  package init(
    snapshotLabel: String,
    isAvailable: Bool = true,
    present: @escaping @MainActor @Sendable (Item) -> Void,
    dismiss: @escaping @MainActor @Sendable (Item.ID) -> Void
  ) {
    self.snapshotLabel = snapshotLabel
    self.isAvailable = isAvailable
    presentHandler = present
    dismissHandler = dismiss
  }

  @MainActor
  package func present(
    _ item: Item
  ) {
    presentHandler(item)
  }

  @MainActor
  package func dismiss(
    id: Item.ID
  ) {
    dismissHandler(id)
  }

  package static func unavailable(
    _ snapshotLabel: String
  ) -> Self {
    Self(
      snapshotLabel: snapshotLabel,
      isAvailable: false,
      present: { _ in },
      dismiss: { _ in }
    )
  }
}

@MainActor
package protocol PresentationCoordinator: AnyObject {
  associatedtype Item: Identifiable & Sendable where Item.ID: Sendable
  associatedtype Body: View

  static var zIndex: Int { get }

  init()

  @ViewBuilder
  func makeBody() -> Body

  func present(_ item: Item)
  func dismiss(id: Item.ID)
}

@MainActor
package protocol ManagedPresentationCoordinator: PresentationCoordinator {
  static var modalPolicy: PortalModalPolicy { get }
  static var overlayKindName: String { get }

  var isActive: Bool { get }
  var latestItem: Item? { get }
  var latestActivationOrdinal: Int? { get }
  func dismissAction(for item: Item) -> (@MainActor @Sendable () -> Void)?

  func beginSynchronizing()
  func sync(sourceIdentity: Identity, items: [Item])
  func endSynchronizing()
  func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  )
  func makeCheckpoint() -> StoredPresentationCoordinatorCheckpoint<Item>
  func restoreCheckpoint(_ checkpoint: StoredPresentationCoordinatorCheckpoint<Item>)
}

extension ManagedPresentationCoordinator {
  package func modalPolicy(
    for _: Item
  ) -> PortalModalPolicy {
    Self.modalPolicy
  }
}

// MARK: - Environment Handles

private enum AlertPresentationCoordinatorHandleKey: EnvironmentKey {
  static let defaultValue = PresentationCoordinatorHandle<PromptPresentationItem>.unavailable(
    "AlertPresentationCoordinatorHandle"
  )
}

private enum ConfirmationDialogPresentationCoordinatorHandleKey: EnvironmentKey {
  static let defaultValue = PresentationCoordinatorHandle<PromptPresentationItem>.unavailable(
    "ConfirmationDialogPresentationCoordinatorHandle"
  )
}

private enum SheetPresentationCoordinatorHandleKey: EnvironmentKey {
  static let defaultValue = PresentationCoordinatorHandle<PromptPresentationItem>.unavailable(
    "SheetPresentationCoordinatorHandle"
  )
}

private enum ToastPresentationCoordinatorHandleKey: EnvironmentKey {
  static let defaultValue = PresentationCoordinatorHandle<ToastPresentationItem>.unavailable(
    "ToastPresentationCoordinatorHandle"
  )
}

extension EnvironmentValues {
  package var alertPresentationCoordinator: PresentationCoordinatorHandle<PromptPresentationItem> {
    get { self[AlertPresentationCoordinatorHandleKey.self] }
    set { self[AlertPresentationCoordinatorHandleKey.self] = newValue }
  }

  package var confirmationDialogPresentationCoordinator:
    PresentationCoordinatorHandle<PromptPresentationItem>
  {
    get { self[ConfirmationDialogPresentationCoordinatorHandleKey.self] }
    set { self[ConfirmationDialogPresentationCoordinatorHandleKey.self] = newValue }
  }

  package var sheetPresentationCoordinator: PresentationCoordinatorHandle<PromptPresentationItem> {
    get { self[SheetPresentationCoordinatorHandleKey.self] }
    set { self[SheetPresentationCoordinatorHandleKey.self] = newValue }
  }

  package var toastPresentationCoordinator: PresentationCoordinatorHandle<ToastPresentationItem> {
    get { self[ToastPresentationCoordinatorHandleKey.self] }
    set { self[ToastPresentationCoordinatorHandleKey.self] = newValue }
  }

}

// MARK: - Declarative Reconciliation Preferences

@MainActor
package struct PresentationCoordinatorDeclaration: Sendable {
  package var sourceIdentity: Identity
  package var apply: @MainActor @Sendable (PresentationCoordinatorRegistry) -> Void

  package init(
    sourceIdentity: Identity,
    apply: @escaping @MainActor @Sendable (PresentationCoordinatorRegistry) -> Void
  ) {
    self.sourceIdentity = sourceIdentity
    self.apply = apply
  }
}

package struct PresentationCoordinatorDeclarationPreferenceValue: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  package var declarations: [PresentationCoordinatorDeclaration] = []

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    let sourcePaths = declarations.map(\.sourceIdentity.path)
    return "PresentationCoordinatorDeclarationPreferenceValue(\(sourcePaths))"
  }
}

package enum PresentationCoordinatorDeclarationPreferenceKey: PreferenceKey {
  package static let defaultValue = PresentationCoordinatorDeclarationPreferenceValue()

  package static func reduce(
    value: inout PresentationCoordinatorDeclarationPreferenceValue,
    nextValue: () -> PresentationCoordinatorDeclarationPreferenceValue
  ) {
    value.declarations.append(contentsOf: nextValue().declarations)
  }
}

// MARK: - Hosting Root

package func presentationPortalIdentity(
  for contentRootIdentity: Identity
) -> Identity {
  Identity(
    components: [
      "__TerminalUIPortalHost",
      contentRootIdentity.path.isEmpty ? "$root" : contentRootIdentity.path,
    ])
}

package struct PresentationPortalRoot<Content: View>: PrimitiveView, ResolvableView {
  package var content: Content
  package var portalState: PresentationPortalDraft
  package var contentRootIdentity: Identity

  package init(
    content: Content,
    portalState: PresentationPortalDraft,
    contentRootIdentity: Identity
  ) {
    self.content = content
    self.portalState = portalState
    self.contentRootIdentity = contentRootIdentity
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let hostIdentity = context.identity
    var contentContext = context.replacingIdentity(with: contentRootIdentity)
    portalState.injectHandles(
      into: &contentContext.environmentValues,
      hostIdentity: hostIdentity,
      invalidator: context.invalidationProxy?.invalidator
    )

    let baseNode = resolveView(content, in: contentContext)
    return [
      composePresentationPortalTree(
        baseNode: baseNode,
        portalState: portalState,
        in: context
      )
    ]
  }
}

@MainActor
private func reconcilePresentationDeclarations(
  from baseNode: ResolvedNode,
  into portalState: PresentationPortalDraft
) {
  let declarations = baseNode.preferenceValues[
    PresentationCoordinatorDeclarationPreferenceKey.self]
  portalState.reconcile(declarations.declarations)
}

@MainActor
package func composePresentationPortalTree(
  baseNode: ResolvedNode,
  portalState: PresentationPortalDraft,
  in context: ResolveContext
) -> ResolvedNode {
  // The portal root is a graph-owned wrapper. Reconcile from the
  // current base snapshot before choosing the wrapper children so stale
  // declarations are removed through ordinary structural child diffing.
  reconcilePresentationDeclarations(
    from: baseNode,
    into: portalState
  )
  let overlayEntries = portalState.overlayEntries()

  guard !overlayEntries.isEmpty else {
    return ResolvedNode(
      identity: context.identity,
      kind: .view("PresentationPortalRoot"),
      children: [baseNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }

  return composeOverlayStackTree(
    baseNode: baseNode,
    entries: overlayEntries,
    in: context
  )
}
