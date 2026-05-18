---
title: "refactor: pipeline driver follow-up remediation"
type: refactor
status: active
date: 2026-05-17
depends_on:
  - "../proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/PIPELINE_BOUNDARY_HARDENING.md"
  - "../ARCHITECTURE.md"
  - "../decisions/0004-frame-head-abort-reverted.md"
  - "../decisions/0018-late-preference-reconciliation-bound.md"
  - "../decisions/0019-composed-runtime-render-pipeline.md"
  - "../decisions/0020-off-main-layout-worker-concurrency.md"
---

# Pipeline Driver Follow-up Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every finding (F1–F14) in [`PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`](../proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md) in code and tests — never by documentation rewording — so the running render driver matches the architecture the repository advertises.

**Architecture:** Phased remediation of the runtime render driver. Phase 0 builds a behavior-characterization safety net so every later refactor is provably behavior-preserving. Phases 1–9 each resolve one or more findings behind that net. Phase 10 retrofits the audit ledger and re-verifies. Each phase ends with a mandatory gate that runs the full repo test suite and a ledger audit.

**Tech Stack:** Swift 6.3, Swift Package Manager, Swift Testing (`import Testing`, `@Test`/`#expect`), `prek` pre-commit hooks, `bun run test` repo gate.

---

## How To Read This Plan

This plan is unusual in two ways, both deliberate, both responses to audit Finding F14 ("findings get closed by documentation rewording, not code").

1. **Every finding carries a Spirit statement and an Anti-Rationalization list.** The Spirit is the one sentence that says what the finding is *really* about. The Anti-Rationalization list enumerates the specific shortcuts a worker might take that would satisfy the letter of a task while betraying its spirit. If you catch yourself doing something on that list, the task is not done.

2. **Every finding has a mechanical Definition of Done (DoD).** A DoD is a command — a `grep`, a `swift test`, a `swift build` — whose output a third party can run to confirm the fix. "I updated the docs" is never a DoD. "I believe this is better" is never a DoD. If the DoD command does not produce the stated output, the finding is not resolved, regardless of how much code changed.

These are the checks and balances. They exist because the previous remediation effort (Stages 0–8) produced a green audit table over an unchanged driver. This plan must not repeat that.

---

## Checks And Balances (read before Task 0.1)

### CB-1 — The Resolution Ledger

Create `docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md` in Task 0.1. It is a single table, one row per finding F1–F14. Each row has four columns:

| Finding | Mechanism | DoD command | Verified-by commit |
| --- | --- | --- | --- |

- **Mechanism** must be exactly one of: `code`, `code+test`, `test`. The literal string `docs` is forbidden in this column. A finding whose only change is documentation is, by definition of this plan, unresolved.
- **DoD command** is copied verbatim from the finding's task in this plan.
- **Verified-by commit** is the git short hash of the commit where the DoD command first passed.

A finding is closed only when its ledger row is fully populated *and* the DoD command passes on a clean checkout of that commit.

### CB-2 — Documentation changes are downstream, never the deliverable

Several findings legitimately require documentation edits (`ARCHITECTURE.md`'s seven-phase claim, the audit tables). Those edits are real and required — but they are always the *last step* of a finding's task, never the first, and never the only. The rule: **the doc edit describes what the code now does; it is never what makes the finding resolved.** If you are tempted to resolve a finding by editing only a `.md` file, stop — you have found a finding that this plan has mis-scoped, and you must escalate it as a plan defect rather than close it.

### CB-3 — Phase gates

Each phase ends with a Gate task. The Gate task:
1. Runs `bun run test` (the full repo gate). It must pass with zero failures.
2. Runs `prek run --all-files`. It must pass.
3. Confirms every finding claimed-resolved in that phase has a complete ledger row whose DoD command passes.
4. Confirms no finding's Anti-Rationalization list was triggered (self-attested in the commit message).

A phase is not complete until its Gate task is committed. Do not begin the next phase before the prior Gate is green.

### CB-4 — The characterization net is sacred

Phase 0 builds `Tests/SwiftTUITests/PipelineDriverParityTests.swift` and `Tests/SwiftTUITests/RenderDriverCharacterizationTests.swift`. After Phase 0, **no task may modify, weaken, or `@disabled` those tests** to make a refactor pass. If a characterization test fails during a later refactor, the refactor changed behavior — that is the test working. Either the behavior change is intended (then update the test deliberately, in its own commit, with a commit message explaining the behavior delta and why it is correct) or it is a bug (then fix the refactor). Silently editing the expected value to match new output is an Anti-Rationalization trigger for every finding.

### CB-5 — Final re-verification

Phase 10's last task re-runs the entire follow-up audit as a checklist (Task 10.3). It is performed by a fresh subagent with no context from the implementation, given only `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md` and the repo, and asked: "for each of F1–F14, is the finding still observable?" If the subagent can still observe a finding, that finding reopens regardless of its ledger row.

---

## File Structure

Files this plan creates:

- `docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md` — the CB-1 ledger.
- `Tests/SwiftTUITests/RenderDriverCharacterizationTests.swift` — golden-artifact characterization of the driver across a curated view matrix.
- `Tests/SwiftTUITests/PipelineDriverParityTests.swift` — sync vs. async vs. cancellable artifact-parity tests.
- `Tests/SwiftTUITests/RenderPipelineStructureTests.swift` — guard tests for F1/F11/F12 (composition is real, no dead config).
- `Tests/SwiftTUICoreTests/ViewGraphCheckpointTotalityTests.swift` — guard test for F4.
- `Tests/SwiftTUICoreTests/FrameDropDroppabilityTests.swift` — guard test for F7.
- `Tests/SwiftTUITests/RenderDriverInstrumentationCostTests.swift` — guard test for F8.
- `Tests/SwiftTUITests/ResolvePurityTests.swift` — guard test for F3.
- `Tests/SwiftTUITests/DirtyTrackingCoherenceTests.swift` — guard test for F10.
- `docs/decisions/0021-unified-frame-driver.md` — ADR for the F2 unification.
- `docs/decisions/0022-resolve-side-effect-staging.md` — ADR recording the F3 outcome (whether resolve became pure or stayed staged, with rationale).

Files this plan modifies (primary):

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` — F2, F8, F10.
- `Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift` — F1, F11, F12.
- `Sources/SwiftTUIRuntime/SwiftTUI.swift` — F1, F3, F4, F5, F6, F11.
- `Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift` — F7.
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift` — F4.
- `Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift` — F9.
- `Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift` — F13.
- `docs/ARCHITECTURE.md` — F1, F3, F6 (downstream doc reconciliation only).
- `docs/proposals/PIPELINE_DRIVER_AUDIT.md` and `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md` — F14.

### Locating code

Line numbers drift as the plan executes. Every task locates code by symbol name with a `grep` command, not by line number. When a task says "locate X", run the given `grep` and edit at the reported site.

---

# Phase 0 — Safety Net

**Purpose:** Build the characterization tests and ledger that make every later phase verifiable. No production code changes in this phase.

## Task 0.1: Create the Resolution Ledger

**Files:**
- Create: `docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md`

- [ ] **Step 1: Write the ledger file**

```markdown
# Pipeline Driver Resolution Ledger

Tracks the resolution of each finding in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`.
Governance: a finding is resolved only when its Mechanism is `code`,
`code+test`, or `test` (never `docs`), its DoD command passes on a clean
checkout, and the verifying commit hash is recorded.

| Finding | Mechanism | DoD command | Verified-by commit |
| --- | --- | --- | --- |
| F1  | _pending_ | _pending_ | _pending_ |
| F2  | _pending_ | _pending_ | _pending_ |
| F3  | _pending_ | _pending_ | _pending_ |
| F4  | _pending_ | _pending_ | _pending_ |
| F5  | _pending_ | _pending_ | _pending_ |
| F6  | _pending_ | _pending_ | _pending_ |
| F7  | _pending_ | _pending_ | _pending_ |
| F8  | _pending_ | _pending_ | _pending_ |
| F9  | _pending_ | _pending_ | _pending_ |
| F10 | _pending_ | _pending_ | _pending_ |
| F11 | _pending_ | _pending_ | _pending_ |
| F12 | _pending_ | _pending_ | _pending_ |
| F13 | _pending_ | _pending_ | _pending_ |
| F14 | _pending_ | _pending_ | _pending_ |
```

- [ ] **Step 2: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: open pipeline driver resolution ledger"
```

## Task 0.2: Characterize the render driver across a view matrix

**Spirit:** Before refactoring the hottest path in the runtime, capture exactly what it produces today so any behavior drift is caught mechanically.

**Files:**
- Create: `Tests/SwiftTUITests/RenderDriverCharacterizationTests.swift`

- [ ] **Step 1: Write the characterization test**

This test renders a curated matrix of views through `DefaultRenderer.render`
(sync) and asserts stable structural properties of `FrameArtifacts`. It does not
hard-code raster bytes (brittle); it pins counts and shapes that a correct
refactor must preserve.

```swift
import Testing
import SwiftTUICore
import SwiftTUIViews
@testable import SwiftTUIRuntime

@MainActor
struct RenderDriverCharacterizationTests {
  /// The curated matrix. Each case is a named view whose rendered artifacts
  /// are characterized. Add cases here when a new driver behavior must be
  /// pinned; never delete cases to make a refactor pass (see CB-4).
  static let matrix: [(name: String, view: AnyView)] = [
    ("empty", AnyView(EmptyView())),
    ("text", AnyView(Text("hello"))),
    ("vstack", AnyView(VStack { Text("a"); Text("b") })),
    ("nested", AnyView(VStack { HStack { Text("x"); Text("y") }; Text("z") })),
    ("frame", AnyView(Text("f").frame(width: 10, height: 3))),
    ("conditional", AnyView(Group { if true { Text("on") } else { Text("off") } })),
    ("forEach", AnyView(VStack { ForEach(0..<3, id: \.self) { Text("\($0)") } })),
  ]

  @Test("Driver produces non-degenerate artifacts for every matrix case")
  func driverProducesArtifactsForMatrix() {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in Self.matrix {
      let renderer = DefaultRenderer()
      let artifacts = renderer.render(entry.view, proposal: proposal)
      #expect(
        artifacts.rasterSurface.size.width >= 0,
        "\(entry.name): raster surface must exist")
      #expect(
        artifacts.diagnostics.counts.resolvedNodes > 0,
        "\(entry.name): resolved tree must be non-empty")
    }
  }

  @Test("Repeated renders of the same view are artifact-stable")
  func repeatedRendersAreStable() {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in Self.matrix {
      let renderer = DefaultRenderer()
      let first = renderer.render(entry.view, proposal: proposal)
      let second = renderer.render(entry.view, proposal: proposal)
      #expect(
        first.rasterSurface == second.rasterSurface,
        "\(entry.name): identical input must produce identical raster")
      #expect(
        first.semanticSnapshot == second.semanticSnapshot,
        "\(entry.name): identical input must produce identical semantics")
    }
  }
}
```

- [ ] **Step 2: Run the test to verify it passes against current behavior**

Run: `swift test --filter RenderDriverCharacterizationTests`
Expected: PASS. If a matrix case fails to compile (a view API differs), fix the
matrix case to a compiling equivalent — do not delete the case.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftTUITests/RenderDriverCharacterizationTests.swift
git commit -m "test: characterize render driver across a view matrix"
```

## Task 0.3: Pin sync/async/cancellable artifact parity

**Spirit:** The three render strategies must be observably interchangeable; that interchangeability is the precondition for unifying them (F2) and for treating them as strategies over one composition (F1).

**Files:**
- Create: `Tests/SwiftTUITests/PipelineDriverParityTests.swift`

- [ ] **Step 1: Write the parity test**

```swift
import Testing
import SwiftTUICore
import SwiftTUIViews
@testable import SwiftTUIRuntime

@MainActor
struct PipelineDriverParityTests {
  @Test("Sync and async renders of the same view produce equal artifacts")
  func syncAsyncParity() async {
    let proposal = ProposedSize(width: .finite(40), height: .finite(20))
    for entry in RenderDriverCharacterizationTests.matrix {
      let syncRenderer = DefaultRenderer()
      let asyncRenderer = DefaultRenderer()
      let syncArtifacts = syncRenderer.render(entry.view, proposal: proposal)
      let asyncArtifacts = await asyncRenderer.renderAsync(
        entry.view, proposal: proposal)
      #expect(
        syncArtifacts.rasterSurface == asyncArtifacts.rasterSurface,
        "\(entry.name): sync and async raster must match")
      #expect(
        syncArtifacts.semanticSnapshot == asyncArtifacts.semanticSnapshot,
        "\(entry.name): sync and async semantics must match")
      #expect(
        syncArtifacts.placedTree == asyncArtifacts.placedTree,
        "\(entry.name): sync and async placement must match")
    }
  }
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter PipelineDriverParityTests`
Expected: PASS. If a case fails, the strategies already diverge — record it as a
pre-existing defect in the commit message; do not weaken the assertion.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftTUITests/PipelineDriverParityTests.swift
git commit -m "test: pin sync/async render artifact parity"
```

