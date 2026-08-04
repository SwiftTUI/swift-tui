# Reuse and invalidation

Learn how SwiftTUI turns value changes into graph work. See how it safely serves
a resolved subtree again and keeps structural churn within its ownership.

This article describes the current `SwiftTUIGraph` implementation. The types
that own the policy are package-internal, but their contracts are load-bearing
for state, focus, presentation, runtime registrations, and every host.

## The two-channel invalidation model

SwiftTUI has two related channels of change.

The **value-change channel** begins when a tracked value publishes a change.
`@State` writes use `ViewNode.setStateSlot`, and Swift Observation callbacks use
the graph's observation-change path. Both identify the actual reader whenever
possible, mark its `ViewNode` dirty, and send invalidated identities through the
frame scheduler. At the next frame boundary, the graph reconciles its
invalidated and graph-local-dirty rails. It removes dirty descendants that
dirty ancestors already cover. Then it builds a `DirtyEvaluationPlan`. Its
frontier is the smallest set of stitchable evaluators that covers the known
dirty work. If the graph cannot form that proof, resolve starts at the root.

The **structural-churn channel** begins while resolve evaluates those frontier
targets or the root. Some topology changes cannot be expressed as another
tracked value read. Examples include a new child list, a re-rooted identity, or
a presentation or preference-derived subtree. A different live parent can also
adopt a child.
Those paths propagate `withinChurnedSubtree` and update `CommittedFreshness`.
They reconcile parent and `evaluationHost` relationships. They also enqueue
teardown work. The paths force fresh resolution inside the affected cone. An
identity-only invalidation test can miss this change.

Resolve is where the channels meet. Every reached node first asks the reuse
door whether its committed subtree is servable. A decline evaluates the authored
body and can produce structural churn. An acceptance restores the subtree's
runtime registrations and reports its retained lifetime without re-running the
body. After resolve, `ViewGraphFrameDraft` publishes the graph's recorded
runtime-registration state into the live dispatch registries. The teardown
barrier then settles structural departures before the frame becomes committed
truth.

## Vocabulary

The following terms are normative in this repository and appear in dependency
order.

**Publication.** In graph code, publication means making the registrations
recorded on `ViewNode`s visible in the live runtime registries. It is not a
synonym for invalidation. `ViewGraphFrameDraft.RuntimeRegistrationPublication`
in `Sources/SwiftTUIGraph/Resolve/ViewGraphFrameDraft.swift` selects
`.unchanged`, `.subtrees`, or `.all` behavior after resolve. State and
Observation “publish” value changes in the general Observation sense, but their
graph effect is to request invalidation and queue dirty work.

**Fingerprint.** A fingerprint is an equality-friendly projection used where
the underlying registration closures cannot be compared. The production
`RuntimeRegistrationGraphFingerprint` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphRuntimeRegistrationFingerprint.swift`
maps node IDs to subtree roots, resolved identities, and mutation generations
so publication can compute a removal/restoration delta. The sampled publication
oracle separately uses `RuntimeRegistrationFingerprintBuilder` in
`Sources/SwiftTUIGraph/Runtime/RuntimeRegistryLifecycle.swift` to compare
`registry|key` counts from the live registries with a scratch full rebuild.

**Frontier.** A frontier is the highest set of graph-local dirty nodes that no
queued dirty ancestor covers. The graph hoists these nodes to evaluators whose
output can be stitched into the committed frame.
`ViewGraphDirtyEvaluationPlanner` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphDirtyEvaluationPlanning.swift` computes
the targets, and `DirtyEvaluationPlan` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphState.swift` records their node IDs and
identities. The graph never partially accepts a target-less frontier. It raises
an oracle signal and escalates to root evaluation.

**Cone.** A cone is the self/ancestor/descendant region whose output can be
affected by a change. `InvalidationSummary` in
`Sources/SwiftTUIGraph/Commit/InvalidationSummary.swift` precomputes the
identity-axis relationships used by retained reuse, while live structural
comparisons cover re-rooted identities and island seams. A **churned cone** is the
downward scope of `ResolveContext.withinChurnedSubtree` in
`Sources/SwiftTUIViews/Environment/ResolveContext.swift`. It marks a
value-derived or identity-re-rooted structural change. Both reuse layers must
stop inside this scope, even if the ordinary invalidation cone does not name
the descendants.

**Rail.** A rail is one of the graph's parallel work ledgers.
`invalidatedNodeIDs` records which live nodes must deny reuse.
`graphLocalDirtyNodeIDs` records which nodes have queued evaluator work.
`ViewGraphInvalidationPlanner` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphInvalidationPlanning.swift` writes the
rails, and the inter-rail reconciliation in `ViewGraph.swift` unions live
invalidated nodes into the dirty rail before frontier planning. The distinction
is intentional. Rail drift can broaden evaluation but must never drop work.

