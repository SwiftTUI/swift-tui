# Pipeline Driver Resolution Ledger

Tracks the resolution of each finding in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`.
Governance: a finding is resolved only when its Mechanism is `code`,
`code+test`, or `test` (never `docs`), its DoD command passes on a clean
checkout, and the verifying commit hash is recorded.

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
| F11 | _pending_ | _pending_ | _pending_ |
| F12 | code+test | `grep -c "case .fusedFrameTail" Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift` returns ≥1 — `RuntimeRenderStageName` is the discriminant the executor switches on; each `render*` entry point dispatches every stage through an exhaustive `switch`, so the enum has a control-flow consumer rather than being unused metadata | 36a8b529 |
| F13 | _pending_ | _pending_ | _pending_ |
| F14 | _pending_ | _pending_ | _pending_ |

## Independent re-audit

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
