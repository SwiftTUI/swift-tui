# Pipeline Driver Resolution Ledger

Tracks the resolution of each finding in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`.
Governance: a finding is resolved only when its Mechanism is `code`,
`code+test`, or `test` (never `docs`), its DoD command passes on a clean
checkout, and the verifying commit hash is recorded.

| Finding | Mechanism | DoD command | Verified-by commit |
| --- | --- | --- | --- |
| F1  | code+test | `grep -rn "RuntimeFrameHeadStage\|precondition(stageOrder" --include="*.swift" Sources` prints nothing — `RuntimeRenderPipeline` is a sequenced executor with no `headStage` field, no `stageOrder` initializer parameter, and no canonical-order `precondition`; `RenderPipelineStructureTests.stageOrderIsStructural` and `composedRenderAllocationBudget` pin the structural property and the within-2x allocation budget | 36a8b529, 1e163dbd |
| F2  | code+test | `grep -n "rerenderedForFocusSync" Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` shows the focus-sync rerender flag declared once (`FocusSyncConvergenceState`) and read/written only through the shared `processFocusSyncIteration` / `applyAcquiredFrame`; both `renderPendingFrames` and `renderPendingFramesAsync` are thin delegators | 6d70ca63 |
| F3  | _pending_ | _pending_ | _pending_ |
| F4  | _pending_ | _pending_ | _pending_ |
| F5  | _pending_ | _pending_ | _pending_ |
| F6  | _pending_ | _pending_ | _pending_ |
| F7  | _pending_ | _pending_ | _pending_ |
| F8  | _pending_ | _pending_ | _pending_ |
| F9  | _pending_ | _pending_ | _pending_ |
| F10 | _pending_ | _pending_ | _pending_ |
| F11 | code+test | `grep -n "prepareAnimationOverlaySnapshot" Sources/SwiftTUIRuntime/SwiftTUI.swift` shows the shared `@MainActor` fused-frame-tail head defined once and called by both `renderFusedFrameTail` (sync) and `renderAsyncFusedFrameTail` (async); the triplicated placed-tree capture / overlay-snapshot orchestration is gone, verified by `PipelineDriverParityTests` and `RenderDriverCharacterizationTests` | f2f1e5bb |
| F12 | code+test | `grep -c "case .fusedFrameTail" Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift` returns ≥1 — `RuntimeRenderStageName` is the discriminant the executor switches on; each `render*` entry point dispatches every stage through an exhaustive `switch`, so the enum has a control-flow consumer rather than being unused metadata | 36a8b529 |
| F13 | _pending_ | _pending_ | _pending_ |
| F14 | _pending_ | _pending_ | _pending_ |