**Strand.** A strand is graph state that remains stored, listed, or published
after it loses the ownership path that makes it reachable or retires it.
Examples include an unreachable node spared by a superseded pass and a
fresh node that still lists a child seated under another live parent.
`ViewGraphSubtreeRemoval.swift`, `TeardownBarrierWork.swift`, and
`ViewGraphStrandedListingProbe.swift` contain the removal and detection seams.
A departed node is not automatically a strand: durable lifetime anchors,
in-flight interaction preservation, and genuine same-frame re-adoption are
explicitly adjudicated.

**Island.** An island is resolved content whose live node chain does not reach
its host through `parent`, usually because content was capture-hosted or
identity-re-rooted. `ViewNode.evaluationHost` in
`Sources/SwiftTUIGraph/Resolve/ViewNode.swift` is the bridge. Dirty-frontier,
staleness, event-bubble, and reuse-intersection walks use
`parent ?? evaluationHost` where host reachability matters. Structural
lifecycle walks retain strict-parent semantics where an island
must not count as an ordinary child.

**Servable.** A committed subtree is servable when a reuse layer has enough
evidence to return it instead of evaluating the body. Servability is a
gate-specific verdict, not a synonym for “stored,” “fresh,” or “live.”
`CommittedFreshness.canServeValueBlind` and `.canServeMemo` in
`Sources/SwiftTUIGraph/Resolve/CommittedFreshness.swift` provide the stamp leg.
The remaining proof comes from `ViewNode.canReuse`, `ViewNode.canMemoReuse`,
invalidation intersection, environment equality, transaction equivalence,
suppression, and dependency coverage.

**Freshness stamp.** A freshness stamp is one component of
`CommittedFreshness` in
`Sources/SwiftTUIGraph/Resolve/CommittedFreshness.swift`. Its three verdicts are
**fresh** (`isCommittedSnapshotFresh`), **island-stale**
(`hasStaleIslandDescendant`), and **foreign-parented**
(`hasForeignParentedChild`). These verdicts are independent. A snapshot that
can be rebuilt through ordinary children cannot necessarily be rebuilt across
an island. A listed child under another parent cannot propagate staleness to
its former owner.

