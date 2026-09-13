import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  package func installHotReloadSession(_ session: HotReloadSession) {
    hotReloadSession = session
    session.requestFrame = { [weak self] in
      guard let self else { return }
      renderer.forceRootEvaluation()
      scheduler.requestInvalidation(of: [rootIdentity])
    }
  }

  package func replaceHotReloadGeneration(_ generation: HotReloadGeneration) throws {
    guard let session = hotReloadSession else { throw HotReloadSwapError.notMounted }
    try session.replace(
      with: generation, proposal: proposal(), focusedIdentity: focusTracker.currentFocusIdentity)
    pendingFocusTraversal = nil
    pendingClickFocusRestore = nil
  }
}
