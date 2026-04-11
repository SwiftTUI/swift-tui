# Architecture notes

Improvement proposals surfaced from a review of the view graph, diffing, and
pipeline layers. Eleven items, ordered by cost class (mechanical → focused →
structural). Each item has concrete file:line references, a code sketch where
useful, risks, and — where applicable — suggested tests.

All items stand alone unless otherwise noted. Ordering dependencies are
called out in the priority section at the end.

**Nothing in this document should be landed blind.** Each item has
enumerated risks; take them seriously. The higher-cost items in particular
are directional and need profiling or instrumentation before any code change.

## Progress snapshot

Last updated 2026-04-10. 7 of 11 items landed; 1 retracted; 3 structural
items deferred pending concrete pain points.

| # | Item | Status | Commit |
|---|---|---|---|
| 1 | `MeasurementCache` stale-entry eviction | ✅ Landed | `24ada3d` |
| 2 | `CollectionDifference`-based `diffChildren` | ✅ Landed | `c077679` |
| 3 | `applyStructuralChildDiff` doc comment | ✅ Landed (Option A doc-fence) | `6698483` |
| 4 | `typeDiscriminator` on `ChildDescriptor` | ✅ Landed (infrastructure + `Text` migration) | `4ae4f5f` |
| 5 | ~~Immutable `ResolvedNode` + kill `Boxed`~~ | ❌ Retracted (misdiagnosis) | `5bea099` |
| 6 | `ViewNode` contains `ResolvedNode` | ✅ Landed | `d8d0a80` |
| 7 | `registrationAliasesByIdentity` investigation | 🔎 Instrumented + findings recorded; code refactor deferred | `fdeaa3c` |
| 8 | Decompose `ViewGraph` into 4 types | ⏸ Deferred — no concrete testability pain point yet |  |
| 9 | Dependency-aware body re-evaluation | ⏸ Deferred — profile first |  |
| 10 | Explicit context threading | ⏸ Deferred — blocked on concurrency or testability wall |  |
| 11 | `Identity` interning | ⏸ Deferred — profile first |  |

**Net outcome so far:** every non-deferred item landed cleanly. Suite went
from 651 → 682 tests (+31) across the seven commits, with no regressions.
Item 4 surfaced a SwiftPM stale-artifact gotcha that's documented in the
commit message. Item 5 was retracted after investigation revealed two
misdiagnoses in the original analysis; the retraction note in section 5
documents what was wrong and why.

The follow-up drip-fed work on Item 4 (migrating the remaining ~46
`.view("Name")` call sites to the typed discriminator) is intentionally
not scheduled — `Text` is the demonstration migration and the bridging
compatibility rule lets the rest follow whenever they naturally come up
in view-specific work.

---

## Section 1 — Mechanical wins

Small, self-contained changes. Each is implementable in a single PR by
somebody who's never touched the surrounding code before.

### 1. Fix the `MeasurementCache` stale-entry bug

> **Status:** ✅ **Landed in `24ada3d`** — fix evicts stale entries on
> equivalence mismatch and splits `misses` from a new `invalidations`
> counter. 3 new `LayoutEngineTests` cases; 1 test in
> `DiagnosticsAndCacheTests` was implicitly asserting the buggy
> `misses == 5` behavior and was updated to `misses == 3 + invalidations == 2`.

**File:** `Sources/Core/LayoutEngine.swift:61-94`
**Size:** ~10 LOC + 1 test.

Look at the current lookup path:

```swift
public func lookup(resolved: ResolvedNode, proposal: ProposedSize) -> MeasuredNode? {
  storage.withLock { storage in
    // … fetch cached entry …
    guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
      storage.misses += 1
      return nil                              // <-- stale entry stays in cache
    }
    storage.hits += 1
    return cached.node
  }
}
```

If the cached `resolved` is not equivalent to the current `resolved`, the
lookup returns `nil` but **leaves the stale entry in the cache**. The next
lookup for the same `(identity, proposal)` will fetch the same stale entry,
fail the equivalence check again, and return nil again. The entry sits there
until `store()` is called to overwrite it.

Two real problems:

1. **Correctness leak:** repeated measurement work that should be cached
   isn't. Every frame pays the full measurement cost, not just the first.
2. **Metrics corruption:** the `misses` counter is inflated with
   structural-invalidation events, obscuring actual cold-cache misses in
   whatever dashboard reads these metrics.

**Fix:**

```swift
guard cached.resolved.isEquivalentForMeasurement(to: resolved) else {
  identityStorage.entries.removeValue(forKey: proposal)
  if identityStorage.entries.isEmpty {
    storage.entriesByIdentity.removeValue(forKey: resolved.identity)
  } else {
    storage.entriesByIdentity[resolved.identity] = identityStorage
  }
  storage.invalidations += 1  // new counter, distinct from misses
  return nil
}
```

Add an `invalidations` counter to `Storage` alongside `misses`.

**Test:**

```swift
@Test("Stale cache entries are evicted on equivalence mismatch")
func staleCacheEviction() {
  let cache = MeasurementCache()
  let identity = testIdentity("Root", "Child")
  let proposal = ProposedSize(width: 100, height: 100)

  let oldResolved = ResolvedNode(identity: identity, kind: .view("Text"), ...)
  let oldMeasured = MeasuredNode(identity: identity, proposal: proposal, measuredSize: .init(width: 50, height: 10))
  cache.store(oldMeasured, for: oldResolved)

  // Mutate resolved so isEquivalentForMeasurement fails
  var newResolved = oldResolved
  newResolved.layoutMetadata = /* something different */

  #expect(cache.lookup(resolved: newResolved, proposal: proposal) == nil)
  #expect(cache.count == 0) // stale entry evicted
}
```

**Risk:** minimal. The only consumer is `LayoutEngine.measure` which already
handles `nil` returns from `lookup` by doing a fresh measurement. Evicting
the stale entry just moves it from "sits there doing nothing useful" to
"gone."

---

### 2. `CollectionDifference`-based `diffChildren`

> **Status:** ✅ **Landed in `c077679`** — `diffChildren` rewritten on
> top of `new.difference(from: old).inferringMoves()`. `ChildDiffOp`
> gained a new `.moved` case; the existing `applyStructuralChildDiff`
> consumer ignores it via its existing `guard case .removed …`
> fall-through, so teardown behavior is unchanged. 5 structural diff
> tests; `reorderMatchesStableDescriptors` replaced by `reorderEmitsMove`.

**File:** `Sources/Core/Graph/StructuralDiff.swift` (43 LOC today)
**Tests:** `Tests/CoreTests/Graph/StructuralDiffTests.swift`
**Size:** 30–60 LOC net, 2 test additions.

#### Why

Three reasons, in order of importance:

1. **Move tracking for animations.** The current greedy-hashmap diff emits
   `.matched(oldIndex, newIndex)` pairs but never a `.moved` op. With the
   resolve-once-animate-through-pipeline the repo is heading toward, move
   detection is the precondition for animating reorders — a ForEach that
   shuffles rows is the canonical case.
2. **Stdlib correctness guarantees.** `CollectionDifference.inferringMoves()`
   is the Heckel/Paul-Heckel variant the stdlib has shipped since Swift 5.1.
   Using it means any bug is Apple's bug, not ours.
3. **Less code.** The hashmap bookkeeping in `StructuralDiff.swift:11-41`
   goes away entirely.

#### Not a correctness fix

An earlier version of this review claimed the greedy algorithm could
produce wrong matches on reorders. That was overstated — look at
`Tests/CoreTests/Graph/StructuralDiffTests.swift:7-26`: the first test
deliberately swaps two rows with explicit IDs and the greedy diff produces
the correct `matched(1,0)` / `matched(0,1)` pairs. This works because
`ChildDescriptor.identity` is distinct per row (the explicit ID is baked
into the identity path), so the hash-keyed lookup in `StructuralDiff.swift:11`
never hits the wrong slot.

