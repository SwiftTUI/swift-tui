/// A value-typed tree node that stores its children inline as `[Self]`.
///
/// Releasing such a tree recurses once per level with no user code in the
/// trace: destroying the root releases its child array, whose storage `deinit`
/// destroys each element, each of which releases *its* child array. The
/// recursion belongs to the compiler-generated value witnesses, so a tree
/// deeper than the thread's stack allows dies with `SIGBUS`/`SIGSEGV` attributed
/// to nothing at all — not to the walker that read the tree, and not to the code
/// that built it.
///
/// The cost is linear in depth and specific to the node type's inline size.
/// Measured on macOS/arm64, debug, at 128 KiB / 512 KiB / 1 MiB stacks:
///
/// | node type      | inline size | stack per level | max depth @ 512 KiB |
/// | -------------- | ----------- | --------------- | ------------------- |
/// | `ResolvedNode` | 1410 B      | ~475 B          | ~1104               |
/// | `MeasuredNode` | 376 B       | ~267 B          | ~1968               |
/// | `PlacedNode`   | 552 B       | ~267 B          | ~1968               |
/// | `DrawNode`     | 248 B       | ~267 B          | ~1968               |
///
/// The per-level cost floors at the array-storage destroy frames, which is why
/// `DrawNode`'s smaller inline size lands in the same bracket as `MeasuredNode`
/// and `PlacedNode`.
///
/// 512 KiB is the number that matters: it is the Dispatch worker stack class
/// the frame tail runs on, and after the D72 walker conversions teardown is the
/// *only* depth-limited operation left on that thread.
///
/// Conforming types get ``flattenForRelease()``, which converts the release
/// into a heap-bounded loop. It is deliberately opt-in rather than automatic:
/// making it automatic needs a mutable class interposed on the child storage,
/// and this package's `Sendable` policy would force that class's reads through
/// a `Mutex` — an unacceptable cost on the hottest accessor in the engine.
package protocol DeeplyNestedValueTree {
  /// Direct access to the inline child storage.
  ///
  /// Where the type keeps a separate backing store, expose that rather than the
  /// public children setter: the drain replaces the array wholesale on a value
  /// that is about to be destroyed, so rebuilding its subtree aggregates is pure
  /// waste. `ResolvedNode` does this. Types whose children property *is* the
  /// storage, with `didSet` observers on it, pay one recompute on the root and
  /// nothing more — the drain never writes to any other node.
  var _childrenForRelease: [Self] { get set }
}

extension DeeplyNestedValueTree {
  /// Drops this value's descendants through a heap worklist, so the subsequent
  /// release costs O(1) stack instead of one frame group per level.
  ///
  /// Leaves `self` childless. The value is only meaningful as something about
  /// to be destroyed — its derived subtree aggregates are *not* refreshed, so
  /// callers must not read it afterwards.
  ///
  /// Use this wherever a tree of unbounded depth is dropped on a small stack,
  /// and in fixtures whose depth should be chosen by the property under test
  /// rather than by the teardown bound.
  ///
  /// Note that flattening a *copy* does not help: children arrays are
  /// copy-on-write, so emptying the copy leaves the original owning the
  /// subtree. Flatten the value that actually holds the last reference.
  package mutating func flattenForRelease() {
    // Take the children, then clear the field. Whole-array replacement never
    // triggers a copy-on-write copy — it just drops this value's reference —
    // so a subtree shared with a live tree is never duplicated here.
    var worklist = _childrenForRelease
    _childrenForRelease = []

    while let node = worklist.popLast() {
      // Copying the grandchildren into the worklist retains each one's own
      // child array. When `node` dies at the end of this iteration its array
      // storage is destroyed, but every element's children are now held by the
      // worklist copy as well, so those releases are plain decrements. The
      // recursion is bounded at two levels regardless of tree depth.
      worklist.append(contentsOf: node._childrenForRelease)
    }
  }
}
