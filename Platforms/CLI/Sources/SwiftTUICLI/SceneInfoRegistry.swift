#if !canImport(WASILibc)
  @_spi(Runners) import SwiftTUI
  import Synchronization

  final class SceneInfoRegistry: Sendable {
    struct Entry: Sendable {
      let id: String
      let title: String?
      let ptyPath: String?
      let isPrimary: Bool
    }

    private let entries: [Entry]
    private let attachedSceneIDs: Mutex<Set<String>>

    @MainActor
    init(runtimes: [SceneRuntime]) {
      self.entries = runtimes.map {
        Entry(
          id: $0.selection.identifier.rawValue,
          title: $0.selection.title,
          ptyPath: $0.sceneInfo.ptyPath,
          isPrimary: $0.isPrimary
        )
      }
      self.attachedSceneIDs = Mutex(
        Set(
          entries
            .filter(\.isPrimary)
            .map(\.id)
        )
      )
    }

    func scenes() -> [SceneInfo] {
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

    func markAttached(sceneID: String) {
      _ = attachedSceneIDs.withLock { $0.insert(sceneID) }
    }

    func markDetached(sceneID: String) {
      attachedSceneIDs.withLock { attachedSceneIDs in
        guard let entry = entries.first(where: { $0.id == sceneID }), !entry.isPrimary else {
          return
        }
        attachedSceneIDs.remove(sceneID)
      }
    }

    func attachResponse(for sceneID: String) -> SocketResponse {
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