So: this is an ergonomics + future-proofing win, not a bug fix. The current
implementation is correct for its current consumer (`applyStructuralChildDiff`
which only reacts to `.removed`).

#### Sketch

```swift
package enum ChildDiffOp: Equatable, Sendable {
  case matched(oldIndex: Int, newIndex: Int)
  case moved(oldIndex: Int, newIndex: Int)   // new
  case inserted(newIndex: Int)
  case removed(oldIndex: Int)
}

package func diffChildren(
  old: [ChildDescriptor],
  new: [ChildDescriptor]
) -> [ChildDiffOp] {
  let difference = new.difference(from: old).inferringMoves()

  var removedOldIndices: Set<Int> = []
  var insertedNewIndices: Set<Int> = []
  var operations: [ChildDiffOp] = []

  for change in difference {
    switch change {
    case let .remove(offset, _, associatedWith):
      removedOldIndices.insert(offset)
      if let newOffset = associatedWith {
        operations.append(.moved(oldIndex: offset, newIndex: newOffset))
      } else {
        operations.append(.removed(oldIndex: offset))
      }

    case let .insert(offset, _, associatedWith):
      insertedNewIndices.insert(offset)
      if associatedWith != nil {
        continue  // move already recorded on the .remove side
      }
      operations.append(.inserted(newIndex: offset))
    }
  }

  // Emit matches for positions that survived both sides.
  var oldIndex = 0
  var newIndex = 0
  while oldIndex < old.count && newIndex < new.count {
    if removedOldIndices.contains(oldIndex) { oldIndex += 1; continue }
    if insertedNewIndices.contains(newIndex) { newIndex += 1; continue }
    operations.append(.matched(oldIndex: oldIndex, newIndex: newIndex))
    oldIndex += 1
    newIndex += 1
  }

  return operations
}
```

#### Risks

- **`applyStructuralChildDiff` needs to learn about `.moved`.** Look at
  `Sources/Core/Graph/ViewGraph.swift:725-745`. Today it only acts on
  `.removed`. If we introduce `.moved`, the consumer either (a) stays the
  same and ignores `.moved` (safe, same behavior as today) or (b) starts
  using moves to drive reorder animations. Pick (a) for the first landing.
- **Matched op ordering changes.** The current algorithm emits matches in
  `new`-index order. The sketch above preserves that.
- **`CollectionDifference` requires `Element: Hashable`.** `ChildDescriptor`
  already conforms, so no work.
- **Associated values in `.moved`:** `.inferringMoves()` is mandatory —
  forgetting it silently degrades the diff to insert/remove pairs. Add a
  test to guard.

#### Tests to add

1. Reorder emits `.moved` not `matched`:
   ```swift
   @Test("reorder with inferred moves emits moved operations")
   func reorderEmitsMoves() {
     let a = ChildDescriptor(identity: testIdentity("Root", "ID[0]"),
                             typeIdentity: "view:Row", explicitID: "ID[0]")
     let b = ChildDescriptor(identity: testIdentity("Root", "ID[1]"),
                             typeIdentity: "view:Row", explicitID: "ID[1]")
     #expect(diffChildren(old: [a, b], new: [b, a])
       .contains(.moved(oldIndex: 1, newIndex: 0)))
   }
   ```
2. Pure insertions / pure removals still work. (Update the existing
   `insertionsAndRemovalsAreEmitted` test.)
3. Snapshot test: feed a real `ForEach` reorder through `ViewGraph` and
   assert `removeSubtree` is not called. Catches the regression where we
   accidentally start tearing down reordered rows.

---

### 3. Consolidate or inline `applyStructuralChildDiff`

> **Status:** ✅ **Landed in `6698483`** — documented-fence variant
> (Option A light). Added a 35-line doc comment explaining what each
> `ChildDiffOp` case means for the reconciler, why `.matched` / `.moved`
> / `.inserted` are intentionally no-ops here, and where they're
> actually handled in `finishEvaluation` / `recordReusedSubtree`.
> Option B (delete `StructuralDiff.swift`) was ruled out once Item 2
> shipped with the diff function intact. The full consolidation
> (Option A) remains available as a future refactor if the split-brain
> becomes painful.

**File:** `Sources/Core/Graph/ViewGraph.swift:725-745`
**Size:** small (inline) or medium (consolidate).

Today this function computes a full diff, then ignores two thirds of it:

```swift
private func applyStructuralChildDiff(for node: ViewNode, resolved: ResolvedNode) {
  let operations = diffChildren(
    old: node.childDescriptors,
    new: resolved.children.map(ChildDescriptor.init)
  )

  for operation in operations {
    guard case .removed(let oldIndex) = operation,
      node.children.indices.contains(oldIndex)
    else {
      continue
    }
    removeSubtree(rootedAt: node.children[oldIndex])
  }
}
```

`.matched` and `.inserted` are handled implicitly through the resolve path
(a matched descriptor reuses via snapshot, an inserted descriptor creates a
fresh `ViewNode`). Only `.removed` gets explicit handling here.

This is a genuine split-brain: reconciliation lives in two places (resolve
path for matches/inserts, `applyStructuralChildDiff` for removes) and you
have to hold both in your head to understand what `ViewGraph` does on a
structural change.

**Two options, not combinable:**

**Option A — centralize in a reconciler:** make the reconciler handle all
three ops. Walk the old child list against the new resolved children; for
matches, copy the existing `ViewNode`; for inserts, spawn a fresh one; for
removes, tear down. The resolve path stops trying to do its own
reconciliation. This is the "right" architecture but requires carefully
preserving the snapshot-reuse behavior that currently lives in
`ViewFoundation.swift:273-288`.

**Option B — inline the removal:** delete `applyStructuralChildDiff` and
`StructuralDiff.swift` entirely. During `finishEvaluation`, tear down old
children that aren't in the new resolved children inline:

```swift
let newIdentities = Set(resolved.children.map(\.identity))
for oldChild in node.children where !newIdentities.contains(oldChild.identity) {
  removeSubtree(rootedAt: oldChild)
}
```

5 lines, inline, obviously correct.

**Compatibility note:** Option B is **incompatible with item 2**, which
wants to keep and improve `diffChildren`. If you're doing item 2, do **not**
do Option B. Instead, document `applyStructuralChildDiff` with a comment
explaining why it discards most of the diff output, and revisit Option A
later if the split-brain becomes painful.

**Recommendation:** Option B iff item 2 isn't going to happen this quarter.
Otherwise, leave `applyStructuralChildDiff` alone and add an explanatory
comment.

---

### 4. Kill the stringly-typed `typeIdentity` on `ChildDescriptor`

> **Status:** ✅ **Infrastructure landed in `4ae4f5f`** — `ResolvedNode`
> and `ChildDescriptor` gained an optional
> `typeDiscriminator: ObjectIdentifier?` field. `ChildDescriptor.==`
> uses the refined rule: equal if identity + explicitID + typeIdentity
> match AND (both discriminators match or at least one is nil).
> `ChildDescriptor.hash` deliberately omits the discriminator so
> bridging-equal descriptors hash the same. `Text` migrated as a
> demonstration call site (`ObjectIdentifier(Text.self)`). Design
> pivot from the original sketch: `NodeKind.view(String)` is unchanged
> — no pattern-match breakage, no `StaticString`-from-runtime-`String`
> problem. 7 new `ChildDescriptorTests`. The remaining ~46 call sites
> stay on the legacy path and can migrate incrementally.
>
> **Surprise during the landing:** the first full-suite run segfaulted
> in `PrototypeUIComponentsTests`. Root cause was stale build artifacts
> — the test binary was linked against the pre-change `ResolvedNode`
> layout and crashed when it loaded my new module. `swift package clean
> && swift test` resolved it. Worth remembering: SwiftPM's incremental
> rebuild doesn't always catch struct-layout changes in dependent
> targets.