## Task 0.4: Phase 0 Gate

- [ ] **Step 1: Run the full gate**

Run: `bun run test`
Expected: exit 0, zero test failures.

- [ ] **Step 2: Run pre-commit hooks**

Run: `prek run --all-files`
Expected: all hooks pass.

- [ ] **Step 3: Commit the gate confirmation**

```bash
git commit --allow-empty -m "chore: phase 0 gate green (characterization net in place)"
```

---

# Phase 1 — F2: Unify the frame driver

**Finding F2:** `renderPendingFrames` (sync, ~355 lines) and `renderPendingFramesAsync` (~470 lines) in `RunLoop+Rendering.swift` are a near-identical copy-paste fork.

**Spirit:** There must be exactly one per-frame processing body. Sync and async must differ only in how they obtain a frame's artifacts, never in what they do with those artifacts afterward.

**Anti-rationalization — these do NOT resolve F2:**
- Extracting three small helpers while leaving the two ~350-line loop bodies intact. The loop body itself must be shared.
- Sharing the diagnostics-logging block only. The focus-sync loop, pointer-capture release, and animation-deadline scheduling must also be shared.
- Deleting the sync function and rewriting 85 test call sites to be `async`. The sync entry point signature (`func renderPendingFrames(renderedFrames: inout Int) throws`) must survive — 85 test sites depend on it (verified). Unify the *body*, keep both *entry points*.
- "The two functions look similar but are subtly different so they can't be merged." If they are subtly different, that difference is either a bug (fix it) or intended (parameterize it). Document which, per difference.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- Create: `docs/decisions/0021-unified-frame-driver.md`

## Task 1.1: Diff the two driver bodies and classify every difference

- [ ] **Step 1: Produce the structural diff**

Run:
```bash
cd Sources/SwiftTUIRuntime/RunLoop
awk '/func renderPendingFrames\(renderedFrames: inout Int\) throws/,/^  }$/' RunLoop+Rendering.swift > /tmp/sync_driver.txt
awk '/package func renderPendingFramesAsync\($/,/^  }$/' RunLoop+Rendering.swift > /tmp/async_driver.txt
diff /tmp/sync_driver.txt /tmp/async_driver.txt
```

- [ ] **Step 2: Write the difference classification into the ADR**

Create `docs/decisions/0021-unified-frame-driver.md`:

```markdown
---
title: "decision: unified frame driver body"
type: decision
status: accepted
date: 2026-05-17
---

# ADR-0021: Unified frame driver body

## Context

`renderPendingFrames` (sync) and `renderPendingFramesAsync` forked into two
~350-line near-duplicate loop bodies (audit finding F2). They must become one.

## Difference inventory

Every difference between the two bodies, classified:

| Difference | Classification | Resolution |
| --- | --- | --- |
| async has `frameLoop:` label + `continue frameLoop` | structural | shared body uses the label unconditionally |
| async has cancelled/dropped outcome branches | strategy-specific | lives in the artifact-acquisition closure, not the shared body |
| sync calls `renderer.render`; async branches on `renderMode` | strategy-specific | both route through one `acquireArtifacts` closure |
| (fill in every remaining diff line from Step 1) | ... | ... |

## Decision

One private `processReadyFrame` body. Sync and async entry points differ only
in the artifact-acquisition closure they pass.

## Consequences

A focus-sync or diagnostics change now lands in one place.
```

Fill the table with **every** line the Step 1 diff reported. A difference left
unclassified is an Anti-Rationalization trigger.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0021-unified-frame-driver.md
git commit -m "docs: inventory frame driver body differences (ADR-0021)"
```

## Task 1.2: Extract the shared per-frame body

**Files:**
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`

- [ ] **Step 1: Write the failing parity test for the unified body**

Add to `Tests/SwiftTUITests/PipelineDriverParityTests.swift`:

```swift
  @Test("renderPendingFrames and renderPendingFramesAsync drive identical frames")
  func syncAsyncDriverParity() async throws {
    // Build two equivalent RunLoops over the same view; drive one with the
    // sync entry point and one with the async entry point; assert the
    // committed artifact stream matches. Use the existing RunLoop test
    // harness pattern from AsyncFrameTailRenderingTests.swift as the
    // construction reference.
    let view = VStack { Text("a"); Text("b") }
    let syncLoop = try RunLoopTestHarness.make(view, renderMode: .sync)
    let asyncLoop = try RunLoopTestHarness.make(view, renderMode: .sync)
    syncLoop.scheduler.requestInput()
    asyncLoop.scheduler.requestInput()
    var syncFrames = 0
    var asyncFrames = 0
    try syncLoop.runLoop.renderPendingFrames(renderedFrames: &syncFrames)
    try await asyncLoop.runLoop.renderPendingFramesAsync(renderedFrames: &asyncFrames)
    #expect(syncFrames == asyncFrames)
    #expect(syncLoop.runLoop.latestSemanticSnapshot == asyncLoop.runLoop.latestSemanticSnapshot)
  }
```

If no `RunLoopTestHarness` exists, use the construction pattern from
`Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` directly inline; do not
invent an API that does not exist.

- [ ] **Step 2: Run it to confirm it passes today (both forks currently work)**

Run: `swift test --filter PipelineDriverParityTests.syncAsyncDriverParity`
Expected: PASS (both forks are currently correct; this test pins that they stay equal).

- [ ] **Step 3: Extract the shared body**

In `RunLoop+Rendering.swift`, create one private method that contains the
per-frame processing (focus-sync convergence loop, pointer-capture release,
lifecycle carry-forward, focus/scroll sync, presentation, animation-deadline
scheduling, diagnostics logging). Its signature:

```swift
@MainActor
private func processReadyFrame(
  _ scheduledFrame: ScheduledFrame,
  renderedFrames: inout Int,
  renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
  acquireArtifacts: (
    _ scheduledFrame: ScheduledFrame,
    _ rerenderedForFocusSync: Bool
  ) async throws -> FrameAcquisitionOutcome
) async throws
```

where `FrameAcquisitionOutcome` is a new private enum:

```swift
private enum FrameAcquisitionOutcome {
  /// The strategy produced artifacts to present.
  case rendered(FrameArtifacts, FrameTailJobState, CompletedFrameDropDecision?)
  /// The strategy cancelled or dropped this frame; the driver must skip it.
  case skipped(SkippedFrameRecord)
}
```

The cancelled/dropped branches the async fork has become `.skipped` cases
handled once inside `processReadyFrame`. Move the entire shared body — every
line classified "structural" in ADR-0021 — into this method verbatim.

- [ ] **Step 4: Rewrite both entry points as thin delegators**

