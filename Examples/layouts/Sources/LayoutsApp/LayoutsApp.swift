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
/// `selectedID` lives on the router because only the router owns
/// the routing bit — `LayoutDetailHost.onBack` must flip it on the
/// parent, and `LayoutPicker.onSelect` must write it from below.
/// The `ConditionalContent` branch swap tears down each subview on
/// transition; the picker self-clears its local `selection` after
/// firing `onSelect`, so a fresh picker on back-trip is the correct
/// state.
struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?

  var body: some View {
    if let id = selectedID, let entry = LayoutCatalog.entry(id: id) {
      LayoutDetailHost(entry: entry, onBack: { @MainActor @Sendable in selectedID = nil })
    } else {
      // Fallback includes the case `selectedID != nil && entry == nil`
      // (stale ID pointing at a removed catalog entry). The catalog is
      // static and compiled-in today, so the case is unreachable in
      // practice; if the catalog ever becomes dynamic, reset
      // `selectedID = nil` here to self-heal.
      LayoutPicker(onSelect: { selectedID = $0 })
    }
  }
}