**File:** `Sources/Core/Graph/ChildDescriptor.swift` (41 LOC today)
**Also touches:** `Sources/Core/EnvironmentAndNodeTypes.swift:98-102`
(`NodeKind`), `Sources/Core/RenderTreeAndSemanticsTypes.swift`, and
~39 call sites that do `kind: .view("SomeName")`.
**Size:** additive field + helper, no call-site changes required if done
carefully. Maybe 80–120 LOC net.

#### Why

`ChildDescriptor` uses `typeIdentity: String` (`ChildDescriptor.swift:3`)
as the discriminator that distinguishes "same slot, different view type"
(tear down) from "same slot, same view type" (reuse). Today that string
is built by reading `ResolvedNode.kind` (`ChildDescriptor.swift:16-28`)
which is `NodeKind.view(String)` — a stringly-typed enum case.

Problems:

1. **Hashing cost.** Every child-diff call hashes and compares arbitrary
   strings. For a ForEach over 10k rows, that's 10k string hashes per frame.
2. **Debug/production coupling.** The "type" identifier is used for both
   semantic discrimination (diff decides whether to reuse) AND debug
   display. One of those needs to be fast and stable; the other wants to be
   human-readable. They should be separate fields.
3. **Collision risk.** Two views from different modules sharing a name
   (`.view("Text")`) are indistinguishable. Unlikely in practice, but it's
   the kind of footgun that bites exactly when you're debugging something
   unrelated.
4. **Lost compile-time safety.** A typo in `kind: .view("Tetx")` compiles
   fine and silently produces a view that never reuses with its siblings.

#### Why `s/String/ObjectIdentifier/` doesn't work

`grep 'kind: \.view("' Sources/View/` returns 39 hits, and some of them
are **modifier role names that don't correspond to a Swift type**, e.g.:

```
Sources/View/Modifiers/ViewModifiers.swift:649:   kind: .view("Padding"),
Sources/View/Modifiers/ViewModifiers.swift:686:   kind: .view("Frame"),
Sources/View/Modifiers/ViewModifiers.swift:720:   kind: .view("Offset"),
```

These are synthesized inside generic modifier resolve code. There isn't a
single `Padding` view type whose `.self` you can grab — the same string is
produced by multiple `ModifiedContent<_, PaddingModifier>`-like
specializations. A naive s/String/ObjectIdentifier/ can't work.

#### Sketch — additive field, no big call-site churn

Add an opaque, stable, hashable discriminator to `NodeKind` alongside the
display string:

```swift
// Sources/Core/EnvironmentAndNodeTypes.swift
public struct NodeKindDiscriminator: Hashable, Sendable {
  fileprivate let storage: Storage
  fileprivate enum Storage: Hashable {
    case type(ObjectIdentifier)
    case role(StaticString)
  }

  public static func type<T>(_: T.Type) -> Self {
    .init(storage: .type(ObjectIdentifier(T.self)))
  }

  public static func role(_ name: StaticString) -> Self {
    .init(storage: .role(name))
  }
}

public enum NodeKind: Equatable, Sendable {
  case root
  case scene(String)
  case view(String, NodeKindDiscriminator)

  // Bridging static func so the 39 call sites don't all have to change
  // at once — defaulting to a stringly-typed discriminator during the
  // transition.
  public static func view(_ name: String) -> Self {
    .view(name, .role(StaticString(stringLiteral: name)))
  }
}
```

Then update `ChildDescriptor`:

```swift
package struct ChildDescriptor: Equatable, Hashable, Sendable {
  package var identity: Identity
  package var typeDiscriminator: NodeKindDiscriminator
  package var explicitID: String?

  package var typeIdentity: String { /* derived for debug only */ … }
}
```

Migrate call sites incrementally from `kind: .view("Padding")` to
`kind: .view("Padding", .role("Padding"))` or
`kind: .view("Text", .type(Text.self))`.

#### What this buys

- `ChildDescriptor` hashing becomes "hash two `ObjectIdentifier`s and maybe
  a short String for `explicitID`" — cheap int-sized ops.
- Wrong-type reuse is impossible for real views, because
  `ObjectIdentifier(Text.self) != ObjectIdentifier(CustomText.self)` even
  when display names collide.
- Debug strings remain for `Snapshots.swift:195` and friends.
- The role-name case keeps modifiers working. You lose compile-time safety
  on modifier roles (~5 sites like "Padding", "Frame"), but those are
  centrally managed.

#### Risks

- **Blast radius bigger than item 2.** Every `.view("Name")` is touched
  eventually — not for the initial landing, but for the full migration.
  The bridging static func means the migration can be drip-fed.
- **`ResolvedNode.kind` is public API**
  (`RenderTreeAndSemanticsTypes.swift:178`). Adding an associated value
  to `NodeKind.view` is source-breaking. The bridging static func keeps
  call sites compiling but test code that pattern-matches
  `case .view(let name)` will need to become `case .view(let name, _)`.
  Check `Tests/` for exhaustive switches.
- **`NodeKind: Equatable`.** Two `.view(name, disc)` cases with the same
  name but different discriminators should be `!=`. Verify the derived
  `Equatable` does the right thing (it does, because all associated values
  participate).

#### Tests to add

1. `ChildDescriptor` inequality when two descriptors have the same identity
   and explicit ID but different `typeDiscriminator`.
2. Regression: a `_ConditionalView<Text, Color>` flipping cases at the same
   identity path must produce a `.removed` op for the old subtree. Run
   against both old and new implementations to prove behavior is preserved.
3. Perf-y: measure child-diff throughput on a 10k-row ForEach before/after.
   The win should show up as a reduction in per-frame string hashing cost.

---

## Section 2 — Focused refactors

Medium-cost changes. Each requires understanding a subsystem end-to-end and
will touch multiple files, but the scope is contained.

### 5. ~~Make `ResolvedNode` truly immutable; kill `Boxed<DrawMetadata>`~~ **RETRACTED**

This item was based on two misdiagnoses. Keeping the section (with a
strike-through) so cross-references still resolve; do not execute it.

#### What the original item claimed

1. **Problem A:** `didSet` on `ResolvedNode.children`
   (`RenderTreeAndSemanticsTypes.swift:179-184`) creates O(n²) cost when
   children are appended incrementally.
2. **Problem B:** `Boxed<DrawMetadata>` on
   `ResolvedNode._boxedDrawMetadata` is a "type-system lie" that breaks
   value semantics via reference aliasing.

#### Why both claims are wrong

**On Problem B — the misdiagnosis:** I wrote that `Boxed` is "a
reference cell sitting inside a value-semantic struct" that breaks
`Equatable`. That is wrong. Look at `Sources/Core/Boxed.swift:11-33`:

```swift
package struct Boxed<Value: Equatable>: Equatable {
  private var _storage: _BoxStorage<Value>

  package var value: Value {
    _read { yield unsafe _storage.value }
    _modify {
      if !isKnownUniquelyReferenced(&_storage) {
        _storage = unsafe _BoxStorage(_storage.value)
      }
      yield unsafe &_storage.value
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    unsafe lhs._storage === rhs._storage || lhs._storage.value == rhs._storage.value
  }
}
```

`Boxed` is a **proper copy-on-write wrapper** — exactly the pattern
Swift's stdlib collections use. `_modify` checks
`isKnownUniquelyReferenced` and allocates fresh storage on shared
mutation. `==` falls back to value equality when storage references
differ. Value semantics are preserved correctly. **There is no aliasing
bug.**

The docstring on `Boxed.swift:1-5` is explicit: *"Use this to store
value types that exceed ~200 bytes inline inside other value types. The
box reduces inline size to a single pointer (8 bytes) while preserving
value semantics through COW."* `DrawMetadata` is genuinely large
(contains a nested `Boxed<HeavyFields>` plus `clipsToBounds`,
`clipIdentifier`, `compositingHint`, `imagePreference`, `ruleStackAxis`
— roughly 50-60 bytes). Embedding it unboxed in every `ResolvedNode`
would meaningfully bloat inline footprint. **Removing the box would be
a size regression, not a fix.**

