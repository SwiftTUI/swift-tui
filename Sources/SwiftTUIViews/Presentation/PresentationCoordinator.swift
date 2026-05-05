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

// MARK: - Shared Item Storage

package struct TrackedPresentationItem<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  var item: Item
  var activationOrdinal: Int
}

@MainActor
package final class PresentationFamilyItemStore<Item: Identifiable & Sendable>
where Item.ID: Sendable {
  package struct Checkpoint: Sendable {
    fileprivate var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]]
    fileprivate var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>]
    fileprivate var seenSources: Set<Identity>
    fileprivate var nextActivationOrdinal: Int
  }

  private var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]] = [:]
  private var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>] = [:]
  private var seenSources: Set<Identity> = []
  private var nextActivationOrdinal = 0

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      declarativeItemsBySource: declarativeItemsBySource,
      imperativeItemsByID: imperativeItemsByID,
      seenSources: seenSources,
      nextActivationOrdinal: nextActivationOrdinal
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    declarativeItemsBySource = checkpoint.declarativeItemsBySource
    imperativeItemsByID = checkpoint.imperativeItemsByID
    seenSources = checkpoint.seenSources
    nextActivationOrdinal = checkpoint.nextActivationOrdinal
  }

  package func beginSynchronizing() {
    seenSources.removeAll(keepingCapacity: true)
  }

  package func sync(
    sourceIdentity: Identity,
    items: [Item]
  ) {
    seenSources.insert(sourceIdentity)

    guard !items.isEmpty else {
      declarativeItemsBySource[sourceIdentity] = [:]
      return
    }

    let previousItems = declarativeItemsBySource[sourceIdentity] ?? [:]
    var nextItems: [Item.ID: TrackedPresentationItem<Item>] = [:]
    for item in items {
      let activationOrdinal =
        previousItems[item.id]?.activationOrdinal
        ?? activeEntry(for: item.id)?.activationOrdinal
        ?? allocateActivationOrdinal()
      nextItems[item.id] = .init(
        item: item,
        activationOrdinal: activationOrdinal
      )
    }
    declarativeItemsBySource[sourceIdentity] = nextItems
  }

  package func endSynchronizing() {
    let staleSources = declarativeItemsBySource.keys.filter { !seenSources.contains($0) }
    for sourceIdentity in staleSources {
      declarativeItemsBySource.removeValue(forKey: sourceIdentity)
    }

    let emptySources = declarativeItemsBySource.compactMap { sourceIdentity, items in
      items.isEmpty ? sourceIdentity : nil
    }
    for sourceIdentity in emptySources {
      declarativeItemsBySource.removeValue(forKey: sourceIdentity)
    }
  }

  package func presentImperatively(
    _ item: Item
  ) {
    let activationOrdinal =
      activeEntry(for: item.id)?.activationOrdinal
      ?? allocateActivationOrdinal()
    imperativeItemsByID[item.id] = .init(
      item: item,
      activationOrdinal: activationOrdinal
    )
  }

  package func dismissImperatively(
    id: Item.ID
  ) {
    imperativeItemsByID.removeValue(forKey: id)
  }

  package var isActive: Bool {
    !mergedActiveItems().isEmpty
  }

  package var latestItem: Item? {
    newestFirst.first
  }

  package var latestActivationOrdinal: Int? {
    mergedActiveItems()
      .values
      .max { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal < rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }?
      .activationOrdinal
  }

  package var newestFirst: [Item] {
    mergedActiveItems()
      .values
      .sorted { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal > rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }
      .map(\.item)
  }

  package var oldestFirst: [Item] {
    mergedActiveItems()
      .values
      .sorted { lhs, rhs in
        if lhs.activationOrdinal != rhs.activationOrdinal {
          return lhs.activationOrdinal < rhs.activationOrdinal
        }
        return String(reflecting: lhs.item.id) < String(reflecting: rhs.item.id)
      }
      .map(\.item)
  }

  private func mergedActiveItems() -> [Item.ID: TrackedPresentationItem<Item>] {
    var merged: [Item.ID: TrackedPresentationItem<Item>] = [:]

    for items in declarativeItemsBySource.values {
      for (itemID, trackedItem) in items {
        if let existing = merged[itemID],
          existing.activationOrdinal > trackedItem.activationOrdinal
        {
          continue
        }
        merged[itemID] = trackedItem
      }
    }

    for (itemID, trackedItem) in imperativeItemsByID {
      if let existing = merged[itemID],
        existing.activationOrdinal > trackedItem.activationOrdinal
      {
        continue
      }
      merged[itemID] = trackedItem
    }

    return merged
  }

  private func activeEntry(
    for itemID: Item.ID
  ) -> TrackedPresentationItem<Item>? {
    if let imperativeItem = imperativeItemsByID[itemID] {
      return imperativeItem
    }

    for items in declarativeItemsBySource.values {
      if let declarativeItem = items[itemID] {
        return declarativeItem
      }
    }

    return nil
  }

  private func allocateActivationOrdinal() -> Int {
    nextActivationOrdinal += 1
    return nextActivationOrdinal
  }
}