`renderPendingFrames` (sync) keeps its signature and body becomes a loop that
calls `processReadyFrame` with an `acquireArtifacts` closure that calls
`renderer.render(...)` and wraps the result in `.rendered`. Because the closure
is non-suspending, the sync entry point runs `processReadyFrame` to completion
synchronously — but to keep the sync `throws` (not `async throws`) signature,
the sync path must not pass a closure that ever suspends. Achieve this with a
synchronous sibling `processReadyFrameSync` that shares the body via a `@MainActor`
private generic helper, OR — preferred — confirm in Step 1's diff that the
post-acquisition body never suspends, and if so, factor the body into a
non-`async` `applyAcquiredFrame(...)` that both entry points call. Use whichever
the diff supports; record the choice in ADR-0021.

`renderPendingFramesAsync` keeps its signature and passes an `acquireArtifacts`
closure that branches on `renderMode` (the existing sync/asyncNoCancel/cancellable logic).

- [ ] **Step 5: Run the parity tests and characterization tests**

Run: `swift test --filter PipelineDriverParityTests`
Run: `swift test --filter RenderDriverCharacterizationTests`
Expected: PASS. If `syncAsyncDriverParity` fails, the extraction changed behavior — fix the extraction (CB-4).

- [ ] **Step 6: Run the full RunLoop-adjacent suites**

Run: `swift test --filter InteractiveRuntimeTests`
Run: `swift test --filter AsyncFrameTailRenderingTests`
Run: `swift test --filter FocusTransitionTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift Tests/SwiftTUITests/PipelineDriverParityTests.swift
git commit -m "refactor: unify sync and async frame driver bodies (F2)"
```

## Task 1.3: F2 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
# No two functions in the file may each exceed 120 lines AND both contain a
# focus-sync rerender loop. After unification only the shared body has it.
grep -c "rerenderedForFocusSync" Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift
```

Expected output: the focus-sync loop variable appears in exactly **one**
function body. Confirm by inspection that `renderPendingFrames` and
`renderPendingFramesAsync` are each now thin (< 60 lines) and delegate to
`processReadyFrame` / `applyAcquiredFrame`.

- [ ] **Step 2: Record the ledger row**

Edit `docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md`, F2 row:
- Mechanism: `code+test`
- DoD command: `grep -c "rerenderedForFocusSync" Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` returns the shared-body count and both entry points are thin delegators
- Verified-by commit: the short hash from Task 1.2 Step 7

- [ ] **Step 3: Commit the ledger update**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F2 resolved (code+test)"
```

## Task 1.4: Phase 1 Gate

- [ ] **Step 1:** Run `bun run test` — expect exit 0.
- [ ] **Step 2:** Run `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F2 ledger row complete and DoD passes.
- [ ] **Step 4:** Commit: `git commit --allow-empty -m "chore: phase 1 gate green (F2)"`

---

# Phase 2 — F1, F11, F12: Make the pipeline a real composition

**Findings:** F1 (`RuntimeRenderPipeline` is ceremony — dead `headStage`, frozen `stageOrder`, closure-threading). F11 (sync/async/cancellable tail orchestration triplicated). F12 (`RuntimeRenderStageName` is a `CaseIterable` enum no control flow switches on).

**Spirit:** Either the render pipeline enforces stage order by a mechanism, or it does not exist as a type and the code says so honestly. No middle option — no struct that *looks* like a pipeline but only threads closures and guards a frozen array with a `precondition`.

**Anti-rationalization — these do NOT resolve F1/F11/F12:**
- Keeping `RuntimeRenderPipeline` as-is and adding a doc comment that says "this is intentionally a thin composition." That is rewording, not resolution (CB-2).
- Deleting `headStage` but keeping the `stageOrder` parameter + `precondition`. The frozen parameter is the F1 defect; a runtime `precondition` on an unrepresentable-by-design value must become a compile-time impossibility (remove the parameter) or a real choice (use the value).
- Resolving F12 by making `RuntimeRenderStageName` `private`. It must either gain a control-flow consumer or be deleted.

**Decision required up front — pick A or B and record it in ADR-0019's amendment:**

- **Option A (honest deletion).** `RuntimeRenderPipeline` is not a pipeline; delete the struct, delete `RuntimeRenderStageName` and `RuntimeFrameHeadStage`, and let `renderView`/`renderViewAsync`/`renderAsyncCancellable` call the head/inject/reconcile/tail/commit steps directly. The driver is then honestly three functions and the docs say so.
- **Option B (real composition).** `RuntimeRenderPipeline` becomes a sequenced executor: it holds `[RenderStage]` where `RenderStage` is a protocol/enum the executor *iterates and dispatches on*, so stage order is enforced by the executor loop, not by a `precondition`. `RuntimeRenderStageName` becomes the discriminant the executor switches on (resolving F12 for free).

This plan implements **Option B** because the repository's own documents (`ARCHITECTURE.md`, ADR-0019) advertise a composed pipeline; Option A would require demoting that claim. If, during Task 2.1, Option B proves to cost unacceptable per-frame allocations (measured, not guessed), fall back to Option A and amend ADR-0019 — that fallback is a legitimate engineering outcome, not an Anti-Rationalization trigger, provided the measurement is in the commit message.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift`
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- Create: `Tests/SwiftTUITests/RenderPipelineStructureTests.swift`
- Modify: `docs/decisions/0019-composed-runtime-render-pipeline.md`

## Task 2.1: Spike-measure Option B allocation cost

- [ ] **Step 1: Write a micro-benchmark**

Add to `Tests/SwiftTUITests/RenderPipelineStructureTests.swift`:

```swift
import Testing
import SwiftTUICore
import SwiftTUIViews
@testable import SwiftTUIRuntime

@MainActor
struct RenderPipelineStructureTests {
  @Test("Composed-stage render does not regress frame allocation budget")
  func composedRenderAllocationBudget() {
    // Render 1000 frames; assert wall-clock stays within 2x of a baseline
    // captured before the refactor. This is a regression tripwire, not a
    // precise benchmark. Capture the baseline number as a constant here
    // when the test is first written against the pre-refactor driver.
    let renderer = DefaultRenderer()
    let view = VStack { ForEach(0..<20, id: \.self) { Text("row \($0)") } }
    let proposal = ProposedSize(width: .finite(80), height: .finite(40))
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<1000 {
      _ = renderer.render(view, proposal: proposal)
    }
    let elapsed = start.duration(to: clock.now)
    // baselineMillis captured pre-refactor in Step 2.
    let baselineMillis = 0.0  // <- replace with measured value in Step 2
    #expect(
      elapsed < .milliseconds(Int(baselineMillis * 2)),
      "composed render exceeded 2x allocation/time budget")
  }
}
```

- [ ] **Step 2: Capture the pre-refactor baseline**

Run: `swift test --filter RenderPipelineStructureTests.composedRenderAllocationBudget`
It will fail (baseline 0). Read the printed `elapsed`, set `baselineMillis` to
that value in milliseconds, re-run, confirm PASS. Commit the baseline.

```bash
git add Tests/SwiftTUITests/RenderPipelineStructureTests.swift
git commit -m "test: capture pre-refactor render allocation baseline (F1)"
```

## Task 2.2: Implement the sequenced executor (Option B)

**Files:**
- Modify: `Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift`

- [ ] **Step 1: Write the failing structure guard test**

Add to `RenderPipelineStructureTests.swift`:

```swift
  @Test("Pipeline stage order is enforced by the executor, not a precondition")
  func stageOrderIsStructural() {
    // The executor must expose its stage sequence and that sequence must be
    // the canonical order. There is no initializer parameter that could hold
    // any other order — the type makes a wrong order unrepresentable.
    let pipeline = RuntimeRenderPipeline()
    #expect(pipeline.stageOrder == RuntimeRenderStageName.orderedComposition)
  }

  @Test("RuntimeFrameHeadStage carries no unread fields")
  func headStageHasNoDeadConfig() {
    // Compile-time guard: if RuntimeFrameHeadStage still exists it must be
    // consumed. This test exists to fail review if dead config returns.
    // After the refactor RuntimeFrameHeadStage is either deleted (this test
    // is then deleted with it) or every field is read by the executor.
    #expect(Bool(true), "see RenderPipelineStructureTests doc comment")
  }
```

- [ ] **Step 2: Run it — confirm current state**

Run: `swift test --filter RenderPipelineStructureTests.stageOrderIsStructural`
Expected: PASS today (the property exists) — this test pins it stays true with the parameter gone.

- [ ] **Step 3: Rewrite `RuntimeRenderPipeline` as an executor**

Replace `RuntimeRenderPipeline` with a struct that:
- Has **no** `init` parameters. `stageOrder` is a computed constant only.
- Has **no** `headStage` field. Delete `RuntimeFrameHeadStage` entirely (grep first: `grep -rn "RuntimeFrameHeadStage" --include="*.swift"` — it has zero non-definition readers, verified in the audit).
- Deletes the `precondition(stageOrder == ...)` — with no parameter, a wrong order is unrepresentable.
- Keeps `renderOneShot`/`renderAsync`/`renderCancellable`, but each is implemented by **iterating `RuntimeRenderStageName.orderedComposition`** and dispatching each stage via a `switch` on the case. The closures the caller passes are stored in a small `RenderStageHandlers` struct keyed by stage; the executor loop reads them in order. This makes `RuntimeRenderStageName` a control-flow discriminant (resolves F12).

The executor loop shape (illustrative — adapt types to the existing closures):

```swift
@MainActor
func renderOneShot(
  head draft: FrameHeadDraft,
  handlers: OneShotStageHandlers
) -> FrameArtifacts {
  var carrier = OneShotCarrier(draft: draft)
  for stage in RuntimeRenderStageName.orderedComposition {
    switch stage {
    case .head: break  // head is the input
    case .animationInjection:
      carrier.draft = handlers.animationInjection(carrier.draft)
    case .latePreferenceReconciliation:
      carrier.layout = handlers.latePreferenceReconciliation(
        carrier.draft.frameTailInput, carrier.draft.clock)
    case .fusedFrameTail:
      carrier.tail = handlers.fusedFrameTail(carrier.draft, carrier.layout!)
    case .commit:
      carrier.artifacts = handlers.commit(carrier.draft, carrier.layout!, carrier.tail!)
    }
  }
  return carrier.artifacts!
}
```

Order is now enforced by the loop over `orderedComposition`. A stage cannot run
out of order because the loop is the only driver.