**On Problem A — the landmine that isn't stepped on:** Every post-init
mutation of `ResolvedNode.children` in `Sources/` is a **bulk
reassignment**, not an incremental append. I grepped:

| Site | Pattern |
|---|---|
| `AnimationController.swift:756` | `node.children = children` after for-loop builds array |
| `AnimationController.swift:791` | `node.children = children` after collecting injections |
| `AnimationController.swift:805` | `node.children = node.children.map { … }` |
| `MenuRendering.swift:80` | `disabled.children = disabled.children.map(disablingFocus)` |

Each assignment fires `didSet` exactly once per node, doing O(direct
children) work — **linear in tree size, not quadratic**. The quadratic
cost I described would only bite a hypothetical future caller doing
`for child in … { node.children.append(child) }`, which no current code
does.

Killing the `didSet` is still defensible as a guard-against-landmine
refactor, but the justification is weaker than the original write-up
implied, and it costs more than "small-medium":

- `ResolvedNode` has ~14 fields. Making `children` a `let` forces
  animation-controller mutation sites to either reconstruct full nodes
  or use a `withChildren(_:)` builder, both of which are noisier than
  the current `node.children = …`.
- Keeping `children` mutable but dropping `didSet` silently breaks
  `preferenceValues` / `subtreeNodeCount` / `supportsRetainedReuse`
  invariants — worse than the original design.
- Making derived state computed-on-read degrades O(1) access to
  O(subtree) at the root (each recursive access re-walks children).

#### What this means for Item 6

The original Item 6 claimed it depends on Item 5 because "`ResolvedNode`
must be truly immutable or the composed type will inherit `Boxed`'s
bugs." Since `Boxed` has no bugs, **Item 6 no longer depends on Item
5**. The real prerequisite for Item 6 is the mutation-site audit above,
which is now done.

#### What this means for Item 9

Same story. Item 9's dependency on "items 5, 6" becomes just "item 6."

#### If you ever want to revisit this

The only defensible piece of the original item is the defensive
killing of `didSet`. If a future caller starts doing incremental
appends, reconsider then — not now. And if you do, the right scope is
*just the `didSet`*, not the `Boxed` wrapper, which should stay.

---

### 6. Make `ViewNode` contain `ResolvedNode`, don't duplicate its fields

> **Status:** ✅ **Landed in `d8d0a80`** — 14 scattered mirror fields
> collapsed into a single stored `committed: ResolvedNode`, with
> computed forwarding accessors in an extension at the bottom of the
> file so every external reader (`node.kind`, `node.lifecycleMetadata`,
> etc.) keeps the exact same API. `cachedResolvedNode: ResolvedNode?`
> (which muxed "have I been committed" and "is subtree snapshot fresh"
> into one nullable) collapsed into a single `isCommittedSnapshotFresh:
> Bool` flag. `apply(resolved:children:)` shrank from 15 lines of
> field-by-field copying to a single `committed = resolved`.
> `childDescriptors` became a computed property derived from
> `committed.children.map(ChildDescriptor.init)`. Audit of the
> committed fields' external read surface (done before touching code)
> found only `lifecycleMetadata` (15 hits in `ViewGraph`) and
> `childDescriptors` (1 hit); no external writes to any mirror field.
> Full suite green on first attempt after clean build.

**Files:** `Sources/Core/Graph/ViewNode.swift:1-320`,
`Sources/Core/RenderTreeAndSemanticsTypes.swift:176-244`
**Size:** medium. No hard dependencies (Item 5 was retracted — see
above — so this no longer depends on it).

`ResolvedNode` and `ViewNode` are parallel representations of the same
tree. Both carry: `identity`, `kind`, `environmentSnapshot`,
`transactionSnapshot`, `layoutBehavior`, `layoutMetadata`, `drawMetadata`,
`semanticMetadata`, `lifecycleMetadata`, `drawPayload`, `intrinsicSize`,
`indexedChildSource`, `preferenceValues`, `supportsRetainedReuse`.

`ViewNode.commit(resolved:children:)` (`ViewNode.swift:291-306`) copies
every field one by one:

```swift
resolvedIdentity = resolved.identity
kind = resolved.kind
environmentSnapshot = resolved.environmentSnapshot
transactionSnapshot = resolved.transactionSnapshot
layoutBehavior = resolved.layoutBehavior
layoutMetadata = resolved.layoutMetadata
drawMetadata = resolved.drawMetadata
semanticMetadata = resolved.semanticMetadata
lifecycleMetadata = resolved.lifecycleMetadata
drawPayload = resolved.drawPayload
intrinsicSize = resolved.intrinsicSize
indexedChildSource = resolved.indexedChildSource
preferenceValues = resolved.preferenceValues
supportsRetainedReuse = resolved.supportsRetainedReuse
childDescriptors = resolved.children.map(ChildDescriptor.init)
```

The only things genuinely unique to `ViewNode` are the mutable tracking
state: `stateSlots`, `dependencies`, `dependencyTracker`, frame-tracking
flags, `registeredHandlers`, `evaluator`, `isDirty`, `children: [ViewNode]`.
Everything else is a cached copy of the last committed `ResolvedNode`.

#### Proposal

```swift
@MainActor
package final class ViewNode {
  package let identity: Identity
  package var committed: ResolvedNode          // replaces ~14 mirror fields
  package var children: [ViewNode]
  package var tracking: ViewNodeTracking       // see item 8
  package var dependencies: DependencySet
  package var stateSlots: [Int: AnyStateSlot]
  package var registeredHandlers: NodeHandlers
  package var isDirty: Bool
  package var evaluator: (@MainActor () -> Void)?
  package weak var ownerGraph: ViewGraph?
  package weak var parent: ViewNode?
}
```

Accessors for `kind`, `drawPayload`, `layoutMetadata`, etc. forward to
`committed`. `commit(resolved:children:)` becomes:

```swift
package func commit(resolved: ResolvedNode, children: [ViewNode]) {
  self.committed = resolved
  self.children = children
  // … parent wiring, dependency reindex …
}
```

#### What this buys

- Removes ~15 lines of field-copy boilerplate from `commit`
- Eliminates the possibility of the mirror drifting from the source
  (today nothing enforces that `ViewNode.kind == cachedResolvedNode?.kind`)
- `invalidateAncestorCachedSnapshots` (called at `ViewNode.swift:314`) may
  become unnecessary — the committed snapshot **is** the cache
- Snapshot reuse can hash/compare a `ViewNode` by its `committed`
  `ResolvedNode` with no separate comparison path

#### Risks

- **`ResolvedNode` must be audited for post-init mutation.** `Boxed<_>`
  members are COW-safe (see Item 5 retraction), so value semantics
  work correctly — but this refactor still needs to verify no caller
  mutates a `ViewNode.committed` field through an unexpected path.
  The mutation-site audit from the Item 5 investigation is the
  prerequisite; it's already done and documented above.
- **Accessor forwarding may churn call sites.** Every `viewNode.kind`
  read works unchanged because of Swift property forwarding via stored
  property, but any code doing `viewNode.layoutMetadata = newValue` (i.e.,
  writing through a committed field) breaks. Audit first.
- **`childDescriptors` is derived.** Today it's stored on `ViewNode` and
  set in `commit`. After the refactor, it can become a computed property:
  `committed.children.map(ChildDescriptor.init)`. Cheap for small arrays,
  but hot-path-sensitive — consider caching if profiling says so.

---

### 7. Investigate `registrationAliasesByIdentity` (don't delete it yet)

