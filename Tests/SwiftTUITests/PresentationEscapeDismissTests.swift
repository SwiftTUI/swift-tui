import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct PresentationEscapeDismissTests {
  @Test("No active presentation yields no Escape dismiss action")
  func noActivePresentationYieldsNoAction() {
    let registry = PresentationCoordinatorRegistry()
    #expect(registry.dismissStack().topmostEscapeDismissAction() == nil)
  }

  @Test("An active sheet exposes its dismiss closure as the Escape action")
  func activeSheetExposesDismissAction() {
    let registry = PresentationCoordinatorRegistry()
    let handle = registry.sheet.handle(
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )

    var dismissed = 0
    handle.present(
      PromptPresentationItem(
        id: "sheet#1",
        title: "",
        descriptor: sheetPromptPresentationSpec().descriptor,
        actionPayloads: [],
        messagePayloads: [],
        contentPayloads: [],
        dismiss: { dismissed += 1 }
      )
    )

    let action = registry.dismissStack().topmostEscapeDismissAction()
    #expect(action != nil)
    action?()
    #expect(dismissed == 1)
  }

  @Test("Alert beats sheet: alert dismisses first when both are active")
  func alertBeatsSheetWhenBothActive() {
    let registry = PresentationCoordinatorRegistry()
    let sheetHandle = registry.sheet.handle(
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )
    let alertHandle = registry.alert.handle(
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )

    var sheetDismissed = 0
    var alertDismissed = 0

    sheetHandle.present(
      PromptPresentationItem(
        id: "sheet#1",
        title: "",
        descriptor: sheetPromptPresentationSpec().descriptor,
        actionPayloads: [],
        messagePayloads: [],
        contentPayloads: [],
        dismiss: { sheetDismissed += 1 }
      )
    )
    alertHandle.present(
      PromptPresentationItem(
        id: "alert#1",
        title: "",
        descriptor: alertPromptPresentationSpec().descriptor,
        actionPayloads: [],
        messagePayloads: [],
        contentPayloads: [],
        dismiss: { alertDismissed += 1 }
      )
    )

    let action = registry.dismissStack().topmostEscapeDismissAction()
    #expect(action != nil)
    action?()

    #expect(alertDismissed == 1)
    #expect(sheetDismissed == 0)
  }

  @Test("Toasts do not contribute an Escape dismiss action")
  func toastsDoNotContributeDismissAction() {
    let registry = PresentationCoordinatorRegistry()
    let toastHandle = registry.toast.handle(
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )

    var toastDismissed = 0
    toastHandle.present(
      ToastPresentationItem(
        id: "toast#1",
        contentPayloads: [],
        presentation: InfoToastStyle().resolvePresentation(
          for: ToastStyleConfiguration()
        ),
        duration: nil,
        dismiss: { toastDismissed += 1 }
      )
    )

    // A toast alone produces no Escape action — toasts auto-expire.
    #expect(registry.dismissStack().topmostEscapeDismissAction() == nil)
    #expect(toastDismissed == 0)
  }
}
