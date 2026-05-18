# Pipeline Driver Resolution Ledger

Tracks the resolution of each finding in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`.
Governance: a finding is resolved only when its Mechanism is `code`,
`code+test`, or `test` (never `docs`), its DoD command passes on a clean
checkout, and the verifying commit hash is recorded.

## Independent audit entrypoints

The current resolution table below is the canonical status. A reviewer who has
only the repo and the follow-up audit can verify the process remediation by:

1. Following the "Resolution mechanism" links in
   `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md` to this ledger.
2. Running `Scripts/check_pipeline_driver_resolution_ledger.sh`, which is also
   part of the repo policy phase executed by `bun run test`.
3. Running any row's recorded DoD command to re-check the code or test evidence.

The historical re-audit table is retained below as evidence of what reopened at
`a595e125`; the current status table records the post-remediation result.

| Finding | Mechanism | DoD command | Verified-by commit |
| --- | --- | --- | --- |
| F1  | code+test | `grep -rn "RuntimeFrameHeadStage\|precondition(stageOrder" --include="*.swift" Sources` prints nothing — `RuntimeRenderPipeline` is a sequenced executor with no `headStage` field, no `stageOrder` initializer parameter, and no canonical-order `precondition`; dead config (`RuntimeFrameHeadStage`, frozen `stageOrder` param + precondition) deleted; stage order now executor-enforced; `RenderPipelineStructureTests.stageOrderIsStructural` pins the structural property and `composedRenderTimeBudget` pins the within-2x wall-clock time budget | 36a8b529, 1e163dbd |
| F2  | code+test | `grep -n "rerenderedForFocusSync" Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` shows the focus-sync rerender flag declared once (`FocusSyncConvergenceState`) and read/written only through the shared `processFocusSyncIteration` / `applyAcquiredFrame`; both `renderPendingFrames` and `renderPendingFramesAsync` are thin delegators | 6d70ca63 |
| F3  | code+test | `swiftly run swift test --filter ResolvePurityTests` passes; the guard now asserts the runtime subsystem snapshot is unchanged immediately after `prepareFrameHeadForCancellationTesting(...)` and again after abort. Abortable heads record prepared graph/frame-input checkpoints, suspend live state back to the committed baseline before returning, and materialize the prepared state only for preview/commit. | c04d5ac1 |
| F4  | code+test | `swiftly run swift test --filter ViewGraphCheckpointTotalityTests`, `swiftly run swift test --filter AsyncFrameTailRenderingTests/previewCommitEqualsRealCommit`, and `swiftly run swift test --filter RenderPipelineStructureTests/completedFramePreviewDoesNotFinalizeLiveGraph` pass; completed-frame preview now uses non-mutating `ViewGraph.previewLifecycleEvents(...)` and the structural guard pins that `previewCompletedFrameCommit` does not call `finalizeFrame`. | 5856eda2 |
| F5  | code+test | `grep -rn "while cancellationToken.currentState\|Task.sleep(for: \\.milliseconds(1))" --include="*.swift" Sources/SwiftTUIRuntime` prints nothing for queued-tail cancellation; `FrameTailJobCancellationToken.waitUntilLeavesQueue()` and `FrameScheduler.waitForPendingFrame(at:)` provide continuation-backed queue-exit / pending-frame signals; `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/queuedFrameTailCancelsBeforeWorkerLayoutStarts` passes | 80011951 |
| F6  | code+test | `swiftly run swift test --filter BoundedReconciliationTests`, `swiftly run swift test --filter AppRuntimeTests/focusSynchronizationRerenderBudgetTripsAtTheConfiguredLimit`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, and `swiftly run swift test --filter PipelineDriverParityTests` pass; late-preference relayout uses a current-tree-derived budget and final reconciled relayout on exhaustion, and focus-sync derives its rerender budget from the acquired semantic graph instead of a fixed default. | be0e54c4 |
| F7  | code+test | `swiftly run swift test --filter FrameDropDroppabilityTests` passes; `grep -n "subtract(\[" Sources/SwiftTUIRuntime/SwiftTUI.swift` prints nothing, so completed-frame eligibility no longer subtracts retained-baseline blockers after tail classification | 61639294, 815ae644 |
| F8  | code+test | `swiftly run swift test --filter RenderDriverInstrumentationCostTests`, `swiftly run swift test --filter DiagnosticsAndCacheTests`, `swiftly run swift test --filter FrameDiagnostics`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, and `swiftly run swift test --filter PipelineDriverParityTests` pass; runtime artifact construction no longer calls `FrameDiagnostics.summarize(...)` unconditionally, and the guard `artifactConstructionDoesNotCallFrameDiagnosticsSummarize` pins the completed-frame constructors to `FrameDiagnostics.fromCachedPhaseProducts(...)` without reintroducing a diagnostics opt-out fork. | 7789bdeb |
| F9  | code+test | `swiftly run swift test --filter FrameTailWorkerFallbackTests`, `swiftly run swift test --filter WASIRenderAsyncTests`, `swiftly run swift test --filter SwiftTUIWASITests`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, and `swiftly run swift test --filter PipelineDriverParityTests` pass; the no-Dispatch frame-tail layout fallback now selects the same `ImmediateFrameTailLayoutWorker` implementation that native tests instantiate through `FrameTailLayoutWorkerBox(scheduling: .immediate)`, so the synchronous fallback semantics are exercised outside the WASI-only compile branch. | ae431c05 |
| F10 | code+test | `swiftly run swift test --filter DirtyTrackingCoherenceTests`, `swiftly run swift test --filter InteractiveRuntimeTests/runLoopPassesScheduledInvalidationsIntoResolveContext`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, and `swiftly run swift test --filter PipelineDriverParityTests` pass; external `RunLoop` state drift is now reconciled into the scheduled invalidation signal with `ScheduledFrame.forceRootEvaluation`, carried through `ResolveContext.forceRootEvaluation` into `FrameResolveState`, and the old direct `previousRenderedState` force-root block is pinned absent by `externalStateDriftUsesScheduledInvalidationSignal`. | cfd378d4 |
| F11 | code+test | `swiftly run swift test --filter RenderPipelineStructureTests`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, `swiftly run swift test --filter PipelineDriverParityTests`, and `swiftly run swift test --filter RenderDriverCharacterizationTests` pass; branch-specific async/cancellable tail helpers (`renderFrameTailAsync`, `renderAsyncFrameTailLayoutStage`, `renderCancellableFrameTailLayoutStage`, `renderAsyncFusedFrameTail`, `renderCancellableFusedFrameTail`) are gone, and `renderTailStrategyEntrySurfaceIsShared` pins that async/cancellable paths share `renderFrameTailLayoutStage`, `renderFrameTailRasterStage`, and `resolveCompletedFrameCandidate`. | 11c9aa9f |
| F12 | code+test | `grep -c "case .fusedFrameTail" Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift` returns ≥1 — `RuntimeRenderStageName` is the discriminant the executor switches on; each `render*` entry point dispatches every stage through an exhaustive `switch`, so the enum has a control-flow consumer rather than being unused metadata | 36a8b529 |
| F13 | code+test | `swiftly run swift test --filter RasterizerTests`, `swiftly run swift test --filter PipelineContractTests/incrementalRasterReuseMatchesFreshRasterForMutationMatrix`, `swiftly run swift test --filter AsyncFrameTailRenderingTests`, and `swiftly run swift test --filter PipelineDriverParityTests` pass; default `Rasterizer()` now verifies every incremental repaint by comparing against a fresh raster and falls back to the fresh result with `presentationDamage == nil` when damage was incomplete; no `verifyIncrementalRepaint` opt-in remains. | bdabfa8d |
| F14 | code+test | `Scripts/check_pipeline_driver_resolution_ledger.sh` passes and is invoked by `bun run test` through `Scripts/lib/repo_policy_checks.sh`; the checker requires all 14 ledger rows to be populated with non-`docs` mechanisms, requires both audit summaries to carry a resolution-mechanism column, requires the follow-up audit to link this ledger and name the checker, and requires the current independent re-audit status to report every finding as `RESOLVED`. | 6e76aa46 |

## Current independent re-audit status

Post-remediation status after reopening F3, F4, F6, F8, F9, F10, F11, F13,
and F14:

| Finding | Current result | Evidence |
| --- | --- | --- |
| F1 | RESOLVED | Current ledger row populated; historical re-audit did not reopen this finding. |
| F2 | RESOLVED | Current ledger row populated; historical re-audit did not reopen this finding. |
| F3 | RESOLVED | Reopened by the historical re-audit and resolved by `c04d5ac1`; the row DoD records the guard. |
| F4 | RESOLVED | Reopened by the historical re-audit and resolved by `5856eda2`; the row DoD records the guard. |
| F5 | RESOLVED | Current ledger row populated; historical re-audit did not reopen this finding. |
| F6 | RESOLVED | Reopened by the historical re-audit and resolved by `be0e54c4`; the row DoD records the guard. |
| F7 | RESOLVED | Current ledger row populated; historical re-audit did not reopen this finding. |
| F8 | RESOLVED | Reopened by the historical re-audit and resolved by `7789bdeb`; the row DoD records the guard. |
| F9 | RESOLVED | Reopened by the historical re-audit and resolved by `ae431c05`; the row DoD records the shared fallback test. |
| F10 | RESOLVED | Reopened by the historical re-audit and resolved by `cfd378d4`; the row DoD records the scheduled-invalidation guard. |
| F11 | RESOLVED | Reopened by the historical re-audit and resolved by `11c9aa9f`; the row DoD records the reduced entry-surface guard. |
| F12 | RESOLVED | Current ledger row populated; historical re-audit did not reopen this finding. |
| F13 | RESOLVED | Reopened by the historical re-audit and resolved by `bdabfa8d`; the row DoD records default fresh-vs-incremental verification. |
| F14 | RESOLVED | Reopened by the historical re-audit and resolved by `6e76aa46`; this ledger now names independent entrypoints and has a repo-policy checker. |

## Historical independent re-audit

Independent re-audit at `a595e125` reported:

| Finding | Result |
| --- | --- |
| F1 | RESOLVED |
| F2 | RESOLVED |
| F3 | STILL-OBSERVABLE |
| F4 | STILL-OBSERVABLE |
| F5 | RESOLVED |
| F6 | STILL-OBSERVABLE |
| F7 | RESOLVED |
| F8 | STILL-OBSERVABLE |
| F9 | STILL-OBSERVABLE |
| F10 | STILL-OBSERVABLE |
| F11 | STILL-OBSERVABLE |
| F12 | RESOLVED |
| F13 | STILL-OBSERVABLE |
| F14 | STILL-OBSERVABLE |

Reopened per Task 10.3: F3, F4, F6, F8, F9, F10, F11, F13, and F14.
