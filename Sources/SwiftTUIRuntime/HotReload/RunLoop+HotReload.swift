import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  package func processPendingHotReload() {
    #if DEBUG && (os(macOS) || os(Linux))
      guard hotReloadLoadRequested, let loader = hotReloadLoader,
        hotReloadSession?.awaitingCommit == false
      else { return }
      hotReloadLoadRequested = false
      do {
        if let replacement = try loader.loadPending() {
          try replaceHotReloadGeneration(replacement)
          if let session = hotReloadSession { loader.installed(generation: session.generation) }
        }
      } catch { loader.report(error) }
    #endif
  }

  package func acknowledgeHotReloadCommit() {
    #if DEBUG && (os(macOS) || os(Linux))
      hotReloadLoader?.didCommit(session: hotReloadSession)
    #endif
  }

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
