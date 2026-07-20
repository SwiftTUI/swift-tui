#if os(WASI) && canImport(WASILibc)
  import WASILibc
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Bounds the resolve descent's native stack depth by chunking deep subtrees.
///
/// JavaScriptCore executes wasm calls on the host thread's native stack and
/// worker threads get a small fraction of the main-thread budget, so an
/// unbounded per-view-level recursion overflows on deep trees (the resolve
/// descent costs 13–15 wasm frames per view level; WebKit's worker budget
/// fits roughly 26 levels of the committed-graph descent). The driver caps
/// inline descent at ``depthLimit`` levels via a drain-and-rerun fixpoint:
///
/// 1. A `resolveView` call that would cross the cap on a structural child
///    edge commits its node's *stale committed snapshot* as a structural
///    placeholder (a no-op child diff against the live children), enqueues a
///    captured re-resolve of the subtree, and returns.
/// 2. The queue drains from the outermost `resolveView` epilogue — a fresh,
///    shallow stack — where each item re-resolves its subtree through the
///    normal begin/finish path with a fresh depth budget.
/// 3. The outermost resolve then RE-RUNS. Cut points whose chunk is fully
///    fresh (its own subtree contains no unfresh chunks) serve their
///    same-frame committed snapshot without re-enqueueing; every enclosing
///    level and value consumer (portal composition, preference absorption,
///    entity occurrence passes) re-applies its post-processing over the real
///    subtree values. A chunk that still contained unfresh inner chunks is
///    re-enqueued and re-drained, so the fixpoint converges bottom-up in at
///    most the chunk-nesting depth (tree depth / K) passes.
///
/// The rerun is what makes chunking correct against the framework's
/// value-pipeline style: ancestors may post-process descendant values
/// arbitrarily (modal suppression stamps, preference clears, occurrence
/// stamps), and production keeps those stamps correct by re-composing on
/// resolve — never by patching committed values after the fact. Splicing
/// the drained subtree into ancestor copies was tried and refuted: it
/// silently reverts whatever the ancestors stamped onto the placeholder.
///
/// The driver's state is transient within one frame: the queue is empty and
/// the depth is zero whenever a frame begins or ends, so it deliberately
/// lives outside the checkpointed graph field groups.
@MainActor
package final class DeferredResolveDriver {
  /// Maximum inline descent depth; `nil` disables chunking entirely.
  ///
  /// Defaults on under ``stackLeanResolveProfile`` (WASI), where
  /// `SWIFTTUI_RESOLVE_DEPTH_LIMIT` overrides the built-in cap. Native
  /// processes default to `nil`; `SWIFTTUI_RESOLVE_DEPTH_LIMIT` force-enables
  /// the driver natively, and tests opt in per graph via
  /// ``ViewGraph/setDeferredResolveDepthLimitForTesting(_:)``.
  package var depthLimit: Int?

  package private(set) var descentDepth = 0
  private var queue: [@MainActor () -> Void] = []
  private var isDraining = false

  /// Chunk identities currently waiting in the queue, so a cut never
  /// enqueues the same subtree twice within one drain pass.
  private var queuedChunkIdentities: Set<Identity> = []

  /// Chunks whose latest drain completed with every inner cut serving a
  /// fully fresh chunk — their committed snapshots are placeholder-free and
  /// safe to serve at a cut without re-resolving.
  private var fullyFreshChunkIdentities: Set<Identity> = []

  /// Per-chunk-resolve freshness accounting: the top entry is poisoned when
  /// a cut inside the running chunk stale-serves or serves a non-fresh
  /// chunk, denying the chunk fully-fresh status for this round.
  private var chunkResolveStack: [ChunkResolveFrame] = []

  private struct ChunkResolveFrame {
    var identity: Identity
    var sawNonFreshCut = false
  }

  /// Per-resolve-pass instrumentation, reset at frame head; read by WASI
  /// depth probes and the native parity tests.
  package private(set) var maxDescentDepth = 0
  package private(set) var deferralCount = 0
  package private(set) var drainPassCount = 0

  package init() {
    depthLimit = Self.profileDefaultDepthLimit
  }

  /// The stack-lean default keeps every chunk comfortably inside WebKit's
  /// worker budget with margin for the inline overshoot past the cap (cuts
  /// fire only on structural edges, so modifier/chrome chains add a few
  /// inline levels) and the per-level cost difference between boot-frame
  /// and committed-graph descents. Measured on the WebExample gallery with
  /// default (non-inline-tuned) wasm packaging: the worker budget fits
  /// ~16 boot levels, and committed-graph levels run ~25% fatter — a cap of
  /// 6 bounds worst-case inline depth around 10 fatter levels, keeping
  /// ≥25% headroom.
  package static let stackLeanDefaultDepthLimit = 6

  /// Fixpoint passes converge in the chunk-nesting depth (≈ tree depth /
  /// depth limit); the cap is a runaway backstop far above any real tree.
  private static let maxDrainPasses = 32

  private static var profileDefaultDepthLimit: Int? {
    // `SWIFTTUI_RESOLVE_DEPTH_LIMIT` tunes the cap on WASI and force-enables
    // the driver on native for composed-runtime debugging and tests.
    if let raw = unsafe getenv("SWIFTTUI_RESOLVE_DEPTH_LIMIT"),
      let parsed = Int(unsafe String(cString: raw))
    {
      return parsed > 0 ? parsed : nil
    }
    guard stackLeanResolveProfile else {
      return nil
    }
    return stackLeanDefaultDepthLimit
  }

  package var isIdle: Bool {
    descentDepth == 0 && queue.isEmpty && !isDraining
  }

  /// Whether a `resolveView` entered at the current depth must stop inline
  /// descent and either serve its fresh chunk or enqueue its subtree.
  package var shouldDeferDescent: Bool {
    guard let depthLimit else {
      return false
    }
    return descentDepth >= depthLimit
  }

  package func enterLevel() {
    descentDepth += 1
    if descentDepth > maxDescentDepth {
      maxDescentDepth = descentDepth
    }
  }

  package func leaveLevel() {
    descentDepth = max(0, descentDepth - 1)
  }

  /// Whether a cut at `identity` may serve the node's same-frame committed
  /// snapshot instead of enqueueing. Serving a chunk that is not fully
  /// fresh would leak placeholder slices buried in value-only interiors of
  /// its committed value, so such chunks re-enqueue and re-drain instead.
  package func canServeFreshChunk(_ identity: Identity) -> Bool {
    fullyFreshChunkIdentities.contains(identity)
      && !queuedChunkIdentities.contains(identity)
  }

  /// Records that a cut served `identity`'s fresh chunk snapshot.
  package func noteFreshChunkServed() {
    // A fresh serve keeps the enclosing chunk's freshness intact; nothing
    // to record.
  }

  /// Records a cut that could not serve fresh: the enclosing chunk resolve
  /// (if any) cannot be marked fully fresh this round.
  private func noteNonFreshCut() {
    if !chunkResolveStack.isEmpty {
      chunkResolveStack[chunkResolveStack.count - 1].sawNonFreshCut = true
    }
  }

  /// Enqueues a deferred subtree resolve for `identity`, deduplicating
  /// against an already-queued item for the same chunk.
  package func enqueueDeferredResolve(
    for identity: Identity,
    work: @escaping @MainActor () -> Void
  ) {
    noteNonFreshCut()
    fullyFreshChunkIdentities.remove(identity)
    guard queuedChunkIdentities.insert(identity).inserted else {
      return
    }
    queue.append { [weak self] in
      guard let self else {
        return
      }
      self.queuedChunkIdentities.remove(identity)
      self.chunkResolveStack.append(ChunkResolveFrame(identity: identity))
      work()
      let frame = self.chunkResolveStack.removeLast()
      if !frame.sawNonFreshCut {
        self.fullyFreshChunkIdentities.insert(identity)
      }
    }
    deferralCount += 1
  }

  /// Drains queued subtree resolves once the call stack has fully unwound,
  /// then reruns the outermost resolve so every enclosing level re-applies
  /// its value post-processing over the drained subtrees — looping until a
  /// rerun completes without enqueueing new work. Runs from every outermost
  /// `resolveView` epilogue; nested epilogues (drained items, the rerun
  /// itself) are rejected by the `isDraining` latch, so this loop is the
  /// single trampoline frame for the whole pass. FIFO order preserves
  /// document order per depth band.
  package func drainIfOutermost(rerun: @MainActor () -> Void) {
    guard descentDepth == 0, !isDraining, !queue.isEmpty else {
      return
    }
    isDraining = true
    defer { isDraining = false }
    var passes = 0
    while !queue.isEmpty, passes < Self.maxDrainPasses {
      passes += 1
      drainPassCount += 1
      var cursor = 0
      while cursor < queue.count {
        let work = queue[cursor]
        cursor += 1
        work()
      }
      queue.removeAll(keepingCapacity: true)
      rerun()
    }
    assert(
      queue.isEmpty,
      "chunked resolve failed to converge in \(Self.maxDrainPasses) passes"
    )
    queue.removeAll(keepingCapacity: true)
    queuedChunkIdentities.removeAll(keepingCapacity: true)
  }

  /// Frame-head reset: chunk freshness never carries across frames (the
  /// next frame's state may change any subtree), and the instrumentation
  /// counters restart.
  package func beginFrame() {
    fullyFreshChunkIdentities.removeAll(keepingCapacity: true)
    queuedChunkIdentities.removeAll(keepingCapacity: true)
    chunkResolveStack.removeAll(keepingCapacity: true)
    maxDescentDepth = 0
    deferralCount = 0
    drainPassCount = 0
  }
}

extension ViewGraph {
  /// Test seam: forces the chunked resolve driver on (with a small limit)
  /// or off for this graph, independent of the platform profile.
  package func setDeferredResolveDepthLimitForTesting(_ limit: Int?) {
    deferredResolveDriver.depthLimit = limit
  }
}
