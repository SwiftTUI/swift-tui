# Framework Glossary

This glossary defines shared framework terms for architecture reviews and
design work. Each term describes current code. Add a term when a design
discussion needs it. Improve a definition when it is not clear. Example-app
vocabulary (sextant, gifeditor, git-viz) lives with those apps in
`SwiftTUI/swift-tui-examples`.

For the published, consumer-facing vocabulary of the reuse system, see
[Reuse-and-Invalidation.md](../Sources/SwiftTUIGraph/SwiftTUIGraph.docc/Reuse-and-Invalidation.md);
this file carries the sharper internal contract statements.

## Reconciliation & reuse

- **Committed snapshot** — A `ViewNode` keeps its most recent committed
  `ResolvedNode`. Reuse returns this node instead of evaluating the view body
  again.
- **CommittedFreshness** — This per-node module owns the freshness stamps. The
  stamps are `isCommittedSnapshotFresh`, `hasStaleIslandDescendant`, and
  `hasForeignParentedChild`. The named transitions are `commitApplied`,
  `markDescendantChanged(crossingIslandSeam:)`, `markChildReseated`, and
  `reclaimChildren`. The module also provides the `canServeValueBlind` and
  `canServeMemo` queries. A
  foreign-parented child prevents value-blind reuse but does not prevent memo
  reuse. Value equality gives memo reuse a separate proof of freshness. Code,
  not a comment, defines this difference between the queries.
- **Layer A / retained reuse** — This layer performs value-blind subtree reuse.
  It returns the committed snapshot when the freshness stamps, environment, and
  transaction permit reuse. It does not examine the view value.
- **Memo gate (Layer B)** — This layer provides value-verified reuse for
  `.equatable()` boundaries. It returns the snapshot only when the view values
  are equal. The graph consults this layer after Layer A denies reuse.
- **Reuse door** — `ViewGraph.reuseResolvedSubtree(inputs:viewValue:)` is the
  single interface for reuse. It owns the A→B order, suppression logic, and
  graph acceptance path. It returns `.retained`, `.memoized`, or `nil`. Callers
  keep only the context tallies.
- **ReuseDecisionInputs** — This Graph value contains all data that crosses into
  the reuse door. This data includes identity, invalidation, environment,
  transaction, suppression, subtree churn, and profile flags. The value is
  necessary because the module graph prevents `SwiftTUIGraph` from accessing
  `ResolveContext`.
- **Suppression** — The run loop denies reuse for identities affected by focus
  or press state. The subset invariant is suppresses-value-verified ⊆
  suppresses-retained.
- **Island seam** — This seam is an `evaluationHost` boundary in the node tree.
  The upward staleness walk changes signals at this boundary. Below the seam,
  the walk clears freshness. Above the seam, it sets
  `hasStaleIslandDescendant`. Clearing freshness above the seam can truncate
  snapshot rebuilds.
- **Foreign-parented child** — A node still lists this child, but another parent
  owns the live child. Upward walks cannot reach the original node through this
  child. Thus, the committed snapshot of the original node can become stale.

## Lifetimes & teardown

- **Lifetime anchor** — `LifetimeAnchorIndex` records why a stored node can stay
  live. An anchor can be a parent, committed value, hosted detached node,
  navigation surface, or entity home.
- **Teardown barrier** — `settleTeardownBarrier` is the single fixed-point
  interface for all deferred teardown work. Teardown debt never grants
  liveness.
- **Census / soundness oracle** — These interface-level checks cover
  reachability, stamp coherence, and stranded freshness listings.
  `SoundnessProbeConfiguration` exposes these checks. Stress tests use their
  assertions. The canonical inventory is [SOUNDNESS-ORACLES.md](SOUNDNESS-ORACLES.md).

## Cross-host wire

- **Capability declaration** — A connected host declares the features that it
  can accept beyond the deployed defaults. WASI environment keys can carry the
  declaration. The WebSocket `caps:` control record and the Android
  `declareCapabilities` call can also carry it. A missing declaration is
  meaningful. The host receives the default bytes without changes.
- **Wire key vs capability** — A client sends JSON keys, but the encoder reads
  capabilities. The keys are the vocabulary of the client. A capability is the
  negotiated feature bit. `HostWireSchema.capabilityMappings` maps keys to
  capabilities. The parser skips unknown keys. Thus, releases can add or retire
  keys without a lockstep client release.
- **Named feature bits, not a version ceiling** — A capability names the record
  shape that it permits, such as `acceptsDeltaFrames`. It does not declare a
  maximum version. A version ceiling assumes that the wire changes in one
  linear sequence. It also duplicates the decoder skew guard. This guard
  rejects records that are newer than the decoder. The retired
  `maxWebSurfaceVersion` field represented only one feature bit. Two fields for
  one bit permitted contradictory declarations.
- **Negotiated encoding state** —
  `HostWireCapabilities.negotiatedEncodingState()` converts one declaration to
  its encoder state. Each transport uses it for the default and for resets
  after declarations. A transport-specific state can emit a record shape that
  the declaration did not request.
- **Connection epoch** — A new encoding state resets the delta baseline and the
  transmitted-image set. Thus, each declaration starts an epoch. Negotiation
  returns a new state instead of changing an existing state.
- **Ingress lifecycle** — Each transport has a separate declaration window. A
  WebSocket accepts declarations at any time, and each declaration starts an
  epoch. Android accepts declarations only before the scene starts. Its poll
  model cannot change the record shape during a session. WASI accepts a
  declaration only during construction. A reload creates a new in-process
  transport. The derivation is shared, but the declaration window is not.
- **Format adapter** — `WebSurfaceFrameEncoder` is the only adapter for the
  shared wire model. It replaced the Android keyed-JSON wire. The adapter owns
  the RS-framed byte format. It reads each emitted value from the model.

## Authoring seam

- **resolveView** — This deep module owns the authoring seam. A two-argument call
  contains frame-input refresh, reuse layers, entity routing, and lifetime
  scope.
- **ForEachIteration** — This model owns five coupled parts of collection
  iteration. They are entity scope, occurrence, explicit identity, authoring
  scope, and route attachment. These parts previously changed independently.