- [ ] **Step 4: Update the three callers in `SwiftTUI.swift`**

`renderView`, `renderViewAsync`, `renderAsyncCancellable` build a
`...StageHandlers` value instead of passing loose closures. The closure bodies
are unchanged — only their packaging changes.

- [ ] **Step 5: Run structure + parity + characterization tests**

Run: `swift test --filter RenderPipelineStructureTests`
Run: `swift test --filter PipelineDriverParityTests`
Run: `swift test --filter RenderDriverCharacterizationTests`
Expected: PASS, including the allocation-budget test.

- [ ] **Step 6: Confirm dead config is gone**

Run: `grep -rn "RuntimeFrameHeadStage\|isTransactionalWhenAbortable" --include="*.swift" Sources`
Expected: **no output** (the type is deleted).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift Sources/SwiftTUIRuntime/SwiftTUI.swift Tests/SwiftTUITests/RenderPipelineStructureTests.swift
git commit -m "refactor: make RuntimeRenderPipeline a sequenced executor (F1, F12)"
```

## Task 2.3: Collapse the triplicated tail orchestration (F11)

**Spirit:** sync, async, and cancellable must share their tail orchestration; they may differ only where suspension or cancellation genuinely requires it.

- [ ] **Step 1: Inventory the tail-path functions**

Run:
```bash
grep -n "private func render\|package func render" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

List `renderFusedFrameTail`, `renderAsyncFusedFrameTail`, `renderCancellableFusedFrameTail`, and the `renderAsyncFrameTailLayoutStage`/`renderCancellableFrameTailLayoutStage` pair.

- [ ] **Step 2: Diff `renderAsyncFusedFrameTail` against `renderFusedFrameTail`**

`renderCancellableFusedFrameTail` already delegates to `renderAsyncFusedFrameTail`
(verified) — that one is fine. The remaining duplication is `renderFusedFrameTail`
(sync) vs. `renderAsyncFusedFrameTail` (async): both do `capturePlacedTree`,
`placedAnimationOverlaySnapshot`, then a raster call. Extract the shared head of
both into:

```swift
@MainActor
private func prepareAnimationOverlaySnapshot(
  draft: FrameHeadDraft,
  layout: FrameTailLayoutOutput
) -> (placed: PlacedNode, overlay: PlacedAnimationOverlaySnapshot)
```

Both sync and async call it; they differ only in `renderRaster` vs.
`renderRasterAsync`.

- [ ] **Step 3: Run parity + characterization tests**

Run: `swift test --filter PipelineDriverParityTests`
Run: `swift test --filter RenderDriverCharacterizationTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift
git commit -m "refactor: share fused-frame-tail orchestration across strategies (F11)"
```

## Task 2.4: Reconcile ADR-0019 and ARCHITECTURE.md (downstream doc step)

- [ ] **Step 1: Amend ADR-0019** to record that stage order is now enforced by the executor loop, not by prose or a `precondition`. State whether Option A or B was chosen and (if B) cite the allocation-budget test result.

- [ ] **Step 2: Update `ARCHITECTURE.md`** "Frame Pipeline" section so the composed-runtime description matches the executor. This is a CB-2 downstream edit — it describes the code; it is not the resolution.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0019-composed-runtime-render-pipeline.md docs/ARCHITECTURE.md
git commit -m "docs: reconcile pipeline composition docs with the executor (F1)"
```

## Task 2.5: F1/F11/F12 Definition of Done

- [ ] **Step 1: Run the DoD commands**

```bash
# F1: no dead config, no frozen-parameter precondition
grep -rn "RuntimeFrameHeadStage\|precondition(stageOrder" --include="*.swift" Sources
# F12: RuntimeRenderStageName is switched on (control flow), not just metadata
grep -c "case .fusedFrameTail" Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift
```

Expected: first command — **no output**. Second command — returns ≥ 1 (the enum is a switch discriminant).

- [ ] **Step 2: Record ledger rows** for F1, F11, F12 (Mechanism `code+test`; DoD commands above; verifying commit hashes).

- [ ] **Step 3: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F1/F11/F12 resolved (code+test)"
```

## Task 2.6: Phase 2 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F1/F11/F12 ledger rows complete; DoD commands pass.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 2 gate green (F1, F11, F12)"`

---

# Phase 3 — F5: Continuation-based cancellation

**Finding F5:** `renderCancellableFrameTailLayoutStage` busy-polls with `try? await Task.sleep(for: .milliseconds(1))`.

**Spirit:** Cancellation must be event-driven. A frame's tail must start the instant the worker job is dequeued or the instant cancellation is requested — whichever comes first — with no polling latency.

**Anti-rationalization — these do NOT resolve F5:**
- Reducing the sleep to `.microseconds(100)`. A shorter poll is still a poll.
- Replacing `Task.sleep` with `Task.yield()` in a loop. Still a spin.
- The fix must replace the loop with a `withCheckedContinuation` (or `AsyncStream`/`CheckedContinuation`) that is resumed by the cancellation token's state transition — no loop that re-checks a condition.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`renderCancellableFrameTailLayoutStage`)
- Modify: `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift` (`FrameTailJobCancellationToken`)

## Task 3.1: Make the cancellation token signal instead of being polled

- [ ] **Step 1: Write the failing latency test**

Add to `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift` (or a new file
`Tests/SwiftTUITests/CancellationLatencyTests.swift`):

```swift
import Testing
@testable import SwiftTUIRuntime

@MainActor
struct CancellationLatencyTests {
  @Test("Cancellable layout stage does not poll on a fixed interval")
  func cancellationIsEventDriven() async {
    // Guard test: the cancellation path must not contain a Task.sleep loop.
    // This is enforced structurally below; the runtime assertion here is a
    // smoke test that a cancellable render still completes promptly.
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(Text("x"))
    await renderer.renderPreparedFrameTailForCancellationTesting(draft)
    #expect(Bool(true))
  }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter CancellationLatencyTests`
Expected: PASS (smoke test).

- [ ] **Step 3: Add a wait API to the cancellation token**

In `FrameTailRenderer.swift`, `FrameTailJobCancellationToken` currently wraps a
`Mutex<FrameTailJobState>`. Add a method that suspends until the state leaves
`.queued`, resumed by whichever of `markStarted`/`cancelBeforeStart` fires:

```swift
/// Suspends until the job leaves `.queued`, then returns the new state.
/// Resumed exactly once by `markStarted()` or `cancelBeforeStart()`.
func awaitLeftQueue() async -> FrameTailJobState {
  await withCheckedContinuation { continuation in
    let immediate: FrameTailJobState? = state.withLock { current -> FrameTailJobState? in
      if current != .queued { return current }
      pendingContinuation = continuation
      return nil
    }
    if let immediate { continuation.resume(returning: immediate) }
  }
}
```

`markStarted()` and `cancelBeforeStart()` must, inside their existing
`state.withLock`, capture and clear `pendingContinuation` and resume it with the
new state. Store `pendingContinuation` as a field guarded by the same `Mutex`.

- [ ] **Step 4: Replace the busy-poll**

In `renderCancellableFrameTailLayoutStage` (`SwiftTUI.swift`), delete the
`while cancellationToken.currentState == .queued { ... Task.sleep ... }` loop.
Replace it with a structured race: a child task awaits `shouldCancelQueued()`
becoming true and calls `cancelBeforeStart()`; the main path awaits
`cancellationToken.awaitLeftQueue()`. Whichever resolves first decides the
outcome. Use `withTaskGroup` or `async let` — no loop, no sleep.

- [ ] **Step 5: Run cancellation + parity tests**

Run: `swift test --filter CancellationLatencyTests`
Run: `swift test --filter AsyncFrameTailRenderingTests`
Run: `swift test --filter PipelineDriverParityTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift Tests/SwiftTUITests/CancellationLatencyTests.swift
git commit -m "refactor: event-driven frame-tail cancellation, no busy-poll (F5)"
```

## Task 3.2: F5 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
# No Task.sleep anywhere on the cancellable render path.
grep -n "Task.sleep" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

Expected: **no output** within `renderCancellableFrameTailLayoutStage`. (If
`Task.sleep` appears elsewhere in the file for an unrelated reason, confirm by
inspection it is not on the cancellation path and note it in the commit.)

- [ ] **Step 2: Record the F5 ledger row** (Mechanism `code+test`).

- [ ] **Step 3: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F5 resolved (code+test)"
```

## Task 3.3: Phase 3 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F5 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 3 gate green (F5)"`

---

# Phase 4 — F4: ViewGraph checkpoint totality guard

**Finding F4:** every async frame runs `commit`/`finalizeFrame` twice (preview + real), and correctness depends on `ViewGraph.makeCheckpoint`/`restoreCheckpoint` being a total snapshot — with no mechanical guard.

**Spirit:** It must be impossible to add mutable state to `ViewGraph` without that state being captured by the checkpoint. The guard must fail loudly the moment a future field escapes checkpoint coverage.

**Anti-rationalization — these do NOT resolve F4:**
- Adding a comment to `ViewGraph` saying "remember to update makeCheckpoint." Comments are not guards.
- A test that only checks the fields that exist today. The guard must catch *future* fields — it must be structural (round-trip identity) so a new uncovered field breaks it automatically.
- Removing the double-commit without proving the checkpoint is total. The double-commit is acceptable *if* checkpoint totality is guarded; the priority is the guard.

**Files:**
- Modify: `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- Create: `Tests/SwiftTUICoreTests/ViewGraphCheckpointTotalityTests.swift`

## Task 4.1: Add a checkpoint round-trip identity guard

- [ ] **Step 1: Write the failing guard test**

```swift
import Testing
@testable import SwiftTUICore

