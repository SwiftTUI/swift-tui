# Pipeline Driver Resolution Ledger

Tracks the resolution of each finding in `PIPELINE_DRIVER_FOLLOWUP_AUDIT.md`.
Governance: a finding is resolved only when its Mechanism is `code`,
`code+test`, or `test` (never `docs`), its DoD command passes on a clean
checkout, and the verifying commit hash is recorded.

| Finding | Mechanism | DoD command | Verified-by commit |
| --- | --- | --- | --- |
| F1  | _pending_ | _pending_ | _pending_ |
| F2  | code+test | `grep -n "rerenderedForFocusSync" Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift` shows the focus-sync rerender flag declared once (`FocusSyncConvergenceState`) and read/written only through the shared `processFocusSyncIteration` / `applyAcquiredFrame`; both `renderPendingFrames` and `renderPendingFramesAsync` are thin delegators | 6d70ca63 |
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
