import Layouts
import TerminalUI
import TerminalUICLI

@main
struct LayoutsApp: App {
  var body: some Scene {
    WindowGroup {
      LayoutsRoot()
    }
  }
}

/// Two-state router: nil → picker, non-nil → detail host.
///
/// `@State var selectedID` is hoisted above both sub-views so
/// returning from detail to picker does not destroy the picker's
/// internal focus/selection state on the way back.
struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?

  var body: some View {
    if let id = selectedID, let entry = LayoutCatalog.entry(id: id) {
      LayoutDetailHost(entry: entry, onBack: { @MainActor @Sendable in selectedID = nil })
    } else {
      LayoutPicker(onSelect: { selectedID = $0 })
    }
  }
}