@MainActor
package struct StoredPresentationCoordinatorCheckpoint<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  fileprivate var itemStore: PresentationFamilyItemStore<Item>.Checkpoint
  fileprivate var invalidationIdentity: Identity?
}

@MainActor
package class StoredPresentationCoordinator<Item: Identifiable & Sendable>
where Item.ID: Sendable {
  package let itemStore = PresentationFamilyItemStore<Item>()

  private weak var imperativeInvalidator: (any Invalidating)?
  private var invalidationIdentity: Identity?

  package init() {}

  package func makeCheckpoint() -> StoredPresentationCoordinatorCheckpoint<Item> {
    StoredPresentationCoordinatorCheckpoint(
      itemStore: itemStore.makeCheckpoint(),
      invalidationIdentity: invalidationIdentity
    )
  }

  package func restoreCheckpoint(
    _ checkpoint: StoredPresentationCoordinatorCheckpoint<Item>
  ) {
    itemStore.restoreCheckpoint(checkpoint.itemStore)
    invalidationIdentity = checkpoint.invalidationIdentity
  }

  package func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) {
    invalidationIdentity = identity
    imperativeInvalidator = invalidator
  }

  package func beginSynchronizing() {
    itemStore.beginSynchronizing()
  }

  package func sync(
    sourceIdentity: Identity,
    items: [Item]
  ) {
    itemStore.sync(
      sourceIdentity: sourceIdentity,
      items: items
    )
  }

  package func endSynchronizing() {
    itemStore.endSynchronizing()
  }

  package var isActive: Bool {
    itemStore.isActive
  }

  package var latestItem: Item? {
    itemStore.latestItem
  }

  package var latestActivationOrdinal: Int? {
    itemStore.latestActivationOrdinal
  }

  package var itemsNewestFirst: [Item] {
    itemStore.newestFirst
  }

  package var itemsOldestFirst: [Item] {
    itemStore.oldestFirst
  }

  package func present(
    _ item: Item,
    message: String
  ) {
    guard PresentationMutationGuard.allowMutation(message) else {
      return
    }
    itemStore.presentImperatively(item)
    requestInvalidation()
  }

  package func dismiss(
    id: Item.ID,
    message: String
  ) {
    guard PresentationMutationGuard.allowMutation(message) else {
      return
    }
    itemStore.dismissImperatively(id: id)
    requestInvalidation()
  }

  private func requestInvalidation() {
    guard let invalidationIdentity else {
      return
    }
    imperativeInvalidator?.requestInvalidation(of: [invalidationIdentity])
  }
}

// MARK: - Built-In Item Models