> **Status:** 🔎 **Instrumented in `fdeaa3c`** — `RegistrationAliasDiagnostics`
> struct landed on `ViewGraph` and is wired through
> `recordRegistrationAlias`. Full characterization suite
> (`RegistrationAliasFindingsTests`, 10 tests) drives `DefaultRenderer`
> over representative view shapes and pins the observed divergence
> counts. The findings contradicted the original hypothesis and are
> documented in detail in the "Findings from the instrumentation"
> subsection below. **Bottom line:** the alias layer's workload is
> tiny (2–5 calls per realistic frame, driven almost exclusively by
> the `.id(_:)` modifier via `IDView`), the original "`IdentityTransparent`
> marker protocol" fix would have had zero effect, and the
> recommendation is to leave the alias layer in place and use the
> diagnostics as a tripwire. A code refactor remains available as
> path 2 in the Findings section if a motivation ever surfaces.

**Files:** `Sources/Core/Graph/ViewGraph.swift:30-31, 147-171, 627-650, 785-791`,
`Sources/View/Foundation/ViewFoundation.swift:110-134`
**Size:** uncertain. Could be small if the hypothesis holds; could be a
multi-week rework if the alias layer is defending against cases not yet
reproduced.

#### Honesty note

This was originally billed as a "cheap win." After reading more of the
code, it's not cheap. Treat this section as a **research task**, not a
drop-in refactor. If you only have bandwidth for one item in Section 2,
**skip this one** — do item 6 first.

#### What the alias layer is

`ViewGraph.swift:30-31`:

```swift
private var registrationAliasesByIdentity: [Identity: Set<Identity>]
private var registrationAliasTargets: [Identity: Identity]
```

`recordRegistrationAlias(from:to:)` (`ViewGraph.swift:147-171`) records a
many-to-one mapping: multiple "requested" identities can all point at the
same "resolved" identity. `restoreRuntimeRegistrations(for:)`
(`ViewGraph.swift:627-650`) uses it to look up runtime registrations
(`onAppear`, `task`, env observations) keyed by the alias identity when
visiting a resolved node.

The single call site that populates it is `ViewFoundation.swift:110-134`:

```swift
if context.viewGraph != nil {
  let resolvedNode = resolveView(view, in: childContext)
  context.viewGraph?.recordRegistrationAlias(
    from: childContext.identity,
    to: resolvedNode.identity
  )
  if resolvedNode.identity == childContext.identity,
    resolvedNode.kind == .view("EmptyView")
  {
    return
  }
  if resolvedNode.identity == childContext.identity,
    resolvedNode.kind == .view("Group")
  {
    resolved.append(contentsOf: resolvedNode.children)
    return
  }
  resolved.append(resolvedNode)
  return
}
```

The alias is recorded **unconditionally**, before the EmptyView/Group
short-circuit. `recordRegistrationAlias` treats equal identities as a
no-op (line 160-166), so when `resolvedNode.identity == childContext.identity`
the alias is effectively free.

#### When does the alias actually carry information?

Only when `resolvedNode.identity != childContext.identity`. Candidate
cases:

1. **`ForEach` inside an `AnyView`.** `ForEach.resolveElements`
   (`Sources/View/Collections/ForEach.swift:22-40`) stamps explicit IDs
   onto each element context via
   `context.identity.explicitID(element[keyPath: id])`. If that runs
   inside an `AnyView` erasure, the outer appender sees a resolved
   identity that ends in `ID[…]` while `childContext.identity` ends in
   `Group[n]`.
2. **Custom `ResolvableView` implementations that rewrite identity.**
   Any view calling `context.replacingIdentity(with:)` in `resolveElements`
   creates the same skew.
3. **`scopedAnyView` interactions.** `scopedAnyView`
   (`ViewFoundation.swift:70-83`) preserves authoring context across
   erasure, which interacts with identity capture in ways not fully
   traced.

If this enumeration is complete, the alias layer is defending against a
specific category of identity-skew that happens when a child's resolved
identity legitimately differs from its context-assigned identity because
the view rewrote the identity path during `resolveElements`. The
question is whether that skew is *necessary* or *accidental*.

#### Hypothesis (not yet verified)

The identity-skew is avoidable by doing the flattening of
`Group` / `EmptyView` / `AnyView` at the **context level**, before
resolving, rather than at the **resolved-node level** after resolving.

If `appendDeclaredChildNodes` detected that the child is a
`Group` / `EmptyView` / `AnyView` wrapper **before calling `resolveView`**,
it could pass the parent's identity context directly to the inner resolve,
and the child would never get a distinct `childContext.identity` in the
first place. The alias table would then be indexing nothing that it
isn't already indexing through the normal identity path.

#### Why it's not obviously safe

1. **Runtime type-check cost.** Detecting "this is a `Group`" before
   resolve requires inspecting the erased view. Today it happens *after*
   resolve by checking `resolvedNode.kind == .view("Group")`. Pushing it
   earlier means either a runtime `is Group<_>` check (hard for generic
   types), a protocol conformance (`protocol IdentityTransparent`), or a
   marker in the type system.
2. **`AnyView` unwrap depth.** `AnyView(AnyView(SomeView()))` needs to
   collapse identities through both layers. Current code doesn't — each
   `AnyView` is a fresh resolve boundary.
3. **The defensive value is real.** If case (2) in the enumeration is
   wrong — if there's a view that legitimately needs a different resolved
   identity from its context identity — removing the alias layer breaks
   `onAppear` / `.task` / environment observation for that case, with no
   test coverage to catch it.

#### What to actually do

**Not** "delete the alias layer." Instead:

1. **Instrument.** Add a debug-only counter that increments every time
   `recordRegistrationAlias` is called with `from != to`. Run the full
   test suite and every example in `Examples/`. Report the non-trivial
   alias call frequency. **✅ Done — see Findings below.**
2. **Log the divergence.** For each non-trivial alias, print
   `(fromIdentity, toIdentity, viewType)` so you can see which views
   trigger the skew. This is the most valuable output — it tells you
   exactly which views need identity-transparent handling.
   **✅ Done — see Findings below.**
3. **Add characterization tests.** Write tests that exercise each observed
   divergence case, asserting the current behavior (`onAppear` fires,
   environment values propagate, etc.). These tests become the safety
   net for any refactor. **✅ Partially done — count-pinning tests
   landed; behavioral characterizations (onAppear etc.) still pending
   if a refactor is attempted.**
4. **Then and only then**, evaluate whether flattening at the context
   level can replace the alias layer. The answer might legitimately be
   "no, keep the alias layer but document what it's defending against."
   **✅ Done — see Findings below.**

#### Findings from the instrumentation

`RegistrationAliasDiagnostics`
(`Sources/Core/Graph/RegistrationAliasDiagnostics.swift`) tracks every
non-trivial alias call on every `ViewGraph`.  A
`RegistrationAliasFindingsTests` suite in `Tests/TerminalUITests/`
drives `DefaultRenderer` over 10 view-shape scenarios and pins the
observed divergence counts.

**The original hypothesis was wrong.**  I speculated that `ForEach`
inside `AnyView` would be the main divergence source because of the
explicit-ID stamping in `ForEach.resolveElements`.  It isn't.  Here's
what actually happens:

1. `ForEach.resolveElements` iterates over its data and, for each
   element, creates a child context with the explicit ID and resolves
   the content into that context.  The per-element resolves happen
   **directly** (the content closure calls `view.resolveElements(in:
   elementContext)`), bypassing `appendDeclaredChildNodes` entirely.
   So the per-element resolves never touch the alias path.
2. `ForEach.resolveElements` returns the flat list of per-element
   `ResolvedNode`s.  When `resolveView` wraps that list in a
   `ResolvedNode` via `normalizeResolvedElements`
   (`ViewFoundation.swift:235-259`), the multi-element case creates a
   synthetic `Group` node whose identity is the **caller's** context
   identity — not the element identities.  So the outer
   `resolvedNode.identity == childContext.identity` and the alias call
   at `ViewFoundation.swift:112-115` is trivial (`from == to`).
3. Immediately after the trivial alias call, the Group short-circuit
   at `ViewFoundation.swift:121-126` flattens `resolvedNode.children`
   into the parent's resolved array, inlining the per-element
   explicit-ID nodes without ever passing them back through
   `appendDeclaredChildNodes`.  So the explicit-ID identities never
   get a chance to trigger an alias recording either.

