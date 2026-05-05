import FilePreviewerApp
import SwiftTUI
import SwiftTUICLI

@main
struct FilePreviewerAppMain: App {
  var body: some Scene {
    WindowGroup("File Previewer") {
      FilePreviewerRootView()
    }
  }
}
