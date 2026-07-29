# Reuse and invalidation

Understand how SwiftTUI turns value changes into graph work, decides whether a
resolved subtree is safe to serve again, and keeps structural churn from
outliving its ownership.

This article describes the current `SwiftTUIGraph` implementation. The types
that own the policy are package-internal, but their contracts are load-bearing
for state, focus, presentation, runtime registrations, and every host.

## The two-channel invalidation model

SwiftTUI has two related channels of change.

The **value-change channel** begins when a tracked value publishes a change.
`@State` writes use `ViewNode.setStateSlot`, and Swift Observation callbacks use
the graph's observation-change path. Both identify the actual reader whenever
possible, mark its `ViewNode` dirty, and send invalidated identities through the
frame scheduler. At the next frame boundary the graph reconciles its invalidated
and graph-local-dirty rails, removes dirty descendants already covered by dirty
ancestors, and builds a `DirtyEvaluationPlan`. Its frontier is the smallest set
of stitchable evaluators that covers the known dirty work. When that proof
cannot be formed, resolve starts at the root instead.

The **structural-churn channel** begins while resolve evaluates those frontier
targets or the root. A new child list, a re-rooted identity, a presentation or
preference-derived subtree, or a child adopted by a different live parent can
change graph topology without being expressible as another tracked value read.
Those paths propagate `withinChurnedSubtree`, update `CommittedFreshness`,
reconcile parent and `evaluationHost` relationships, and enqueue teardown work.
They force fresh resolution inside the affected cone even when an identity-only
invalidation test would miss it.

Resolve is where the channels meet. Every reached node first asks the reuse
door whether its committed subtree is servable. A decline evaluates the authored
body and may produce structural churn. An acceptance restores the subtree's
runtime registrations and reports its retained lifetime without re-running the
body. After resolve, `ViewGraphFrameDraft` publishes the graph's recorded
runtime-registration state into the live dispatch registries, and the teardown
barrier settles structural departures before the frame becomes committed truth.

## Vocabulary

The following terms are normative in this repository and appear in dependency
order.

**Publication.** In graph code, publication means making the registrations
recorded on `ViewNode`s visible in the live runtime registries; it is not a
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

**Frontier.** A frontier is the highest set of graph-local dirty nodes not
covered by another queued dirty ancestor, subsequently hoisted to evaluators
whose output can be stitched into the committed frame.
`ViewGraphDirtyEvaluationPlanner` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphDirtyEvaluationPlanning.swift` computes
the targets, and `DirtyEvaluationPlan` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphState.swift` records their node IDs and
identities. A target-less frontier is never partially accepted; it raises an
oracle signal and escalates to root evaluation.

**Cone.** A cone is the self/ancestor/descendant region whose output may be
affected by a change. `InvalidationSummary` in
`Sources/SwiftTUIGraph/Commit/InvalidationSummary.swift` precomputes the
identity-axis relationships used by retained reuse, while live structural
checks cover re-rooted identities and island seams. A **churned cone** is the
downward scope of `ResolveContext.withinChurnedSubtree` in
`Sources/SwiftTUIViews/Environment/ResolveContext.swift`: a value-derived or
identity-re-rooted structural change that both reuse layers must stand down
inside, even when the ordinary invalidation cone does not name the descendants.

**Rail.** A rail is one of the graph's parallel work ledgers:
`invalidatedNodeIDs` records which live nodes must deny reuse, while
`graphLocalDirtyNodeIDs` records which nodes have queued evaluator work.
`ViewGraphInvalidationPlanner` in
`Sources/SwiftTUIGraph/Resolve/ViewGraphInvalidationPlanning.swift` writes the
rails, and the inter-rail reconciliation in `ViewGraph.swift` unions live
invalidated nodes into the dirty rail before frontier planning. The distinction
is intentional; rail drift may broaden evaluation but must never drop work.

**Strand.** A strand is graph state that remains stored, listed, or published
after the ownership path that should make it reachable or retire it has been
lost. Examples include an unreachable node spared by a superseded pass and a
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
`parent ?? evaluationHost` where host reachability matters; structural
lifecycle walks intentionally retain strict-parent semantics where an island
must not count as an ordinary child.

**Servable.** A committed subtree is servable when a reuse layer has enough
evidence to return it instead of evaluating the body. Servability is a
gate-specific verdict, not a synonym for “stored,” “fresh,” or “live.”
`CommittedFreshness.canServeValueBlind` and `.canServeMemo` in
`Sources/SwiftTUIGraph/Resolve/CommittedFreshness.swift` provide the stamp leg,
while `ViewNode.canReuse`, `ViewNode.canMemoReuse`, invalidation intersection,
environment equality, transaction equivalence, suppression, and dependency
coverage provide the remaining proof.

