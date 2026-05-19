package import SwiftTUICore

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
package final class PopoverPresentationCoordinator:
  StoredPresentationCoordinator<PopoverPresentationItem>,
  ManagedPresentationCoordinator
{
  package static let zIndex = 220
  package static let modalPolicy = PortalModalPolicy.disablesBaseInteraction
  package static let overlayKindName = "PopoverPresentation"

  @ViewBuilder
  package func makeBody() -> some View {
    if let latestItem {
      HostedPopoverPresentation(item: latestItem)
    }
  }

  package func present(
    _ item: PopoverPresentationItem
  ) {
    super.present(
      item,
      message: "PopoverPresentationCoordinator.present(_:) must not be called during view update."
    )
  }

  package func dismiss(
    id: String
  ) {
    super.dismiss(
      id: id,
      message: "PopoverPresentationCoordinator.dismiss(id:) must not be called during view update."
    )
  }

  package func dismissAction(
    for item: PopoverPresentationItem
  ) -> (@MainActor @Sendable () -> Void)? {
    item.surfaceItem.dismiss
  }

  package func modalPolicy(
    for item: PopoverPresentationItem
  ) -> PortalModalPolicy {
    item.modalPolicy
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
