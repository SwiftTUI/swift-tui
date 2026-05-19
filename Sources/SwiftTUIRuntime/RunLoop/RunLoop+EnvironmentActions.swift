import SwiftTUICore
import SwiftTUIViews

// Runtime environment-action factories.
//
// Several `Environment` actions ship as inert placeholders so views can read
// them before a run loop exists. When the run loop assembles a frame's
// `ResolveContext` (see `resolveContext(for:)`), it swaps any still-placeholder
// action for the live runtime implementation built here: focus reset wired to
// the scheduler, and clipboard read/write wired to the presentation surface.
extension RunLoop {
  /// Live `resetFocus` action: clears local default-focus state for the given
  /// namespace and asks the scheduler to re-resolve the root.
  package func runtimeResetFocusAction() -> ResetFocusAction {
    ResetFocusAction(
      snapshotLabel: "ResetFocusAction.runtime",
      isPlaceholder: false,
      handler: { [weak scheduler, localDefaultFocusRegistry, rootIdentity] namespace in
        localDefaultFocusRegistry.requestReset(in: namespace)
        scheduler?.requestInvalidation(of: [rootIdentity])
        return true
      }
    )
  }

  /// Live `clipboardWrite` action. Returns `false` when the presentation
  /// surface cannot write to a clipboard or the write throws.
  package func runtimeClipboardWriteAction() -> ClipboardWriteAction {
    ClipboardWriteAction(
      snapshotLabel: "ClipboardWriteAction.runtime",
      isPlaceholder: false
    ) { [presentationSurface] text in
      guard let surface = presentationSurface as? any ClipboardWritingPresentationSurface else {
        return false
      }

      do {
        return try surface.writeClipboard(text)
      } catch {
        return false
      }
    }
  }

  /// Live `clipboardRead` action. Returns `nil` when the presentation surface
  /// cannot read a clipboard or the read throws.
  package func runtimeClipboardReadAction() -> ClipboardReadAction {
    ClipboardReadAction(
      snapshotLabel: "ClipboardReadAction.runtime",
      isPlaceholder: false
    ) { [presentationSurface] in
      guard let surface = presentationSurface as? any ClipboardReadingPresentationSurface else {
        return nil
      }

      do {
        return try surface.readClipboard()
      } catch {
        return nil
      }
    }
  }
}
