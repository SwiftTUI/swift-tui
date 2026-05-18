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
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHostEscapeSequences.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPlatformIO.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalProcessExitCleanup.swift`
- Dependencies: Packet 10.
- Invariants: raw-mode enter/exit bytes, mouse reporting mode bytes, bracketed
  paste toggles, cursor visibility/focus bytes, process-exit reset bytes, and
  synchronous cleanup ordering remain stable. Shared full-repaint byte accounting
  and the WASI/web host write path continue using the same sequence catalog.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalHost`
  - `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - `swiftly run swift test --filter WebSurfaceTransportTests`
  - `swiftly run swift test --filter SwiftTUITerminalTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 12: Terminal Presentation Planning

- Objective: keep `TerminalPresentation.swift` focused on rendering terminal
  surfaces by moving incremental/full repaint planning into a dedicated
  internal file.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationPlanning.swift`
- Dependencies: Packets 1, 2, and 7-11 clarified terminal presentation and image
  replay ownership.
- Invariants: public capability APIs, renderer output, damage hint
  normalization, row-batch construction, edit-operation lowering, full-repaint
  fallbacks, and Kitty image replay planning remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 13: Animation Tree Queries

- Objective: begin decomposing the animation lifecycle controller by moving pure
  resolved/placed tree query helpers into a same-module helper without widening
  package API.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationTreeQueries.swift`
- Dependencies: Packet 12 completed the terminal presentation split; read-only
  animation review identified this as the safest first `AnimationController`
  slice.
- Invariants: `AnimationController` and `AnimationFrameDraft` package-facing
  APIs remain unchanged; matched-geometry capture order, `isSource` filtering,
  removal lookup against previous resolved/placed trees, single-child wrapper
  removal walk-up, child-index reinsertion, batch ref counts, completion
  deferral, and frame-head transaction semantics remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 14: Animation Transition Overlays

- Objective: continue decomposing `AnimationController` by moving resolved-tree
  removal overlay value transforms behind an internal facade while keeping
  controller-owned state and batch bookkeeping in place.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationTransitionOverlay.swift`
- Dependencies: Packet 13 extracted pure tree queries. Read-only review
  confirmed this next slice is safe only if the extraction remains a
  value-transform boundary.
- Invariants: resolved-level injection still only happens when no placed
  snapshot is available; removal clones are transient before reinjection;
  opacity cascades to descendants; offsets apply only at the removal subtree
  root; existing offsets compose by addition; non-offset roots get the same
  stable `__transitionOffset` wrapper identity; injection remains child-first
  and sorted by previous child index; animation state, purge decisions, batch
  ref counts, deadlines, and completion deferral stay in `AnimationController`.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 15: Animation Property Value Application

- Objective: finish the current safe `AnimationController` value-transform
  split by moving property-slot lookup, interpolation fallback, and resolved-tree
  property writeback into a same-subsystem helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationPropertyValueApplication.swift`
- Dependencies: Packets 13 and 14 separated pure tree queries and removal
  overlay transforms, leaving property animation value application as the next
  isolated non-bookkeeping boundary.
- Invariants: active animation iteration, custom-animation state writeback,
  batch ref counts, completion deferral, deadlines, removal purge decisions,
  and frame-head transaction behavior stay in `AnimationController`; property
  writeback preserves tree shape with `setChildrenPreservingDerivedState`;
  layout updates preserve derived state and keep `.flexibleFrame` slot priority
  in max, ideal, then min order; shape-style slots continue writing to their
  original draw metadata or shape payload destinations; interpolation still
  snaps to the target value on type mismatch.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - `swiftly run swift test --filter AnimationController`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 16: DefaultRenderer Completed Frame Artifacts

- Objective: reduce `DefaultRenderer` completed-frame commit/candidate noise by
  moving artifact assembly, worker timing derivation, and drop-eligibility
  classification into a same-subsystem helper, and move the completed-frame
  candidate model out of `FrameTailRenderer`.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/CompletedFrameArtifactBuilder.swift`
  - `Sources/SwiftTUIRuntime/Rendering/CompletedFrameCandidate.swift`
- Dependencies: Packet 15 completed the animation-controller value split.
  Read-only runtime review ranked this `DefaultRenderer` seam as the most
  central remaining rendering debt; run-loop diagnostics and input parsing are
  next candidates after this checkpoint.
- Invariants: public renderer APIs stay unchanged; candidate preview still uses
  `previewLifecycleEvents` and never finalizes the live graph; actual commit
  still runs through `commitCompletedFrameCandidate`; runtime registration
  diagnostics are attached only after the commit path; scroll geometry,
  retained frame storage, presentation dismiss-stack commit, measurement-cache
  pruning, worker timings, main-actor timings, render-generation diagnostics,
  frame-tail drop blockers, and completed-frame policy decisions remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

## Human Checkpoints

Stop for approval before:

- Any public API change.
- Any intentional terminal-output, rendering, lifecycle, or frame-drop behavior
  change.
- Any fixture re-recording.
- Any example-app change.
- Any test weakening or broad test rewrite.
