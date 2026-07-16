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
  private let activeItemHandler: (@MainActor @Sendable (Item.ID) -> Item?)?

  package init(
    snapshotLabel: String,
    isAvailable: Bool = true,
    present: @escaping @MainActor @Sendable (Item) -> Void,
    dismiss: @escaping @MainActor @Sendable (Item.ID) -> Void,
    activeItem: (@MainActor @Sendable (Item.ID) -> Item?)? = nil
  ) {
    self.snapshotLabel = snapshotLabel
    self.isAvailable = isAvailable
    presentHandler = present
    dismissHandler = dismiss
    activeItemHandler = activeItem
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

  /// The live registry's currently-active item for `id`, if the handle is
  /// bound to a portal state. Deadline tasks consult this at fire time so a
  /// re-synced item dismisses through its current closure — the handle
  /// outlives per-frame draft registries, which are replaced wholesale at
  /// every commit.
  @MainActor
  package func activeItem(
    id: Item.ID
  ) -> Item? {
    activeItemHandler?(id)
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

extension PresentationCoordinatorHandle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    // Handles are injected by one live portal state and route through that
    // state at call time; within a graph, family label + availability is the
    // stable semantic carrier. Unlike public custom environment actions there
    // is no user-authored closure surface here.
    return snapshotLabel == other.snapshotLabel
      && isAvailable == other.isAvailable
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
  var declaredSourceIdentities: Set<Identity> { get }
  var latestItem: Item? { get }
  var latestActivationOrdinal: Int? { get }
  func activeItem(id: Item.ID) -> Item?
  func dismissAction(for item: Item) -> (@MainActor @Sendable () -> Void)?
  // Requirement (not just the extension default) so per-item policies like the
  // popover tip's read-only `.nonModal` dispatch dynamically through generic
  // coordinator boxes.
  func modalPolicy(for item: Item) -> PortalModalPolicy

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

/// Monotonic mint for declaration freshness. A presentation declaration is
/// value-carried (its payload is closures), so the portal cannot compare two
/// declarations' content — but it can tell a *re-built* declaration from a
/// committed one carried forward by a spared trigger leaf: every construction
/// mints a new generation.
@MainActor
package enum PresentationDeclarationGenerationMint {
  private static var nextGeneration: UInt64 = 0

  package static func next() -> UInt64 {
    nextGeneration &+= 1
    return nextGeneration
  }
}

@MainActor
package struct PresentationCoordinatorDeclaration: Sendable {
  package var sourceIdentity: Identity
  /// Construction-time mint — see ``PresentationDeclarationGenerationMint``.
  package var mintGeneration: UInt64
  /// The presenting declaration's inherited environment, captured when the
  /// declaration was built. Overlay entry composition resolves portal-hosted
  /// content under it (`ResolveContext.replacingEnvironmentValues`) so the
  /// presenter's authored environment reaches the presented content. `nil`
  /// for imperative presentations, which have no declaration context.
  package var sourceEnvironmentValues: EnvironmentValues?
  package var apply: @MainActor @Sendable (PresentationCoordinatorRegistry) -> Void

  package init(
    sourceIdentity: Identity,
    apply: @escaping @MainActor @Sendable (PresentationCoordinatorRegistry) -> Void
  ) {
    self.sourceIdentity = sourceIdentity
    mintGeneration = PresentationDeclarationGenerationMint.next()
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
package func composePresentationPortalTree(
  baseNode: ResolvedNode,
  portalState: PresentationPortalDraft,
  in context: ResolveContext
) -> ResolvedNode {
  // The portal root is a graph-owned wrapper. Reconcile from the
  // current base snapshot before choosing the wrapper children so stale
  // declarations are removed through ordinary structural child diffing.
  //
  // Declarations emitted inside detached overlay content (a tip declared in
  // sheet content) never bubble into `baseNode` — they surface on the
  // overlay subtree, which only exists *after* composing. Seed the first
  // reconcile with the committed overlay host's declarations so steady
  // frames keep overlay-declared sources without re-minting them (activation
  // ordinals decide escape recency; a drop-and-re-add would make the entry
  // newest every escalated frame), then iterate to a bounded fixpoint: a
  // compose whose overlay subtree carries different declarations than the
  // reconcile consumed re-reconciles and recomposes. Activation, dismissal,
  // and content-refresh frames converge on the second compose; steady
  // frames exit after the first.
  let baseDeclarations = baseNode.preferenceValues[
    PresentationCoordinatorDeclarationPreferenceKey.self
  ].declarations
  let overlaysIdentity =
    context
    .child(component: .named("PortalHost"))
    .child(component: .named("overlays"))
    .identity
  let seedOverlayDeclarations =
    context.viewGraph?.nodeForIdentity(overlaysIdentity)?.committed.preferenceValues[
      PresentationCoordinatorDeclarationPreferenceKey.self
    ].declarations ?? []

  var reconciledMints = declarationMints(baseDeclarations + seedOverlayDeclarations)
  var declarationsRefreshed = portalState.reconcile(baseDeclarations + seedOverlayDeclarations)
  var composed = composePortalRootTree(
    baseNode: baseNode,
    entries: portalState.overlayEntries(),
    in: context,
    forceEntryRefresh: declarationsRefreshed
  )

  for _ in 0..<3 {
    let composedDeclarations = composed.preferenceValues[
      PresentationCoordinatorDeclarationPreferenceKey.self
    ].declarations
    let composedMints = declarationMints(composedDeclarations)
    guard composedMints != reconciledMints else {
      break
    }
    reconciledMints = composedMints
    let refreshed = portalState.reconcile(composedDeclarations)
    declarationsRefreshed = declarationsRefreshed || refreshed
    composed = composePortalRootTree(
      baseNode: baseNode,
      entries: portalState.overlayEntries(),
      in: context,
      forceEntryRefresh: declarationsRefreshed
    )
  }

  return composed
}

/// The (source, mint-generation) fingerprint of a declaration list — the
/// fixpoint's convergence currency. Declarations are closure payloads, so
/// content cannot be compared; a rebuilt declaration mints a new generation.
private func declarationMints(
  _ declarations: [PresentationCoordinatorDeclaration]
) -> Set<DeclarationMint> {
  Set(
    declarations.map {
      DeclarationMint(sourceIdentity: $0.sourceIdentity, mintGeneration: $0.mintGeneration)
    }
  )
}

private struct DeclarationMint: Hashable {
  var sourceIdentity: Identity
  var mintGeneration: UInt64
}

@MainActor
private func composePortalRootTree(
  baseNode: ResolvedNode,
  entries: [OverlayStackEntry],
  in context: ResolveContext,
  forceEntryRefresh: Bool
) -> ResolvedNode {
  guard !entries.isEmpty else {
    return ResolvedNode(
      identity: context.identity,
      structuralPath: context.structuralPath,
      structuralEdgeRole: .detachedOverlayRoot,
      kind: .view("PresentationPortalRoot"),
      children: [baseNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      surfaceComposition: .init(
        role: .detachedOverlayRoot,
        stableKey: context.structuralPath.description,
        invalidationScope: .fullSurfaceDiff
      )
    )
  }

  return composeOverlayStackTree(
    baseNode: baseNode,
    entries: entries,
    in: context,
    forceEntryRefresh: forceEntryRefresh
  )
}
