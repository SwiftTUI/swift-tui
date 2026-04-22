import TerminalUI

/// Demonstrates `.dropDestination` by collecting file paths dropped onto
/// the terminal (or pasted as a file-URL-shaped payload). The handler is
/// registered on a single `Panel`, returns `true` to consume the drop,
/// and appends each dropped path's `rawValue` to a local `@State` list.
struct FileDropTab: View {
  @State private var droppedPaths: [String] = []

  var body: some View {
    Panel(id: "drop-demo") {
      VStack(alignment: .leading, spacing: 1) {
        Text("Drag a file from Finder onto this terminal to see its path.")
          .foregroundStyle(.muted)
        Divider()
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(droppedPaths.enumerated()), id: \.offset) { _, path in
            let ext = path.components(separatedBy: ".").last
            if let ext, ext.lowercased() == "png" {
              Image(fileURL: ext)
            }
            Text(path)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .dropDestination { paths in
      droppedPaths.append(contentsOf: paths.map(\.rawValue))
      return true
    }
  }
}