/// Visual chrome treatment applied to a prompt presentation's surface.
///
/// Sheets, alerts, and confirmation dialogs share one rendering path;
/// this enum selects how the chrome around the content is drawn.
public enum PresentationChrome: Equatable, Sendable {
  /// Default: rounded inset surface with a foreground-tint stroke on
  /// every side. Used by alerts, confirmation dialogs, and standard
  /// sheets.
  case surface

  /// Flat, edge-to-edge strip with no side or top border and a single
  /// soft divider along the bottom that reads like a shadow under the
  /// content. Used for command-palette dropdowns and similar banners
  /// that should read as part of the window chrome rather than a
  /// floating card.
  case dropdown

  /// Compact, intrinsic-width bordered box with no header — the
  /// rendering used by `Menu` to float its expanded content above the
  /// surrounding layout without reflowing siblings. Smaller and
  /// chromier than `.surface` (no title row, no close button), this
  /// chrome anchors at the presentation's `alignment` and sizes to its
  /// content rather than expanding to fill.
  case menu
}

/// Controls how a prompt presentation surface accepts the full-screen
/// portal overlay proposal.
package enum PromptPresentationContentSizing: Equatable, Sendable {
  /// Let the surface consume the host proposal. This preserves the
  /// existing sheet/dropdown behavior where content can expand to the
  /// available presentation area.
  case fillAvailable

  /// Measure the surface at its intrinsic size before placing it in the
  /// full-screen portal overlay. Used by compact floating presentations
  /// such as menus, where internal spacers must not stretch rows to the
  /// terminal width.
  case intrinsic
}

package struct PromptPresentationDescriptor: Equatable, Sendable {
  package enum BodyMode: Equatable, Sendable {
    case contentOnly
    case messageAndActions
  }

  package var alignment: Alignment
  package var accessibilityRole: AccessibilityRole
  package var backdropOpacity: Double
  package var defaultDismissTitle: String
  package var headerTone: TerminalTone
  package var minWidth: Int
  package var maxWidth: Int?
  package var scrollMinHeight: Int
  package var scrollIdealHeight: Int
  package var scrollMaxHeight: Int
  package var bodyMode: BodyMode
  package var chrome: PresentationChrome
  package var contentSizing: PromptPresentationContentSizing

  package init(
    alignment: Alignment,
    accessibilityRole: AccessibilityRole,
    backdropOpacity: Double,
    defaultDismissTitle: String,
    headerTone: TerminalTone,
    minWidth: Int,
    maxWidth: Int? = nil,
    scrollMinHeight: Int,
    scrollIdealHeight: Int,
    scrollMaxHeight: Int,
    bodyMode: BodyMode,
    chrome: PresentationChrome = .surface,
    contentSizing: PromptPresentationContentSizing = .fillAvailable
  ) {
    self.alignment = alignment
    self.accessibilityRole = accessibilityRole
    self.backdropOpacity = backdropOpacity
    self.defaultDismissTitle = defaultDismissTitle
    self.headerTone = headerTone
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.scrollMinHeight = scrollMinHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaxHeight = scrollMaxHeight
    self.bodyMode = bodyMode
    self.chrome = chrome
    self.contentSizing = contentSizing
  }
}

package struct PromptPresentationItem: Identifiable, Sendable {
  package var id: String
  package var title: String
  package var descriptor: PromptPresentationDescriptor
  package var actionPayloads: [PortalContentPayload]
  package var messagePayloads: [PortalContentPayload]
  package var contentPayloads: [PortalContentPayload]
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    id: String,
    title: String,
    descriptor: PromptPresentationDescriptor,
    actionPayloads: [PortalContentPayload],
    messagePayloads: [PortalContentPayload],
    contentPayloads: [PortalContentPayload],
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.title = title
    self.descriptor = descriptor
    self.actionPayloads = actionPayloads
    self.messagePayloads = messagePayloads
    self.contentPayloads = contentPayloads
    self.dismiss = dismiss
  }
}