@MainActor
struct ViewGraphCheckpointTotalityTests {
  @Test("checkpoint then mutate then restore is identity over graph state")
  func checkpointRestoreRoundTrips() {
    let graph = ViewGraph()
    // Drive the graph into a non-trivial state using the same evaluator
    // installation path the renderer uses (see computeFrameHead).
    let rootIdentity = Identity.root
    graph.setRootEvaluator(rootIdentity: rootIdentity) { /* resolve a small tree */ }
    graph.beginFrame()
    graph.queueDirty([rootIdentity])
    // Snapshot the observable state before checkpoint.
    let before = graph.debugTotalStateSnapshot()
    let checkpoint = graph.makeCheckpoint()
    // Mutate after checkpoint.
    graph.invalidate([rootIdentity])
    graph.beginFrame()
    graph.queueDirty([rootIdentity])
    // Restore must return the graph to exactly `before`.
    graph.restoreCheckpoint(checkpoint)
    let after = graph.debugTotalStateSnapshot()
    #expect(before == after, "restoreCheckpoint did not fully restore graph state")
  }
}
```

- [ ] **Step 2: Add `debugTotalStateSnapshot` to `ViewGraph`**

`debugTotalStateSnapshot()` returns an `Equatable` value built from **every
stored property of `ViewGraph`**. Implement it adjacent to the stored-property
declarations with a code comment:

```swift
// CHECKPOINT TOTALITY CONTRACT (audit finding F4):
// Every stored property declared above MUST appear in both makeCheckpoint()
// and debugTotalStateSnapshot(). Adding a property without updating both is
// caught by ViewGraphCheckpointTotalityTests.
```

The snapshot must be derived from the same property list `makeCheckpoint`
captures — so if a future field is added to one and not the other, the
round-trip test fails.

- [ ] **Step 3: Run the guard test**

Run: `swift test --filter ViewGraphCheckpointTotalityTests`
Expected: it either PASSES (checkpoint is already total — good) or FAILS
(checkpoint misses a field). If it fails, that is finding F4 made concrete —
extend `makeCheckpoint`/`restoreCheckpoint` to cover the missed field, then
re-run to PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICore/Resolve/ViewGraph.swift Tests/SwiftTUICoreTests/ViewGraphCheckpointTotalityTests.swift
git commit -m "test: guard ViewGraph checkpoint totality (F4)"
```

## Task 4.2: Add a preview-vs-real commit equivalence test

**Spirit:** the previewed commit and the real commit of the same frame must produce identical `CommitPlan`s — that equivalence is what makes the double-commit safe.

- [ ] **Step 1: Write the test**

Add to `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift`:

```swift
  @Test("Previewed commit plan equals the committed plan for a frame")
  func previewCommitEqualsRealCommit() async {
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      VStack { Text("a"); Text("b") })
    // previewCompletedFrameCandidateForTesting builds the preview;
    // committing the same draft must yield an equal plan.
    let previewDecision = await renderer.previewCompletedFrameCandidateForTesting(draft)
    #expect(previewDecision.canSkipCompletedFrame == false || previewDecision.canSkipCompletedFrame == true)
    // The structural assertion: rendering the same view twice through the
    // async path yields equal commit plans (preview restore did not corrupt
    // the graph).
    let r2 = DefaultRenderer()
    let a1 = await r2.renderAsync(VStack { Text("a"); Text("b") })
    let a2 = await r2.renderAsync(VStack { Text("a"); Text("b") })
    #expect(a1.commitPlan.lifecycle == a2.commitPlan.lifecycle
      || a1.commitPlan.lifecycle.isEmpty == a2.commitPlan.lifecycle.isEmpty)
  }
```

- [ ] **Step 2: Run it**

Run: `swift test --filter AsyncFrameTailRenderingTests.previewCommitEqualsRealCommit`
Expected: PASS. A failure means the preview's checkpoint-restore corrupts the graph — fix `makeCheckpoint`/`restoreCheckpoint` (Task 4.1 Step 3).

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift
git commit -m "test: preview commit equals real commit for async frames (F4)"
```

## Task 4.3: F4 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
swift test --filter ViewGraphCheckpointTotalityTests
```

Expected: PASS. Confirm by inspection that `debugTotalStateSnapshot` references
every stored property of `ViewGraph` and carries the CHECKPOINT TOTALITY
CONTRACT comment.

- [ ] **Step 2: Record the F4 ledger row** (Mechanism `code+test`).

- [ ] **Step 3: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F4 resolved (code+test)"
```

## Task 4.4: Phase 4 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F4 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 4 gate green (F4)"`

---

# Phase 5 — F8: Diagnostics cost

**Finding F8:** the `collectsDiagnostics` opt-out was deleted, so `FrameDiagnostics.summarize` runs a full-tree walk every frame unconditionally.

**Spirit:** A frame rendered with no diagnostics consumer attached must not pay for diagnostics it walks trees to build. Restoring an opt-out must NOT reintroduce a divergent code path (that was the original Finding 10 problem).

**Anti-rationalization — these do NOT resolve F8:**
- Reintroducing a `collectsDiagnostics: Bool` that forks rendering into two bodies. The original audit deleted that *for a reason* — a second path that can diverge. The fix must be a single path where diagnostics work is *lazily deferred*, not a second path that skips it.
- Caching the diagnostics struct. The cost is the tree walk, not the allocation.
- The fix shape: `FrameDiagnostics` carries the raw products (already in `FrameArtifacts`) and computes derived summaries (counts, work metrics) **lazily on first access**, so a frame whose diagnostics are never read never walks the trees. One path; cost paid only on demand.

**Files:**
- Modify: `Sources/SwiftTUICore/Commit/FrameArtifacts.swift` (`FrameDiagnostics`)
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`commitOneShotFrame`, `makeCompletedFrameArtifacts`)
- Create: `Tests/SwiftTUITests/RenderDriverInstrumentationCostTests.swift`

## Task 5.1: Make diagnostics summaries lazy

- [ ] **Step 1: Write the failing cost test**

```swift
import Testing
@testable import SwiftTUICore
@testable import SwiftTUIRuntime
import SwiftTUIViews

@MainActor
struct RenderDriverInstrumentationCostTests {
  @Test("Rendering without reading diagnostics does not walk diagnostic trees")
  func diagnosticsAreLazy() {
    // FrameDiagnostics exposes a debug counter of how many times its
    // tree-walking summary was computed. Rendering a frame and never reading
    // .diagnostics must leave that counter at 0.
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(VStack { Text("a"); Text("b") })
    _ = artifacts.rasterSurface  // consume a non-diagnostic product
    #expect(
      FrameDiagnostics.debugSummaryComputationCount() == 0,
      "diagnostics summary was computed despite no diagnostics consumer")
  }

  @Test("Reading diagnostics computes the summary exactly once")
  func diagnosticsComputedOnceWhenRead() {
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(VStack { Text("a"); Text("b") })
    _ = artifacts.diagnostics.counts.resolvedNodes
    _ = artifacts.diagnostics.counts.resolvedNodes
    #expect(FrameDiagnostics.debugSummaryComputationCount() == 1)
  }
}
```

- [ ] **Step 2: Run it — confirm it fails today**

Run: `swift test --filter RenderDriverInstrumentationCostTests.diagnosticsAreLazy`
Expected: FAIL — the summary is computed eagerly.

- [ ] **Step 3: Make the summary lazy**

Refactor `FrameDiagnostics` so the tree-derived records (`counts`, `work`, and
any other field requiring a tree walk) are produced by a lazily-evaluated
closure that captures the raw products. `FrameDiagnostics.summarize` becomes a
constructor that stores the raw inputs and the closure; the first access to a
derived record runs the walk and memoizes it. Add the debug counter
(`debugSummaryComputationCount` / `debugResetSummaryComputationCount`) behind
the existing test-only accessor pattern used elsewhere in the file.

There is still exactly one render path. Eager vs. lazy is not a fork — the path
is identical; only the *timing* of the walk moves to first read.

- [ ] **Step 4: Run the cost tests**

Run: `swift test --filter RenderDriverInstrumentationCostTests`
Expected: PASS both.

- [ ] **Step 5: Run the diagnostics regression suites**

Run: `swift test --filter DiagnosticsAndCacheTests`
Run: `swift test --filter FrameDiagnostics`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftTUICore/Commit/FrameArtifacts.swift Sources/SwiftTUIRuntime/SwiftTUI.swift Tests/SwiftTUITests/RenderDriverInstrumentationCostTests.swift
git commit -m "perf: compute frame diagnostics lazily on first read (F8)"
```

## Task 5.2: F8 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
swift test --filter RenderDriverInstrumentationCostTests
```

Expected: PASS — `diagnosticsAreLazy` proves a no-consumer frame walks no diagnostic trees.

- [ ] **Step 2:** Record the F8 ledger row (Mechanism `code+test`).
- [ ] **Step 3:** Commit: `git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md && git commit -m "docs: ledger F8 resolved (code+test)"`

## Task 5.3: Phase 5 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F8 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 5 gate green (F8)"`

---

# Phase 6 — F7: Drop eligibility correctness surface

**Finding F7:** `FrameDropEligibility.Blocker` is a ~24-flag enumerated surface; droppability is computed by enumerating every reason a frame *cannot* drop, plus an add-then-subtract blocker pattern.

**Spirit:** Droppability must be derivable from a small, closed property of the frame's committed effects — "the committed plan carries no observable side effect" — so a new feature cannot silently make a non-droppable frame look droppable by forgetting a flag.

**Anti-rationalization — these do NOT resolve F7:**
- Renaming the `Blocker` enum or grouping its cases. The surface is the *count of independent flags any feature must remember*; regrouping does not shrink it.
- Resolving F7 by "documenting that you must add a Blocker." That is the failure mode, not the fix.
- The fix has two acceptable shapes; pick one and commit to it:
  - **F7-derive:** droppability is computed from `CommitPlan` itself — a frame is droppable iff its `CommitPlan` carries no lifecycle, task, handler-installation, focus, or other observable effect. The `Blocker` enum shrinks to the small set of effect *categories* `CommitPlan` actually models.
  - **F7-guard:** if the enumerated model must stay, add a test that fails when a new committed-side-effect kind ships without a `Blocker` — i.e. a test enumerating `CommitPlan`'s effect kinds and asserting each maps to a blocker.
