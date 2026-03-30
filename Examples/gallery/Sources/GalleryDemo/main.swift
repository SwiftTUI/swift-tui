import Foundation
import Observation
import TerminalUI
import TerminalUICharts
import TerminalUIScenes

struct GalleryDemoApp: App {
  private let model = GalleryDemoModel()

  var body: some Scene {
    WindowGroup("Component Gallery") {
      GalleryDemoSceneView(model: model)
    }
  }
}

// SwiftUI-style app construction remains main-actor isolated in this package.
let app = await MainActor.run { GalleryDemoApp() }

do {
  try await MultiSceneLauncher.run(app)
} catch let error as TerminalHostError {
  FileHandle.standardError.write(Data(galleryLaunchFailureMessage(for: error).utf8))
  Foundation.exit(1)
} catch {
  FileHandle.standardError.write(Data("Gallery demo failed to launch: \(error)\n".utf8))
  Foundation.exit(1)
}

func galleryLaunchFailureMessage(
  for error: TerminalHostError
) -> String {
  switch error {
  case .notATTY:
    """
    Gallery demo must be launched from an interactive terminal.
    Run `swift run --package-path Examples/gallery` from Terminal, iTerm, or another TTY-backed shell.
    """
      + "\n"
  case .failedToReadAttributes(let errno):
    "Gallery demo failed to read terminal attributes (errno \(errno)).\n"
  case .failedToSetAttributes(let errno):
    "Gallery demo failed to configure the terminal (errno \(errno)).\n"
  case .failedToReadWindowSize(let errno):
    "Gallery demo failed to read the terminal size (errno \(errno)).\n"
  case .failedToReadFileStatusFlags(let errno):
    "Gallery demo failed to read terminal file status flags (errno \(errno)).\n"
  case .failedToSetFileStatusFlags(let errno):
    "Gallery demo failed to update terminal file status flags (errno \(errno)).\n"
  case .failedToWrite(let errno):
    "Gallery demo failed while writing to the terminal (errno \(errno)).\n"
  }
}
