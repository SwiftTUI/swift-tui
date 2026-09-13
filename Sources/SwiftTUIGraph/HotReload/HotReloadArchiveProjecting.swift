/// Framework-owned inactive containers expose state archives for immediate
/// value encoding. The resulting replay snapshot retains none of these objects.
package protocol HotReloadArchiveProjecting {
  @MainActor func hotReloadArchives() -> [DormantStateArchive]
}

extension Optional: HotReloadArchiveProjecting where Wrapped: HotReloadArchiveProjecting {
  package func hotReloadArchives() -> [DormantStateArchive] {
    switch self {
    case .none: return []
    case .some(let value): return value.hotReloadArchives()
    }
  }
}

extension RetainedSubviewState: HotReloadArchiveProjecting {
  package func hotReloadArchives() -> [DormantStateArchive] {
    let records = restorationRecords.map { record in
      DormantStateArchive.NodeRecord(
        identity: record.identity, entityIdentity: nil,
        stateSlots: record.slots.compactMapValues { $0.dormantSnapshot() })
    }
    return [DormantStateArchive(records: records)]
  }
}