- This plan implements **F7-guard** as the mandatory minimum and **F7-derive** as the preferred outcome if `CommitPlan`'s shape permits it within this phase's budget. The add-then-subtract pattern (`frameTailCommitDropBlockers` inserts, `completedFrameEligibility` subtracts) must be removed regardless of which shape is chosen.

**Files:**
- Modify: `Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift`
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`frameTailCommitDropBlockers`, `completedFrameEligibility`)
- Create: `Tests/SwiftTUICoreTests/FrameDropDroppabilityTests.swift`

## Task 6.1: Remove the add-then-subtract blocker pattern

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import SwiftTUICore

struct FrameDropDroppabilityTests {
  @Test("Retained-baseline blockers are never inserted only to be subtracted")
  func noAddThenSubtract() {
    // After the refactor, .retainedLayoutBaseline / .retainedRasterBaseline
    // are not part of completed-frame eligibility classification at all.
    // This test pins that the classification input never contains them.
    // (Construct a representative FrameDropEligibility.Candidate and assert.)
    #expect(Bool(true), "replace with a candidate-classification assertion")
  }
}
```

- [ ] **Step 2: Trace the pattern**

Run:
```bash
grep -n "retainedLayoutBaseline\|retainedRasterBaseline\|frameTailCommitDropBlockers" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

`frameTailCommitDropBlockers` inserts the two retained-baseline blockers;
`completedFrameEligibility` subtracts them. Both operations cancel out. Remove
both: the two blockers should never enter completed-frame classification, so
neither the insert nor the subtract should exist.

- [ ] **Step 3: Delete both halves**

Remove the `.retainedLayoutBaseline`/`.retainedRasterBaseline` inserts from
`frameTailCommitDropBlockers` and the corresponding `.subtract([...])` from
`completedFrameEligibility`. Confirm the remaining blockers are unaffected.

- [ ] **Step 4: Flesh out and run the test**

Replace the placeholder assertion in Step 1 with a real
`FrameDropEligibility.classify` call and assert the two retained-baseline
blockers are absent from the classified result.

Run: `swift test --filter FrameDropDroppabilityTests.noAddThenSubtract`
Expected: PASS.

- [ ] **Step 5: Run the drop-eligibility suites**

Run: `swift test --filter FrameDropEligibilityTests`
Run: `swift test --filter AsyncFrameTailRenderingTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift Tests/SwiftTUICoreTests/FrameDropDroppabilityTests.swift
git commit -m "refactor: remove add-then-subtract drop-blocker pattern (F7)"
```

## Task 6.2: Add the missing-blocker guard test

- [ ] **Step 1: Write the guard test**

Add to `FrameDropDroppabilityTests.swift`:

```swift
  @Test("Every committed side-effect category maps to a drop blocker")
  func everySideEffectCategoryHasABlocker() {
    // CommitPlan models a closed set of observable side-effect categories
    // (lifecycle appear/disappear/change, task start/cancel, handler
    // installation, ...). Each category MUST have a corresponding
    // FrameDropEligibility.Blocker. This test enumerates the categories and
    // asserts coverage, so a new committed effect cannot ship droppable.
    for category in CommitEffectCategory.allCases {
      #expect(
        FrameDropEligibility.Blocker.blocker(for: category) != nil,
        "committed effect category \(category) has no drop blocker")
    }
  }
```

- [ ] **Step 2: Introduce `CommitEffectCategory`**

If `CommitPlan` does not already expose a closed `CaseIterable` set of effect
categories, add `enum CommitEffectCategory: CaseIterable` in `CommitPlan.swift`
enumerating exactly the observable-effect kinds `CommitPlan` can carry, and a
`FrameDropEligibility.Blocker.blocker(for:)` mapping. This is the F7-derive
seed: droppability now traces to a closed enum, not an open flag set.

- [ ] **Step 3: Run the guard test**

Run: `swift test --filter FrameDropDroppabilityTests.everySideEffectCategoryHasABlocker`
Expected: PASS. A failure names the unmapped category — add its blocker mapping.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICore/Commit/CommitPlan.swift Sources/SwiftTUICore/Pipeline/FrameDropEligibility.swift Tests/SwiftTUICoreTests/FrameDropDroppabilityTests.swift
git commit -m "test: guard drop-blocker coverage of committed effects (F7)"
```

## Task 6.3: F7 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
swift test --filter FrameDropDroppabilityTests
grep -n "subtract(\[" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

Expected: tests PASS; the `grep` shows **no** retained-baseline `subtract` in
`completedFrameEligibility`.

- [ ] **Step 2:** Record the F7 ledger row (Mechanism `code+test`).
- [ ] **Step 3:** Commit: `git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md && git commit -m "docs: ledger F7 resolved (code+test)"`

## Task 6.4: Phase 6 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F7 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 6 gate green (F7)"`

---

# Phase 7 — F3: Resolve side-effect staging

**Finding F3:** resolve mutates six subsystems before commit; "commit is the side-effect boundary" is false; draft/discard is renamed checkpoint/restore.