package struct ToastPresentationItem: Identifiable, Sendable {
  package var id: String
  package var contentPayloads: [PortalContentPayload]
  package var presentation: ToastStylePresentation
  package var duration: Double?
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    id: String,
    contentPayloads: [PortalContentPayload],
    presentation: ToastStylePresentation,
    duration: Double?,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.contentPayloads = contentPayloads
    self.presentation = presentation
    self.duration = duration
    self.dismiss = dismiss
  }
}

package func presentationAttachmentID(
  for sourceIdentity: Identity,
  token: String
) -> String {
  "\(sourceIdentity.path)#\(token)"
}

// MARK: - Built-In Coordinators

@MainActor
package final class AlertPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 260
  package static let modalPolicy = PortalModalPolicy.disablesBaseInteraction
  package static let overlayKindName = "AlertPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if let latestItem {
      HostedPromptPresentation(item: latestItem)
    }
  }

  package func present(
    _ item: PromptPresentationItem
  ) {
    super.present(
      item,
      message: "AlertPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message: "AlertPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for item: PromptPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    item.dismiss
  }
}

@MainActor
package final class ConfirmationDialogPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 240
  package static let modalPolicy = PortalModalPolicy.disablesBaseInteraction
  package static let overlayKindName = "ConfirmationDialogPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if let latestItem {
      HostedPromptPresentation(item: latestItem)
    }
  }

  package func present(
    _ item: PromptPresentationItem
  ) {
    super.present(
      item,
      message:
        "ConfirmationDialogPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message:
        "ConfirmationDialogPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for item: PromptPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    item.dismiss
  }
}

@MainActor
package final class SheetPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 200
  package static let modalPolicy = PortalModalPolicy.disablesBaseInteraction
  package static let overlayKindName = "SheetPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if let latestItem {
      HostedPromptPresentation(item: latestItem)
    }
  }

  package func present(
    _ item: PromptPresentationItem
  ) {
    super.present(
      item,
      message: "SheetPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message: "SheetPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for item: PromptPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    item.dismiss
  }
}

@MainActor
package final class MenuPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 180
  package static let modalPolicy = PortalModalPolicy.nonModal
  package static let overlayKindName = "MenuPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if let latestItem {
      HostedPromptPresentation(item: latestItem)
    }
  }

  package func present(
    _ item: PromptPresentationItem
  ) {
    super.present(
      item,
      message: "MenuPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message: "MenuPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for item: PromptPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    item.dismiss
  }
}

