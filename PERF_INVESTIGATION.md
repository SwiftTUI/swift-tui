  ---
  Comprehensive Investigation Results

  Architecture of the Problem

  The rendering pipeline spends 74% of total frame time (112ms avg) in the resolve phase and the remaining time is distributed across measure (17ms), place (11ms),
  raster (6ms), and presentation (2ms). Here are the root causes, ranked by impact:

  ---
  Root Cause 1: recordReusedSubtree() walks the ENTIRE tree — O(n) per frame

  Files: Sources/Core/Graph/ViewGraph.swift:287-352

  When a subtree is identified as reusable (not dirty), recordReusedSubtree() is called on it. This function recursively visits every single node in the subtree to:
  - Call nodeForIdentity() (dictionary lookup)
  - Call node.prepareForFrame()
  - Append to frameOrder
  - Call node.beginReuse()
  - Call applyStructuralChildDiff() (diffs children against previous)
  - Call node.apply() (updates metadata)
  - Check and emit lifecycle events

  With a 132-node tree and only 2 dirty identities, ~130 nodes go through this full bookkeeping path despite having zero changes. This is the single largest
  contributor to the 125ms cost.

  Root Cause 2: reusableSnapshot() conflict checking does O(n) tree searches

  Files: Sources/Core/Graph/ViewGraph.swift:354-428

  Before a node can be reused, reusableSnapshot() (line 390-404) checks whether the node's subtree conflicts with any invalidated identity. For each invalidated
  identity, it calls subtree(snapshot, contains: invalidatedIdentity) — a recursive tree search that walks all descendants. With 2 invalidated identities, every
  candidate reuse node triggers 2 full subtree searches, plus node.snapshot() reconstructs the resolved node tree recursively.

  Root Cause 3: Damage tracking always fails — root identity always invalidated

  Files: Sources/TerminalUI/TerminalUI.swift:245-248, Sources/Core/FocusTracker.swift:402, Sources/Core/StateContainer.swift:28

  The presentationDamage() guard at line 246:
  guard !directlyInvalidated.isEmpty, !directlyInvalidated.contains(rootIdentity) else {
    return nil
  }

  Always returns nil because both FocusTracker and StateContainer have invalidationIdentities: [rootIdentity]. Any focus change or state change invalidates the root
  identity, which is then in directlyInvalidated, hitting the guard's second condition. This means:
  - 100% of frames get damage=full
  - The incremental presentation planner must diff the entire surface cell-by-cell
  - The indexPlacedNodes() full-tree walk at line 251 is never reached, but the nil return prevents any narrowing

  Root Cause 4: Raster surface uses nested [[RasterCell]] arrays

  Files: Sources/Core/Rasterizer.swift:29-32, Sources/Core/RasterTypes.swift

  The rasterizer allocates Array(repeating: Array(repeating: RasterCell.empty, count: width), count: height) — one heap allocation per row. RasterCell is a struct with
   Character, Int, Int?, ResolvedTextStyle?, String?. For the 197-node tree frames, the surface grows significantly and raster jumps from 2ms to 36ms. The surface is
  also a struct that gets copied into FrameArtifacts and lastSubmittedSurface.

  Root Cause 5: Measurement cache hits only 30% — aggressive pruning + low cap

  Files: Sources/Core/LayoutEngine.swift:22, 128-136, 180

  - The per-identity proposal cap is 4 variants (maxProposalVariantsPerIdentity = 4). Gallery views see more than 4 distinct proposal sizes.
  - prune(keeping:) is called every frame and removes ALL identities not in the current live set — scrolled-out items lose their cache immediately with no grace
  period.

  Root Cause 6: RuntimeRegistrationSet.removeSubtrees() does O(handlers × roots × depth) ancestry checks

  Files: Sources/Core/RuntimeRegistrationSet.swift

  Before resolve, removeSubtrees(rootedAt: frontierIdentities) iterates through every registered handler in all 9 registries, calling isDescendant(of:) for each —
  which compares identity component arrays element by element.

  ---
  Impact Summary

  ┌─────────────────────────────┬──────────────────────────────┬──────────────────────────────────────────────────────────────────────┬───────────────────────────┐
  │         Root Cause          │          Est. Time           │                            Fix Complexity                            │          Impact           │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 1. recordReusedSubtree O(n) │ ~60-80ms                     │ Medium — skip reuse recording for clean subtrees                     │ Eliminates majority of    │
  │  walk                       │                              │                                                                      │ resolve cost              │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 2. reusableSnapshot O(n)    │ ~20-30ms                     │ Medium — use identity-set lookup instead of tree walk                │ Eliminates redundant tree │
  │ searches                    │                              │                                                                      │  searches                 │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 3. Damage tracking always   │ ~0ms direct, but causes      │ Low — remove !directlyInvalidated.isEmpty from guard, or stop        │ Enables incremental       │
  │ nil                         │ full-surface diff            │ invalidating root for focus changes                                  │ presentation              │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 4. Nested array raster      │ ~34ms on large trees         │ High — requires flat buffer refactor                                 │ Eliminates raster spikes  │
  │ surface                     │                              │                                                                      │                           │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 5. Cache pruning too        │ ~5-10ms (measure phase)      │ Low — increase cap, add grace period                                 │ Reduces measure phase     │
  │ aggressive                  │                              │                                                                      │                           │
  ├─────────────────────────────┼──────────────────────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────┤
  │ 6. Registry subtree removal │ ~5-10ms                      │ Medium — index by subtree prefix                                     │ Reduces per-frame         │
  │                             │                              │                                                                      │ overhead                  │
  └─────────────────────────────┴──────────────────────────────┴──────────────────────────────────────────────────────────────────────┴───────────────────────────┘

  The resolve phase (#1 + #2) is the critical path. Fixing recordReusedSubtree to skip truly-clean subtrees and replacing the subtree(contains:) linear search with a
  Set lookup would reduce steady-state frame time from ~150ms to an estimated ~20-30ms.