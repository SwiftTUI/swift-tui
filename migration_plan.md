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

### Packet 17: RunLoop Frame Diagnostics

- Objective: make the runtime frame loop easier to read by moving committed,
  cancelled-before-start, and dropped-completed diagnostic record construction
  into a same-folder helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnostics.swift`
- Dependencies: Packet 16 isolated completed-frame artifact support. Read-only
  run-loop review identified diagnostics record assembly as the highest-locality
  remaining `RunLoop+Rendering` block because it is verbose, mostly data
  mapping, and separable from frame control flow.
- Invariants: frame scheduling, async acquisition, focus-sync convergence,
  lifecycle carry-forward, cancelled-frame intent replay, completed-frame drop
  policy, presentation ordering, progress-probe events, and public diagnostics
  fields remain unchanged. The skipped-frame diagnostics path still drains
  render-suspension input counters once per logged skipped record, and committed
  frames still include the full-record drop-eligibility blocker.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 18: InputReader Pure Support Types

- Objective: make terminal input infrastructure easier to navigate by moving
  pure input value types, reading protocols, coordinate capability contracts,
  and pointer-event coalescing support out of the file-descriptor reader.
- Owned files:
  - `Sources/SwiftTUIRuntime/Input/InputReader.swift`
  - `Sources/SwiftTUIRuntime/Input/InputReading.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputEvents.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputCapabilities.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputCoalescing.swift`
- Dependencies: Packet 17 completed the run-loop diagnostics split. A read-only
  input audit identified this as the safest first `InputReader` step because it
  leaves parser state and platform I/O untouched while separating public event
  models and pure coalescing policy from stream ownership.
- Invariants: public event and protocol names/access levels stay unchanged;
  package capability and coalescing contracts stay package-visible; parser
  normalization, bracketed-paste buffering, SGR mouse decoding, platform read
  loops, control-message routing, dispatch-source flush timing, and the
  `InputReaderTiming.mouseEventFlushDelayMilliseconds == 1` guard remain
  unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 19: Late Preference Reconciliation

- Objective: make `DefaultRenderer` easier to follow by moving late-preference
  reconciliation policy, sync/async loop mechanics, and reconciliation runtime
  issue construction into a rendering helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/LatePreferenceReconciliation.swift`
- Dependencies: Packet 18 split low-risk terminal input support. A read-only
  runtime review ranked late-preference reconciliation as the next central
  rendering debt because the verbose loop is separable from frame-head
  preparation, queued cancellation, and commit orchestration.
- Invariants: public renderer APIs stay unchanged; pass budget remains
  `max(1, input.resolved.subtreeNodeCount + 1)`; sync and async loops preserve
  nil-layout cancellation behavior, suspension-duration accumulation, and
  bound-exhaustion "warn and commit latest reconciled layout" behavior; toolbar
  runtime issue codes, messages, identities, and sources remain stable; prepared
  graph materialization and queued cancellation stay in `DefaultRenderer`.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.BoundedReconciliationTests`
  - `swiftly run swift test --filter SwiftTUITests.ToolbarTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests`
  - `swiftly run swift test --filter SwiftTUITests.ViewThatFitsSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 20: Frame-Head Draft Transaction

- Objective: make frame-tail rendering easier to scan by moving the frame-head
  mode, checkpoint, transaction, and draft support types into a same-folder
  rendering helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameHeadDraftTransaction.swift`
- Dependencies: Packet 19 isolated late-preference reconciliation. Read-only
  runtime review ranked this as the next low-risk central rendering cleanup
  because the frame-head transaction model sat ahead of tail input/output and
  worker execution in `FrameTailRenderer.swift`.
- Invariants: public renderer APIs stay unchanged; frame-head commit, prepared
  state materialization, checkpoint recording, suspension, discard preconditions,
  draft drop blockers, observation draft commit/discard, presentation portal
  draft commit/discard, animation draft commit/discard, and one-shot abort
  precondition text remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 21: RunLoop Focus-Sync Convergence

- Objective: make the runtime frame driver easier to follow by moving
  focus/scroll convergence state, rerender budget handling, lifecycle
  carry-forward collection, and the per-rendered-tree convergence body into a
  same-folder run-loop helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FocusSync.swift`
- Dependencies: Packet 20 completed the frame-head support split. Read-only
  run-loop review identified focus-sync convergence as the next central runtime
  block because both sync and async frame drivers share this body and the logic
  obscured the scheduler/acquisition/commit shape.
- Invariants: sync and async rendering still call the same convergence helper;
  focus-sync rerenders still force root evaluation; side-effect order inside a
  convergence iteration remains latest semantic snapshot publication, gesture
  pruning, pointer-hover update, vanished pointer capture/hover release, focus
  region update, explicit focus request, default focus request, focus binding
  sync, focused-value update, scroll-position sync, diagnostic flag folding,
  lifecycle carry-forward, and rerender-budget accounting; budget exhaustion
  still commits the latest frame while asserting; focus-sync rerenders still
  disable presentation damage; cancelled/dropped async tails still carry
  lifecycle entries forward.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AppRuntimeTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FocusTrackerTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.LocalScrollPositionRegistryTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 22: RunLoop Frame Acquisition

