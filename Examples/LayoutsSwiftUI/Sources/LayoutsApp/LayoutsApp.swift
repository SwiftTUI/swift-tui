import Layouts
import SwiftUI

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
struct LayoutsRoot: View {
  @State private var selectedID: LayoutEntry.ID?

  var body: some View {
    NavigationStack {
      LayoutPicker(onSelect: showDetail)
        .navigationDestination(
          item: $selectedID,
          destination: { dest in
            if let entry = LayoutCatalog.entry(id: dest) {
              LayoutDetailHost(entry: entry, onBack: backToPicker)
            }
          })
    }
  }

  private func showDetail(_ id: LayoutEntry.ID) {
    selectedID = id
  }

  private func backToPicker() {
    selectedID = nil
  }
}
