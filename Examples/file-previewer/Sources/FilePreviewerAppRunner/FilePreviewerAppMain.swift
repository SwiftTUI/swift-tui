import FilePreviewerApp
import SwiftTUI

@main
struct FilePreviewerAppMain: App {
  var body: some Scene {
    WindowGroup("File Previewer") {
      FilePreviewerRootView()
    }
  }
}