The net effect: **standard composition primitives (VStack, HStack,
Group, EmptyView, AnyView, ForEach, `if`, `if-else`) produce ZERO
non-trivial aliases.**  I verified this against 8 separate
characterization scenarios including "realistic composite tree
exercising every control-flow shape in the view builder" — all zero.

**The real divergence source is identity-remapping modifiers.** A
`grep` for `replacingIdentity` across `Sources/View/` turned up
exactly three call sites:

- `IDView.resolveElements`
  (`Sources/View/Modifiers/ViewModifiers.swift:365-377`) — the
  internal type backing `.id(_:)`.  Calls `content.resolve(in:
  context.replacingIdentity(with: identity))` and returns the
  single-element result.  `normalizeResolvedElements` with count == 1
  passes the element through unchanged, so the outer resolved node
  has the replaced identity while `childContext.identity` is still
  the positional path.  **This is the only common view API that
  triggers the alias path.**
- `PointerRouteView.resolveElements`
  (`Sources/View/Controls/SelectionAndValueSupport.swift:717-739`) —
  constructs a `ResolvedNode` with an explicit `identity` argument
  instead of `context.identity`, and has the same divergence pattern
  as `IDView` for the same reasons.  Used internally by pointer
  routing; not directly author-facing.
- `IndexedChildSources`
  (`Sources/View/Collections/IndexedChildSources.swift:60`) —
  replaces identity inside the lazy-child resolution path.  This one
  runs inside an `IndexedChildSource` and goes through a different
  resolve flow; my instrumentation doesn't currently cover it because
  it bypasses `appendDeclaredChildNodes`.

The `.id(_:)` test scenario produces exactly the divergences you'd
expect:

```
nonTrivialCallCount = 2
uniqueDivergenceCount = 2
  [1] Root/VStack[0] → header [view(Text)]
  [1] Root/VStack[2] → trailer [view(Text)]
```

(Only two, even with three additional `.id(_:)` calls inside a nested
`ForEach`, because those inner `.id` uses are absorbed by the same
`Group`-normalization path that eats `ForEach` divergences.)

#### What this means for a potential refactor

The architecture doc's original proposal was a marker protocol
`IdentityTransparent` applied to `Group`/`EmptyView`/`AnyView` to
flatten identity earlier.  The instrumentation shows that proposal
**would have no effect** on the alias layer's workload, because the
`Group`/`EmptyView`/`AnyView` path already produces trivial aliases
today — the normalization wrapper absorbs the divergence.

The real question is: **can `.id(_:)` be rewired to not go through
the alias layer?**  Two paths:

1. **Delete the alias layer and break `.id(_:)`.** Not acceptable;
   `.id(_:)` is a public API and its runtime registrations need to
   route correctly when identity is remapped.
2. **Route `IDView.resolveElements` through a different bridge** that
   doesn't need a global alias table.  For example, `IDView` could
   directly register its runtime handlers against the replaced
   identity inside its `resolveElements`, bypassing
   `recordRegistrationAlias` entirely.  `PointerRouteView` could do
   the same.

Path 2 is doable but scoped more narrowly than the original
"delete the alias layer" proposal.  The alias layer would still exist
to handle any future identity-remapping view, or could be deleted
entirely once `IDView` and `PointerRouteView` are rewired.  Either
way, the decision no longer depends on a broad investigation — the
instrumentation has pinned down exactly where the alias layer earns
its keep.

#### Recommendation after the investigation

**Leave the alias layer in place and move on.**  The instrumentation
revealed the workload is already narrow (2–5 calls per realistic
frame, only from `.id(_:)`) and the complexity budget for a refactor
isn't justified by the payoff.  The `RegistrationAliasDiagnostics`
struct stays in the code as a tripwire — if a future change makes
the alias count balloon, the characterization tests will fail and
surface the regression before it becomes invisible work.

If a refactor is ever attempted, path 2 above (rewire
`IDView.resolveElements` to register runtime handlers directly) is
the narrowest-blast-radius approach.  Don't delete
`registrationAliasesByIdentity` without rewiring the `.id(_:)` path
first.

#### A proper fix, IF instrumentation shows the alias layer is always papering over flattening that could happen earlier

```swift
@MainActor
package protocol IdentityTransparent {}

extension Group: IdentityTransparent {}
extension EmptyView: IdentityTransparent {}
extension AnyView: IdentityTransparent {}
```

Then in `appendDeclaredChildNodes`:

```swift
if let transparent = view as? any IdentityTransparent {
  // Reuse the parent's identity context — the transparent view contributes
  // no identity of its own.
  let elements = resolveViewElements(view, in: context)
  resolved.append(contentsOf: elements)
  return
}
// ... existing path for non-transparent views
```

And delete `registrationAliasesByIdentity`, `registrationAliasTargets`,
`recordRegistrationAlias`, and the alias iteration in
`restoreRuntimeRegistrations`.

**Do not do this without the instrumentation step above.** The alias
layer has the distinct smell of "added to fix a subtle bug that nobody
wrote a test for."

#### Tests to add (independent of whether the refactor ever lands)

1. One test per observed divergence case from the instrumentation step.
2. `onAppear` fires for a view inside `AnyView(ForEach(...))`.
3. `@Environment` propagates correctly through `AnyView(Group { ... })`.
4. `.task { ... }` on a view inside a transparent wrapper is cancelled
   when the wrapper disappears.

These tests are valuable **regardless** of whether the alias layer is
ever deleted — they pin down behavior the current code only implicitly
guarantees.

---

## Section 3 — Structural changes

Large-cost items. Each requires profiling or instrumentation to justify,
and each is worth doing only if a specific pain point motivates it. None
of these should be started "just because."

### 8. Decompose `ViewGraph` into responsibility-focused types

> **Status:** ⏸ **Deferred.** No concrete testability pain point has
> surfaced yet that would justify the multi-PR rework. The current
> integration-test coverage is sufficient for correctness; the
> decomposition's stated payoff is "unit-testable invalidation
> frontier" which nobody has asked for.

**File:** `Sources/Core/Graph/ViewGraph.swift` (1069 lines)
**Size:** large. Multi-PR refactor.

`ViewGraph` is doing four distinct jobs:

1. **Registry:** `nodesByIdentity`, `nodeForIdentity(_:)`, alias table
   (`ViewGraph.swift:16, 670-681, 147-171`)
2. **Invalidation tracking:** `invalidatedIdentities`,
   `graphLocalDirtyIdentities`, `stateSlotDependents`, `environmentDependents`,
   `observableDependents`, `selectiveDirtyEvaluationPlan`, `dirtyFrontierNodes`
   (lines 27-36, 173-220, 683-723, 795-855)
3. **Lifecycle event collection:** `viewportLifecycleNodesByIdentity`,
   `structuralAppearEvents`, `structuralDisappearEvents`,
   `stableTaskCancelEvents`, `latestLifecycleEvents` (lines 19-29)
4. **Structural reconciliation:** `applyStructuralChildDiff`, `removeSubtree`
   (lines 725-793)

**Proposal:** extract four types with explicit collaboration:

```swift
package final class NodeRegistry            // identity ↔ ViewNode, alias table
package final class InvalidationTracker     // dirty set, dependency indices
package final class LifecycleEventLog       // per-frame event collection
package final class StructuralReconciler    // diff application, subtree teardown

package final class ViewGraph {
  let registry: NodeRegistry
  let invalidation: InvalidationTracker
  let lifecycle: LifecycleEventLog
  let reconciler: StructuralReconciler
  // thin orchestration layer
}
```

Each subsystem becomes independently testable. Today, invalidation frontier
logic can only be tested through full integration snapshots; after the
refactor, `InvalidationTracker` can be unit-tested with synthetic
dependency sets.

#### Risks

