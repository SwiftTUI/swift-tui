#if DEBUG
  /// Diagnostic state is graph-local and checkpointed independently of production
  /// dependencies. The attempt allocator is lifetime currency and never rewinds.
  @MainActor
  package final class BodyChangeTracker {
    package static let maximumCauses = 64
    package static let maximumBodies = 4_096
    package static let maximumOwners = 4_096

    package enum Reason: Hashable {
      case state(StateSlotKey)
      case environment(ObjectIdentifier)
      case observation
      case explicit
      case dynamicProperty
    }

    package struct Key: Hashable {
      package var owner: NodeOwnerLifetimeID
      package var type: ObjectIdentifier
      package var kind: String
      package var ordinal: Int
    }

    package struct History {
      package var states: Set<StateSlotKey> = []
      package var environment: Set<ObjectIdentifier> = []
      package var complete = true
    }

    package struct Pending {
      package var reasons: [Reason: UInt64] = [:]
      package var omitted = 0
    }

    package struct Entry {
      package var pending: Pending
      package var sequence: UInt64
      package var initial: Bool
      package var ordinal = 0
    }

    package struct Snapshot {
      package var pending: [NodeOwnerLifetimeID: Pending] = [:]
      package var entries: [NodeOwnerLifetimeID: Entry] = [:]
      package var histories: [Key: History] = [:]
      package var overflow = false
    }

    package var snapshot = Snapshot()
    private var sequence: UInt64 = 0
    private var attempt: UInt64 = 0

    package init() {}

    package func note(_ reason: Reason, owner: NodeOwnerLifetimeID) {
      sequence &+= 1
      guard snapshot.pending[owner] != nil || snapshot.pending.count < Self.maximumOwners else {
        snapshot.overflow = true
        return
      }
      var pending = snapshot.pending[owner] ?? Pending()
      if pending.reasons[reason] != nil || pending.reasons.count < Self.maximumCauses {
        pending.reasons[reason] = sequence
      } else {
        pending.omitted = min(Int.max - 1, pending.omitted) + 1
      }
      snapshot.pending[owner] = pending
    }

    package func beginOwner(_ owner: NodeOwnerLifetimeID, initial: Bool) {
      guard snapshot.entries[owner] != nil || snapshot.entries.count < Self.maximumOwners else {
        snapshot.overflow = true
        return
      }
      snapshot.entries[owner] = Entry(
        pending: snapshot.pending[owner] ?? Pending(), sequence: sequence, initial: initial)
    }

    package func finishOwner(_ owner: NodeOwnerLifetimeID) {
      guard let entry = snapshot.entries.removeValue(forKey: owner),
        var pending = snapshot.pending[owner]
      else { return }
      pending.reasons = pending.reasons.filter { $0.value > entry.sequence }
      // An overflow cannot be attributed to an individual write. Keep the
      // uncertainty if any write arrived after the entry snapshot.
      if pending.reasons.isEmpty {
        snapshot.pending.removeValue(forKey: owner)
      } else {
        snapshot.pending[owner] = pending
      }
    }

    package func reused(_ owner: NodeOwnerLifetimeID) {
      snapshot.pending.removeValue(forKey: owner)
    }

    package func remove(_ owner: NodeOwnerLifetimeID) {
      snapshot.pending.removeValue(forKey: owner)
      snapshot.entries.removeValue(forKey: owner)
      snapshot.histories = snapshot.histories.filter { $0.key.owner != owner }
    }

    package func makeScope(type: Any.Type, kind: String, node: ViewNode) -> BodyChangeScope {
      let owner = node.ownerLifetimeID
      let entry = snapshot.entries[owner]
      let ordinal = entry?.ordinal ?? 0
      if entry != nil { snapshot.entries[owner]?.ordinal += 1 }
      attempt &+= 1
      let key = Key(owner: owner, type: ObjectIdentifier(type), kind: kind, ordinal: ordinal)
      return BodyChangeScope(
        tracker: self, key: key, type: type,
        graph: node.ownerGraph?.stateGraphScopeID.rawValue ?? 0,
        attempt: attempt, entry: entry, prior: snapshot.histories[key], overflow: snapshot.overflow)
    }

    package func finish(_ scope: BodyChangeScope) {
      guard scope.enrolled else { return }
      if snapshot.histories[scope.key] == nil, snapshot.histories.count >= Self.maximumBodies {
        // Drop all optional history rather than build an unbounded LRU. A new
        // registration explicitly reports missing provenance until warmed up.
        snapshot.histories.removeAll(keepingCapacity: true)
        snapshot.overflow = true
      }
      snapshot.histories[scope.key] = scope.reads
    }
  }

  /// A synchronous getter scope, deliberately not task-local: tasks must not
  /// inherit a completed body's attribution. Nested scopes restore with defer.
  @MainActor
  package final class BodyChangeScope {
    package static var current: BodyChangeScope?
    package let tracker: BodyChangeTracker
    package let key: BodyChangeTracker.Key
    package let type: Any.Type
    package let graph: UInt64
    package let attempt: UInt64
    package let entry: BodyChangeTracker.Entry?
    package let prior: BodyChangeTracker.History?
    package let overflow: Bool
    package var enrolled: Bool
    package var reads: BodyChangeTracker.History
    private var readBeforeEnrollment = false
    package var names: (() -> [StateSlotKey: String])?

    package init(
      tracker: BodyChangeTracker, key: BodyChangeTracker.Key, type: Any.Type,
      graph: UInt64, attempt: UInt64, entry: BodyChangeTracker.Entry?,
      prior: BodyChangeTracker.History?, overflow: Bool
    ) {
      self.tracker = tracker
      self.key = key
      self.type = type
      self.graph = graph
      self.attempt = attempt
      self.entry = entry
      self.prior = prior
      self.overflow = overflow
      enrolled = prior != nil
      reads = .init(complete: prior != nil)
    }

    package func run<Result>(_ apply: () throws -> Result) rethrows -> Result {
      let saved = Self.current
      Self.current = self
      defer {
        Self.current = saved
        tracker.finish(self)
      }
      return try apply()
    }

    package func stateRead(_ key: StateSlotKey) {
      guard enrolled else {
        readBeforeEnrollment = true
        return
      }
      if reads.states.count < BodyChangeTracker.maximumCauses {
        reads.states.insert(key)
      } else {
        reads.complete = false
      }
    }

    package func environmentRead(_ key: ObjectIdentifier) {
      guard enrolled else {
        readBeforeEnrollment = true
        return
      }
      if reads.environment.count < BodyChangeTracker.maximumCauses {
        reads.environment.insert(key)
      } else {
        reads.complete = false
      }
    }

    package func record() -> BodyChangeRecord {
      if !enrolled { reads.complete = !readBeforeEnrollment }
      enrolled = true
      let propertyNames = names?() ?? [:]
      var causes: Set<BodyChangeRecord.Cause> = []
      if entry?.initial == true {
        causes.insert(.init("identity", precision: "exact", property: "@identity"))
      } else if prior == nil || prior?.complete != true {
        causes.insert(.init("provenance-unavailable", precision: "unavailable"))
      }
      for reason in entry?.pending.reasons.keys ?? [BodyChangeTracker.Reason: UInt64]().keys {
        switch reason {
        case .state(let slot):
          if prior?.states.contains(slot) == true {
            causes.insert(.init("state", precision: "exact", property: propertyNames[slot]))
          } else if prior?.complete != true {
            causes.insert(.init("state", precision: "owner-only"))
          }
        case .environment(let key):
          if prior?.environment.contains(key) == true {
            causes.insert(.init("environment", precision: "exact"))
          } else if prior?.complete != true {
            causes.insert(.init("environment"))
          }
        case .observation: causes.insert(.init("observation"))
        case .explicit: causes.insert(.init("explicit"))
        case .dynamicProperty: causes.insert(.init("dynamic-property", precision: "unavailable"))
        }
      }
      if causes.isEmpty { causes.insert(.init("input-unverified", precision: "unavailable")) }
      if overflow { causes.insert(.init("provenance-unavailable", precision: "unavailable")) }
      return BodyChangeRecord(
        typeName: String(reflecting: type), kind: key.kind, graph: graph,
        owner: key.owner.rawValue, body: key.ordinal, attempt: attempt,
        causes: Array(causes), omitted: (entry?.pending.omitted ?? 0) + (overflow ? 1 : 0))
    }
  }
#endif
