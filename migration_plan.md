# Production Code Humanization Plan

## Strategy

Use small, behavior-preserving slices. Each slice must have explicit file
ownership, a targeted validation command, and a rollback note before edits
begin. Start at the terminal rendering path because it is central production
infrastructure and contains the largest debt indicators by file size and
coupling.

## Discovery Lanes

Read-only subagents mapped:

- Terminal host and presentation internals.
- Runtime render pipeline and frame artifacts.
- Run-loop, scene, and CLI integration.
- Validation commands and existing terminal-rendering tests.

The first implementation packet was selected after checking those findings
against local source evidence.

## Candidate Packet Order

### Packet 1: Terminal Presentation Writer and Session State

- Objective: make terminal presentation submission state explicit and easier to
  review without changing behavior.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`
- Scope: move and rename `PresentationFrame`, `PresentationWriter`, and
  `PresentationSession` into terminal-specific internal types. Preserve the
  "latest pending frame wins" writer behavior and the "dropped frame forces the
  next full repaint" session behavior.
- Dependencies: baseline status and subagent findings are complete.
- Invariants: terminal bytes, process cleanup, capability probing, writer
  batching, and cursor/focus commands remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 2: Terminal Presentation Emission

- Objective: make `TerminalHost.present(_:damage:)` read as orchestration by
  moving output assembly and metrics bookkeeping into named helpers.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`
- Scope: preserve terminal output byte-for-byte while splitting full repaint,
  incremental row emission, Kitty graphics replay, synchronized-output wrapping,
  writer submission, and metrics construction into named units.
- Dependencies: Packet 1.
- Invariants: terminal bytes, graphics replay scope/count metrics, edit-operation
  lowering metrics, retained surface updates, synchronized-output wrapping, and
  Kitty image-id cache behavior remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 3: Frame Tail Presentation Damage

- Objective: move the retained-frame presentation-damage proof boundary out of
  `FrameTailRenderer` so terminal damage safety is isolated and reviewable.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailPresentationDamage.swift`
- Dependencies: Packet 2.
- Invariants: retained frame reuse, damage hints, raster reuse fallback,
  async/sync artifact parity, and frame-drop classifications remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 4: Frame Artifact File Split

- Objective: separate frame diagnostics and frame context from the artifact
  payload so `FrameArtifacts.swift` describes the artifact bundle directly.
- Likely owned files:
  - `Sources/SwiftTUICore/Commit/FrameArtifacts.swift`
  - `Sources/SwiftTUICore/Commit/FrameDiagnostics.swift`
  - `Sources/SwiftTUICore/Commit/FrameContext.swift`
- Dependencies: Packet 3.
- Invariants: public API inventory, diagnostic lazy-summary behavior,
  `FrameArtifacts` equality semantics, `drawnIdentities` visibility, and
  `FrameDiagnostics.fromCachedPhaseProducts` field mapping remain stable.
- Required checks:
  - `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 5: RunLoop Presentation Path

- Objective: reduce cognitive load in frame acquisition, commit, and
  presentation handoff code.
- Likely owned files: pending discovery, expected to be inside
  `Sources/SwiftTUIRuntime/RunLoop/`.
- Dependencies: Packet 2 if presentation artifacts are clarified there.
- Invariants: lifecycle callbacks, drop decisions, accessibility, focus, and
  input responsiveness remain stable.
- Required checks: interactive runtime and pipeline tests first, then
  `bun run test`.
- Rollback: revert the packet commit/files only.

### Packet 6: Platform Entrypoint Clarity

- Objective: clarify how CLI/render-once entrypoints connect to runtime and
  terminal hosts.
- Likely owned files: pending discovery, expected to be inside
  `Platforms/CLI/Sources/SwiftTUICLI/`.
- Dependencies: terminal host concepts from Packet 1.
- Invariants: command-line behavior, exit behavior, and rendered text output
  remain stable.
- Required checks: focused CLI tests first, then `bun run test`.
- Rollback: revert the packet commit/files only.

### Packet 10: Terminal Host Capability Probing

- Objective: keep `TerminalHost` focused on terminal lifecycle and presentation
  orchestration by moving graphics and pointer capability probing into a
  same-module extension.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHostCapabilities.swift`
- Dependencies: Packets 1, 2, 7, 8, and 9 clarified terminal presentation and
  image-rendering ownership.
- Invariants: public host APIs, raw-mode ordering, image-probe drain-before-query
  behavior, live Kitty/Sixel probing, SGR-pixels trust policy decisions, cell
  pixel metric cache refresh behavior, and input-reader precision propagation
  remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - `swiftly run swift test --filter SwiftTUITests.CellPixelMetricsRefreshTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 11: Terminal Host Sequences and Cleanup

- Objective: continue reducing `TerminalHost` by isolating escape-sequence
  construction and process-exit cleanup from presentation orchestration.
- Likely owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - new terminal-host helper file selected after discovery.
- Dependencies: Packet 10.
- Invariants: raw-mode enter/exit bytes, mouse reporting mode bytes, bracketed
  paste toggles, cursor visibility/focus bytes, process-exit reset bytes, and
  synchronous cleanup ordering remain stable.
- Required checks: terminal host presentation, raw-mode cleanup, input, and repo
  gate tests selected from touched helpers.
- Rollback: revert the packet commit/files only.

## Human Checkpoints

Stop for approval before:

- Any public API change.
- Any intentional terminal-output, rendering, lifecycle, or frame-drop behavior
  change.
- Any fixture re-recording.
- Any example-app change.
- Any test weakening or broad test rewrite.