- **Real coupling between responsibilities.** `removeSubtree`
  (`ViewGraph.swift:747-793`) touches `nodesByIdentity`,
  `registrationAliasesByIdentity`, **and** `liveIdentities` simultaneously.
  Splitting means either a callback protocol between the pieces or a
  shared mutable context. Neither is free.
- **Existing tests rely on the current API shape.** Any test that calls
  `viewGraph.foo()` will need a migration path.
- **Mostly aesthetic until you have a test you can't write today.** The
  payoff is "I can write isolated tests for the invalidation frontier
  algorithm." If you don't want that test, don't start this refactor.

#### Do this in service of testing, not aesthetics

If you can't articulate a specific test you want to write but can't
because of the current coupling, postpone this item.

---

### 9. Dependency-aware body re-evaluation

> **Status:** ⏸ **Deferred — profile first.** Body re-evaluation has
> not been shown to be a bottleneck. The snapshot-reuse path at
> `ViewFoundation.swift:273-288` already catches most of the wasted
> work. Item 6 removed the dependency on Item 5, so the only real
> prerequisite is profiling data showing body-eval as the hot path.
> Don't start without numbers.

**Files:** `Sources/Core/Graph/ViewGraph.swift:227-245`,
`Sources/View/Foundation/ViewFoundation.swift:85-134, 262-334`
**Size:** large, with real design questions.

The repo already tracks which identities read which state slots,
environment keys, and observables (`ViewGraph.swift:32-34`,
`DependencyTracker.swift:1-25`). When a state slot changes,
`queueDirtyForStateChange(_:)` (`ViewGraph.swift:101-105`) marks only the
readers dirty. Good.

But re-evaluation is still all-or-nothing at the **body** granularity.
When a frontier node is dirty, `evaluateDirtyNodes` calls
`nodesByIdentity[identity]?.evaluate()`, which runs the view's entire body
closure. If the body is `VStack { A(); B(); C() }` and only `B` reads the
changed slot, you still construct contexts for `A` and `C`.
`reusableSnapshot()` (`ViewFoundation.swift:273-288`) catches them on the
way in, but you've already paid:

- Running the ViewBuilder macro-expanded code
- Constructing `ResolveContext` instances for each child
- Identity-path construction for each child
- The snapshot-equivalence check itself

#### Proposal

During re-evaluation of a dirty parent, consult the per-child dependency
set. If the child's **transitive** read-set is disjoint from the dirty-slot
set, skip it before calling `resolveView`. Add a field to `ViewNode`:

```swift
package var transitiveDependencies: DependencySet   // union of own + descendants
```

updated lazily during `finishEvaluation`. Then `appendDeclaredChildNodes`
checks before calling `resolveView`:

```swift
if let priorChild = parentNode.child(matching: childContext.identity),
   priorChild.transitiveDependencies.isDisjoint(
     fromDirty: context.effectiveInvalidatedIdentities
   )
{
  resolved.append(priorChild.committed)
  return
}
```

This is a strict superset of `reusableSnapshot` — same idea, but the check
happens one level earlier, before any resolve-context construction.

#### Risks

- **Transitive dependency maintenance is the hard part.** Dependencies
  are union-up on evaluation, but they only *grow* during a given
  evaluation; **shrinking** (because a view stopped reading a slot)
  requires subtracting that view's contribution from all ancestors.
  That's expensive unless you track per-child contributions explicitly.
- **Over-invalidation is possible.** If the transitive set is an
  over-approximation, you'll correctly re-evaluate too often but never
  incorrectly skip. If it's an under-approximation, you'll skip views
  that should re-evaluate. The set must be an over-approximation by
  construction — verify this with property-based tests.
- **Only worth it if body-evaluation is the bottleneck.** Profile first.
  If the hot cost is layout or rasterization, this change is a wash.

---

### 10. Thread animation & authoring context through `ResolveContext`, not global task-local

> **Status:** ⏸ **Deferred.** Blocked on either a concurrency wall
> (off-main-thread rendering demand) or a testability wall (tests
> leaking context). Neither has been hit. The dynamic-property
> ergonomics concern (property wrappers would need a different
> mechanism) remains the main blocker if it does become needed.

**Files:** `Sources/View/State/State.swift:11-90`,
`Sources/Core/AnimationContextStorage.swift`, dozens of call sites
**Size:** large.

Two global task-locals today:

- `AuthoringContextStorage.current: @TaskLocal AuthoringContext?`
  (`Sources/View/State/State.swift:11-13`)
- `AnimationContextStorage.currentRequest` (inferred from
  `ViewNode.swift:189` usage)

Both are @MainActor-scoped. `withAuthoringContext` (`State.swift:72-90`)
sets and clears; callers must remember to wrap.

#### Problems

1. **Couples the whole system to @MainActor.** If you ever want to
   render to an offscreen buffer on a background actor (differential
   testing, background rendering, headless CI snapshots), every
   `withAuthoringContext` call fights you.
2. **Re-entrancy and testing are brittle.** A test that wants to evaluate
   a view without an authoring context has to remember to clear the
   task-local. A test that evaluates two views in sequence can leak
   context between them if a code path forgets `withValue` wrapping.
3. **No static place to find "which things read the authoring context."**
   `currentAuthoringContext()` is called from a dozen places; only
   dynamic tracing tells you the full set.

#### Proposal

Put `authoringContext` and `animationRequest` as explicit fields on
`ResolveContext`. Code that needs them reads from the context parameter;
code that doesn't, doesn't. `withAuthoringContext` becomes
`context.with(authoringContext:)` returning a new context.

#### Risks

- **Dynamic-property ergonomics.** `@State`, `@Environment`, `@Observable`
  expect to call `currentAuthoringContext()` from their `init` or
  `update` without a context parameter. Moving those to explicit
  context threading means property wrappers need a different mechanism
  (e.g., a registration closure that fires during body evaluation,
  receiving the context). This is the main blocker.
- **Call-site churn is pervasive.** Every code path that touches
  authoring context is affected.
- **Only worth it if you hit the concurrency wall or the testability
  wall.** If you haven't, this is premature.

---

### 11. `Identity` interning (hash-cons)

> **Status:** ⏸ **Deferred — profile first.** No identity hashing /
> allocation bottleneck has been measured. The Item 4 typed
> discriminator already reduced per-child-diff hashing cost somewhat,
> so the baseline is better than when this item was first written.
> Do not start without profiling data showing identity as the
> bottleneck on a realistic workload (10k+ nodes).

**File:** `Sources/Core/GeometryTypes.swift:425-498`
**Size:** large, with subtle correctness implications.

```swift
public struct Identity: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
  public let components: [String]
  // …
  public func child(_ component: String) -> Self {
    Self(components: components + [component])
  }
}
```

Every child identity allocates a new `[String]` — O(depth) per child,
O(depth × fanout) per node creation pass. Every hash walks the array.
Every `==` walks the array and compares each string.

For a 10-node tree nobody cares. For a 10k-row `ForEach` inside a scroll
view that resolves on demand, this adds up.

#### Proposal

Hash-cons the identity paths. An `IdentityInterner` maintains a trie of
seen components → canonical ID:

```swift
public struct Identity: Hashable, Sendable {
  private let internedID: UInt64
  // path reconstruction via interner lookup for debug/codable
}
```

Equality becomes `UInt64 ==`. Hashing becomes `UInt64.hash`. Child creation
allocates one trie node, not an array of strings. Debug representation
walks the trie backwards (slow, but only in error paths).

#### Risks

1. **`Identity: Codable`.** The interned form isn't stable across runs,
   so codable representations need to serialize the component list, not
   the interned ID. This is a footgun if you're not careful — snapshot
   tests may embed identities in their golden files.
2. **Shared mutable state.** An `IdentityInterner` is by definition
   shared mutable state. Either make it `Sendable` with a lock (hurts
   throughput) or make it per-`ViewGraph` (which works, since the graph
   already owns node identity across frames).