**Reuse door.** The reuse door is the single resolve-time policy seam,
`ViewGraph.reuseResolvedSubtree(inputs:viewValue:)` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphReuseDoor.swift`. Every `resolveView`
entry presents a `ReuseDecisionInputs` value to it. The door owns retained-
before-memo ordering, stack-lean policy, suppression, the two exceptional
certification legs, denial tracing, and the common acceptance plumbing.

**Suppression scope.** A suppression scope is a finite set of identities that
must recompute for a frame cause not completely represented by ordinary
invalidation. `RetainedReuseSuppressionScope` in
`Sources/SwiftTUIViews/Environment/FrameResolveState.swift` models focus and
press members plus an all-tree fallback. Its matching covers each member and
the ancestors needed to reach it. It also covers dependent presentation in
descendants, with narrowly declared inert and value-verified slot exemptions.

**Oracle.** An oracle is an independently evaluated invariant. It can reveal a
false reuse, lost dirty target, incoherent stamp, or stranded ownership claim
even when visible output looks correct. The graph records them through
`SoundnessProbeConfiguration` in
`Sources/SwiftTUIGraph/Resolve/SoundnessProbeConfiguration.swift`. The
canonical enforcement, sampling, residual, and test-owner inventory is
contributor-facing and maintained in the repository's internal
`docs/SOUNDNESS-ORACLES.md` map, not here.

## The reuse door

`resolveView` assembles `ReuseDecisionInputs`. Policy does not remain split
across call sites. Each field has one role:

| Field | Contract |
| --- | --- |
| `identity` | The authored identity whose existing `ViewNode` and committed value are candidates. |
| `invalidatedIdentities` | The current frame's raw invalidation set. It supplies precise conflict comparisons and the memo layer's self-invalidated veto. |
| `invalidationSummary` | The precomputed identity and structural-path projection. Retained reuse reads it before its live-graph structural comparison. |
| `environment` | The current `EnvironmentSnapshot`. Both layers require equality with the committed snapshot for covered environment values. |
| `transaction` | The current `TransactionSnapshot`. Both layers require reuse-equivalent animation intent and batch metadata. |
| `allowsEmptyInvalidation` | A certificate that a finite suppression scope completely names why an otherwise empty-invalidation frame is evaluating. |
| `invalidator` | The current invalidation target installed on reused nodes so later state and observation changes still schedule work. |
| `uncoveredEnvironmentKeys` | Focus and press keys excluded from snapshot equality. A memo candidate that read one is not dependency-covered. |
| `suppressesRetainedReuse` | The broad focus/press scope verdict for value-blind retained reuse. |
| `suppressesValueVerifiedReuse` | The narrower scope verdict after value-verified slot exemptions. It is a subset of `suppressesRetainedReuse`. |
| `withinChurnedSubtree` | The propagated structural-churn marker. Both layers must decline when it is set. |
| `structuralPath` | The caller's current structural position, written onto a served result before it returns. |
| `runtimeRegistrations` | The current pass's registration intake, into which acceptance restores the served subtree's recorded registrations. |

The door always asks **Layer A, retained reuse**, first. Layer A is value-blind.
The node must have existed at frame start. It must remain unvisited and clean,
carry a value-blind-servable committed snapshot, and support retained reuse.
It must match the environment and reuse-equivalent transaction. It must also
be disjoint from invalidation on both identity and live structural axes. A hit snapshots the
node, records the subtree as retained, and ends the decision.

Only after a Layer-A miss does the door ask **Layer B, memoized-body reuse**.
This layer exists for a node reached below a re-evaluated ancestor. It still
requires a clean, unvisited, memo-servable node. It also requires an equal
environment, a reuse-equivalent transaction, and no self invalidation. No
state, Observation, or focus/press dependency can remain uncovered. It then compares the newly presented
view value with the prior value through
`MemoValueComparator.compareEquatable`. Production memo reuse is
`Equatable`-only. A directly `Equatable` view or an `EquatableView` or
`.equatable()` boundary opts in. The comparator does not reflect
non-`Equatable` containers. The reflective comparator belongs only to the
sampled shadow oracle.

Both layers share the same acceptance path. `recordReusedSubtree` refreshes the
retained root and its invalidator. The door restores recorded runtime
registrations into the pass and rewrites the caller's structural path. It then
reports the resolved lifetime result. A layer is not permitted to invent a narrower
accept path that bypasses these effects.

The door also relies on `resolveView` preserving the authoring-owner seam when
a dirty frontier invokes a stored evaluator. A node-backed style body roots its
interior state slots on the live style-body node while its registrations remain
owned by the stable enclosing control. The evaluator therefore captures the
same `authoringContextOverride` used by the original resolve. Before storage,
it strips the live `viewNode` reference. It then rebases onto the fresh fire-site
node. Dropping the override degrades imperative state writes to detached seed
storage. Retaining the live node creates an ownership cycle. Separately,
structural invalidation walks bridge `parent ?? evaluationHost` and remap an
unmapped invalidated identity to its nearest live ancestor. If no ancestor
exists, they deny reuse for that frame. These steps are prerequisites for a
sound reuse decision across style and capture-host islands.

### The two certification legs

Most accepts prove safety by nonempty invalidation disjointness. Two paths need
an additional certificate:

1. **Empty-invalidation certification.** A focus/press-only frame can be forced
   while carrying no ordinary invalidated identity.
   `allowsEmptyInvalidation` can be true only when a finite, nonempty
   `RetainedReuseSuppressionScope` completely names the cause. The caller tests
   suppression before opening the door, so a node that reaches Layer A lies
   outside every named recompute cone. Environment and transaction equality
   complete its proof. Without that certificate, an empty invalidation set
   proves nothing and Layer A declines.
2. **Memo focus exemption.** A control can declare a focus-presentation
   **value-verified** slot whose handed-down value contains every focus-derived
   input. Value-blind Layer A stays suppressed under that slot. Layer B can use
   the narrower `suppressesValueVerifiedReuse` verdict. `Equatable` equality
   shows whether the value changed. Exact members and ancestors are never
   exempt. Uncovered focus or press environment reads still deny reuse. A
   DEBUG assertion also makes sure that an accepted subtree has no wholesale
   runtime-focus dependency.

Engine-profile policy is part of the door, not a host call-site choice. The
full/native profile offers both layers. The stack-lean profile disables
memoized reuse and selective evaluation. Retained reuse is also off unless
`SWIFTTUI_LEAN_RETAINED_REUSE=1` opts into the descent-shortening Layer-A path.
The canonical host/profile matrix and environment switches live in the
`SwiftTUIRuntime` catalog's
[Hosts And Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms)
article.

## Freshness stamps and servability

`CommittedFreshness` is a three-bit algebra with named transitions:

| Transition | Fresh | Island-stale | Foreign-parented |
| --- | --- | --- | --- |
| Initial node | `false` | `false` | `false` |
| `commitApplied()` | `true` | `false` | `false` |
| `snapshotRefreshed()` | `true` | unchanged | unchanged |
| `markChildReseated()` | unchanged | unchanged | `true` |
| `markDescendantChanged(crossingIslandSeam: false)` | `false` | unchanged | unchanged |
| `markDescendantChanged(crossingIslandSeam: true)` | unchanged | `true` | unchanged |

An ordinary descendant change clears freshness so `snapshot()` can rebuild the
committed value from live children. After a staleness walk crosses
`evaluationHost`, it sets island-stale instead. A rebuild from only live
`children` can omit the capture-hosted interior. It can then mark that truncated
value as fresh. A competing apply sets foreign-parented when it seats a listed
child under a different parent. Future upward staleness walks follow the new
parent and cannot reach the old lister.

The service queries intentionally differ:

- `canServeValueBlind` requires fresh and neither island-stale nor
  foreign-parented.
- `canServeMemo` requires fresh and not island-stale. The memo layer allows a
  foreign-parented child only because it independently compares the view value
  before serving.
- `hasFreshCommittedSnapshot` controls whether `snapshot()` can return the
  committed value without rebuilding. It does not authorize reuse by itself.

Retained write-back has its own admission test. `applyRetainedSnapshot`
receives a value whose gate passed earlier in the frame, but
`snapshotRefreshed()` restores only freshness. It therefore asserts
`admitsRetainedWriteBack` before the refresh: island-stale or
foreign-parented must not have flipped in the interval. DEBUG traps at the
write site. Sampled release probing records the same stamp-coherence failure.
The rebuild path does not use this admission comparison. A rebuild of an
island-stale node from its ordinary live children is a legitimate intermediate
operation. Its island denial must remain set.

Freshness is not liveness. Structural removal can encounter a node visited by a
reused or superseded same-frame pass. A removal cascade can provisionally spare
that descendant, but it enqueues `TeardownWorkReason.sparedVisitedDescent`
instead of treating “visited” or “served” as a right to survive. Once all
applies have settled, `settleTeardownBarrier` in `ViewGraph.swift` runs a
fixed-point reachability adjudication: a durable anchor or committed-root path
keeps the node. Otherwise, `SubtreeRemovalPolicy.barrierAdjudicated` removes the
strand and repeats for newly exposed descendants. Fresh stamps alone do not let
SwiftTUI serve a snapshot *across* that departure boundary. The
reuse door's structural intersection denies the departing cone, and the barrier
owns the final liveness verdict.

## Suppression scopes and cones

Focus and press changes are not represented completely by ordinary environment
snapshot equality: the high-churn `focusedIdentity` and `pressedIdentity` side
fields are deliberately excluded. The run loop therefore builds a
`RetainedReuseSuppressionScope` from runtime readers and old/new focus or press
identities. `ResolveContext.effectiveSuppressesRetainedReuse` applies the broad
verdict to Layer A. `effectiveSuppressesValueVerifiedReuse` applies the narrower
value-verified verdict to Layer B.

A scope member normally suppresses itself, the ancestors resolve must traverse
to reach it, and descendants whose presentation can depend on it. Two
declarations narrow only the descendant leg:

- a **focus-presentation-inert slot** promises that its handed-down value cannot
  vary with the declaring control's own focus or press presentation. Both reuse
  layers can treat that descendant match as exempt.
- a **focus-presentation value-verified slot** can hand down a changing value.
  Layer A remains suppressed, and only Layer B can compare equality.

An exact member, an ancestor of a member, or a separate wholesale focus reader
is never exempt. This keeps evaluation connected to every real reader while
preventing a near-root control from blanketing an unrelated content subtree.

`withinChurnedSubtree` handles a different proof gap. Exact-identity rebinding,
presentation-entry changes, preference-derived overlays/backgrounds, and
similar values synthesized during resolve can change descendants without
creating a tracked invalidation for those descendants. The marker is inherited
by every derived `ResolveContext`. The reuse door declines both layers until
it resolves and commits the fresh values. This stand-down is
orthogonal to focus/press suppression: a node must pass both policies.

## The DEBUG oracle suite

The reuse subsystem's local oracles are deliberately small:

- `ViewGraph.strandedFreshServableViolations()` walks live node objects at the
  sampled `finalizeFrame` barrier. It reports a node whose freshness stamps
  claim ownership of a child seated under another parent. In DEBUG, any report
  also traps.
- `ViewNode.assertResolvedStampsCoherent` makes sure that the runtime-node IDs in
  a supposedly fully stamped resolved value agree with the live paired nodes.
  `applyRetainedSnapshot` separately asserts the retained write-back admission
  interval. Sampled release probes record both classes through
  `recordStampCoherenceViolation`.
- The memo shadow path recomputes sampled nodes that the production path can
  skip. It compares their
  fresh output with the committed output. A no-reads content divergence records
  `memo-unsound-skip`. The production gate remains `Equatable`-only.

This section is not the inventory of every graph and runtime probe. Enforcement
tier, sampling, release behavior, residual quarantine, source recorder, and
owning tests are contributor-facing and belong to the repository's internal
`docs/SOUNDNESS-ORACLES.md` map.
