/// Instrumentation for Item 7 of ARCHITECTURE_NOTES.md — a bounded,
/// low-overhead record of every non-trivial call to
/// `ViewGraph.recordRegistrationAlias`.
///
/// The registration alias layer exists to let runtime registrations
/// (onAppear / task / env observation) recorded against a context's
/// identity still be looked up when that identity later resolves to a
/// different `ResolvedNode.identity`.  The architecture notes hypothesize
/// that these divergences come from a small, enumerable set of view
/// patterns (`ForEach` explicit-ID stamping, custom `ResolvableView`
/// identity rewrites, nested `AnyView`s), and that flattening identity
/// at the context level could eliminate the alias layer entirely.
///
/// This struct lets a live `ViewGraph` capture the exact set of
/// divergences it observes so the hypothesis can be checked against
/// real data rather than guessed at.  It's always on — the overhead is
/// a dictionary lookup and increment per alias call — and the unique
/// divergence map is hard-capped so a pathological workload can't leak
/// unbounded memory.
package struct RegistrationAliasDiagnostics: Equatable, Sendable {
  /// Total count of `recordRegistrationAlias` calls where the alias and
  /// target identities differed.  Every call is counted, even if the
  /// same (from, to, kind) tuple has already been seen.
  package private(set) var nonTrivialCallCount: Int

  /// Unique `(from, to, kindDescription)` tuples observed, mapped to
  /// the number of times each has been seen.  Hard-capped at
  /// `divergenceCap` entries — once full, new unique tuples are dropped
  /// but `nonTrivialCallCount` keeps incrementing so the "did we hit
  /// the cap" signal isn't lost.
  package private(set) var divergences: [DivergenceKey: Int]

  private let divergenceCap: Int

  package struct DivergenceKey: Hashable, Sendable, CustomStringConvertible {
    /// The identity the caller was resolving under at the time the
    /// alias was recorded (typically a positional context identity).
    package let fromIdentity: Identity
    /// The identity the resolved node actually ended up with.
    package let toIdentity: Identity
    /// Human-readable description of the resolved node's `NodeKind`.
    /// A string form is used instead of storing `NodeKind` directly
    /// to avoid imposing `Hashable` on a public API.
    package let kindDescription: String

    package init(
      fromIdentity: Identity,
      toIdentity: Identity,
      kindDescription: String
    ) {
      self.fromIdentity = fromIdentity
      self.toIdentity = toIdentity
      self.kindDescription = kindDescription
    }

    package var description: String {
      "\(fromIdentity) → \(toIdentity) [\(kindDescription)]"
    }
  }

  /// Creates an empty diagnostics record.
  ///
  /// - Parameter divergenceCap: Maximum number of unique `(from, to,
  ///   kind)` tuples to retain.  Once hit, new unique tuples are
  ///   dropped silently.  Defaults to 1024 which is more than enough
  ///   for any realistic view tree and well under a megabyte of
  ///   overhead.
  package init(divergenceCap: Int = 1024) {
    nonTrivialCallCount = 0
    divergences = [:]
    self.divergenceCap = divergenceCap
  }

  /// Records a single alias observation.  No-op when `from == to`; the
  /// trivial case is the common path and is deliberately not counted.
  package mutating func record(
    from: Identity,
    to: Identity,
    resolvedKind: NodeKind
  ) {
    guard from != to else {
      return
    }
    nonTrivialCallCount += 1

    let key = DivergenceKey(
      fromIdentity: from,
      toIdentity: to,
      kindDescription: Self.describe(resolvedKind)
    )
    if let existing = divergences[key] {
      divergences[key] = existing + 1
    } else if divergences.count < divergenceCap {
      divergences[key] = 1
    }
  }

  /// Number of unique `(from, to, kind)` tuples currently tracked.
  /// Returns a value less than or equal to `divergenceCap`.
  package var uniqueDivergenceCount: Int {
    divergences.count
  }

  /// Returns the observed divergences sorted by observation count,
  /// descending.  The top of the list is where the alias layer is
  /// doing the most work; those are the call sites a future refactor
  /// would want to address first.
  package func topDivergences(limit: Int = 16) -> [(key: DivergenceKey, count: Int)] {
    divergences
      .sorted { lhs, rhs in
        if lhs.value != rhs.value {
          return lhs.value > rhs.value
        }
        return lhs.key.description < rhs.key.description
      }
      .prefix(limit)
      .map { ($0.key, $0.value) }
  }

  /// Clears all tracked state.  Useful for test isolation.
  package mutating func reset() {
    nonTrivialCallCount = 0
    divergences.removeAll(keepingCapacity: true)
  }

  private static func describe(_ kind: NodeKind) -> String {
    switch kind {
    case .root:
      return "root"
    case .scene(let name):
      return "scene(\(name))"
    case .view(let name):
      return "view(\(name))"
    }
  }
}