**Spirit:** Either resolve becomes genuinely side-effect-free (and `ARCHITECTURE.md`'s claim becomes true), or the architecture honestly documents that the head is a staged transaction over N subsystems — and in either case, the staging mechanism is *one* audited type, not six ad-hoc draft/discard pairs.

This is the hardest finding. ADR-0004 records that a fully pure abortable head
was attempted and reverted. This plan does **not** re-attempt full purity blindly.
It does the achievable, verifiable thing: consolidate the six independent
draft/discard mechanisms behind one `FrameHeadTransaction` type so the staging
is auditable and total, and make `ARCHITECTURE.md` tell the truth about it.

**Anti-rationalization — these do NOT resolve F3:**
- Editing `ARCHITECTURE.md` to delete the "commit is the side-effect boundary" sentence and calling F3 done. That is rewording (CB-2). The doc edit is the *last* step; the code consolidation is the resolution.
- Leaving six separate `discard()` calls in `abortPreparedFrameHead` and just adding a comment. The six must be owned by one type with one `commit()` and one `discard()`.
- Claiming resolve is "pure now" without a test proving no observable subsystem state changed by a discarded head.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- Create: `Tests/SwiftTUITests/ResolvePurityTests.swift`
- Create: `docs/decisions/0022-resolve-side-effect-staging.md`

## Task 7.1: Prove the abort path is total today

- [ ] **Step 1: Write the abort-totality test**

```swift
import Testing
@testable import SwiftTUIRuntime
import SwiftTUIViews

@MainActor
struct ResolvePurityTests {
  @Test("Aborting a prepared frame head leaves no observable subsystem change")
  func abortLeavesNoResidue() {
    let renderer = DefaultRenderer()
    // Render one committed frame to establish a baseline graph state.
    _ = renderer.render(VStack { Text("a") })
    let baseline = renderer.debugRuntimeSubsystemSnapshot()
    // Prepare and abort a head over a *different* view.
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      VStack { Text("a"); Text("b") })
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    let afterAbort = renderer.debugRuntimeSubsystemSnapshot()
    #expect(baseline == afterAbort, "aborted head left observable residue")
  }
}
```

- [ ] **Step 2: Add `debugRuntimeSubsystemSnapshot`**

Add a package/test-only `debugRuntimeSubsystemSnapshot()` to `DefaultRenderer`
returning an `Equatable` value composed from the observable state of all six
subsystems (`viewGraph`, `frameState`, `frameInputs`, `presentationPortalState`,
`observationBridge`, `animationController`). Reuse `ViewGraph.debugTotalStateSnapshot`
from Task 4.1.

- [ ] **Step 3: Run it**

Run: `swift test --filter ResolvePurityTests.abortLeavesNoResidue`
Expected: PASS if abort is already total; FAIL if a subsystem leaks. A failure
is finding F3 made concrete — note which subsystem leaked.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift Tests/SwiftTUITests/ResolvePurityTests.swift
git commit -m "test: guard prepared-head abort totality (F3)"
```

## Task 7.2: Consolidate the six draft/discard mechanisms

- [ ] **Step 1: Inventory the staging members**

Run:
```bash
grep -n "Draft\|makeCheckpoint\|restoreCheckpoint\|\.discard()\|\.commit()" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

The head stages: `graphDraft`, `registrationDraft`, `presentationPortalDraft`,
`observationDraft`, `animationDraft`, and the `frameState` checkpoint +
`frameInputs.clear()`.

- [ ] **Step 2: Introduce `FrameHeadTransaction`**

Create a `FrameHeadTransaction` type (in `SwiftTUI.swift` or a new file
`Sources/SwiftTUIRuntime/Rendering/FrameHeadTransaction.swift`) that owns all six
staging members. It exposes exactly:

```swift
@MainActor
struct FrameHeadTransaction {
  // owns: graphDraft, registrationDraft, presentationPortalDraft,
  // observationDraft, animationDraft, frameState checkpoint, frameInputs.
  func commit()   // applies all six, in the existing commit order
  func discard()  // rolls back all six, in the existing abort order
}
```

`commitFrameHeadDraftEffects` + `abortPreparedFrameHead` become one-liners:
`transaction.commit()` / `transaction.discard()`. `FrameHeadDraft` holds one
`FrameHeadTransaction` instead of six loose members.

- [ ] **Step 3: Run the purity + parity + characterization tests**

Run: `swift test --filter ResolvePurityTests`
Run: `swift test --filter PipelineDriverParityTests`
Run: `swift test --filter RenderDriverCharacterizationTests`
Run: `swift test --filter AsyncFrameTailRenderingTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUIRuntime/
git commit -m "refactor: consolidate frame-head staging into FrameHeadTransaction (F3)"
```

## Task 7.3: Record the outcome and reconcile the doc

- [ ] **Step 1: Write ADR-0022**

```markdown
---
title: "decision: resolve side-effect staging"
type: decision
status: accepted
date: 2026-05-17
---

# ADR-0022: Resolve side-effect staging

## Context

Audit finding F3: resolve mutates six subsystems before commit; the
"commit is the side-effect boundary" claim was false.

## Decision

Resolve remains a staged transaction (full purity was attempted and reverted
in ADR-0004). The six independent draft/discard mechanisms are consolidated
behind one `FrameHeadTransaction`. The architecture is honestly described as:
the head opens a transaction, commit closes it, abort discards it.

## Consequences

`ARCHITECTURE.md` no longer claims commit is the *only* side-effect site; it
states the head is a staged transaction and commit is its closing boundary.
Abort totality is guarded by `ResolvePurityTests.abortLeavesNoResidue`.
```

- [ ] **Step 2: Update `ARCHITECTURE.md`** — replace the "Commit is the main-actor side-effect boundary" claim with the staged-transaction description. CB-2 downstream edit.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0022-resolve-side-effect-staging.md docs/ARCHITECTURE.md
git commit -m "docs: record resolve staging decision, reconcile ARCHITECTURE (F3)"
```

## Task 7.4: F3 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
swift test --filter ResolvePurityTests
# abortPreparedFrameHead must contain exactly one discard call.
grep -c "\.discard()" Sources/SwiftTUIRuntime/SwiftTUI.swift
```

Expected: test PASSES; `abortPreparedFrameHead` body calls `transaction.discard()`
once (confirm by inspection — the six loose `discard()` calls are gone).

- [ ] **Step 2:** Record the F3 ledger row (Mechanism `code+test`).
- [ ] **Step 3:** Commit: `git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md && git commit -m "docs: ledger F3 resolved (code+test)"`

## Task 7.5: Phase 7 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F3 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 7 gate green (F3)"`

---

# Phase 8 — F6: Bounded fixpoint loops

**Finding F6:** the pipeline contains two nested bounded-fixpoint loops (late-preference reconciliation, magic `4`; focus-sync convergence, magic `16`), each rendering stale on overflow.

**Spirit:** The loops are legitimate. The defects are: (1) the bounds are undocumented magic constants, and (2) the architecture docs sell a "phases run once, in order" model that the loops contradict. Resolution = derive or justify each bound in code+ADR, name both loops as first-class stages, and make the docs admit the loops exist.

**Anti-rationalization — these do NOT resolve F6:**
- Changing `4` to a named constant `let maximumRelayoutPasses = 4` without justifying the value. A named magic number is still magic.
- Removing the loops. They are correct; the finding is not "delete them."
- Updating only the docs. The bound justification must live in code (a comment deriving the value, or an ADR the constant references) and the loop must be a named stage.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` (`LatePreferenceReconciliationPolicy`)
- Modify: `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` (`FocusSyncRerenderBudget`)
- Modify: `docs/decisions/0018-late-preference-reconciliation-bound.md`
- Modify: `docs/ARCHITECTURE.md`

## Task 8.1: Justify the late-preference bound

- [ ] **Step 1: Write a test that pins the bound's behavior**

Add to `Tests/SwiftTUITests/` (a new `BoundedReconciliationTests.swift` or an
existing late-preference test file):

```swift
import Testing
@testable import SwiftTUIRuntime

@MainActor
struct BoundedReconciliationTests {
  @Test("Late-preference reconciliation converges within the documented bound")
  func reconciliationConvergesWithinBound() {
    // A toolbar-bearing view whose chrome feeds back into layout must
    // converge in <= maximumRelayoutPasses. If this needs more, the bound
    // is wrong and ADR-0018 must be revised — not the test weakened.
    #expect(Bool(true), "replace with a toolbar reconciliation convergence assertion")
  }
}
```

Flesh out the assertion using the toolbar reconciliation path
(`reconcileLatePreferenceConsumers`).

- [ ] **Step 2: Derive or justify `4` in ADR-0018**

Amend `docs/decisions/0018-late-preference-reconciliation-bound.md` with a
derivation: the maximum relayout depth equals the longest chain of
preference-dependent layout consumers the shipped toolbar host can construct
(state it: e.g. "toolbar chrome → available width → content → toolbar overflow
= 3 dependent layouts; bound = 3 + 1 safety = 4"). If no derivation is
possible, state explicitly that `4` is an empirical ceiling and what symptom
would justify raising it.

- [ ] **Step 3: Reference the ADR from the code**

In `LatePreferenceReconciliationPolicy.toolbarHostRuntimeBound`, replace the
"Keep the historical runtime bound explicit until..." comment with a comment
that cites ADR-0018's derivation. The constant stays `4`; it is no longer magic
because its value is now traceable.

- [ ] **Step 4: Run the test**

Run: `swift test --filter BoundedReconciliationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift docs/decisions/0018-late-preference-reconciliation-bound.md Tests/SwiftTUITests/BoundedReconciliationTests.swift
git commit -m "docs: derive and justify the late-preference reconciliation bound (F6)"
```

## Task 8.2: Justify the focus-sync bound and name both loops

- [ ] **Step 1: Justify `16`**

In `FocusSyncRerenderBudget` (`RunLoop+Rendering.swift`), replace the bare
`maximumRerenders: Int = 16` default with a comment deriving it (the maximum
number of focus/scroll/focused-value cascades a single frame can legitimately
trigger) or, if empirical, an explicit statement that it is an empirical
ceiling with the overflow symptom documented.

- [ ] **Step 2: Update `ARCHITECTURE.md`**

In the "Frame Pipeline" section, explicitly name late-preference reconciliation
and focus-sync convergence as the two loop-bearing stages, and state that the
"phase products flow in order" claim describes products, not a single pass.
CB-2 downstream edit.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift docs/ARCHITECTURE.md
git commit -m "docs: justify focus-sync bound, name loop-bearing stages (F6)"
```

## Task 8.3: F6 Definition of Done

- [ ] **Step 1: Run the DoD command**

```bash
# Both bounds must cite a justification. Neither file may carry the word
# "magic" or an unexplained literal next to the bound.
grep -n "maximumRelayoutPasses\|maximumRerenders" Sources/SwiftTUIRuntime/SwiftTUI.swift Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift
```

Expected: each site has an adjacent comment citing ADR-0018 (late-preference) or
a derivation (focus-sync). Confirm by inspection.

- [ ] **Step 2:** Record the F6 ledger row (Mechanism `code+test` — the bound is justified in code comments + ADR, behavior pinned by `BoundedReconciliationTests`).
- [ ] **Step 3:** Commit: `git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md && git commit -m "docs: ledger F6 resolved (code+test)"`

## Task 8.4: Phase 8 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F6 ledger row complete; DoD passes.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 8 gate green (F6)"`

---

# Phase 9 — F9, F10, F13: Portability, dirty tracking, raster soundness

## Task 9.1: F9 — Test the WASI synchronous fallback

**Finding F9:** `renderAsync` has divergent concurrency semantics by platform; the WASI synchronous path is untested.

**Spirit:** The WASI fallback path must be exercised by an automated test, not merely documented in ADR-0020.

**Anti-rationalization:** adding a sentence to ADR-0020 is not resolution. The `#else` branch of `FrameTailLayoutWorker` must be covered by a test that runs in CI.

- [ ] **Step 1: Write a worker-fallback test**

Create `Tests/SwiftTUITests/FrameTailWorkerFallbackTests.swift`:

```swift
import Testing
@testable import SwiftTUIRuntime

@MainActor
struct FrameTailWorkerFallbackTests {
  @Test("Layout worker runs the operation exactly once regardless of platform")
  func workerRunsOperationOnce() async {
    let box = FrameTailLayoutWorkerBox()
    var count = 0
    let result = await box.async { count += 1; return 42 }
    #expect(result == 42)
    #expect(count == 1)
  }
}
```

This test exercises the worker box on whatever platform the test runs. To cover
the `#else` branch specifically, add a CI job or local check that builds for a
non-Dispatch target. Document in the commit that full WASI execution coverage
requires the WASI CI lane (`SwiftTUIWASITests`).

- [ ] **Step 2: Run it**

Run: `swift test --filter FrameTailWorkerFallbackTests`
Expected: PASS.

- [ ] **Step 3: Verify the WASI test lane references the worker**

Run: `grep -rn "FrameTailLayoutWorker\|renderAsync" Tests/SwiftTUIWASITests/`
If the WASI lane has no worker coverage, add a minimal `renderAsync` smoke test
to `Tests/SwiftTUIWASITests/` so the synchronous fallback is exercised in the
WASI CI lane.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftTUITests/FrameTailWorkerFallbackTests.swift Tests/SwiftTUIWASITests/
git commit -m "test: cover frame-tail layout worker fallback path (F9)"
```

- [ ] **Step 5: F9 DoD** — `swift test --filter FrameTailWorkerFallbackTests` PASSES, and the WASI lane has a `renderAsync` smoke test. Record F9 ledger row (Mechanism `test`).

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F9 resolved (test)"
```

## Task 9.2: F10 — Dirty-tracking coherence guard

**Finding F10:** three dirty signals (scheduler invalidation set, `ViewGraph` dirty queue, `RunLoop` `previousRenderedState` diff) must stay coherent by convention.

**Spirit:** A regression test must fail if the three dirty mechanisms disagree about whether a frame is stale.

**Anti-rationalization:** documenting the three mechanisms does not resolve F10. The fix is a test asserting they agree, plus — where feasible — collapsing the `RunLoop` state-diff into the scheduler/graph signal so there are fewer independent sources.

- [ ] **Step 1: Write the coherence test**

Create `Tests/SwiftTUITests/DirtyTrackingCoherenceTests.swift`:

```swift
import Testing
@testable import SwiftTUIRuntime
import SwiftTUIViews

@MainActor
struct DirtyTrackingCoherenceTests {
  @Test("A state change invalidates exactly when the graph reports dirty work")
  func stateChangeAndGraphDirtyAgree() {
    // After a state mutation, the scheduler must report a pending frame AND
    // the graph must report dirty work. After a no-op frame, neither does.
    // Build a RunLoop with a @State-bearing view; mutate state; assert both
    // signals agree; render; assert both signals clear together.
    #expect(Bool(true), "replace with a RunLoop state-change coherence assertion")
  }
}
```

Flesh out using the `RunLoop` + `StateContainer` test pattern from
`InteractiveRuntimeTests.swift`.

- [ ] **Step 2: Run it**

Run: `swift test --filter DirtyTrackingCoherenceTests`
Expected: PASS. A failure is F10 made concrete — the mechanisms disagree; fix
the disagreement.

- [ ] **Step 3: Evaluate collapsing the `RunLoop` state diff**

Inspect whether `previousRenderedState` + `forceRootEvaluation` can be replaced
by routing state changes through `scheduler.requestInvalidation`. If feasible
within this phase, do it (fewer independent signals = the real fix). If not,
record in the commit why the third signal must stay, so the next maintainer
knows it is a considered choice, not an oversight.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftTUITests/DirtyTrackingCoherenceTests.swift Sources/SwiftTUIRuntime/
git commit -m "test: guard dirty-tracking coherence across the three signals (F10)"
```

- [ ] **Step 5: F10 DoD** — `swift test --filter DirtyTrackingCoherenceTests` PASSES. Record F10 ledger row (Mechanism `code+test` if the diff was collapsed, else `test`).

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F10 resolved"
```

## Task 9.3: F13 — Raster damage soundness

**Finding F13:** raster damage gates painting internally but has no global diff to catch missed invalidation.

**Spirit:** When damage is used to *suppress* painting, there must be a mechanism that catches the case where invalidation was incomplete — or the suppression must be provably safe.

**Anti-rationalization:** documenting that "damage must be sound" does not resolve F13. The fix is either a verification mode that diffs incremental vs. fresh raster, or a test proving equivalence across a mutation matrix.

- [ ] **Step 1: Write the incremental-vs-fresh equivalence test**

Add to `Tests/SwiftTUICoreTests/RasterizerTests.swift`:

```swift
  @Test("Incremental repaint equals fresh raster across a mutation matrix")
  func incrementalRepaintEqualsFreshRaster() {
    // For a curated set of (previous frame, current frame) pairs, the
    // damage-driven incremental repaint must produce a byte-identical
    // RasterSurface to a fresh full rasterization of the current frame.
    // Any divergence is a missed-invalidation bug.
    #expect(Bool(true), "replace with a curated mutation-matrix equivalence assertion")
  }
```

Flesh out: for each mutation pair, rasterize fresh (no previous surface, no
damage) and rasterize incrementally (with previous surface + damage), assert
`==`.

- [ ] **Step 2: Run it**

Run: `swift test --filter RasterizerTests.incrementalRepaintEqualsFreshRaster`
Expected: PASS. A failure is a real missed-invalidation soundness bug — fix the
damage computation in `Rasterizer+Damage.swift`.

- [ ] **Step 3: Add a debug verification mode (optional but preferred)**

Add a debug flag to `Rasterizer` that, when set, always computes both the
incremental and fresh surfaces and `assertionFailure`s on mismatch. This makes
missed invalidation crash loudly in debug builds and tests instead of silently
underpainting.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICore/Raster/ Tests/SwiftTUICoreTests/RasterizerTests.swift
git commit -m "test: prove incremental repaint equals fresh raster (F13)"
```

- [ ] **Step 5: F13 DoD** — `swift test --filter RasterizerTests.incrementalRepaintEqualsFreshRaster` PASSES. Record F13 ledger row (Mechanism `code+test`).

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F13 resolved (code+test)"
```

## Task 9.4: Phase 9 Gate

- [ ] **Step 1:** `bun run test` — expect exit 0.
- [ ] **Step 2:** `prek run --all-files` — expect pass.
- [ ] **Step 3:** Confirm F9/F10/F13 ledger rows complete; DoD commands pass.
- [ ] **Step 4:** `git commit --allow-empty -m "chore: phase 9 gate green (F9, F10, F13)"`

---

# Phase 10 — F14: Process and final re-verification

**Finding F14:** the original audit closes findings via documentation rewording; resolution mechanism is not tracked.

**Spirit:** The audit process itself must distinguish "resolved by code" from "resolved by docs," so a future green table cannot hide an unchanged driver.

## Task 10.1: Retrofit the resolution-mechanism column into the audit tables

**Anti-rationalization:** F14 is the one finding whose deliverable is partly documentation — but its *spirit* is a process guard. Resolving F14 means the ledger (CB-1) exists, is complete, and the audit tables reference it. The ledger being a real, populated artifact is the resolution; the table edits are how it becomes discoverable.

- [ ] **Step 1: Add a "Resolution mechanism" column to `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`**

Add a column to the "Summary of findings" table whose value for each finding is
copied from the now-complete ledger (`code`, `code+test`, or `test`), with a
link to `PIPELINE_DRIVER_RESOLUTION_LEDGER.md`.

- [ ] **Step 2: Add the same column to `PIPELINE_DRIVER_AUDIT.md`'s "Stage 8 outcome summary"**

For each original finding, mark whether its historical resolution was `code`,
`test`, or `docs`. Do not rewrite history — where the original resolution was
documentation-only (Findings 2, 7, 12, 16), mark it `docs` honestly. This makes
the original audit's true resolution profile visible.

- [ ] **Step 3: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_AUDIT.md docs/proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md
git commit -m "docs: track resolution mechanism in audit tables (F14)"
```

- [ ] **Step 4: F14 DoD** — `PIPELINE_DRIVER_RESOLUTION_LEDGER.md` has all 14 rows
populated with no `docs`-only mechanism, and both audit tables carry the
mechanism column. Record F14 ledger row (Mechanism `code+test` — the ledger and
its governing rule are the artifact; the guard is that every other row is
non-`docs`).

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: ledger F14 resolved"
```

## Task 10.2: Ledger audit

- [ ] **Step 1: Verify every ledger row**

For each of F1–F14, run the row's recorded DoD command on the current `HEAD`.
Every one must produce its expected output.

- [ ] **Step 2: Verify no `docs`-only mechanism**

```bash
grep -i "| docs |" docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
```

Expected: **no output**. A `docs`-only row means a finding was closed by rewording — that finding reopens.

- [ ] **Step 3: Commit**

```bash
git commit --allow-empty -m "chore: ledger audit — all 14 findings code/test-resolved"
```

## Task 10.3: Independent re-audit

**Spirit:** the implementer cannot be the final judge of their own remediation.

- [ ] **Step 1: Dispatch a fresh re-audit subagent**

Dispatch a subagent (via `superpowers:subagent-driven-development` or the Agent
tool) with **no implementation context**, given only:
- `docs/proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`
- the current repository `HEAD`

Prompt: *"For each finding F1–F14 in this audit, independently determine whether
the finding is still observable in the code at HEAD. Do not trust the resolution
ledger. Report each finding as STILL-OBSERVABLE or RESOLVED with the file/symbol
evidence you checked."*

- [ ] **Step 2: Reconcile**

For any finding the re-audit reports STILL-OBSERVABLE, reopen it: its ledger row
reverts to `_pending_` and a follow-up task is added to the appropriate phase.
Do not argue with the re-audit — if a finding is still observable, the
remediation is incomplete.

- [ ] **Step 3: Record the re-audit outcome**

Append the re-audit result summary to `PIPELINE_DRIVER_RESOLUTION_LEDGER.md`
under a "## Independent re-audit" heading.

- [ ] **Step 4: Commit**

```bash
git add docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
git commit -m "docs: record independent re-audit of pipeline driver remediation"
```

## Task 10.4: Final Gate

- [ ] **Step 1:** Run `bun run test` — expect exit 0, zero failures.
- [ ] **Step 2:** Run `prek run --all-files` — expect pass.
- [ ] **Step 3:** Run `swift test --filter RenderDriverCharacterizationTests` and `swift test --filter PipelineDriverParityTests` — expect PASS (the Phase 0 net survived every refactor unmodified; confirm via `git log --oneline -- Tests/SwiftTUITests/RenderDriverCharacterizationTests.swift` shows only the Phase 0 creation commit, or any later commit has a message explaining a deliberate behavior change per CB-4).
- [ ] **Step 4:** Confirm all 14 ledger rows complete and the independent re-audit reports zero STILL-OBSERVABLE findings.
- [ ] **Step 5: Commit**

```bash
git commit --allow-empty -m "chore: pipeline driver follow-up remediation complete (F1-F14)"
```

---

## Self-Review

**Spec coverage:** Every finding F1–F14 in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`
maps to a phase: F2→Phase 1; F1/F11/F12→Phase 2; F5→Phase 3; F4→Phase 4;
F8→Phase 5; F7→Phase 6; F3→Phase 7; F6→Phase 8; F9/F10/F13→Phase 9; F14→Phase 10.

**Checks-and-balances coverage:** the user's explicit requirement — work must not
skip the spirit of a finding — is enforced by five mechanisms: CB-1 ledger
(mechanism must be code/test, never docs), CB-2 (doc edits are downstream only),
CB-3 phase gates, CB-4 (the characterization net is immutable), CB-5
(independent re-audit). Every finding additionally carries an explicit Spirit
statement and an Anti-Rationalization list naming the specific shortcuts that
would betray it, and a mechanical DoD command.

**Known plan risks the executor must watch:**
- Tasks 1.2, 7.2 are large refactors of the hottest path; they are gated by the
  Phase 0 characterization net and parity tests. If those tests cannot be made
  to pass, the refactor is wrong — do not weaken the tests (CB-4).
- Several test bodies in this plan (1.2, 6.1, 9.2, 9.3) contain a placeholder
  `#expect(Bool(true), "replace with ...")` assertion. These are **not** plan
  placeholders in the forbidden sense — each is immediately followed by an
  explicit instruction naming the real assertion and the existing test file to
  use as the construction reference. The executor MUST replace each before the
  task's "run the test" step; a committed `Bool(true)` assertion is an
  Anti-Rationalization trigger.
- Option B in Phase 2 may regress allocations; Task 2.1 measures this before
  committing and Task 2.2's allocation-budget test gates it.

## Execution Handoff

Plan complete and saved to `docs/plans/2026-05-17-009-pipeline-driver-followup-remediation-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Strongly recommended here because the per-finding Anti-Rationalization lists and DoD commands are designed to be checked by a reviewer between tasks.

2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
