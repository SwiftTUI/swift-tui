package import Core

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
  static var disablesBaseInteractionWhenActive: Bool { get }
  static var overlayKindName: String { get }

  var isActive: Bool { get }

  func beginSynchronizing()
  func sync(sourceIdentity: Identity, items: [Item])
  func endSynchronizing()
  func setImperativeInvalidationTarget(
    identity: Identity,
    invalidator: (any Invalidating)?
  )
}

// MARK: - Shared Item Storage

private struct TrackedPresentationItem<Item: Identifiable & Sendable>: Sendable
where Item.ID: Sendable {
  var item: Item
  var activationOrdinal: Int
}

@MainActor
package final class PresentationFamilyItemStore<Item: Identifiable & Sendable>
where Item.ID: Sendable {
  private var declarativeItemsBySource: [Identity: [Item.ID: TrackedPresentationItem<Item>]] = [:]
  private var imperativeItemsByID: [Item.ID: TrackedPresentationItem<Item>] = [:]
  private var seenSources: Set<Identity> = []
  private var nextActivationOrdinal = 0

  package init() {}

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
package class StoredPresentationCoordinator<Item: Identifiable & Sendable>
where Item.ID: Sendable {
  package let itemStore = PresentationFamilyItemStore<Item>()

  private weak var imperativeInvalidator: (any Invalidating)?
  private var invalidationIdentity: Identity?

  package init() {}

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

package struct PromptPresentationDescriptor: Equatable, Sendable {
  package enum BodyMode: Equatable, Sendable {
    case contentOnly
    case messageAndActions
  }

  package var alignment: Alignment
  package var presentationRole: PresentationRole
  package var backdropOpacity: Double
  package var defaultDismissTitle: String
  package var headerTone: TerminalTone
  package var minWidth: Int
  package var maxWidth: Int?
  package var scrollMinHeight: Int
  package var scrollIdealHeight: Int
  package var scrollMaxHeight: Int
  package var bodyMode: BodyMode

  package init(
    alignment: Alignment,
    presentationRole: PresentationRole,
    backdropOpacity: Double,
    defaultDismissTitle: String,
    headerTone: TerminalTone,
    minWidth: Int,
    maxWidth: Int? = nil,
    scrollMinHeight: Int,
    scrollIdealHeight: Int,
    scrollMaxHeight: Int,
    bodyMode: BodyMode
  ) {
    self.alignment = alignment
    self.presentationRole = presentationRole
    self.backdropOpacity = backdropOpacity
    self.defaultDismissTitle = defaultDismissTitle
    self.headerTone = headerTone
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.scrollMinHeight = scrollMinHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaxHeight = scrollMaxHeight
    self.bodyMode = bodyMode
  }
}

package struct PromptPresentationItem: Identifiable, Sendable {
  package var id: String
  package var title: String
  package var descriptor: PromptPresentationDescriptor
  package var actionPayloads: [DeferredViewPayload]
  package var messagePayloads: [DeferredViewPayload]
  package var contentPayloads: [DeferredViewPayload]
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    id: String,
    title: String,
    descriptor: PromptPresentationDescriptor,
    actionPayloads: [DeferredViewPayload],
    messagePayloads: [DeferredViewPayload],
    contentPayloads: [DeferredViewPayload],
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
  package var contentPayloads: [DeferredViewPayload]
  package var style: ToastStyle
  package var duration: Double?
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    id: String,
    contentPayloads: [DeferredViewPayload],
    style: ToastStyle,
    duration: Double?,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.contentPayloads = contentPayloads
    self.style = style
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
  package static let disablesBaseInteractionWhenActive = true
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
}

@MainActor
package final class ConfirmationDialogPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 240
  package static let disablesBaseInteractionWhenActive = true
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
}

@MainActor
package final class SheetPresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 200
  package static let disablesBaseInteractionWhenActive = true
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
}

@MainActor
package final class ToastPresentationCoordinator:
  StoredPresentationCoordinator<ToastPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 100
  package static let disablesBaseInteractionWhenActive = false
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
}

@MainActor
package final class CommandPalettePresentationCoordinator:
  StoredPresentationCoordinator<PromptPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 300
  package static let disablesBaseInteractionWhenActive = true
  package static let overlayKindName = "CommandPalettePresentation"

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
        "CommandPalettePresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message:
        "CommandPalettePresentationCoordinator.dismiss(id:) must not be called during view update."
    )
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

