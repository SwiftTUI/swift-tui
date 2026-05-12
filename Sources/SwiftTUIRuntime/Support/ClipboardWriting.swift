import SwiftTUIViews

extension RunLoop {
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