@MainActor
package final class ToastPresentationCoordinator:
  StoredPresentationCoordinator<ToastPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 100
  package static let modalPolicy = PortalModalPolicy.nonModal
  package static let overlayKindName = "ToastPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if isActive {
      ToastCoordinatorBodyView(items: itemsOldestFirst)
    }
  }

  package func present(
    _ item: ToastPresentationItem
  ) {
    super.present(
      item,
      message: "ToastPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message: "ToastPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for _: ToastPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    nil
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

// MARK: - Coordinator Registry

@MainActor
package final class PresentationCoordinatorBox<C: ManagedPresentationCoordinator>
where C.Item.ID: Sendable {
  package struct Checkpoint: Sendable {
    fileprivate var coordinator: StoredPresentationCoordinatorCheckpoint<C.Item>?
  }

  private var coordinator: C?
  private weak var configuredInvalidator: (any Invalidating)?
  private var configuredInvalidationIdentity: Identity?

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      coordinator: coordinator?.makeCheckpoint()
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    guard let coordinatorCheckpoint = checkpoint.coordinator else {
      coordinator = nil
      return
    }

    instance().restoreCheckpoint(coordinatorCheckpoint)
  }

  package var zIndex: Int {
    C.zIndex
  }

  package var isActive: Bool {
    coordinator?.isActive ?? false
  }

  package var latestItem: C.Item? {
    coordinator?.latestItem
  }

  package func beginSynchronizing() {
    coordinator?.beginSynchronizing()
  }

  package func sync(
    sourceIdentity: Identity,
    items: [C.Item]
  ) {
    let coordinator = instance()
    coordinator.sync(
      sourceIdentity: sourceIdentity,
      items: items
    )
  }

  package func endSynchronizing() {
    coordinator?.endSynchronizing()
  }

  package func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  ) {
    configuredInvalidationIdentity = identity
    configuredInvalidator = invalidator
    coordinator?.setImperativeInvalidationTarget(
      identity: identity,
      invalidator: invalidator
    )
  }

  package func handle(
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) -> PresentationCoordinatorHandle<C.Item> {
    setImperativeInvalidationTarget(
      identity: hostIdentity,
      invalidator: invalidator
    )
    return PresentationCoordinatorHandle(
      snapshotLabel: C.overlayKindName,
      present: { [weak self] item in
        self?.instance().present(item)
      },
      dismiss: { [weak self] itemID in
        self?.instance().dismiss(id: itemID)
      }
    )
  }

  package func overlayEntry() -> OverlayStackEntry? {
    guard let coordinator, coordinator.isActive, let item = coordinator.latestItem else {
      return nil
    }

    let stableID = "\(C.overlayKindName):\(String(reflecting: item.id))"
    return OverlayStackEntry(
      id: stableID,
      ordering: PortalOrdering(
        zIndex: C.zIndex,
        activationOrdinal: coordinator.latestActivationOrdinal ?? 0,
        stableTieBreaker: stableID
      ),
      kindName: C.overlayKindName,
      modalPolicy: C.modalPolicy,
      acceptsEscape: coordinator.dismissAction(for: item) != nil,
      dismiss: coordinator.dismissAction(for: item),
      payload: PortalContentPayload {
        coordinator.makeBody()
      }
    )
  }

  private func instance() -> C {
    if let coordinator {
      return coordinator
    }

    let coordinator = C()
    if let configuredInvalidationIdentity {
      coordinator.setImperativeInvalidationTarget(
        identity: configuredInvalidationIdentity,
        invalidator: configuredInvalidator
      )
    }
    self.coordinator = coordinator
    return coordinator
  }
}

@MainActor
private struct AnyPresentationCoordinatorBox {
  private let beginSynchronizingImpl: @MainActor () -> Void
  private let endSynchronizingImpl: @MainActor () -> Void
  private let overlayEntryImpl: @MainActor () -> OverlayStackEntry?

  init<C>(
    _ box: PresentationCoordinatorBox<C>
  ) where C: ManagedPresentationCoordinator, C.Item.ID: Sendable {
    beginSynchronizingImpl = {
      box.beginSynchronizing()
    }
    endSynchronizingImpl = {
      box.endSynchronizing()
    }
    overlayEntryImpl = {
      box.overlayEntry()
    }
  }

  @MainActor
  func beginSynchronizing() {
    beginSynchronizingImpl()
  }

  @MainActor
  func endSynchronizing() {
    endSynchronizingImpl()
  }

  @MainActor
  func overlayEntry() -> OverlayStackEntry? {
    overlayEntryImpl()
  }
}