**Freshness stamp.** A freshness stamp is one component of
`CommittedFreshness` in
`Sources/SwiftTUIGraph/Resolve/CommittedFreshness.swift`. Its three verdicts are
**fresh** (`isCommittedSnapshotFresh`), **island-stale**
(`hasStaleIslandDescendant`), and **foreign-parented**
(`hasForeignParentedChild`). They are independent because a snapshot that can
be rebuilt through ordinary children cannot necessarily be rebuilt across an
island, and a listed child seated under another parent can no longer propagate
staleness to its former owner.

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
press members plus an all-tree fallback. Its matching covers each member,
ancestors needed to reach it, and descendants whose presentation may depend on
it, with narrowly declared inert and value-verified slot exemptions.

**Oracle.** An oracle is an independently evaluated invariant that can reveal
a false reuse, lost dirty target, incoherent stamp, or stranded ownership claim
even when visible output happens to look correct. The graph records them through
`SoundnessProbeConfiguration` in
`Sources/SwiftTUIGraph/Resolve/SoundnessProbeConfiguration.swift`; the
repository's canonical enforcement, sampling, residual, and test-owner
inventory is the
[soundness oracle map](https://github.com/SwiftTUI/swift-tui/blob/main/docs/SOUNDNESS-ORACLES.md).

## The reuse door

`resolveView` assembles `ReuseDecisionInputs`; policy does not remain split
across call sites. Each field has one role:

| Field | Contract |
| --- | --- |
| `identity` | The authored identity whose existing `ViewNode` and committed value are candidates. |
| `invalidatedIdentities` | The current frame's raw invalidation set, used for precise self/ancestor/descendant conflict checks and by the memo layer's self-invalidated veto. |
| `invalidationSummary` | The precomputed identity/structural-path projection used by retained reuse before its live-graph structural check. |
| `environment` | The current `EnvironmentSnapshot`; both layers require equality with the committed snapshot for covered environment values. |
| `transaction` | The current `TransactionSnapshot`; both layers require resolve-time animation intent and batch metadata to be reuse-equivalent. |
| `allowsEmptyInvalidation` | A certificate that a finite suppression scope completely names why an otherwise empty-invalidation frame is evaluating. |
| `invalidator` | The current invalidation target installed on reused nodes so later state and observation changes still schedule work. |
| `uncoveredEnvironmentKeys` | Focus/press environment keys deliberately excluded from snapshot equality; a memo candidate that read one is not dependency-covered. |
| `suppressesRetainedReuse` | The broad focus/press scope verdict for value-blind retained reuse. |
| `suppressesValueVerifiedReuse` | The narrower scope verdict after value-verified slot exemptions; it is a subset of `suppressesRetainedReuse`. |
| `withinChurnedSubtree` | The propagated structural-churn marker; either layer must decline when it is set. |
| `structuralPath` | The caller's current structural position, written onto a served result before it returns. |
| `runtimeRegistrations` | The current pass's registration intake, into which acceptance restores the served subtree's recorded registrations. |

The door always asks **Layer A, retained reuse**, first. Layer A is value-blind:
the node must have existed at frame start, remain unvisited and clean, carry a
value-blind-servable committed snapshot, support retained reuse, match the
environment and reuse-equivalent transaction, and be disjoint from the
invalidation on both identity and live structural axes. A hit snapshots the
node, records the subtree as retained, and ends the decision.

Only after a Layer-A miss does the door ask **Layer B, memoized-body reuse**.
This layer exists for a node reached below a re-evaluated ancestor. It still
requires a clean, unvisited, memo-servable node, an equal environment and
reuse-equivalent transaction, no self invalidation, and no uncovered state,
Observation, or focus/press dependency. It then compares the newly presented
view value with the prior value through
`MemoValueComparator.compareEquatable`. Production memo reuse is
`Equatable`-only: a directly `Equatable` view or an `EquatableView` /
`.equatable()` boundary opts in; non-`Equatable` containers are not reflected
over. The reflective comparator belongs only to the sampled shadow oracle.

Both layers share the same acceptance path. `recordReusedSubtree` refreshes the
retained root and its invalidator, the door restores recorded runtime
registrations into the pass, rewrites the caller's structural path, and reports
the resolved lifetime result. A layer is not permitted to invent a narrower
accept path that bypasses these effects.

The door also relies on `resolveView` preserving the authoring-owner seam when
a dirty frontier invokes a stored evaluator. A node-backed style body roots its
interior state slots on the live style-body node while its registrations remain
owned by the stable enclosing control. The evaluator therefore captures the
same `authoringContextOverride` used by the original resolve, but strips its
live `viewNode` reference before storing it and rebases onto the fresh fire-site
node. Dropping the override degrades imperative state writes to detached seed
storage; retaining the live node creates an ownership cycle. Separately,
structural invalidation walks bridge `parent ?? evaluationHost` and remap an
unmapped invalidated identity to its nearest live ancestor, or deny reuse for
that frame when no ancestor exists. Those are prerequisites for asking the
door a sound question across style and capture-host islands.

### The two certification legs

Most accepts prove safety by nonempty invalidation disjointness. Two paths need
an additional certificate:

1. **Empty-invalidation certification.** A focus/press-only frame can be forced
   while carrying no ordinary invalidated identity.
   `allowsEmptyInvalidation` may be true only when a finite, nonempty
   `RetainedReuseSuppressionScope` completely names the cause. The caller tests
   suppression before opening the door, so a node that reaches Layer A lies
   outside every named recompute cone; environment and transaction equality
   complete its proof. Without that certificate, an empty invalidation set
   proves nothing and Layer A declines.
2. **Memo focus exemption.** A control may declare a focus-presentation
   **value-verified** slot whose handed-down value contains every focus-derived
   input. Value-blind Layer A stays suppressed below that slot, but Layer B may
   use the narrower `suppressesValueVerifiedReuse` verdict: `Equatable`
   equality proves whether the value changed. Exact members and ancestors are
   never exempt, uncovered focus/press environment reads still deny, and a
   DEBUG assertion walks an accepted subtree to prove it contains no wholesale
   runtime-focus dependency.

Engine-profile policy is part of the door, not a host call-site choice. The
full/native profile offers both layers. The stack-lean profile disables
memoized reuse and selective evaluation; retained reuse is also off unless
`SWIFTTUI_LEAN_RETAINED_REUSE=1` opts into the descent-shortening Layer-A path.
The canonical host/profile matrix and environment switches live in
[Hosts and platforms](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md#per-host-engine-profiles).

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
`evaluationHost`, it sets island-stale instead: rebuilding only from live
`children` would omit the capture-hosted interior and then launder that
truncated value as fresh. A competing apply that seats a listed child under a
different parent sets foreign-parented, because future upward staleness walks
follow the new parent and can no longer reach the old lister.

The service queries intentionally differ:

- `canServeValueBlind` requires fresh and neither island-stale nor
  foreign-parented.
- `canServeMemo` requires fresh and not island-stale. A foreign-parented child
  is allowed only because the memo layer independently verifies the view value
  before serving.
- `hasFreshCommittedSnapshot` controls whether `snapshot()` can return the
  committed value without rebuilding; it does not by itself authorize reuse.

Retained write-back has its own admission check. `applyRetainedSnapshot`
receives a value whose gate passed earlier in the frame, but
`snapshotRefreshed()` restores only freshness. It therefore asserts
`admitsRetainedWriteBack` before the refresh: island-stale or
foreign-parented must not have flipped in the interval. DEBUG traps at the
write site; sampled release probing records the same stamp-coherence failure.
The rebuild path does not use this admission check because rebuilding an
island-stale node from its ordinary live children is a legitimate intermediate
operation whose island denial must remain set.

Freshness is not liveness. Structural removal can encounter a node visited by a
reused or superseded same-frame pass. A removal cascade may provisionally spare
that descendant, but it enqueues `TeardownWorkReason.sparedVisitedDescent`
instead of treating “visited” or “served” as a right to survive. Once all
applies have settled, `settleTeardownBarrier` in `ViewGraph.swift` runs a
fixed-point reachability adjudication: a durable anchor or committed-root path
keeps the node; otherwise `SubtreeRemovalPolicy.barrierAdjudicated` removes the
strand and repeats for newly exposed descendants. No snapshot may be served
*across* that departure boundary merely because its stamps are fresh; the
reuse door's structural intersection denies the departing cone, and the barrier
owns the final liveness verdict.

## Suppression scopes and cones

Focus and press changes are not represented completely by ordinary environment
snapshot equality: the high-churn `focusedIdentity` and `pressedIdentity` side
fields are deliberately excluded. The run loop therefore builds a
`RetainedReuseSuppressionScope` from runtime readers and old/new focus or press
identities. `ResolveContext.effectiveSuppressesRetainedReuse` applies the broad
verdict to Layer A; `effectiveSuppressesValueVerifiedReuse` applies the narrower
value-verified verdict to Layer B.

A scope member normally suppresses itself, the ancestors resolve must traverse
to reach it, and descendants whose presentation can depend on it. Two
declarations narrow only the descendant leg:

- a **focus-presentation-inert slot** promises its handed-down value cannot
  vary with the declaring control's own focus or press presentation, so both
  reuse layers may treat that descendant match as exempt;
- a **focus-presentation value-verified slot** may hand down a changing value,
  so Layer A remains suppressed and only Layer B may consult equality.

An exact member, an ancestor of a member, or a separate wholesale focus reader
is never exempt. This keeps evaluation connected to every real reader while
preventing a near-root control from blanketing an unrelated content subtree.

`withinChurnedSubtree` handles a different proof gap. Exact-identity rebinding,
presentation-entry changes, preference-derived overlays/backgrounds, and
similar values synthesized during resolve can change descendants without
creating a tracked invalidation for those descendants. The marker is inherited
by every derived `ResolveContext`; the reuse door declines both layers until
the fresh values have been resolved and committed. This stand-down is
orthogonal to focus/press suppression: a node must pass both policies.

## The DEBUG oracle suite

The reuse subsystem's local oracles are deliberately small:

- `ViewGraph.strandedFreshServableViolations()` walks live node objects at the
  sampled `finalizeFrame` barrier and reports a node whose freshness stamps
  claim ownership of a child seated under another parent. In DEBUG, any report
  also traps.
- `ViewNode.assertResolvedStampsCoherent` verifies that the runtime-node IDs in
  a supposedly fully stamped resolved value agree with the live paired nodes.
  `applyRetainedSnapshot` separately asserts the retained write-back admission
  interval. Sampled release probes record both classes through
  `recordStampCoherenceViolation`.
- The memo shadow path recomputes sampled would-skip nodes and compares their
  fresh output with the committed output. A no-reads content divergence records
  `memo-unsound-skip`; the production gate remains `Equatable`-only.

The stranded-listing implementation must compare **objects**, not names from
mixed identity systems. `identityByNodeID` describes nodes in
`resolvedIdentity` space, while `ViewNode.identity` and `parent.identity` are
authored-space names. Comparing those maps manufactured 13–14 apparent
co-listings on a healthy graph. `ViewGraphStrandedListingProbe.swift` instead
tests `child.parent !== node`, the same object relation the upward staleness
walk follows.

This section is not the inventory of every graph and runtime probe. Enforcement
tier, sampling, release behavior, residual quarantine, source recorder, and
owning tests belong to the canonical
[soundness oracle map](https://github.com/SwiftTUI/swift-tui/blob/main/docs/SOUNDNESS-ORACLES.md).

## Design history

> Design-history references below are evidence for why the current contracts
> exist. They are dated coordination records, not normative descriptions of
> HEAD.
>
> `SwiftTUI/swift-tui-org` was private at implementation time. The paths are
> collaborator-only references and are intentionally not links; outside readers
> should rely on this article's public current-source links and the public
> `SwiftTUI/swift-tui` commit history.

- `docs/reports/2026-06-13-swifttui-invalidation-gap-analysis.md` and
  `docs/reports/2026-06-14-stage-0-frontier-publication-inventory.md`
  established the value-change, dirty-frontier, and registration-publication
  model.
- `docs/reports/2026-06-15-reuse-trace-productization-and-cone-confirmation.md`
  measured ancestor invalidation blanketing a descendant background and made
  the cone vocabulary operational.
- `docs/reports/2026-06-17-memo-stage0-killgate.md` demonstrated the shadow
  oracle's teeth;
  `docs/reports/2026-06-17-memo-stage2-flag-gated-gate.md` established why
  production comparison ultimately became an `Equatable`-only opt-in.
- `docs/reports/2026-07-17-001-gallery-fuzzer-diagnostics-campaign.md`, §9.10
  “Style-seam re-land + retained-placement identity fix (2026-07-18, session
  5),” explains the authoring-owner override and island-bridging invalidation.
  Section §9.11, “Final two fixes: paired-route leak and visited-spare strand
  (2026-07-18, session 5),” records fixed-point spare adjudication. Public
  [commit `8560d337`](https://github.com/SwiftTUI/swift-tui/commit/8560d3371b031268a7e92d95c744feef494e71ec)
  is the corresponding combined child-repository evidence.
- `docs/reports/2026-07-23-002-reuse-freshness-quirk-register.md`, “Residual 2
  — closure (2026-07-25),” records the live-object stranded-listing invariant,
  its deliberate teeth, and the resolved-vs-authored identity naming pitfall.