- Objective: make the runtime frame driver easier to follow by moving async
  artifact acquisition, render-mode dispatch, queued-tail cancellation policy,
  skipped-tail diagnostics, cancelled-intent replay, and completed-frame drop
  blockers into a same-folder run-loop helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift`
- Dependencies: Packet 21 isolated focus-sync convergence. Read-only runtime
  review identified frame acquisition as the next dense runtime seam because
  cancellation, dropped completed frames, event-pump fairness, and diagnostics
  were interleaved with the outer frame loop.
- Invariants: `renderPendingFramesAsync` remains the frame driver and skipped
  tails still continue its outer frame loop; `FrameAcquisitionState` remains a
  private rendering-file detail for the final commit body; skipped tails never
  enter `processFocusSyncIteration` or `applyAcquiredFrame`; cancelled-before-
  start frames still report runtime issues, carry lifecycle forward, increment
  `cancelledRenderCount`, replay the cancelled intent, log diagnostics, record
  `.frameSkipped`, and avoid incrementing `renderedFrames`; dropped-completed
  frames still report issues, carry lifecycle forward, log diagnostics, record
  `.frameSkipped`, and avoid replay/cancellation counts; `.sync` inside the
  async entry still uses `renderer.render`, event-pump-free async still uses
  `renderer.renderAsync`, `.asyncNoCancel` disables queued cancellation, and
  `.asyncNoDrop` passes `.orderedCommitOnly`.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 23: DefaultRenderer Committed Frame Commit Path

- Objective: make `DefaultRenderer`'s actual commit body easier to follow by
  sharing one-shot and async committed-frame artifact assembly, renaming the
  completed-frame artifact helper to the more accurate committed-frame helper,
  and extracting live commit effects and committed-frame publication helpers.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/CompletedFrameArtifactBuilder.swift`
  - `Sources/SwiftTUIRuntime/Rendering/CommittedFrameArtifactBuilder.swift`
- Dependencies: Packet 22 isolated async frame acquisition. A read-only
  renderer audit confirmed that the safest next extraction was the actual
  commit shared surface only, not stale-frame policy, preview reconciliation,
  or the pipeline executor.
- Invariants: public renderer APIs stay unchanged; completed-candidate preview
  still uses `previewLifecycleEvents` and never finalizes the live graph; dropped
  completed candidates still abort without worker-cache updates or committed
  publication; completed async commits still materialize prepared state before
  finalizing; one-shot worker timing is captured before commit effects; actual
  commit still finalizes the frame, commits frame-head draft effects, plans the
  commit, applies worker custom-layout cache updates once, prunes the
  measurement cache, updates scroll geometry, stores the retained baseline
  placed tree, and stores the committed presentation dismiss stack.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUITests.DirtyTrackingCoherenceTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - `swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 24: Terminal Host Raw-Mode Session Boundary

- Objective: keep `TerminalHost` focused on terminal lifecycle orchestration by
  moving saved terminal state and process-exit cleanup registration into a
  small raw-mode session helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalRawModeSession.swift`
- Dependencies: Packet 23 consolidated the renderer commit path. Runtime review
  ranked this as the next terminal-host cleanup because raw-mode saved state,
  pointer reporting state, and process-exit cleanup registration were still
  interleaved with enter/exit byte ordering and POSIX mutations.
- Invariants: public host APIs stay unchanged; raw-mode enter and exit escape
  sequence ordering remains stable; `TerminalHost` still owns termios mutation,
  nonblocking input setup, presentation writer draining, and terminal writes;
  process-exit cleanup reset bytes remain byte-for-byte stable; cleanup
  registration refresh still happens when SGR-pixels hover changes while raw
  mode is enabled; normal disable unregisters cleanup before manual teardown;
  enable failure rollback restores file flags and termios state and unregisters
  cleanup; presentation session reset still occurs on raw-mode session
  boundaries.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalCapabilityProfileApplyingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 25: Input Reader Event Decoding

- Objective: make `InputReader` easier to follow by extracting the repeated
  control-message filtering and terminal parser feeding into a small decoder,
  while leaving platform-specific stream loops unchanged.
- Owned files:
  - `Sources/SwiftTUIRuntime/Input/InputReader.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputEventDecoding.swift`
- Dependencies: Packet 18 extracted pure input support types, and Packet 24
  completed the latest terminal-host cleanup. A read-only input audit narrowed
  this slice to parser/control-message feeding only so the WASI polling loop
  and DispatchSource drain/cancel behavior stay reviewable in place.
- Invariants: public input APIs stay unchanged; `events()` remains
  keyboard-only while still routing control messages; `inputEvents()` preserves
  stream-creation mouse-coordinate snapshot semantics; control messages from a
  chunk are handled before decoded payload events; full-input streams still
  flush pending mouse events before each control message; coalescible mouse
  events still buffer only `.moved`, `.dragged`, and `.scrolled`; WASI still
  reads 512-byte chunks, flushes pending mouse events on would-block, sleeps
  1 ms on would-block, and finishes on EOF/error after flushing; DispatchSource
  still drains 256-byte chunks until would-block/EOF/error, arms the mouse
  flush timer once per cluster, flushes before EOF/error/cancel finish, and
  cancels the scheduled flush on teardown.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
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