3. **Unbounded growth.** The interner grows unless you evict unused
   entries. Eviction tied to `removeSubtree` is doable but adds coupling.
4. **Arbitrary user content.** `Identity.explicitID(id:)`
   (`GeometryTypes.swift:465`) uses `String(reflecting: id)`, which is
   essentially arbitrary. Interning it is fine, but your trie branching
   factor can be huge.

#### Do not do this without profiling

It's a real improvement for large trees, but "large trees" is a specific
workload — if the target apps don't have 1000+-node bodies, it won't
move the needle. Instrument first.

---

## Priority ranking

Ordered by rough clarity-per-unit-of-work. Ordering dependencies are noted.

| # | Item | Cost | Depends on | Why |
|---|------|------|------------|-----|
| 1 | MeasurementCache eviction | Small | — | Real bug, 10-line fix. ✅ Landed in `24ada3d`. |
| 2 | CollectionDifference diff | Small | — | Smallest blast radius among the diff items. Unblocks future move-animation work. ✅ Landed in `c077679`. |
| 3 | Consolidate `applyStructuralChildDiff` | Small | — | Shipped as a documented fence (Option A light), not a full consolidation. ✅ Landed in `6698483`. |
| 4 | `typeDiscriminator` on `ChildDescriptor` | Small-med | ideally after item 2 | Perf + safety win. Infrastructure + `Text` migration. ✅ Landed in `4ae4f5f`. |
| 5 | ~~Immutable `ResolvedNode` + kill `Boxed`~~ | — | — | ❌ **Retracted in `5bea099`.** Based on misdiagnosis of `Boxed<_>` (a proper COW wrapper) and a landmine nobody steps on. See the retraction note in section 5. |
| 6 | `ViewNode` contains `ResolvedNode` | Medium | — | Biggest clarity win. Prerequisite (post-init mutation audit) was already done during Item 5 retraction. ✅ Landed in `d8d0a80`. |
| 7 | Investigate alias layer | Medium (research), large (code) | — | 🔎 Instrumentation landed in `fdeaa3c`; findings disproved the original hypothesis. Code refactor not justified — see Item 7 Findings. |
| 8 | Decompose `ViewGraph` | Large | — | ⏸ Deferred. Only worth it if you want to unit-test invalidation in isolation; no such test request has surfaced. |
| 9 | Dependency-aware re-evaluation | Large | — (Item 6 prerequisite landed) | ⏸ Deferred. Only if profiling shows body re-evaluation as the hot path. |
| 10 | Explicit context threading | Large | — | ⏸ Deferred. Only if you want off-main-thread rendering or hit a testability wall. |
| 11 | `Identity` interning | Large | — | ⏸ Deferred. Only if profiling shows identity string allocation / comparison as a bottleneck. |

### Landing history

Recorded for posterity — this is the order the non-deferred items
actually shipped in, and the lessons learned along the way.

1. ✅ **Item 1** (MeasurementCache stale-entry eviction) —
   `24ada3d`. Small, surgical, cleanest item on the list.
2. ✅ **Item 2** (`CollectionDifference`-based `diffChildren`) —
   `c077679`. Self-contained rewrite with expanded test coverage.
3. ❌ **Item 5** (Immutable `ResolvedNode` + kill `Boxed`) — retracted
   in `5bea099`. Investigation revealed two misdiagnoses in my
   original analysis: `Boxed<_>` is a proper COW wrapper (not a
   type-system lie), and the quadratic construction landmine is
   purely hypothetical (no current caller appends children
   incrementally). The mutation-site audit done during this
   investigation became the actual prerequisite for Item 6.
4. ✅ **Item 4** (`typeDiscriminator` on `ChildDescriptor`) —
   `4ae4f5f`. Design pivoted from the original sketch — the
   architecture doc proposed widening `NodeKind.view` with a nested
   struct, but that would have broken pattern matches at 4 call sites
   and hit a `StaticString`-from-runtime-`String` compile error. The
   actual landing added `typeDiscriminator: ObjectIdentifier?` as a
   parallel field on `ResolvedNode`/`ChildDescriptor`, leaving
   `NodeKind` completely unchanged. Also surfaced a SwiftPM
   stale-artifact gotcha — struct-layout changes can leave the test
   binary ABI-incompatible, `swift package clean` resolves it.
5. ✅ **Item 3** (`applyStructuralChildDiff` split-brain) —
   `6698483`. Doc-comment variant, not the full reconciler
   consolidation. Option B (delete `StructuralDiff.swift`) was
   already off the table after Item 2 shipped with the diff function
   intact.
6. ✅ **Item 6** (`ViewNode` contains `ResolvedNode`) — `d8d0a80`.
   Biggest clarity win in the doc. The mutation-site audit from the
   Item 5 retraction was the real prerequisite. Full suite green on
   first attempt after clean build.
7. 🔎 **Item 7 instrumentation** — `fdeaa3c`. The findings contradicted
   the original hypothesis: standard composition primitives produce
   zero non-trivial aliases; the only real trigger is the `.id(_:)`
   modifier via `IDView`. The proposed `IdentityTransparent` marker
   protocol fix would have had no effect. Recommendation is to leave
   the alias layer in place and use the diagnostics as a tripwire. No
   code refactor scheduled.

**Items 8, 9, 10, 11 remain deferred** — each requires specific
motivation (profiling data, testability wall, concurrency wall) before
it's worth starting.

---

## What NOT to do

- **Don't combine small items in a single PR.** Each of items 1–4 is
  independent and combining them defeats the purpose of making each easy
  to revert.
- **Don't start on item 7 before the other quick wins.** It depends on
  good coverage around identity diffing, and the quick wins incidentally
  produce that coverage.
- **Don't delete `typeIdentity: String` from `ChildDescriptor`** in item 4.
  Keep it as a derived debug-only property. It's used by
  `Snapshots.swift:195` and by test assertions that compare human-readable
  representations.
- **Don't add `ObjectIdentifier` to `NodeKind` as a replacement** for the
  String in item 4. Add it as a parallel field. The String is genuinely
  useful for logging, snapshots, and test failure messages.
- **Don't start item 8 (ViewGraph decomposition) as a pure cleanup.**
  The payoff is testability; if you don't want the tests, don't do the
  refactor.
- **Don't start item 9 (dependency-aware re-eval) without profiling.**
  It's a real improvement but the maintenance cost of transitive
  dependency tracking is significant. Justify it with numbers.
- **Don't start item 10 (explicit context threading) as a
  single-PR refactor.** It touches dozens of call sites and will break
  every property wrapper at once. If you decide to do it, plan for a
  multi-PR migration with a bridging task-local that both old and new
  code paths can read from.
- **Don't start item 11 (identity interning) without profiling.** A
  trie-backed interner is the kind of thing that looks clever and costs
  two weeks.

## Out of scope (deliberately)

Things the review surfaced that are **not** on this list, in case they
come up:

- **Replacing the whole `Identity` substrate with something
  non-stringly-typed** beyond interning. A real win, not cheap — `Identity`
  is `Codable` and used in snapshot goldens, so the migration path is
  long. Item 11 above is the right-sized version of this idea.
- **Teaching `evaluateDirtyNodes` to skip children** whose transitive
  dependency set doesn't intersect the dirty slot set. This is item 9.
- **Adding a static `size` fast path for lazy containers with
  statically known body types.** Interesting but redundant with
  `IndexedChildSource` and friends; probably not worth it.
- **Replacing the closure-based `AnyView` storage** with a protocol
  existential. Saves some closure allocations but loses the context
  preservation that `scopedAnyView` provides. Not a clear win.
- **Making the pipeline stages consume earlier frames' outputs.**
  `Renderer<Root>` (`Sources/Core/Pipeline.swift:16-98`) is a clean
  seven-phase closure composition where each phase only sees its
  immediate input. This is a feature, not a limitation — adding
  cross-frame plumbing would couple the phases. Leave it alone unless a
  specific use case demands it.
