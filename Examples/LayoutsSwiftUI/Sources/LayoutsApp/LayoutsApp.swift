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
  @State private var imgs: [LayoutEntry.ID: NSImage] = [:]

  var body: some View {
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(LayoutCatalog.all.map(\.id), id: \.self) { c in
            Text("\(c)").monospaced()
              Rectangle().fill(.white)
                .frame(width: 100, height: 100)
                .overlay(alignment: .topLeading) {
                  if let img = imgs[c] {
                    Image(nsImage: img)
                      .resizable()
                      .aspectRatio(contentMode: .fit)
                      .border(.red)
                  }
                }
            .clipped()
            .onTapGesture {
              selectedID = selectedID == c ? nil : c
            }
          }
        }
      }
      .safeAreaInset(edge: .trailing) {
        Rectangle().fill(.gray)
          .frame(width: 500, height: 500)
          .overlay(alignment: .topLeading) {
            if let selectedID, let img = imgs[selectedID] {
              Image(nsImage: img)
                .border(.red)
            } else {
              Text("x").foregroundStyle(.red).font(.custom("System", size: 99999))
                .minimumScaleFactor(0.00001)
            }
          }
      }
      .task {
        for id in LayoutCatalog.all.map(\.id) {
          let entry = LayoutCatalog.entry(id: id)!
          let imgRenderer = ImageRenderer(content: entry.makeView())
          imgRenderer.proposedSize = .init(width: 500, height: 500)
          imgRenderer.scale = 2
          imgs[id] = imgRenderer.nsImage
        }
      }
  }

  private func showDetail(_ id: LayoutEntry.ID) {
    selectedID = id
  }

  private func backToPicker() {
    selectedID = nil
  }
}
