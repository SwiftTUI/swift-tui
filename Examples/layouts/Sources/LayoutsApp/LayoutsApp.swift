import Layouts
import SwiftTUI

@main
struct LayoutsApp: App, SwiftTUICommand {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

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
struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?

  var body: some View {
    if let id = selectedID, let entry = LayoutCatalog.entry(id: id) {
      LayoutDetailHost(entry: entry, onBack: backToPicker)
    } else {
      // Fallback includes the case `selectedID != nil && entry == nil`
      // (stale ID pointing at a removed catalog entry). The catalog is
      // static and compiled-in today, so the case is unreachable in
      // practice; if the catalog ever becomes dynamic, reset
      // `selectedID = nil` here to self-heal.
      LayoutPicker(onSelect: showDetail)
    }
  }

  private func showDetail(_ id: LayoutEntry.ID) {
    selectedID = id
  }

  private func backToPicker() {
    selectedID = nil
  }
}