@MainActor
package final class PresentationCoordinatorRegistry {
  package struct Checkpoint: Sendable {
    fileprivate var alert: PresentationCoordinatorBox<AlertPresentationCoordinator>.Checkpoint
    fileprivate var confirmationDialog:
      PresentationCoordinatorBox<ConfirmationDialogPresentationCoordinator>.Checkpoint
    fileprivate var sheet: PresentationCoordinatorBox<SheetPresentationCoordinator>.Checkpoint
    fileprivate var menu: PresentationCoordinatorBox<MenuPresentationCoordinator>.Checkpoint
    fileprivate var toast: PresentationCoordinatorBox<ToastPresentationCoordinator>.Checkpoint
  }

  package let alert = PresentationCoordinatorBox<AlertPresentationCoordinator>()
  package let confirmationDialog = PresentationCoordinatorBox<
    ConfirmationDialogPresentationCoordinator
  >()
  package let sheet = PresentationCoordinatorBox<SheetPresentationCoordinator>()
  package let menu = PresentationCoordinatorBox<MenuPresentationCoordinator>()
  package let toast = PresentationCoordinatorBox<ToastPresentationCoordinator>()
  private lazy var allBoxes = [
    AnyPresentationCoordinatorBox(alert),
    AnyPresentationCoordinatorBox(confirmationDialog),
    AnyPresentationCoordinatorBox(sheet),
    AnyPresentationCoordinatorBox(menu),
    AnyPresentationCoordinatorBox(toast),
  ]

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      alert: alert.makeCheckpoint(),
      confirmationDialog: confirmationDialog.makeCheckpoint(),
      sheet: sheet.makeCheckpoint(),
      menu: menu.makeCheckpoint(),
      toast: toast.makeCheckpoint()
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    alert.restoreCheckpoint(checkpoint.alert)
    confirmationDialog.restoreCheckpoint(checkpoint.confirmationDialog)
    sheet.restoreCheckpoint(checkpoint.sheet)
    menu.restoreCheckpoint(checkpoint.menu)
    toast.restoreCheckpoint(checkpoint.toast)
  }

  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    environmentValues.alertPresentationCoordinator = alert.handle(
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
    environmentValues.confirmationDialogPresentationCoordinator =
      confirmationDialog.handle(
        hostIdentity: hostIdentity,
        invalidator: invalidator
      )
    environmentValues.sheetPresentationCoordinator = sheet.handle(
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
    environmentValues.toastPresentationCoordinator = toast.handle(
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
  }

  package func reconcile(
    _ declarations: [PresentationCoordinatorDeclaration]
  ) {
    for box in allBoxes {
      box.beginSynchronizing()
    }

    for declaration in declarations {
      declaration.apply(self)
    }

    for box in allBoxes {
      box.endSynchronizing()
    }
  }

  package func overlayEntries() -> [OverlayStackEntry] {
    allBoxes
      .compactMap {
        $0.overlayEntry()
      }
      .sorted { lhs, rhs in
        portalOrderingPrecedes(lhs.ordering, rhs.ordering)
      }
  }

  package func dismissStack() -> DismissStack {
    DismissStack(
      entries: overlayEntries().compactMap { entry in
        guard let dismiss = entry.dismiss else {
          return nil
        }
        return DismissStackEntry(
          id: entry.id,
          ordering: entry.ordering,
          acceptsEscape: entry.acceptsEscape,
          dismiss: dismiss
        )
      }
    )
  }
}

@MainActor
package final class PresentationPortalState {
  package struct Checkpoint: Sendable {
    fileprivate var registry: PresentationCoordinatorRegistry.Checkpoint
  }

  private let registry = PresentationCoordinatorRegistry()

  package init() {}

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(registry: registry.makeCheckpoint())
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    registry.restoreCheckpoint(checkpoint.registry)
  }

  package func injectHandles(
    into environmentValues: inout EnvironmentValues,
    hostIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    registry.injectHandles(
      into: &environmentValues,
      hostIdentity: hostIdentity,
      invalidator: invalidator
    )
  }

  package func reconcile(
    _ declarations: [PresentationCoordinatorDeclaration]
  ) {
    registry.reconcile(declarations)
  }

  package func overlayEntries() -> [OverlayStackEntry] {
    registry.overlayEntries()
  }

  package func dismissStack() -> DismissStack {
    registry.dismissStack()
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

package struct PresentationPortalRoot<Content: View>: View, ResolvableView {
  package var content: Content
  package var portalState: PresentationPortalState
  package var contentRootIdentity: Identity

  package init(
    content: Content,
    portalState: PresentationPortalState,
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
  into portalState: PresentationPortalState
) {
  let declarations = baseNode.preferenceValues[
    PresentationCoordinatorDeclarationPreferenceKey.self]
  portalState.reconcile(declarations.declarations)
}

@MainActor
package func composePresentationPortalTree(
  baseNode: ResolvedNode,
  portalState: PresentationPortalState,
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