private enum CommandPalettePresentationCoordinatorHandleKey: EnvironmentKey {
  static let defaultValue = PresentationCoordinatorHandle<PromptPresentationItem>.unavailable(
    "CommandPalettePresentationCoordinatorHandle"
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

  package var commandPalettePresentationCoordinator:
    PresentationCoordinatorHandle<PromptPresentationItem>
  {
    get { self[CommandPalettePresentationCoordinatorHandleKey.self] }
    set { self[CommandPalettePresentationCoordinatorHandleKey.self] = newValue }
  }
}

// MARK: - Coordinator Registry

package struct PresentationOverlayEntry: Sendable {
  var zIndex: Int
  var kindName: String
  var payload: DeferredViewPayload
}

@MainActor
package final class PresentationCoordinatorBox<C: ManagedPresentationCoordinator>
where C.Item.ID: Sendable {
  private var coordinator: C?
  private weak var configuredInvalidator: (any Invalidating)?
  private var configuredInvalidationIdentity: Identity?

  package init() {}

  package var zIndex: Int {
    C.zIndex
  }

  package var disablesBaseInteractionWhenActive: Bool {
    C.disablesBaseInteractionWhenActive && isActive
  }

  package var isActive: Bool {
    coordinator?.isActive ?? false
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

  package func overlayEntry() -> PresentationOverlayEntry? {
    guard let coordinator, coordinator.isActive else {
      return nil
    }

    return PresentationOverlayEntry(
      zIndex: C.zIndex,
      kindName: C.overlayKindName,
      payload: DeferredViewPayload {
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
  private let overlayEntryImpl: @MainActor () -> PresentationOverlayEntry?
  private let disablesBaseInteractionWhenActiveImpl: @MainActor () -> Bool

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
    disablesBaseInteractionWhenActiveImpl = {
      box.disablesBaseInteractionWhenActive
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
  func overlayEntry() -> PresentationOverlayEntry? {
    overlayEntryImpl()
  }

  @MainActor
  var disablesBaseInteractionWhenActive: Bool {
    disablesBaseInteractionWhenActiveImpl()
  }
}

@MainActor
package final class PresentationCoordinatorRegistry {
  package let alert = PresentationCoordinatorBox<AlertPresentationCoordinator>()
  package let confirmationDialog = PresentationCoordinatorBox<
    ConfirmationDialogPresentationCoordinator
  >()
  package let sheet = PresentationCoordinatorBox<SheetPresentationCoordinator>()
  package let toast = PresentationCoordinatorBox<ToastPresentationCoordinator>()
  package let commandPalette = PresentationCoordinatorBox<CommandPalettePresentationCoordinator>()

  private lazy var allBoxes = [
    AnyPresentationCoordinatorBox(alert),
    AnyPresentationCoordinatorBox(confirmationDialog),
    AnyPresentationCoordinatorBox(sheet),
    AnyPresentationCoordinatorBox(toast),
    AnyPresentationCoordinatorBox(commandPalette),
  ]

  package init() {}

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
    environmentValues.commandPalettePresentationCoordinator =
      commandPalette.handle(
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

  package var disablesBaseInteraction: Bool {
    allBoxes.contains {
      $0.disablesBaseInteractionWhenActive
    }
  }

  package func overlayEntries() -> [PresentationOverlayEntry] {
    allBoxes
      .compactMap {
        $0.overlayEntry()
      }
      .sorted { lhs, rhs in
        if lhs.zIndex != rhs.zIndex {
          return lhs.zIndex < rhs.zIndex
        }
        return lhs.kindName < rhs.kindName
      }
  }
}

@MainActor
package final class PresentationHostState {
  private let registry = PresentationCoordinatorRegistry()

  package init() {}

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

  package var disablesBaseInteraction: Bool {
    registry.disablesBaseInteraction
  }

  package func overlayEntries() -> [PresentationOverlayEntry] {
    registry.overlayEntries()
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

package struct PresentationHostingRoot<Content: View>: View, ResolvableView {
  package var content: Content
  package var hostState: PresentationHostState

  package init(
    content: Content,
    hostState: PresentationHostState
  ) {
    self.content = content
    self.hostState = hostState
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let hostIdentity = context.child(component: .named("PresentationHost")).identity
    var contentContext = context
    hostState.injectHandles(
      into: &contentContext.environmentValues,
      hostIdentity: hostIdentity,
      invalidator: context.invalidationProxy?.invalidator
    )

    let baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: contentContext),
      in: contentContext
    )
    let declarations = baseNode.preferenceValues[
      PresentationCoordinatorDeclarationPreferenceKey.self]
    hostState.reconcile(declarations.declarations)

    let overlayEntries = hostState.overlayEntries()
    guard !overlayEntries.isEmpty else {
      return [baseNode]
    }

    let hostContext = context.child(component: .named("PresentationHost"))
    let baseContext = hostContext.child(component: .named("base"))
    var hostedBaseNode = normalizeResolvedElements(
      resolveViewElements(content, in: baseContext),
      in: baseContext
    )
    if hostState.disablesBaseInteraction {
      hostedBaseNode.setEnabledRecursively(false)
    }

    let overlayNode = PresentationOverlayHost(entries: overlayEntries).resolve(
      in: hostContext.child(component: .named("overlay"))
    )

    return [
      ResolvedNode(
        identity: hostContext.identity,
        kind: .view("PresentationHost"),
        children: [hostedBaseNode, overlayNode],
        environmentSnapshot: hostContext.environment,
        transactionSnapshot: hostContext.transaction,
        layoutBehavior: .overlay(alignment: .topLeading)
      )
    ]
  }
}

private struct PresentationOverlayHost: View {
  var entries: [PresentationOverlayEntry]

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(entries.indices, id: \.self) { index in
        PresentationCoordinatorBodyHost(
          kindName: entries[index].kindName,
          payload: entries[index].payload
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct PresentationCoordinatorBodyHost: View, ResolvableView {
  var kindName: String
  var payload: DeferredViewPayload

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let childNode = payload.resolve(
      in: context.child(component: .named("body"))
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view(kindName),
        children: [childNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

extension ResolvedNode {
  package mutating func setEnabledRecursively(
    _ isEnabled: Bool
  ) {
    var style = environmentSnapshot.style
    style.isEnabled = isEnabled
    environmentSnapshot.style = style

    for index in children.indices {
      children[index].setEnabledRecursively(isEnabled)
    }
  }
}
