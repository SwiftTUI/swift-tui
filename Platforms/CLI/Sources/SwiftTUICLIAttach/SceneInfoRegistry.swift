#if !canImport(WASILibc) && !os(Windows)
  package import SwiftTUIPrimitives
  import Synchronization

  /// Tracks the attachable scenes of a running app for the discovery server.
  ///
  /// Constructed from plain `Entry` values rather than the launcher's scene
  /// runtimes so this module never names the portable launch half — the
  /// dependency edge runs `SwiftTUITerminalCLI → SwiftTUICLIAttach`, and the
  /// launcher maps its runtimes into entries at the call site.
  package final class SceneInfoRegistry: Sendable {
    package struct Entry: Sendable {
      let id: WindowIdentifier
      let title: String?
      let ptyPath: String?
      let isPrimary: Bool

      package init(id: WindowIdentifier, title: String?, ptyPath: String?, isPrimary: Bool) {
        self.id = id
        self.title = title
        self.ptyPath = ptyPath
        self.isPrimary = isPrimary
      }
    }

    private let entries: [Entry]
    private let attachedSceneIDs: Mutex<Set<WindowIdentifier>>

    package init(entries: [Entry]) {
      self.entries = entries
      self.attachedSceneIDs = Mutex(
        Set(
          entries
            .filter(\.isPrimary)
            .map(\.id)
        )
      )
    }

    package func scenes() -> [SceneInfo] {
      let attachedSceneIDs = attachedSceneIDs.withLock { $0 }
      return entries.map {
        SceneInfo(
          id: $0.id,
          title: $0.title,
          ptyPath: $0.ptyPath,
          isAttached: attachedSceneIDs.contains($0.id)
        )
      }
    }

    package func markAttached(sceneID: WindowIdentifier) {
      _ = attachedSceneIDs.withLock { $0.insert(sceneID) }
    }

    package func markDetached(sceneID: WindowIdentifier) {
      attachedSceneIDs.withLock { attachedSceneIDs in
        guard let entry = entries.first(where: { $0.id == sceneID }), !entry.isPrimary else {
          return
        }
        attachedSceneIDs.remove(sceneID)
      }
    }

    package func attachResponse(for sceneID: WindowIdentifier) -> SocketResponse {
      guard let entry = entries.first(where: { $0.id == sceneID }) else {
        return .error("scene not found: \(sceneID)")
      }
      guard let ptyPath = entry.ptyPath else {
        return .error("scene has no pty (primary scenes cannot be attached)")
      }
      return .attachOK(ptyPath: ptyPath)
    }
  }
#endif
