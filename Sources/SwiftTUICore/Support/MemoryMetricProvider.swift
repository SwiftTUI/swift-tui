import Synchronization

/// One store's occupancy reading at a moment in time.
///
/// `count` (an element count) is always cheap and always reported.
/// `approxBytes` is a best-effort estimate provided only where a store can
/// compute one without scanning; `detail` carries optional named sub-counts
/// (hits, misses, order-buffer depth, …).
package struct MemoryMetricSnapshot: Sendable, Equatable {
  package var name: String
  package var count: Int
  package var approxBytes: Int?
  package var detail: [String: Int]?

  package init(
    name: String,
    count: Int,
    approxBytes: Int? = nil,
    detail: [String: Int]? = nil
  ) {
    self.name = name
    self.count = count
    self.approxBytes = approxBytes
    self.detail = detail
  }
}

/// A long-lived store that can report its current occupancy on demand.
///
/// Conformers reference their backing store *weakly* when the store is
/// graph-scoped, so that staying registered never keeps the store alive. A
/// store whose lifetime ends without its registration token being released is
/// exactly the leak the occupancy signal is meant to surface.
package protocol MemoryMetricProvider: Sendable {
  func snapshot() -> MemoryMetricSnapshot
}

/// Process-wide registry of occupancy providers.
///
/// Stores register a provider near their declaration and hold the returned
/// ``Token`` for as long as the store should be counted. Releasing the token
/// (typically by letting it deallocate alongside the store) deregisters the
/// provider. The profiling product reads ``snapshotAll()`` on its configured
/// interval; ``providerCount`` is itself a leak signal, since a graph-scoped
/// provider that never deregisters reveals a retained graph.
package final class MemoryMetricRegistry: Sendable {
  package static let shared = MemoryMetricRegistry()

  private struct State {
    var providers: [UInt64: any MemoryMetricProvider] = [:]
    var nextID: UInt64 = 0
  }

  private let state = Mutex(State())

  package init() {}

  /// Registers a provider and returns a token whose lifetime controls
  /// registration. The provider is snapshotted by ``snapshotAll()`` until the
  /// token is released.
  package func register(_ provider: any MemoryMetricProvider) -> Token {
    let id = state.withLock { state -> UInt64 in
      let id = state.nextID
      state.nextID += 1
      state.providers[id] = provider
      return id
    }
    return Token(id: id, registry: self)
  }

  /// Number of currently-registered providers. A monotonically climbing count
  /// across otherwise-quiescent activity indicates graph-scoped providers that
  /// failed to deregister.
  package var providerCount: Int {
    state.withLock { $0.providers.count }
  }

  /// Snapshots every registered provider. Order is unspecified.
  package func snapshotAll() -> [MemoryMetricSnapshot] {
    let providers = state.withLock { Array($0.providers.values) }
    return providers.map { $0.snapshot() }
  }

  private func deregister(_ id: UInt64) {
    state.withLock { _ = $0.providers.removeValue(forKey: id) }
  }

  /// Controls the lifetime of a registration. Releasing the token (explicitly
  /// or by deallocation) deregisters the associated provider.
  package final class Token: Sendable {
    private let id: UInt64
    private let registry: MemoryMetricRegistry

    init(id: UInt64, registry: MemoryMetricRegistry) {
      self.id = id
      self.registry = registry
    }

    deinit {
      registry.deregister(id)
    }
  }
}
