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

### Packet 26: Terminal Input Parser File Split

- Objective: keep `InputReader.swift` focused on stream ownership by moving the
  public terminal byte parser and keyboard parser into a dedicated input parser
  file.
- Owned files:
  - `Sources/SwiftTUIRuntime/Input/InputReader.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputParser.swift`
- Dependencies: Packet 25 isolated the feed pipeline. A read-only parser audit
  confirmed this is a pure declaration move: parser types, bracketed-paste
  marker matching, CSI modifier parsing, SGR mouse parsing, and private numeric
  helpers move together, while platform stream loops stay in `InputReader`.
- Invariants: public `TerminalInputParser` and `KeyParser` symbols stay
  unchanged; `TerminalInputParser.init(mouseCoordinateMode:)` remains package
  only; private parser helpers stay private; partial CSI, SGR, and
  bracketed-paste buffers keep waiting for completion; lone `ESC` still emits a
  key event immediately; bracketed paste still emits one `.paste` event and
  preserves unterminated bytes across feeds; SGR cell coordinates remain
  1-based input to 0-based cell fallback; SGR pixel mode keeps zero/negative raw
  pixel behavior; the `asciiSignedInteger` implementation shape remains
  unchanged to avoid the documented Swift 6.3.1 wasm optimizer issue.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/keyParserParsesExpectedSequences`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalInputParserDecodesMixedMouseStreams`
  - `swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests/terminalPixelMouseInputReachesDragGestureAsFractionalLocation`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 27: Terminal Input Descriptor Reading

- Objective: keep `InputReader.swift` focused on stream ownership by moving
  platform `read` classification and nonblocking descriptor draining into a
  small helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Input/InputReader.swift`
  - `Sources/SwiftTUIRuntime/Input/TerminalInputStreamReading.swift`
  - `Tests/SwiftTUITests/InputBatchingResponsivenessTests.swift`
- Dependencies: Packet 26 moved parser state out of `InputReader`. A read-only
  stream-loop audit confirmed this slice should extract read/drain mechanics
  only, while leaving WASI task-backed polling and DispatchSource lifecycle
  semantics in `InputReader`.
- Invariants: public input APIs stay unchanged; WASI keeps detached task-backed
  polling, 512-byte reads, 1 ms would-block sleep, keyboard-only `Task.yield()`,
  and EOF/error finish behavior; DispatchSource streams keep queue/source
  ownership, cancellation handlers, stream termination, and 256-byte drains in
  `InputReader`; full-input streams still flush pending mouse events before
  control messages and before EOF/error finish; non-would-block read failures
  still finish/cancel the stream; EOF after drained bytes still decodes/yields
  those bytes before finishing; mouse-coordinate mode remains a
  stream-creation snapshot.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 28: Animation Controller Overlay Sampling

- Objective: continue the runtime decomposition by moving placed-overlay
  sampling out of `AnimationController.swift` without changing animation state
  ownership.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/PlacedAnimationOverlaySampling.swift`
- Dependencies: Packets 13-15 extracted tree queries, transition overlays, and
  property value application; Packet 27 finished the input stream read/drain
  boundary. A read-only animation audit identified placed overlay sampling as a
  safe value boundary and explicitly rejected moving insertion/removal detection
  in this packet.
- Invariants: `AnimationController` still owns mutable animation dictionaries,
  custom-state writeback, completed-key removal, batch ref counts, purge
  decisions, and completion deferral; placed-level animations are still
  evaluated only in the placed overlay path, not in `applyInterpolations`;
  removal entries with no placed snapshot or no parent identity still fall back
  to resolved-level injection; removal sampling completion is still handled by
  `applyInterpolations`; insertion offsets keep truncating integer math;
  matched-geometry offsets keep rounded integer math and use current placed
  bounds as the destination; overlay application order remains removals,
  insertion offsets, then matched-geometry offsets.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 29: DefaultRenderer Frame-Tail Coordinator

- Objective: return to the largest remaining runtime file and make
  `DefaultRenderer` read as frame-head and commit ownership by moving
  post-head/pre-commit frame-tail orchestration into a named helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameTailCoordinator.swift`
- Dependencies: Packet 28 completes the placed-overlay sampling extraction. A
  read-only renderer audit rejected frame-head extraction as too stateful for
  this packet and identified the frame-tail coordinator as the safer
  decomposition boundary.
- Invariants: renderer public APIs, frame-head transaction semantics,
  animation draft ownership, observation/presentation portal drafts, one-shot
  versus abortable tail behavior, queued-tail cancellation, prepared-state
  materialization, late-preference reconciliation, retained baseline placement,
  and commit behavior remain stable.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedBuiltInLayoutQueuesInputWithoutCommittingAhead`
  - `swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests/hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents`
  - `swiftly run swift test --filter SwiftTUITests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 30: Animation Completion Scheduling Policy

- Objective: make `AnimationController` lifecycle bookkeeping easier to review
  by moving stranded completion scheduling and pending-drain partitioning into a
  pure helper, without moving mutable controller ownership.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationCompletionScheduling.swift`
- Dependencies: Packet 29 completed the frame-tail coordinator split. A
  read-only animation audit ranked completion scheduling as the safest next
  `AnimationController` boundary and rejected the removal loop as too
  behaviorally dense for this packet.
- Invariants: public and package-facing APIs stay unchanged;
  `AnimationController` keeps ownership of completion closures, batch ref
  counts, pending empty-batch completions, frame-head deferral state, and
  `lastFrameHeadCompletionCount`; empty tracked batches still fire after the
  animation's nominal duration; `withAnimation(nil)` stranded completions still
  fire on the next tick; `.repeatForever` stranded completions still never fire
  and do not leak; frame-head transactions still defer completions until commit
  and suppress them on abort; `frameDropEligibilityBlockers` still reports
  `.animationCompletion` for live, deferred, and pending completion state.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortKeepsAnimationCompletionsUncommitted`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadDefersAnimationCompletionUntilCommit`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 31: DefaultRenderer Frame-Head Preparation

- Objective: continue the primary runtime rendering cleanup by making
  `DefaultRenderer`'s frame-head preparation read as named orchestration,
  without changing commit, cancellation, or public renderer APIs.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift`
- Dependencies: Packet 30 completed the bounded animation-completion scheduling
  split. A read-only runtime audit ranked frame-head preparation as the next
  central terminal-rendering infrastructure candidate because `SwiftTUI.swift`
  still combines generation, checkpoints, selective evaluation, portal wrapping,
  observation drafts, animation draft collection, retained tail input, and
  transaction assembly.
- Invariants: sync and async frame-head behavior stay equivalent;
  abort/discard behavior, `viewGraph.beginFrame` ordering, dirty evaluation
  plans, presentation portal root identity, observation and presentation drafts,
  animation draft collection, retained frame-tail input, and public
  `DefaultRenderer` API stay unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)`
  - `swiftly run swift test --filter SwiftTUITests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 32: Frame-Tail Job Cancellation and Outcome Types

- Objective: make async frame-tail cancellation and cancellable render outcomes
  easier to review by moving the job state, cancellation token, and outcome
  payload out of `FrameTailRenderer.swift`.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift`
- Dependencies: Packet 31 completed the frame-head coordinator extraction. A
  read-only runtime audit ranked this as the safest next rendering packet
  because it moves a self-contained async tail concept without widening private
  renderer or core graph state. A ViewGraph audit rejected checkpoint/debug
  snapshot file splits because those would require private-state widening.
- Invariants: `FrameTailJobState.rawValue` strings stay unchanged;
  `CancellableRenderOutcome` fields and package access stay unchanged;
  `FrameTailJobCancellationToken` remains a final `Sendable` class with `.queued`
  initial state; `cancelBeforeStart()` only transitions queued jobs to
  `.cancelledBeforeStart`; `markStarted()` returns `false` only after pre-start
  cancellation; `markCompleted()` only changes `.started` to `.completed`;
  `waitUntilLeavesQueue()` still resumes every waiter exactly once and removes
  cancelled waiters; DefaultRenderer frame-tail cancellation races and layout
  task cancellation stay behaviorally identical.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.RuntimeRenderPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 33: ViewGraph Lifecycle Planning

- Objective: make the core graph lifecycle tail easier to follow by moving the
  lifecycle event planning algorithm into a dedicated helper, while keeping
  checkpoint, debug snapshot, selective evaluation, and mutable graph ownership
  in `ViewGraph.swift`.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift`
- Dependencies: Packet 32 completed the frame-tail cancellation type split. A
  read-only core audit rejected file-splitting checkpoint/debug snapshot or
  evaluation logic because those paths directly read and write private
  `ViewGraph` storage. The audit recommended the lifecycle planner as the
  safe adjacent core split because `ViewGraph` can pass the current private
  state into the helper and receive a value plan back.
- Invariants: every mutable `ViewGraph` field remains covered by `Checkpoint`
  and `DebugTotalStateSnapshot`; checkpoint restore order stays graph maps
  first, then node checkpoints; `previewLifecycleEvents` remains non-mutating;
  `finalizeFrame` still updates committed presence, computes lifecycle,
  persists viewport lifecycle state, unions live identities, then clears dirty
  state; lifecycle event ordering stays stable-task cancels, structural task
  cancels, viewport task cancels, structural disappears, viewport disappears,
  structural appears, viewport appears, changes, viewport changes, stable task
  starts, viewport task starts; viewport lifecycle remains derived from placed
  visible children for indexed lazy content rather than the full resolved tree.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortRestoresBroadResetState`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/lazyForEachRowsEmitViewportLifecycleTransitions`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/runLoopEmitsViewportLifecycleTransitionsForFullLazyRows`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 34: Presentation Item and Storage Models

- Objective: make the presentation implementation easier to navigate by
  moving item model and per-family storage types out of
  `PresentationCoordinator.swift`, without changing presentation semantics or
  the SwiftUI-like API surface.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift`
  - `Sources/SwiftTUIViews/Presentation/PresentationItems.swift`
- Dependencies: Packet 33 completed the core lifecycle planning extraction.
  A presentation audit should confirm the exact move set before editing, but
  the safe default is to keep coordinator orchestration, draft coordination,
  registry mutation, and built-in coordinator implementations in
  `PresentationCoordinator.swift` while moving value-like item/storage models.
- Candidate move set:
  - `TrackedPresentationItem`
  - `PresentationFamilyItemStore`
  - `StoredPresentationCoordinatorCheckpoint`
  - `StoredPresentationCoordinator`
  - `PresentationChrome`
  - `PromptPresentationContentSizing`
  - `PromptPresentationDescriptor`
  - `PromptPresentationItem`
  - `PopoverPresentationItem`
  - `ToastPresentationItem`
  - `presentationAttachmentID`
- Invariants: public presentation modifiers and environment keys do not
  change; `AnyView` storage remains limited to the existing reviewed
  presentation item escape hatches; per-family checkpoint capture/restore
  remains paired with its storage type; presentation identity, escape dismissal,
  popover attachment, toast ordering, overlay stacking, and sheet draft
  isolation remain behaviorally identical.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUIViewsTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationEscapeDismissTests`
  - `swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.OverlayStackTests`
  - `swiftly run swift test --filter SwiftTUITests.DismissStackTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 35: Builtin Presentation Coordinators

- Objective: make presentation orchestration easier to read by moving the six
  concrete built-in coordinator declarations out of
  `PresentationCoordinator.swift`, while keeping registry, draft, environment,
  declaration preference, and portal composition state in place.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
  - `Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift`
- Dependencies: Packet 34 completed the passive item/storage model split. A
  read-only presentation audit confirmed this follow-up is safe if it remains a
  pure declaration move. There is no `CommandPalettePresentationCoordinator`;
  palette sheets route through `SheetPresentationCoordinator`, and expanded
  menus use `MenuPresentationCoordinator`.
- Move set:
  - `AlertPresentationCoordinator`
  - `ConfirmationDialogPresentationCoordinator`
  - `SheetPresentationCoordinator`
  - `PopoverPresentationCoordinator`
  - `MenuPresentationCoordinator`
  - `ToastPresentationCoordinator`
- Avoid moving:
  - `ViewUpdateGuard` / `PresentationMutationGuard`
  - `PresentationCoordinatorHandle`
  - `PresentationCoordinator` / `ManagedPresentationCoordinator`
  - environment handle keys and `EnvironmentValues` extensions
  - `PresentationCoordinatorBox`, `AnyPresentationCoordinatorBox`, and
    `PresentationCoordinatorRegistry`
  - `PresentationPortalState` and `PresentationPortalDraft`
  - declaration preference types, `PresentationPortalRoot`, reconciliation, and
    portal composition
- Invariants: z-index order remains alert 260, confirmation dialog 240,
  popover 220, sheet 200, menu 180, toast 100; modal policies remain
  unchanged; mutation-guard messages stay byte-for-byte stable; registry
  checkpoint fields and box order stay unchanged; popover keeps its per-item
  `modalPolicy(for:)` override; toast keeps `itemsOldestFirst`; no public
  modifier, environment, declaration preference, or portal composition behavior
  changes.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.MenuSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PaletteSheetAbsorptionTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 36: Presentation Registry Support

- Objective: make presentation state ownership easier to follow by moving the
  cohesive registry support block into a dedicated file, while leaving portal
  state/draft publication and portal-root composition untouched.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift`
- Dependencies: Packet 35 completed the built-in coordinator declaration move.
  A read-only state-boundary audit selected the registry block as the next safe
  move because it keeps checkpoint fields and registry users together without
  broadening access.
- Move set:
  - `PresentationCoordinatorBox`
  - `AnyPresentationCoordinatorBox`
  - `PresentationCoordinatorRegistry`
- Avoid moving:
  - `ViewUpdateGuard` / `PresentationMutationGuard`
  - `PresentationCoordinatorHandle`
  - `PresentationCoordinator` / `ManagedPresentationCoordinator`
  - environment handle keys and `EnvironmentValues` extensions
  - `PresentationPortalState` and `PresentationPortalDraft`
  - declaration preference types
  - `presentationPortalIdentity`, `PresentationPortalRoot`,
    `reconcilePresentationDeclarations`, and `composePresentationPortalTree`
- Invariants: `allBoxes` order remains alert, confirmation dialog, sheet,
  popover, menu, toast; registry checkpoint field shape and restore order stay
  unchanged; coordinator instantiation remains lazy; invalidator retention
  stays weak; host identity propagation is unchanged; overlay stable IDs keep
  the `"\(C.overlayKindName):\(String(reflecting: item.id))"` format; overlay
  ordering stays through `portalOrderingPrecedes`; dismiss-stack derivation
  stays based on `overlayEntries()`; no public API, package API, z-index,
  modal-policy, environment-key, or draft commit/discard behavior changes.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter 'SwiftTUITests\.(PresentationEscapeDismissTests|PopoverPresentationTests|OverlayStackTests|DismissStackTests|PresentationSurfaceTests)'`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 37: Presentation Portal State Transactions

- Objective: make the presentation draft transaction layer easier to follow by
  moving live portal state and draft state into a dedicated file, while leaving
  declaration preferences and portal-root tree composition untouched.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
  - `Sources/SwiftTUIViews/Presentation/PresentationPortalState.swift`
- Dependencies: Packet 36 completed registry support extraction. A read-only
  audit selected this move and explicitly deferred portal composition helpers
  because `composePresentationPortalTree` must keep reconciling declarations
  from `baseNode.preferenceValues`, not stale host/root state.
- Move set:
  - `PresentationPortalState`
  - `PresentationPortalState.Checkpoint`
  - `PresentationPortalDraft`
- Avoid moving:
  - `PresentationPortalRoot`
  - `presentationPortalIdentity`
  - `reconcilePresentationDeclarations`
  - `composePresentationPortalTree`
  - `PresentationCoordinatorDeclaration` preference types
  - coordinator guards, handles, and protocols
- Invariants: draft public methods keep the `!didCommit && !didDiscard`
  preconditions; `commit()` publishes the draft registry into live state exactly
  once; `discard()` does not mutate live state; `makeDraft()` starts from
  `PresentationPortalState.makeCheckpoint()`; `injectHandles`, `reconcile`,
  `overlayEntries`, and `dismissStack` continue delegating through
  `PresentationCoordinatorRegistry`; no visibility broadening beyond what the
  move requires.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationEscapeDismissTests`
  - `swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 38: ViewGraph Structural Removal Planning

- Objective: make the structural child-removal boundary explicit without
  moving mutable graph ownership out of `ViewGraph`.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift`
- Dependencies: Packet 33 extracted lifecycle event planning. A fresh
  production debt scan selected `ViewGraph` as the highest-value remaining
  central infrastructure file because it still owns dirty evaluation,
  structural child reconciliation, dependency indexing, aliases, lifecycle
  side effects, and subtree removal.
- Move set:
  - child-removal planning for `applyStructuralChildDiff`
  - value-only removal records containing the old child index and optional
    committed snapshot
- Avoid moving:
  - `nodesByIdentity` mutation
  - `removeSubtree` and `removeResolvedSubtree`
  - lifecycle event mutation
  - dependency edge cleanup
  - registration alias cleanup
  - dirty-frontier evaluation
  - checkpoint/debug snapshot state
- Invariants: `ViewGraph` remains the only owner of live `ViewNode` storage and
  subtree teardown; removed-child index guards match the previous
  `node.children.indices.contains(oldIndex)` behavior; committed-snapshot
  selection still uses `node.committed.children[oldIndex]` when present;
  matched, moved, and inserted children are still materialized by the existing
  commit/reuse/install paths; lifecycle event ordering, dependency cleanup,
  alias cleanup, checkpoint totality, and public API remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StructuralDiffTests`
  - `swiftly run swift test --filter SwiftTUICoreTests`
  - `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - `swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 39: ViewGraph Dirty Evaluation Planning

- Objective: make selective dirty-evaluation target selection readable without
  moving dirty-bit mutation or the `DirtyEvaluationPlan` commit boundary out of
  `ViewGraph`.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphDirtyEvaluationPlanning.swift`
- Dependencies: Packets 33 and 38 extracted adjacent lifecycle and structural
  planning seams. A fresh production-code scan selected this slice because
  `ViewGraph.selectiveDirtyEvaluationPlan()` still mixed validation,
  dirty-frontier discovery, lifecycle-owner promotion, evaluator fallback, and
  graph mutation in one flow.
- Move set:
  - graph-known invalidation coverage checks
  - dirty-frontier discovery and stable ordering
  - lifecycle evaluation owner promotion
  - nearest evaluator ancestor fallback
  - duplicate target collapse
- Avoid moving:
  - `markDirty()` calls on selected targets
  - `DirtyEvaluationPlan` construction
  - `graphLocalDirtyIdentities` and `invalidatedIdentities` mutation
  - live `ViewNode` storage ownership
  - lifecycle owner registration/pruning
  - dependency edge cleanup
- Invariants: identities without graph nodes still do not block selective
  planning; graph-known invalidated identities must still be graph-local dirty;
  dirty descendants remain suppressed when an ancestor is already dirty;
  frontier order remains depth-then-identity stable; lifecycle-owned nodes
  still promote to their owner before evaluator fallback; selected evaluator
  targets are still marked dirty by `ViewGraph`; public API remains unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphDirtyEvaluationPlanning.swift`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - `swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUICoreTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 40: TerminalHost Presentation Emission Builder

- Objective: separate terminal frame emission assembly from raw-mode/session
  ownership inside `TerminalHost` while preserving byte-for-byte output order.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift`
- Dependencies: Packets 1, 2, 7-12 clarified terminal presentation state,
  image rendering, capability probing, and planning. A fresh terminal-runtime
  audit selected this slice because `TerminalHost` still mixed raw-mode/session
  sequencing with full repaint, incremental row output, edit-operation
  lowering, and Kitty replay emission.
- Move set:
  - presentation emission dispatch for full repaint vs incremental plans
  - full-repaint clear/home/text/graphics append order
  - incremental row cursor/output append order
  - erase-to-end-of-line lowering for eligible row batches
  - Kitty targeted/full replay emission and graphics replay metric recording
  - graphics write-step appending with the transmitted Kitty image cache passed
    by `inout`
- Avoid moving:
  - raw-mode enable/disable sequencing
  - presentation writer creation, drain, and drop recovery
  - `TerminalPresentationSession` retained-surface rules
  - graphics capability probing
  - synchronized-output wrapping and metrics finalization
  - `presentationSession.lastSubmittedSurface` updates
- Invariants: full repaint still clears, homes the cursor, writes text rows,
  and then writes graphics; Kitty full repaint still invalidates transmitted
  image IDs before retransmit; incremental text rows still precede Kitty replay;
  full Kitty replay still deletes visible placements before graphics writes;
  erase-to-end lowering still records metrics only when terminal edit
  operations are enabled and the row batch is safe to lower; synchronized output
  wrapping remains in `TerminalHost.present`.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 41: Terminal Render Style Codec File Split

- Objective: separate Web runner style transport encoding/decoding from
  terminal control-message parsing without changing the SPI codec surface or
  transport bytes.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
- Dependencies: Packet 40 finished the terminal-host emission extraction. A
  fresh terminal-runtime audit compared the remaining `TerminalSurfaceRenderer`
  seams with this control-message slice and selected the codec split as the
  lower-risk preparatory cleanup before touching terminal text rendering and
  sanitization.
- Move set:
  - `@_spi(Runners) public enum TerminalRenderStyleCodec`
  - style transport JSON value/parser helpers
  - style transport base64 helper
  - JSON string literal, whitespace, hex digit, and base64 digit helpers
- Avoid moving:
  - `TerminalControlMessage`
  - `ControlMessageParser`
  - resize/style command dispatch behavior
  - the `style:` command prefix handling
  - any Web/Swift transport schema behavior
- Invariants: `TerminalRenderStyleCodec.encodeBase64` and `decodeBase64` keep
  their SPI/public names and access; the schema alignment comment remains with
  the codec; `ControlMessageParser` still calls `TerminalRenderStyleCodec
  .decodeBase64`; JSON field order, lowercase hex output, base64 padding, and
  invalid input rejection remain unchanged; no Foundation import is introduced.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
  - `swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - `swiftly run swift test --filter WASISurfaceBridgeTests`
  - `swiftly run swift test --filter SwiftTUIWebHostTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 42: Terminal Cell Text Rendering Extraction

- Objective: separate terminal cell text rendering, style lowering, text
  sanitization, ASCII glyph degradation, and OSC 8 hyperlink emission from the
  presentation damage planner while preserving terminal bytes.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
- Dependencies: Packet 40 split host-level presentation emission and Packet 41
  removed unrelated Web style transport code from terminal control-message
  parsing. A fresh terminal presentation audit selected this packet as the next
  focused extraction because the remaining `TerminalPresentation.swift` body
  still mixed row-damage planning with byte-level cell rendering concerns.
- Move set:
  - row-span cell text emission state
  - render-state transition and close handling
  - cursor-forward sequence construction
  - terminal control-scalar replacement
  - ASCII glyph fallback mapping
  - SGR style lowering and color-code helpers
  - OSC 8 hyperlink open/close and destination sanitization
  - ANSI16 palette matching helpers
- Avoid moving:
  - full-repaint and incremental presentation planning
  - row-batch coalescing
  - erase-to-end lowering decisions and metrics accounting
  - graphics replay planning
  - synchronized-output wrapping
  - presentation session state
- Invariants: full repaint and incremental row spans keep byte-for-byte text
  behavior; render state is shared across adjacent row spans and closed once at
  batch end; control scalars still render as replacement characters; hyperlink
  destinations still strip terminal-control and C1 bytes before OSC 8 output;
  ASCII profile rendering still degrades non-ASCII glyphs through the existing
  mapping; SGR reset/style/color ordering remains unchanged; no public or SPI
  API is added.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.Phase1PresentationIntegrationTests`
  - `swiftly run swift test --filter SwiftTUITests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
  - `bun run test`
- Rollback: revert the packet commit/files only.

### Packet 43: Terminal Surface Damage Rendering Extraction

- Objective: separate incremental row-damage span detection and row-batch
  rendering from `TerminalSurfaceRenderer` while keeping the existing internal
  test-visible forwarding methods.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift`
- Dependencies: Packet 42 isolated byte-level cell text rendering. This packet
  moves the remaining incremental damage/span planning that belongs beside that
  renderer but not inside the public `TerminalSurfaceRenderer` type body.
- Move set:
  - `renderRowBatch`
  - `diffSpans` and candidate-range limiting
  - span normalization around wide-glyph continuation cells
  - out-of-bounds row-cell lookup
  - changed-cell accounting for metrics
- Avoid moving:
  - public `TerminalSurfaceRenderer.render(_:)`
  - full-row rendering and trailing-whitespace trimming
  - terminal cell text/style/hyperlink emission
  - `TerminalPresentationPlanner`
  - host emission and graphics replay planning
- Invariants: no public or SPI API changes; `TerminalSurfaceRenderer` keeps the
  same internal wrappers; span sorting, cursor-forward gaps, shared render state
  across row spans, one final state close, damage range clamping, `.empty`
  out-of-bounds cells, wide-glyph continuation normalization, and `cellsChanged`
  span-width accounting remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.Phase1PresentationIntegrationTests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 44: Terminal Capability Profile File Split

- Objective: move terminal capability detection and runtime-configuration
  overlays out of `TerminalPresentation.swift` so the presentation file focuses
  on raster-to-terminal rendering.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalCapabilityProfile.swift`
- Dependencies: Packet 43 left `TerminalPresentation.swift` with two remaining
  concerns: capability-profile policy and the actual renderer. This packet
  isolates the policy type without changing the public declaration.
- Move set:
  - `public struct TerminalCapabilityProfile`
  - nested glyph/color enums
  - stored properties and initializer
  - static preview/ANSI/true-color profiles
  - environment/TTY capability detection
  - `RuntimeConfiguration` overlay application
- Avoid moving:
  - `TerminalSurfaceRenderer`
  - terminal presentation planning
  - terminal host probing or live graphics capability detection
  - any public API names, access levels, or defaults
- Invariants: public API inventory remains unchanged; UTF-8 locale detection,
  `NO_COLOR`, non-TTY/`dumb` fallback, rich-terminal term list,
  synchronized-output/mouse/hyperlink flags, color/glyph override semantics,
  and default initializer values remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCapabilityProfile.swift`
  - `swiftly run swift test --filter SwiftTUITests.TerminalCapabilityProfileApplyingTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.EnvironmentResolverTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 45: TabView Style Host Split

- Objective: separate TabView style host plumbing, style type erasure, hosted
  strip/overflow views, and layout slot metadata from the public style
  declarations and raw tab chrome rendering.
- Owned files:
  - `Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift`
  - `Sources/SwiftTUIViews/NavigationViews/TabViewStyleHosting.swift`
- Dependencies: Packets 34-37 split presentation support, leaving navigation
  styles as a remaining high-traffic SwiftUI-shaped surface. A fresh audit
  selected TabView because `TabViewStyles.swift` still mixed public style
  declarations with host/layout/type-erasure internals and raw glyph chrome.
- Move set:
  - style type-erasure box protocol and concrete box
  - hosted tab strip, overflow slot, and overflow menu views
  - tab style body host and layout slot node
  - layout subview role metadata and container layout
  - package tab item, overflow trigger, and overflow item identity helpers
- Avoid moving:
  - public `TabViewStyle` and concrete style declarations
  - literal/powerline/underline tab chrome rendering
  - reviewed raw glyph declarations
  - consumer-visible style API names, defaults, or builder behavior
- Invariants: no public API change; `AnyTabViewStyle` still erases through the
  same private stored box; package identity helpers keep the same components;
  active `DeferredPayloadView` resolution and overflow placement remain
  unchanged; raw tab glyph/chrome behavior stays in `TabViewStyles.swift`.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift Sources/SwiftTUIViews/NavigationViews/TabViewStyleHosting.swift`
  - `swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests`
  - `./Scripts/check_accessibility_guardrails.sh`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 46: Semantic Accessibility Extraction

- Objective: separate accessibility node and warning extraction from the main
  semantic routing walk so `Semantics.swift` can focus on interaction, focus,
  scroll, and payload routing.
- Owned files:
  - `Sources/SwiftTUICore/Semantics/Semantics.swift`
  - `Sources/SwiftTUICore/Semantics/SemanticAccessibilityExtraction.swift`
- Dependencies: Packet 45 finished the first view-surface split in the
  aggressive batch. A core audit selected semantics next because the extractor
  remains a central typed phase and had a large accessibility-specific block
  embedded between scroll target and interaction payload routing.
- Move set:
  - accessibility node two-pass subtree emission
  - hidden descendant propagation
  - focus identity relevance
  - text-input cursor anchor hoisting
  - role and label inference
  - visual-content accessibility warnings
- Avoid moving:
  - the placed-tree semantic walk
  - interaction and focus region routing
  - scroll route/target extraction
  - rich-text/list/table payload interaction semantics
  - public `SemanticSnapshot` or `AccessibilityNode` API
- Invariants: transient and accessibility-hidden subtrees are still skipped;
  parent identity threading, hidden descendant flags, role/label inference,
  focus relevance, cursor anchors, and visual-content warnings remain
  unchanged; shared `semanticBounds` geometry remains the single offset-aware
  bounds helper; only module-internal helper visibility changes.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Semantics/Semantics.swift Sources/SwiftTUICore/Semantics/SemanticAccessibilityExtraction.swift`
  - `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.FocusPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - `swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests`
  - `swiftly run swift test --filter SwiftTUITests.ContentShapeTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 47: Text Layout Cache Extraction

- Objective: move text layout cache storage and LRU bookkeeping out of
  `TextLayout.swift`, leaving the public text layout types and wrapping logic
  easier to follow.
- Owned files:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutCache.swift`
  - `Tests/SwiftTUITests/TextLayoutCacheTests.swift`
- Dependencies: Packet 46 isolated semantic accessibility extraction. A core
  content audit selected text layout next because `TextLayout.swift` still
  mixed public layout types, cache state, wrapping, truncation, rich-text
  clusterization, and Unicode cell-width policy.
- Move set:
  - package `TextLayoutCache`
  - cache key, metrics, storage, access records, and shared instance
  - generation refresh and eviction bookkeeping
  - reset and metrics reporting
- Avoid moving:
  - public `TextCluster`, `TextLayoutLine`, `TextLayoutOptions`, and
    `TextLayoutResult`
  - public `layoutText`
  - rich-text layout entry point
  - wrapping/truncation algorithms
  - Unicode cell-width policy
- Invariants: public API inventory remains unchanged; `layoutText` still routes
  through `TextLayoutCache.shared`; cache key shape, hit/miss/store/eviction
  counters, generation refresh, and capacity eviction remain unchanged; the
  uncached string layout helper is module-internal only so the extracted cache
  can call it.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutCache.swift Tests/SwiftTUITests/TextLayoutCacheTests.swift`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.RenderedTextFixtureSupportTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 48: Text Layout Wrapping Extraction

- Objective: move word-boundary wrapping, continuation-marker handling, and
  cluster wrapping fallback out of `TextLayout.swift` so the main text layout
  entry point reads as orchestration.
- Owned files:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutWrapping.swift`
  - `Tests/SwiftTUITests/TextLayoutTests.swift`
- Dependencies: Packet 47 split cache storage. This packet starts decomposing
  the remaining high-risk text layout algorithms while preserving the public
  SwiftUI-shaped text surface.
- Move set:
  - `wrapTextLine`
  - word-boundary run tokenization
  - separator whitespace deferral and consumption
  - oversized word-like continuation-marker wrapping
  - cluster fallback wrapping and cell-width slicing helpers
  - word-like and whitespace classification helpers
- Avoid moving:
  - public text layout types and `layoutText`
  - rich-text explicit line expansion
  - line-limit truncation
  - Unicode cell-width policy
- Invariants: nil width, zero width, empty text, leading whitespace,
  separator whitespace, oversized word-like markers, narrow-width fallback,
  wide cluster handling, and the existing test hook remain unchanged; no
  public or package consumer API is added.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
- Rollback: revert the packet commit/files only.

### Packet 49: Text Layout Truncation Extraction

- Objective: move line-limit truncation and head/middle/tail fitting helpers
  out of `TextLayout.swift`, keeping truncation width accounting separate from
  wrapping and cache concerns.
- Owned files:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutTruncation.swift`
  - `Tests/SwiftTUITests/TextLayoutTests.swift`
- Dependencies: Packet 48 isolated wrapping. This packet isolates the next
  phase in the text layout pipeline.
- Move set:
  - `truncating`
  - leading cluster fitting
  - trailing cluster fitting
- Avoid moving:
  - public text layout types and `layoutText`
  - wrapping algorithms
  - Unicode cell-width policy
  - cache storage
- Invariants: nil-width and no-forced-indicator behavior, zero-width and
  one-cell ellipsis handling, head/tail/middle width splitting, wide-cluster
  fitting, and post-wrap line-limit behavior remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutTruncation.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
- Rollback: revert the packet commit/files only.

### Packet 50: Text Cell Width Policy Extraction

- Objective: move terminal cell-width classification out of `TextLayout.swift`
  so layout, borders, tile style, rasterization, and text input share a clearly
  named policy file.
- Owned files:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextCellWidth.swift`
- Dependencies: Packet 49 isolated truncation. This packet leaves
  `TextLayout.swift` focused on public types, explicit line expansion, and
  phase orchestration.
- Move set:
  - package `cellWidth(of:)`
  - zero-width scalar classification
  - wide scalar classification
- Avoid moving:
  - text wrapping and truncation
  - text input layout maps
  - border, tile, or raster call sites
- Invariants: package visibility remains unchanged; ASCII/NUL fast path,
  multi-scalar ASCII fallback, emoji presentation, VS16, wide CJK/emoji
  ranges, zero-width marks, and empty-character behavior remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextCellWidth.swift`
  - `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - `swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests`
  - `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - `swiftly run swift test --filter TileStyle`
  - `swiftly run swift test --filter BorderSet`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - `./Scripts/generate_public_api_inventory.sh --check`
  - `./Scripts/check_accessibility_guardrails.sh`
  - `git diff --check`
- Rollback: revert the packet commit/files only.

### Packet 51: Prompt Presentation Entrypoint Extraction

- Objective: move prompt presentation specs and public `.alert(...)`,
  `.confirmationDialog(...)`, and `.sheet(...)` entrypoints out of
  `PresentationModifiers.swift` so modifier resolution and public authoring
  surface are easier to review independently.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`
  - `Sources/SwiftTUIViews/Presentation/PromptPresentationEntrypoints.swift`
  - `Scripts/lib/public_documentation_ratchet.txt`
- Dependencies: presentation item/coordinator splits from Packets 34-37.
- Move set:
  - `PromptPresentationSpec`
  - alert, confirmation-dialog, menu, and sheet prompt spec builders
  - public prompt/sheet authoring entrypoints
  - default prompt dismiss action builder
- Avoid moving:
  - prompt modifier resolve implementations
  - palette sheet modifier
  - prompt surface rendering
  - toast presentation system
- Invariants: public API shape, overload signatures, default dismiss titles,
  attachment tokens, authoring-context capture, and presentation reconciliation
  behavior remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift Sources/SwiftTUIViews/Presentation/PromptPresentationEntrypoints.swift`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - `./Scripts/check_public_documentation_ratchet.sh`
  - `./Scripts/check_public_surface_policies.sh`
- Rollback: revert the packet files only; the ratchet entries should move back
  with the public declarations.

### Packet 52: Prompt Presentation Surface Extraction

- Objective: move hosted prompt presentation rendering out of
  `PresentationModifiers.swift` so the prompt modifier file no longer mixes
  modifier resolution with rendered chrome.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`
  - `Sources/SwiftTUIViews/Presentation/PromptPresentationSurface.swift`
  - `Scripts/lib/accessibility_color_state_sources.txt`
- Dependencies: Packet 51 separated prompt entrypoints from modifier
  resolution.
- Move set:
  - `HostedPromptPresentation`
  - `PromptPresentationSurface`
  - prompt surface sizing, inset, header, content, menu, action, and semantic
    metadata helpers
- Avoid moving:
  - prompt spec builders and public entrypoints
  - prompt modifier resolve implementations
  - toast presentation system
- Invariants: alert/sheet/confirmation/menu chrome, backdrop opacity, focus
  scope metadata, close button behavior, scroll bounds, menu intrinsic sizing,
  and accessibility color-state guardrail coverage remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests`
  - `swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests`
  - `./Scripts/check_accessibility_guardrails.sh`
- Rollback: revert the packet files only; the color-state manifest entry should
  move back with the prompt chrome.

### Packet 53: Toast Presentation Extraction

- Objective: move toast styles, toast modifiers, coordinator body, and rendered
  toast surface out of `PresentationModifiers.swift` so transient notification
  behavior has a dedicated home.
- Owned files:
  - `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`
  - `Sources/SwiftTUIViews/Presentation/ToastPresentation.swift`
  - `Scripts/lib/public_documentation_ratchet.txt`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
  - `Scripts/lib/accessibility_color_state_sources.txt`
- Dependencies: Packet 52 removed prompt surface rendering from the same file.
- Move set:
  - `AnyToastStyle`, `ToastStyle`, `ToastStyleConfiguration`, and
    `ToastStylePresentation`
  - built-in info/success/warning/danger toast styles
  - public `.toast(...)` entrypoints
  - `ToastModifier`
  - `ToastCoordinatorBodyView`
  - `ToastPresentationView`
- Avoid moving:
  - toast coordinator storage/registry
  - presentation item models
  - prompt presentation behavior
- Invariants: public toast API shape, default style/duration, semantic icon
  glyphs, auto-dismiss lifecycle task, bottom-left overlay placement,
  hit-testing behavior, and docs/accessibility guardrail coverage remain
  unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - `swiftly run swift test --filter SwiftTUITests.PresentationEscapeDismissTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/toastAutoDismissRegistersLifecycleTask`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput`
  - `./Scripts/check_public_documentation_ratchet.sh`
  - `./Scripts/check_accessibility_guardrails.sh`
  - `./Scripts/check_public_surface_policies.sh`
  - `git diff --check`
- Batch gate for Packets 51-53:
  - `bun run test`
- Rollback: revert the packet files only; docs and accessibility manifests
  should follow the toast public declarations and moved raw glyph/color-state
  usage.

### Packet 54: Resolved Semantic Metadata Extraction

- Objective: move semantic metadata support types out of `ResolvedNode.swift`
  so the main resolved-tree model starts with the node itself and its derived
  state maintenance.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedSemanticMetadata.swift`
- Dependencies: none beyond the existing resolve-layer module boundary.
- Move set:
  - `TabItemLabel`
  - `AccessibilityVisualContent`
  - `SemanticMetadata`
  - `TextInputAccessibilityCursorAnchor`
- Avoid moving:
  - `ResolvedNode` stored fields
  - derived-state recomputation helpers
  - traversal/equivalence helpers
- Invariants: public metadata signatures, focus/hit-test flags, accessibility
  merge precedence, tab label display text, cursor-anchor propagation, and
  interaction-availability merging remain unchanged.
- Required checks:
  - `swiftly run swift build`
  - `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - `swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests`
  - `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
- Rollback: revert the new metadata file and restore the moved declarations to
  `ResolvedNode.swift`; no policy manifests should need rollback.

### Packet 55: Resolved Support Value-Type Extraction

- Objective: move lifecycle metadata, matched-geometry value types, and
  indexed-child support out of `ResolvedNode.swift` while preserving all access
  levels and public signatures.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedLifecycleMetadata.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedMatchedGeometry.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedIndexedChildSupport.swift`
- Dependencies: Packet 54 removed the semantic metadata block from the same
  file.
- Move set:
  - `LifecycleMetadata`
  - `MatchedGeometryNamespace`
  - `MatchedGeometryKey`
  - `MatchedGeometryConfig`
  - `IndexedChildSource`
  - `CustomLayoutFallbackSummary`
  - `IndexedChildSourceSnapshot`
  - `ResolvedNode.usesIndexedChildSource`
- Avoid moving:
  - `ResolvedNode` stored fields
  - private derived-state recomputation helpers
  - traversal/equivalence helpers
- Invariants: public lifecycle and matched-geometry API shape, indexed-child
  worker snapshot behavior, custom-layout fallback summary aggregation, and
  retained-reuse indexed-source decisions remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ChildDescriptorTests`
  - `swiftly run swift test --filter matchedGeometry`
  - `swiftly run swift test --filter LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests`
  - `swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests`
- Rollback: revert the three new support files and restore the moved
  declarations to `ResolvedNode.swift`; no examples or tests should change.

### Packet 56: Resolved Node Traversal And Equivalence Extraction

- Objective: move tree traversal, lifecycle collection, and retained-layout
  equivalence helpers out of the core `ResolvedNode` declaration so the file
  now focuses on stored phase data plus derived-state maintenance.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedNodeTraversal.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedNodeEquivalence.swift`
- Dependencies: Packets 54 and 55 removed support declarations from the top of
  `ResolvedNode.swift`.
- Move set:
  - `descendant(with:)`
  - `path(to:)`
  - `collectIdentities(...)`
  - lifecycle node/handler collection helpers
  - measurement and placement equivalence helpers
  - type-discriminator compatibility helper
  - `ResolvedNode ==`
- Avoid moving:
  - private derived-state recomputation helpers, which would require widening
    access if moved mechanically
  - `ResolvedNode` stored fields or initializers
- Invariants: stack-safe traversal order, lifecycle collection order,
  measurement-cache equivalence semantics, retained-placement invalidation,
  type-discriminator bridging, and Equatable behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ChildDescriptorTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
- Batch gate for Packets 54-56:
  - `bun run test`
- Rollback: revert the traversal/equivalence files and restore the moved
  extension members to `ResolvedNode.swift`; public API inventory should remain
  unchanged after rollback.

### Packet 57: View Metadata Modifier Family Extraction

- Objective: move identity, metadata, accessibility, focus, environment,
  layout-value, and alignment-guide modifiers out of `ViewModifiers.swift` so
  the remaining file no longer mixes all view modifier families.
- Owned files:
  - `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewMetadataModifiers.swift`
  - `Sources/SwiftTUIViews/Layout/CustomLayout.swift`
- Move set:
  - `id`, package identity, `layoutMetadata`, `layoutValue`, alignment-guide,
    draw metadata, opacity, semantic/accessibility, focus, hit-testing, and
    environment entrypoints
  - `IDModifier`, `ExactIdentityModifier`, `LayoutMetadataModifier`,
    `LayoutValueModifier`, alignment-guide modifiers, `DrawMetadataModifier`,
    `SemanticMetadataModifier`, and environment modifier implementations
- Invariants: public modifier signatures, semantic metadata merge precedence,
  tab metadata peeking, explicit identity rewriting, layout values, alignment
  guides, and environment propagation remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests`
  - `swiftly run swift test --filter SwiftTUIViewsTests.ViewModifierAlgebraTests`
  - `swiftly run swift test --filter SwiftTUIViewsTests.DependencyTrackingTests`
  - `swiftly run swift test --filter SwiftTUIViewsTests.EnvironmentTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReadsLayoutValuesAndPlacesSubviews`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/alignmentGuideOverridesFeedStackPlacement`
- Rollback: restore the moved declarations to `ViewModifiers.swift` and move
  layout-value/alignment-guide implementations back to the custom-layout file.

### Packet 58: View Lifecycle Modifier Family Extraction

- Objective: isolate lifecycle modifiers from the general modifier file while
  keeping `.task` actor-inheritance guardrails intact.
- Owned files:
  - `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewLifecycleModifiers.swift`
  - `Scripts/check_public_surface_policies.sh`
- Move set:
  - `onAppear`, `onDisappear`, `onChange`, and both `task` overloads
  - lifecycle handler helpers
  - `AppearLifecycleModifier`, `DisappearLifecycleModifier`,
    `ChangeLifecycleModifier`, `TaskLifecycleDescriptorIdentity`, and
    `TaskLifecycleModifier`
- Invariants: public lifecycle signatures, `@_inheritActorContext` on task
  closures, task-id replacement semantics, local lifecycle registry ordering,
  and imperative authoring-context capture remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.Phase2LifecycleFixtureTests`
  - `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/onChangeDefersExecutionUntilCommitAndTracksOldAndNewValues`
  - `swiftly run swift test --filter SwiftTUITests.ImperativeAuthoringContextDispatchTests`
  - `./Scripts/check_public_surface_policies.sh`
- Rollback: restore lifecycle declarations to `ViewModifiers.swift` and point
  the public-surface task guard back at that file.

### Packet 59: View Layout And Decoration Modifier Family Extraction

- Objective: isolate layout, safe-area, frame, offset, matched-geometry,
  overlay, background, clipping, and border modifier behavior.
- Owned files:
  - `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewLayoutModifiers.swift`
- Move set:
  - layout sizing/text policy entrypoints
  - offset, position, matched geometry, padding, safe area, frame, overlay, and
    background entrypoints
  - corresponding primitive modifier implementations and local stored-content
    resolution helpers
- Invariants: public modifier signatures, safe-area propagation, border layout
  behavior, geometry-reader proposals, overlay/background ordering, transition
  offset contribution, and matched-geometry tagging remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.SafeAreaSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.BorderModifierLayoutTests`
  - `swiftly run swift test --filter SwiftTUITests.BorderRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.GeometryReaderSurfaceTests`
  - `swiftly run swift test --filter matchedGeometry`
  - `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests/reducedMotionSuppressesMatchedGeometryTranslation`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/overlayAlignmentUsesPrimaryGuides`
- Rollback: restore layout/decorative declarations to `ViewModifiers.swift`;
  no public API inventory changes should be required.

### Packet 60: Built-In Stack Layout Extraction

- Objective: move built-in `HStackLayout`, `VStackLayout`, `ZStackLayout`, and
  their private stack/overlay placement helpers out of the custom-layout bridge.
- Owned files:
  - `Sources/SwiftTUIViews/Layout/CustomLayout.swift`
  - `Sources/SwiftTUIViews/Layout/StackLayouts.swift`
- Move set:
  - public built-in stack layout structs
  - private stack size, stack placement, stack spacing, cross-axis metrics,
    overlay metrics, and overlay placement helpers
- Invariants: public stack layout signatures, built-in layout-behavior
  detection, stack spacing, alignment-guide placement, and `AnyLayout`
  identity/cache behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/zStackLayoutMirrorsZStackPlacement`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/anyLayoutPreservesIdentityAcrossSwitches`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/anyLayoutFlattensForEachChildren`
  - `./Scripts/generate_public_api_inventory.sh --check`
- Rollback: move stack layout declarations and helpers back into the
  custom-layout file and make the built-in behavior protocol private again if
  it has no cross-file conformers.

### Packet 61: Custom Layout Bridge File Rename

- Objective: rename the remaining custom-layout API and bridge from the broad
  `Layout.swift` name to `CustomLayout.swift` without splitting its private
  cache, placement-recorder, and proxy seams.
- Owned files:
  - `Sources/SwiftTUIViews/Layout/Layout.swift`
  - `Sources/SwiftTUIViews/Layout/CustomLayout.swift`
- Move set:
  - `LayoutValueKey`, `LayoutSubview`, `LayoutSubviews`, `Layout`,
    `SendableLayout`, `AnyLayout`, custom-layout reuse protocols, custom layout
    boxes/proxies, `LayoutContainer`, placement recorder/default placement
    helpers, and worker/main-actor bridge implementations
- Invariants: public custom layout signatures, `AnyLayout` behavior, cache
  scoping, worker-safe `SendableLayout` execution, default placement fallback,
  and custom-layout stack-minimum behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReadsLayoutValuesAndPlacesSubviews`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReusesCacheBetweenMeasurementAndPlacement`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sharedAnyLayoutInstancesKeepCacheScopedPerContainer`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/publicSendableLayoutOptInRunsLayoutOnFrameTailWorker`
  - `./Scripts/check_public_surface_policies.sh`
  - `./Scripts/generate_public_api_inventory.sh --check`
- Batch gate for Packets 57-61:
  - `bun run test`
- Rollback: rename `CustomLayout.swift` back to `Layout.swift` and restore the
  Packet 60 stack declarations if needed; public API inventory should remain
  unchanged after rollback.

### Packet 62: ViewGraph Dependency And Registration Helpers

- Objective: move dependency-index maintenance and runtime-registration replay
  out of the central `ViewGraph` implementation without exposing private graph
  storage.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphDependencyIndexing.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphRuntimeRegistrationRestoration.swift`
- Move set:
  - dependency reindex, remove, observable-dependent, and
    environment-dependent helper logic
  - current-frame and resolved-subtree runtime registration restoration logic
- Invariants: `ViewGraph` stored properties stay private, dependency cleanup
  and observation/environment invalidation behavior remain unchanged, and alias
  runtime registrations are still replayed.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
- Rollback: inline the helper calls back into `ViewGraph.swift` and delete the
  two helper files.

### Packet 63: Built-In TabView Style Chrome Extraction

- Objective: keep public TabView style declarations anchored in
  `TabViewStyles.swift` while moving built-in style conformances and private
  terminal chrome helpers to a named file.
- Owned files:
  - `Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift`
  - `Sources/SwiftTUIViews/NavigationViews/BuiltinTabViewStyles.swift`
  - `Scripts/lib/accessibility_color_state_sources.txt`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
- Move set:
  - `AutomaticTabViewStyle`, `UnderlineTabViewStyle`,
    `LiteralTabsTabViewStyle`, and `PowerlineTabViewStyle` conformances
  - underline, literal-tabs, overflow, and powerline chrome helpers
- Invariants: public TabView style declarations and ratchet paths remain in
  `TabViewStyles.swift`; tab identity, overflow calculation, raw glyph review,
  and color-state review remain covered.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests`
  - `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/literalTabOverflowUpdatesOnSIGWINCHWithoutAdditionalInput`
  - `./Scripts/check_accessibility_guardrails.sh`
  - `./Scripts/check_public_surface_policies.sh`
- Rollback: move built-in style conformances and chrome helpers back into
  `TabViewStyles.swift` and restore the accessibility manifest paths.

### Packet 64: List And Outline Style Family Split

- Objective: split the combined collection style file into list and outline
  style families.
- Owned files:
  - `Sources/SwiftTUIViews/Collections/CollectionStyles.swift`
  - `Sources/SwiftTUIViews/Collections/ListStyles.swift`
  - `Sources/SwiftTUIViews/Collections/OutlineStyles.swift`
  - `Scripts/lib/public_documentation_ratchet.txt`
- Move set:
  - `ListStyle`, `AnyListStyle`, and built-in list styles
  - `OutlineStyle`, `AnyOutlineStyle`, and built-in outline styles
- Invariants: public style protocols remain extensible, list/table
  presentation behavior and outline connector presentation remain unchanged,
  and documentation ratchet anchors follow the new files.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `./Scripts/check_public_documentation_ratchet.sh`
  - `./Scripts/check_public_surface_policies.sh`
  - `swiftly run swift test --filter SwiftTUITests.CollectionSupportTests`
  - `swiftly run swift test --filter SwiftTUITests.OutlineSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/listUsesTagsAndArrowKeys`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/listAndTableRenderEditingChromeDirectlyFromFocus`
- Rollback: restore `CollectionStyles.swift`, delete the split files, and point
  the public documentation ratchet back at the combined file.

### Packet 65: Button Style Chrome Extraction

- Objective: keep public button style declarations in `ButtonStyles.swift` and
  move built-in chrome resolution and concrete style-body views to a focused
  chrome file.
- Owned files:
  - `Sources/SwiftTUIViews/Controls/ButtonStyles.swift`
  - `Sources/SwiftTUIViews/Controls/ButtonStyleChrome.swift`
  - `Scripts/lib/accessibility_color_state_sources.txt`
- Move set:
  - built-in button style kind and chrome-resolution helpers
  - `resolvedLinkButtonChrome`
  - `ButtonPlainStyleBody`, `ButtonLinkStyleBody`, `ButtonChromeStyleBody`,
    and their private background/border helpers
- Invariants: public button style declarations and ratchet paths remain in
  `ButtonStyles.swift`; link button chrome remains package-visible for
  `Link.swift`; focus rail, pressed, disabled, role, and border rendering
  behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.ButtonFocusStabilityTests`
  - `swiftly run swift test --filter SwiftTUITests.ButtonSystemHintTests`
  - `./Scripts/check_accessibility_guardrails.sh`
  - `./Scripts/check_public_documentation_ratchet.sh`
- Rollback: move the chrome helpers and style-body views back to
  `ButtonStyles.swift` and restore the color-state manifest path.

### Packet 66: Adjustable Control Split

- Objective: split `Stepper` and `Slider` into separate control files while
  leaving shared value-update logic in a small support file.
- Owned files:
  - `Sources/SwiftTUIViews/Controls/AdjustableValueControls.swift`
  - `Sources/SwiftTUIViews/Controls/Stepper.swift`
  - `Sources/SwiftTUIViews/Controls/Slider.swift`
  - `Sources/SwiftTUIViews/Controls/AdjustableControlValueSupport.swift`
  - `Scripts/lib/accessibility_color_state_sources.txt`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
- Move set:
  - `Stepper` and its private value storage and body helpers
  - `Slider` and its private value storage and body helpers
  - shared `updateBoundControlValue`
- Invariants: public `Stepper`/`Slider` initializers, key/pointer handling,
  value clamping, fractional slider pointer math, raw glyph review, and
  accessibility roles remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIViews`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/stepperDispatchesAndClamps`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sliderHandlesArrowKeysAndRendersTrack`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/doubleAdjustableControlsRenderCleanFractionalValues`
  - `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sliderTrackUsesFractionalPointerLocations`
  - `./Scripts/check_accessibility_guardrails.sh`
- Batch gate for Packets 62-66:
  - `bun run test`
- Rollback: restore `AdjustableValueControls.swift`, delete the split
  Stepper/Slider/support files, and restore accessibility manifest paths.

### Packet 67: Measurement Work Stack Decomposition

- Objective: split iterative measurement stack orchestration into named support
  files so the driver reads as the measurement control flow rather than a mix of
  scheduling, result-stack, and node-building details.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkStack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkItems.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementResultStack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+MeasuredNodeBuilding.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackMeasurementScheduling.swift`
- Move set:
  - measurement work-item enum and request payloads
  - result-stack pop/build helpers
  - measured-node construction helpers
  - stack child scheduling and stack measurement reconciliation
- Invariants: measurement order, cache reuse, stack sizing, stack-safety
  behavior, and public layout behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
- Rollback: move the extracted declarations back into
  `LayoutEngine+MeasurementWorkStack.swift` and delete the measurement support
  files.

### Packet 68: Placement Work Stack Decomposition

- Objective: split iterative placement stack orchestration into named support
  files so the driver owns traversal while request/result details live beside
  the placement phase.
- Owned files:
  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkStack.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkItems.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementResultStack.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+PlacementRequests.swift`
  - `Sources/SwiftTUICore/Place/LayoutEngine+StackPlacementRequests.swift`
- Move set:
  - placement work-item enum and result-stack helpers
  - child placement request construction
  - stack placement request reconciliation
  - retained/custom placement short-circuit support
- Invariants: placement order, retained-placement reuse, stack placement,
  custom-layout placement, and stack-safety behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
- Rollback: move the extracted declarations back into
  `LayoutEngine+PlacementWorkStack.swift` and delete the placement support
  files.

### Packet 69: ViewNode Debug And Committed Accessor Split

- Objective: remove debug snapshot formatting and committed-field forwarding
  accessors from the central `ViewNode` file while keeping mutable node state
  private.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewNode.swift`
  - `Sources/SwiftTUICore/Resolve/ViewNodeHandlerDebugSnapshots.swift`
  - `Sources/SwiftTUICore/Resolve/ViewNodeCommittedAccessors.swift`
- Move set:
  - `NodeHandlers` debug snapshot formatting and sorting helpers
  - `ViewNode` committed-field forwarding accessors
- Invariants: debug snapshot output, committed-node read behavior, `ViewNode`
  state privacy, and graph checkpoint behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
- Rollback: move debug helpers and committed accessors back into
  `ViewNode.swift` and delete the helper files.

### Packet 70: Layout Border Raster Extraction

- Objective: separate layout-border rasterization from shape stroke and rule
  border drawing, keeping each border path readable in its own file.
- Owned files:
  - `Sources/SwiftTUICore/Raster/Rasterizer+Borders.swift`
  - `Sources/SwiftTUICore/Raster/Rasterizer+LayoutBorders.swift`
- Move set:
  - layout border perimeter/color/index helpers
  - layout border side color resolution
  - layout border edge and corner glyph writers
- Invariants: regular border drawing, gradient border drawing, layout border
  corner behavior, raw glyph output, and raster damage behavior remain
  unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUITests.BorderRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.BorderGradientTests`
- Rollback: move layout-border helpers back into
  `Rasterizer+Borders.swift` and delete `Rasterizer+LayoutBorders.swift`.

### Packet 71: LineChart Support Decomposition

- Objective: split line chart domain, rasterization, tick calculation, and
  series composition helpers out of the chart view-support file.
- Owned files:
  - `Sources/SwiftTUICharts/LineChartSupport.swift`
  - `Sources/SwiftTUICharts/LineChartDomainSupport.swift`
  - `Sources/SwiftTUICharts/LineChartRasterization.swift`
  - `Sources/SwiftTUICharts/LineChartAxisTickSupport.swift`
  - `Sources/SwiftTUICharts/LineChartSeriesComposition.swift`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
- Move set:
  - domain range and value formatting helpers
  - line rasterization helpers
  - axis tick calculation helpers
  - multi-series composition helpers
- Invariants: public chart APIs, domain calculation, rendered line glyphs,
  axis labels, series composition, raw-glyph guardrails, and legend behavior
  remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICharts`
  - `swiftly run swift test --filter SwiftTUITests.LineChartDomainTests`
  - `swiftly run swift test --filter LineChart`
  - `./Scripts/check_accessibility_guardrails.sh`
- Batch gate for Packets 67-71:
  - `bun run test`
- Rollback: move the extracted chart helpers back into
  `LineChartSupport.swift`, delete the chart support files, and restore the
  raw-glyph manifest path.

### Packet 72: Semantic Payload Routing Split

- Objective: move semantic payload routing and clipping helpers out of the
  semantic extractor driver so the traversal reads as extraction control flow.
- Owned files:
  - `Sources/SwiftTUICore/Semantics/Semantics.swift`
  - `Sources/SwiftTUICore/Semantics/SemanticPayloadRouting.swift`
- Move set:
  - payload semantic emission helpers for list, table, rich text, and scroll
    indicator metadata
  - payload clipping and union helpers
- Invariants: semantic snapshot contents, focus regions, interaction regions,
  scroll routes, and accessibility extraction remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.ScrollIndicatorDraggingTests`
- Rollback: move payload routing helpers back into `Semantics.swift` and delete
  `SemanticPayloadRouting.swift`.

### Packet 73: Pointer Hit-Testing And Hover Split

- Objective: separate pointer hit-testing, focus routing, and hover state from
  mouse event dispatch in the run loop.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHandling.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHitTesting.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHover.swift`
- Move set:
  - hit target lookup, interaction-region lookup, scroll target lookup, focus
    identity lookup, and pointer capture assertions
  - hover route resolution, hover state transitions, armed pointer state, and
    pressed identity updates
- Invariants: click focus behavior, drag capture, scroll target selection,
  hover delivery, and pointer invalidation behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests`
  - `swiftly run swift test --filter SwiftTUITests.PointerHoverTests`
  - `swiftly run swift test --filter SwiftTUITests.ScrollIndicatorDraggingTests`
- Rollback: move hit-testing and hover helpers back into
  `RunLoop+PointerHandling.swift` and delete the two split files.

### Packet 74: RunLoop Session Types Split

- Objective: move top-level run-loop input/session/support types out of the
  primary `RunLoop.swift` implementation.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoopSessionTypes.swift`
- Move set:
  - builder aliases, key-handler result types, run-loop result and exit reason
    types
  - signal reader protocol/default implementation and render-suspension
    diagnostics
- Invariants: public run-loop initializer contracts, signal reading, key
  handling, render-suspension diagnostics, and exit result semantics remain
  unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminationRequestTests`
- Rollback: inline the session/support types back into `RunLoop.swift` and
  delete `RunLoopSessionTypes.swift`.

### Packet 75: Snapshot Style Description Split

- Objective: separate snapshot style/shape formatting helpers from the snapshot
  renderer's tree traversal and frame formatting logic.
- Owned files:
  - `Sources/SwiftTUICore/Pipeline/Snapshots.swift`
  - `Sources/SwiftTUICore/Pipeline/SnapshotRenderer+StyleDescriptions.swift`
- Move set:
  - text-style, resolved-style, shape-style, gradient, tile, chrome, shape,
    stroke, and border-background description helpers
- Invariants: snapshot strings, scheduled-frame diagnostics, cache diagnostics,
  and pipeline contract snapshots remain unchanged. Helper visibility should
  stay as narrow as cross-file snapshot entry points allow.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- Rollback: move the style/shape description helpers back into
  `Snapshots.swift` and delete `SnapshotRenderer+StyleDescriptions.swift`.

### Packet 76: Image Asset Model Split

- Objective: separate decoded-image and pixel model contracts from image asset
  lookup, loading, and decoding implementation.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/ImageAssetRepository.swift`
  - `Sources/SwiftTUIRuntime/Terminal/ImageAssetModels.swift`
- Move set:
  - `RGBAImagePixel`
  - `ImageEncodedFormat`
  - `DecodedImage`
- Invariants: PNG/JPEG decode behavior, image repository caching, Kitty/Sixel
  renderer behavior, and WASI/web image payload semantics remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
- Batch gate for Packets 72-76:
  - `bun run test`
- Rollback: move image model types back into `ImageAssetRepository.swift` and
  delete `ImageAssetModels.swift`.

### Packet 77: Canvas Pixel Grid Drawing Split

- Objective: move dense pixel-grid canvas drawing out of the core canvas
  protocol/context file.
- Owned files:
  - `Sources/SwiftTUICore/Draw/CanvasDrawing.swift`
  - `Sources/SwiftTUICore/Draw/CanvasPixelGridDrawing.swift`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
- Move set:
  - `CanvasPixelGridMode`
  - `CanvasPixelGridDrawing` and full-cell/half-block drawing helpers
- Invariants: full-cell rendering, vertical half-block packing, raw-glyph
  review, and canvas draw output remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUITests.CanvasViewTests`
  - `./Scripts/check_accessibility_guardrails.sh`
- Rollback: move pixel-grid declarations back into `CanvasDrawing.swift`,
  delete `CanvasPixelGridDrawing.swift`, and restore the raw-glyph manifest.

### Packet 78: Canvas Payload Split

- Objective: keep type-erased canvas draw-tree payload and equality plumbing
  separate from the public drawing protocol and mutable drawing context.
- Owned files:
  - `Sources/SwiftTUICore/Draw/CanvasDrawing.swift`
  - `Sources/SwiftTUICore/Draw/CanvasPayload.swift`
- Move set:
  - `CanvasPayload`
  - type-erased `CanvasDrawing` equality helper
- Invariants: canvas payload equality, draw-tree payload identity, and canvas
  rendering behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUITests.CanvasViewTests`
- Rollback: move payload declarations back into `CanvasDrawing.swift` and delete
  `CanvasPayload.swift`.

### Packet 79: Frame Diagnostic Record Split

- Objective: move the diagnostics record schema out of the file logger so the
  logger file is focused on TSV writing and formatting.
- Owned files:
  - `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsLogger.swift`
  - `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticRecord.swift`
- Move set:
  - `FrameDiagnosticRecord`
- Invariants: logged columns, runtime diagnostics records, async frame-tail
  diagnostics, and public logger API remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
- Rollback: move `FrameDiagnosticRecord` back into
  `FrameDiagnosticsLogger.swift` and delete `FrameDiagnosticRecord.swift`.

### Packet 80: Gradient Style Family Split

- Objective: move gradient style model declarations out of the broader styling
  file.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Sources/SwiftTUICore/Styling/GradientStyles.swift`
- Move set:
  - `Gradient`
  - `LinearGradient`
  - `RadialGradient`
- Invariants: public gradient APIs, animatable data, shape-style erasure,
  opacity, and gradient rasterization behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter gradient`
  - `swiftly run swift test --filter RadialGradient`
- Rollback: move gradient declarations back into `Styling.swift` and delete
  `GradientStyles.swift`.

### Packet 81: RunLoop Runtime Support Split

- Objective: move run-loop registration aggregation and session support helpers
  out of the primary session driver.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeSupport.swift`
- Move set:
  - `runtimeRegistrations`
  - runtime issue reporting helpers
  - next-wake scheduling helper
  - termination-disposition mapping
  - focus-presentation handoff helper
- Invariants: runtime registration restoration, issue reporting de-duplication,
  scheduler wake behavior, termination request dispatch, focus presentation, and
  run-loop result behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.TerminationRequestTests`
  - `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- Batch gate for Packets 77-81:
  - `bun run test`
- Rollback: move support helpers back into `RunLoop.swift` and delete
  `RunLoop+RuntimeSupport.swift`.

### Packet 82: Stack Axis Support Split

- Objective: keep stack axis conversion helpers out of the stack allocation and
  minimum-size algorithms.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackAxisSupport.swift`
- Move set:
  - stack proposal construction
  - main/cross dimension accessors for proposals, sizes, and points
  - main-dimension mutation and spacer detection helpers
- Invariants: stack measurement proposals, axis conversions, spacer detection,
  and retained layout behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
- Rollback: move axis helpers back into `LayoutEngine+Stack.swift` and delete
  `LayoutEngine+StackAxisSupport.swift`.

### Packet 83: Stack Lazy Allocation Split

- Objective: isolate lazy-stack child sourcing, allocation snapshots, and
  visible-range lookup from the eager stack sizing helpers.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackLazyAllocation.swift`
- Move set:
  - indexed-child source resolution
  - lazy stack allocation snapshot construction
  - binary-search visible child range lookup
- Invariants: lazy stack overscan, viewport range selection, allocation
  snapshots, and indexed child ordering remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
- Rollback: move lazy allocation helpers back into `LayoutEngine+Stack.swift`
  and delete `LayoutEngine+StackLazyAllocation.swift`.

### Packet 84: Stack Metrics Split

- Objective: put stack spacing and cross-axis alignment metrics in one focused
  helper file.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackMetrics.swift`
- Move set:
  - resolved stack spacing calculation
  - preferred sibling spacing distance
  - cross-axis alignment metric aggregation
- Invariants: default horizontal and vertical spacing, alignment-guide usage,
  and measured cross-axis extents remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
- Rollback: move metric helpers back into `LayoutEngine+Stack.swift` and delete
  `LayoutEngine+StackMetrics.swift`.

### Packet 85: Stack Space Allocation Split

- Objective: isolate stack surplus distribution and compression mechanics from
  minimum-size derivation.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackSpaceAllocation.swift`
- Move set:
  - extra main-axis space distribution to spacers and flexible subtrees
  - priority-aware child compression
  - even remainder distribution helper
- Invariants: layout-priority compression order, spacer growth, flexible child
  growth, and stack overflow behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
- Rollback: move allocation helpers back into `LayoutEngine+Stack.swift` and
  delete `LayoutEngine+StackSpaceAllocation.swift`.

### Packet 86: Stack Minimums Split

- Objective: move derived stack minimum-size and flexible-subtree detection into
  a dedicated file.
- Owned files:
  - `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
  - `Sources/SwiftTUICore/Measure/LayoutEngine+StackMinimums.swift`
- Move set:
  - minimum main-size derivation
  - fixed-size and explicit minimum dimension helpers
  - subtree flexibility detection
  - cross-axis remeasurement no-op detection
- Invariants: stack minimum-size results, custom-layout minimum fallback,
  flexible frame handling, divider/shape/canvas flexibility, and retained layout
  cache behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUICore`
  - `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
- Batch gate for Packets 82-86:
  - `bun run test`
- Rollback: move minimum-size helpers back into `LayoutEngine+Stack.swift` and
  delete `LayoutEngine+StackMinimums.swift`. Restore the placeholder
  `LayoutEngine+Stack.swift` only if SwiftPM or reviewers need it.

### Packet 87: Frame Diagnostics TSV Formatting Split

- Objective: keep the frame diagnostics logger focused on file lifecycle and
  row emission by moving TSV schema and field formatting into a helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsLogger.swift`
  - `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsTSVFormatting.swift`
- Move set:
  - header field list
  - diagnostic record field formatting
  - runtime issue, drop blocker, generation, and duration formatting helpers
- Invariants: TSV column order, nil placeholders, diagnostic field values, and
  logger public behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
- Rollback: move TSV formatting helpers back into
  `FrameDiagnosticsLogger.swift` and delete
  `FrameDiagnosticsTSVFormatting.swift`.

### Packet 88: Terminal Style JSON Transport Split

- Objective: keep the terminal render-style codec focused on style mapping by
  moving the small JSON parser/writer support into transport-specific code.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalStyleTransportJSON.swift`
- Move set:
  - transport JSON value enum
  - JSON parser
  - JSON escaping and object serialization helpers
- Invariants: Web runner style payload JSON, nil style decoding, color decoding,
  and control-message style dispatch remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
- Rollback: move JSON transport helpers back into
  `TerminalRenderStyleCodec.swift` and delete
  `TerminalStyleTransportJSON.swift`.

### Packet 89: Terminal Style Base64 Transport Split

- Objective: isolate terminal style transport Base64 encoding/decoding from the
  style codec.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalStyleTransportBase64.swift`
- Move set:
  - Base64 encoder
  - Base64 decoder
  - scalar-to-value lookup helper
- Invariants: style transport payload bytes, invalid Base64 rejection, padding
  handling, and codec round-trips remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests`
  - `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
- Rollback: move Base64 transport helpers back into
  `TerminalRenderStyleCodec.swift` and delete
  `TerminalStyleTransportBase64.swift`.

### Packet 90: Frame Tail Models Split

- Objective: reduce `FrameTailRenderer.swift` to orchestration and phase work by
  moving frame-tail state and typed data products into a dedicated model file.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailModels.swift`
- Move set:
  - retained frame-tail state and retained input
  - frame-tail input, diagnostics, layout, semantics, draw, raster, and output
    models
  - worker result, generation sequencer, and render-suspension hook types
- Invariants: retained baseline placement, previous raster damage input,
  async/sync tail parity, worker timing fields, cancellation diagnostics, and
  test hook behavior remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
- Rollback: move model declarations back into `FrameTailRenderer.swift` and
  delete `FrameTailModels.swift`.

### Packet 91: Terminal POSIX Controller Split

- Objective: keep `TerminalHost.swift` focused on terminal lifecycle by moving
  POSIX descriptor control into a terminal controller file.
- Owned files:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPOSIXController.swift`
- Move set:
  - terminal controller protocol
  - default POSIX controller implementation
  - file status, read, write, poll, and cell-pixel-size support
- Invariants: raw-mode attribute reads/writes, window-size reads,
  nonblocking flag management, partial-write retry behavior, read timeout
  behavior, cell pixel metrics, and process cleanup remain unchanged.
- Required checks:
  - `swiftly run swift build --target SwiftTUIRuntime`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
- Batch gate for Packets 87-91:
  - `bun run test`
- Rollback: move the controller protocol and POSIX implementation back into
  `TerminalHost.swift` and delete `TerminalPOSIXController.swift`.

### Packet 92: Shape Style Family Split

- Objective: keep authored shape-style erasure and semantic style roles in a
  dedicated styling file after the larger styling source was decomposed.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Sources/SwiftTUICore/Styling/ShapeStyles.swift`
- Move set:
  - `SemanticStyleRole`
  - `ShapeStyle`
  - `SemanticShapeStyle`
  - `AnyShapeStyle`
  - `Color: ShapeStyle` and opacity erasure support
- Invariants: shape-style public API, opacity erasure, semantic style
  resolution, and public API inventory remain unchanged.
- Rollback: move shape-style declarations back into `Styling.swift` and delete
  `ShapeStyles.swift`.

### Packet 93: Theme And Terminal Style Split

- Objective: isolate theme and terminal render-style state from general styling
  payload declarations.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Sources/SwiftTUICore/Styling/Theme.swift`
- Move set:
  - `Theme`
  - `TerminalRenderStyle`
  - style environment snapshot and heavy-field storage
- Invariants: terminal style codec payloads, theme override behavior, and
  appearance-derived colors remain unchanged.
- Rollback: move declarations back into `Styling.swift` and delete
  `Theme.swift`.

### Packet 94: Stroke And Shape Payload Split

- Objective: split border/stroke declarations and shape draw payload models into
  files named for their responsibilities.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Sources/SwiftTUICore/Styling/StrokeStyles.swift`
  - `Sources/SwiftTUICore/Styling/ShapePayload.swift`
- Move set:
  - `StrokeStyle`, `BorderBackgroundStyle`, and `BorderSide`
  - `ShapeFillMode`, `ShapeGeometry`, `ShapeOperation`, and `ShapePayload`
- Invariants: border defaults, shape payload equality, raster shape behavior,
  and snapshot style descriptions remain unchanged.
- Rollback: move declarations back into `Styling.swift` and delete
  `StrokeStyles.swift` and `ShapePayload.swift`.

### Packet 95: Resolved Text Style Split

- Objective: move resolved text style and color resolution helpers out of the
  broad styling source.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Sources/SwiftTUICore/Styling/ResolvedTextStyle.swift`
- Move set:
  - `TextLineStyle`
  - `ResolvedTextStyle`
  - style color resolution helpers and error type
- Invariants: resolved raster style output, terminal cell text rendering, and
  text-decoration behavior remain unchanged.
- Rollback: move declarations back into `Styling.swift` and delete
  `ResolvedTextStyle.swift`.

### Packet 96: Styling Policy Path Update

- Objective: remove the empty `Styling.swift` source after its declarations
  were distributed to focused files and update policy references.
- Owned files:
  - `Sources/SwiftTUICore/Styling/Styling.swift`
  - `Scripts/lib/public_documentation_ratchet.txt`
  - `Scripts/check_public_surface_policies.sh`
- Move set:
  - public-documentation ratchet path for `ShapeStyle` and `AnyShapeStyle`
  - public-surface policy path for `ShapeStyle`
- Invariants: public symbol count, public API baseline, DocC policy, and
  package discovery remain unchanged.
- Batch gate for Packets 92-96:
  - `bun run test`
- Rollback: restore `Styling.swift`, move declarations back, and restore policy
  references to the old path.

### Packet 97: Draw Payload Split

- Objective: keep the draw-payload enum and its custom equality isolated from
  unrelated text, metadata, and list models.
- Owned files:
  - `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
  - `Sources/SwiftTUICore/Draw/DrawPayload.swift`
- Move set:
  - `DrawPayload`
  - custom equality for foreign-surface payloads
- Invariants: draw payload cases, equality behavior, and snapshot descriptions
  remain unchanged.
- Rollback: move the enum back into `RenderMetadataTypes.swift` and delete
  `DrawPayload.swift`.

### Packet 98: Text Style Metadata Split

- Objective: separate authored text-style metadata from draw metadata and list
  payload models.
- Owned files:
  - `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
  - `Sources/SwiftTUICore/Draw/TextStyle.swift`
- Move set:
  - `TextTruncationMode`
  - `TextWrappingStrategy`
  - `TextStyle`
  - `BaseStyle`
- Invariants: text emphasis/debug names, opacity merging, text layout, and
  raster style resolution remain unchanged.
- Rollback: move declarations back into `RenderMetadataTypes.swift` and delete
  `TextStyle.swift`.

### Packet 99: Draw Metadata Split

- Objective: isolate resolved draw metadata and list-style metadata propagation
  from payload declarations.
- Owned files:
  - `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
  - `Sources/SwiftTUICore/Draw/DrawMetadata.swift`
- Move set:
  - `DrawMetadata`
  - nested list-style metadata
  - heavy-field storage and merge helpers
- Invariants: metadata merging, clipping flags, scroll-indicator metadata, and
  draw-only style reuse remain unchanged.
- Rollback: move declarations back into `RenderMetadataTypes.swift` and delete
  `DrawMetadata.swift`.

### Packet 100: Selection Tag Split

- Objective: move type-erased selection identity storage into a focused draw
  support file.
- Owned files:
  - `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
  - `Sources/SwiftTUICore/Draw/SelectionTag.swift`
- Move set:
  - selection tag value-box protocol
  - typed value box
  - `SelectionTag`
- Invariants: exact and optional selection matching, picker/list/table tag
  behavior, and equality semantics remain unchanged.
- Rollback: move declarations back into `RenderMetadataTypes.swift` and delete
  `SelectionTag.swift`.

### Packet 101: List Payload Split

- Objective: move list-specific draw payload models into a file named for list
  drawing support.
- Owned files:
  - `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
  - `Sources/SwiftTUICore/Draw/ListPayload.swift`
  - `Scripts/lib/accessibility_color_state_sources.txt`
- Move set:
  - `ListSeparatorPreferences`
  - `ListItemPayload`
  - `ListPayload`
  - color-state manifest path update
- Invariants: list row/section separator visibility, selected row styling,
  viewport markers, table/list payload compatibility, and accessibility
  guardrail coverage remain unchanged.
- Batch gate for Packets 97-101:
  - `bun run test`
- Rollback: move declarations back into `RenderMetadataTypes.swift`, delete the
  split files, and restore the accessibility manifest path.

### Packet 102: Scene Builder Artifact Split

- Objective: keep `App.swift` focused on public app/window declarations by
  moving scene-builder artifacts into a scene-builder file.
- Owned files:
  - `Sources/SwiftTUIRuntime/Scenes/App.swift`
  - `Sources/SwiftTUIRuntime/Scenes/SceneBuilder.swift`
- Move set:
  - `EmptyScene`, `TupleScene`, `ConditionalScene`, and `VariadicScene`
  - `AnyScene`
  - `SceneBuilder`
- Invariants: scene builder branch/order behavior, AnyScene traversal, and
  public API inventory remain unchanged.
- Rollback: move declarations back into `App.swift` and delete
  `SceneBuilder.swift`.

### Packet 103: Window Scene Configuration Split

- Objective: move scene configuration and host-root layout support out of
  `App.swift`.
- Owned files:
  - `Sources/SwiftTUIRuntime/Scenes/App.swift`
  - `Sources/SwiftTUIRuntime/Scenes/WindowSceneConfiguration.swift`
- Move set:
  - `WindowSceneConfiguration`
  - `WindowHostLayout`
  - `WindowHostView`
- Invariants: root identity, exit-key binding configuration, full-canvas
  window layout, clipping, and focus-scope behavior remain unchanged.
- Rollback: move declarations back into `App.swift` and delete
  `WindowSceneConfiguration.swift`.

### Packet 104: Window Scene Selection Split

- Objective: isolate selected-window collection and runner closure plumbing
  from public app declarations.
- Owned files:
  - `Sources/SwiftTUIRuntime/Scenes/App.swift`
  - `Sources/SwiftTUIRuntime/Scenes/WindowSceneSelection.swift`
- Move set:
  - `collectWindowSceneDescriptors`
  - `SelectedWindowScene`
  - `collectWindowSceneSelections`
  - selected-window visitor
- Invariants: scene manifest ordering, default scene selection, hosted scene
  lookup, and runner handoff remain unchanged.
- Rollback: move declarations back into `App.swift` and delete
  `WindowSceneSelection.swift`.

### Packet 105: Hosted Raster Surface State Split

- Objective: move hosted-surface state and waiter models out of the surface
  orchestration class.
- Owned files:
  - `Sources/SwiftTUIRuntime/Scenes/HostedRasterSurface.swift`
  - `Sources/SwiftTUIRuntime/Scenes/HostedRasterSurfaceState.swift`
- Move set:
  - hosted frame waiter models
  - hosted surface state storage
- Invariants: frame sequence assignment, frame history limit, waiter resumption,
  damage metrics, and clipboard behavior remain unchanged.
- Rollback: move state and waiter models back into `HostedRasterSurface.swift`
  and delete `HostedRasterSurfaceState.swift`.

### Packet 106: Accessibility Text Sanitizer Split

- Objective: keep linear accessibility rendering focused on tree traversal and
  line assembly by extracting ASCII sanitization.
- Owned files:
  - `Sources/SwiftTUIRuntime/Accessibility/LinearAccessibilityRenderer.swift`
  - `Sources/SwiftTUIRuntime/Accessibility/AccessibilityTextSanitizer.swift`
- Move set:
  - control-scalar normalization
  - non-ASCII replacement
  - ASCII-space trimming and collapsing
- Invariants: accessible runtime output, warning text, role/label/hint
  sanitization, and JSON frame rendering remain unchanged.
- Batch gate for Packets 102-106:
  - `bun run test`
- Rollback: move sanitizer helpers back into `LinearAccessibilityRenderer.swift`
  and delete `AccessibilityTextSanitizer.swift`.

### Packet 107: Completed-Frame Candidate Coordination Split

- Objective: keep `DefaultRenderer`'s public render entry file focused by
  moving completed-frame candidate preview, drop, and commit coordination into a
  renderer extension named for that responsibility.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/DefaultRenderer+CompletedFrameCandidates.swift`
  - `Tests/SwiftTUITests/RenderPipelineStructureTests.swift`
- Move set:
  - `CompletedFrameCandidateResolution`
  - `CommittedFrameEffects`
  - `CompletedFrameCandidateCommitPlanComparison`
  - completed-frame candidate construction, resolution, commit, preview, and
    discard helpers
  - source-structure test lookup for the moved helper body
- Invariants: completed-frame preview side-effect isolation, drop
  classification, ordered commit effects, diagnostics timing, retained baseline
  placement, and public API inventory remain unchanged.
- Rollback: move declarations and helpers back into `SwiftTUI.swift`, delete
  `DefaultRenderer+CompletedFrameCandidates.swift`, and restore the structure
  test source path.

### Packet 108: Run-Loop Render Driver Support Split

- Objective: make the sync/async render-driver bodies easier to scan by moving
  support types and shared small helpers out of `RunLoop+Rendering.swift`.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RenderDriverSupport.swift`
- Move set:
  - `RenderIntentCoalescingDiagnostics`
  - `AnimationWakeTiming`
  - `FrameAcquisitionState`
  - render-intent diagnostics construction
  - external-state frame reconciliation
  - lifecycle carry-forward merge
  - gesture-deadline drain helper
- Invariants: render intent generation, coalesced wake diagnostics, deadline
  wake behavior, focus-sync lifecycle carry-forward, animation deadline lead
  time, and sync/async render-driver parity remain unchanged.
- Rollback: move support declarations and helpers back into
  `RunLoop+Rendering.swift` and delete `RunLoop+RenderDriverSupport.swift`.

### Packet 109: Animation Placed-Tree Capture Split

- Objective: give matched-geometry placed-tree capture a named helper while
  keeping the animation controller as the owner of mutable animation state.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationPlacedTreeCapture.swift`
- Move set:
  - placed-tree capture payload
  - matched-geometry bounds and identity collection wrapper
- Invariants: previous placed-root storage, matched-geometry key capture,
  insertion/removal overlay sampling, and animation controller counters remain
  unchanged.
- Rollback: inline the capture helper back into `AnimationController` and delete
  `AnimationPlacedTreeCapture.swift`.

### Packet 110: ViewGraph Debug Snapshot Split

- Objective: separate ViewGraph debug snapshot declarations from the mutable
  graph implementation while keeping the source-level checkpoint totality guard.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphDebugSnapshots.swift`
  - `Tests/SwiftTUICoreTests/Graph/ViewGraphCheckpointTotalityTests.swift`
- Move set:
  - `ViewGraph.ObjectDependencySnapshot`
  - `ViewGraph.DebugTotalStateSnapshot`
  - debug object-dependency snapshot formatting helper
  - source path used by the checkpoint totality parser
- Invariants: checkpoint/debug totality, graph-state round trip, dependency
  snapshot sorting, and runtime subsystem debug snapshots remain unchanged.
- Rollback: move declarations and helper back into `ViewGraph.swift`, delete
  `ViewGraphDebugSnapshots.swift`, and restore the test source path.

### Packet 111: Frame-Tail Worker Executor Split

- Objective: isolate frame-tail worker queueing, timing, and cancellation-start
  checks from the renderer's layout/raster product construction.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailWorkerExecutor.swift`
- Move set:
  - renderer queue sync wrapper
  - timed sync/async worker wrappers
  - timed layout-worker wrapper with `FrameTailJobCancellationToken`
  - cancellation-test layout worker entrypoint
- Invariants: retained state serialization, layout offload cancellation, worker
  timing diagnostics, WASI immediate fallback behavior, and raster handoff
  remain unchanged.
- Batch gate for Packets 107-111:
  - `bun run test`
- Rollback: move executor helpers back into `FrameTailRenderer.swift` and delete
  `FrameTailWorkerExecutor.swift`.

### Packet 112: DefaultRenderer Runtime Subsystems Split

- Objective: move renderer subsystem/debug support types out of `SwiftTUI.swift`
  while keeping live renderer state owned by `DefaultRenderer`.
- Owned files:
  - `Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - `Sources/SwiftTUIRuntime/Rendering/DefaultRendererRuntimeSubsystems.swift`
- Move set:
  - portal-hosted content-root extraction helper
  - committed presentation dismiss-stack storage helper
  - debug observation bridge tracker
  - `RuntimeSubsystemSnapshot`
- Invariants: presentation portal content-root identity, Escape dismiss-stack
  storage, observation bridge debug snapshots, runtime subsystem snapshots, and
  public API inventory remain unchanged.
- Rollback: move declarations back into `SwiftTUI.swift` and delete
  `DefaultRendererRuntimeSubsystems.swift`.

### Packet 113: Run-Loop Resolve Context Split

- Objective: keep render-driver loops focused on frame acquisition/commit by
  moving resolve-context and proposal assembly into a dedicated run-loop file.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+ResolveContext.swift`
- Move set:
  - reset-focus action factory
  - `ResolveContext` environment and registry assembly
  - proposal derivation from presentation-surface size
- Invariants: runtime environment values, motion policy, clipboard/open-link
  placeholders, focused values, terminal size/capability propagation,
  invalidation proxy, and deadline scheduling remain unchanged.
- Rollback: move helpers back into `RunLoop+Rendering.swift` and delete
  `RunLoop+ResolveContext.swift`.

### Packet 114: Frame Acquisition Outcome Split

- Objective: isolate skipped-frame acquisition reporting and drop-blocker
  support from the frame acquisition strategy body.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisitionOutcome.swift`
- Move set:
  - `FrameAcquisitionOutcome`
  - cancelled-before-start and dropped-completed reporting
  - cancelled-frame intent replay helper
  - completed-frame additional drop blockers
  - skipped-frame progress probe helper
- Invariants: cancelled-intent replay, skipped-frame diagnostics,
  lifecycle carry-forward, animation/focus/scroll drop blockers, progress
  events, and async-no-cancel/async-no-drop behavior remain unchanged.
- Rollback: move declarations and helpers back into
  `RunLoop+FrameAcquisition.swift` and delete
  `RunLoop+FrameAcquisitionOutcome.swift`.

### Packet 115: Animation Controller Snapshot Type Split

- Objective: separate animation checkpoint/debug snapshot type declarations
  from the controller's mutation-heavy implementation without widening mutable
  controller fields.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationControllerStateSnapshots.swift`
- Move set:
  - `AnimationController.Checkpoint`
  - `AnimationController.DebugStateSnapshot`
- Invariants: frame-head transaction checkpoint/restore behavior, debug state
  equality, active animation bookkeeping, batch completion deferral, and removal
  overlay state remain unchanged.
- Rollback: move snapshot type declarations back into
  `AnimationController.swift` and delete `AnimationControllerStateSnapshots.swift`.

### Packet 116: ViewGraph Node Checkpointing Split

- Objective: keep the full ViewGraph checkpoint methods in the graph owner while
  moving repeated node checkpoint map construction/restoration into a helper.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphCheckpointing.swift`
- Move set:
  - node checkpoint map construction
  - node checkpoint restoration loop
- Invariants: ViewGraph checkpoint totality, node checkpoint round trip,
  registration alias restoration, command/drop registration restoration, and
  graph debug snapshots remain unchanged.
- Batch gate for Packets 112-116:
  - `bun run test`
- Rollback: inline the helper calls back into `ViewGraph.swift` and delete
  `ViewGraphCheckpointing.swift`.

### Packet 117: Run-Loop Post-Commit Support Split

- Objective: keep the shared acquired-frame body focused on orchestration by
  moving post-commit presentation timing, damage choice, post-action
  invalidation flushing, and animation wake scheduling into named helpers.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PostCommitSupport.swift`
- Move set:
  - focus-sync presentation damage choice
  - presentation metrics plus diagnostics timing wrapper
  - post-action invalidation flush
  - next animation deadline scheduling
- Invariants: focus-sync full-repaint behavior, presentation timing
  diagnostics, lifecycle commit ordering, post-action invalidation behavior,
  and repeat-animation wake scheduling remain unchanged.
- Rollback: inline helpers back into `RunLoop+Rendering.swift` and delete
  `RunLoop+PostCommitSupport.swift`.

### Packet 118: Frame Diagnostic Record Assembly Split

- Objective: make diagnostics logging call sites readable by moving committed
  and zero-artifact `FrameDiagnosticRecord` construction into a dedicated
  assembly file.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnostics.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnosticRecordAssembly.swift`
- Move set:
  - committed-frame diagnostic record construction
  - zero-artifact diagnostic record construction
  - wake-cause and animation-request formatting helpers
  - frame-drop blocker formatting/classification helpers
- Invariants: TSV field order, sentinel values, render-suspension input counts,
  drop-blocker classifications, timing totals, and public API inventory remain
  unchanged.
- Rollback: move record assembly helpers back into
  `RunLoop+FrameDiagnostics.swift` and delete
  `RunLoop+FrameDiagnosticRecordAssembly.swift`.

### Packet 119: Animation Resolved-Tree Diffing Support Split

- Objective: extract low-risk resolved-tree diff planning without moving the
  behavior-heavy removal overlay loop.
- Owned files:
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
  - `Sources/SwiftTUIRuntime/Lifecycle/AnimationResolvedTreeDiffing.swift`
- Move set:
  - identity diff set construction
  - matched-geometry animation planning and consumed-key collection
- Invariants: insertion/removal identity sets, matched-geometry same-identity
  suppression, no-animation snap behavior, batch ref-counting, and active
  animation replacement remain unchanged.
- Rollback: inline the diff planning helpers back into
  `AnimationController.swift` and delete `AnimationResolvedTreeDiffing.swift`.

### Packet 120: ViewGraph Invalidation Planning Split

- Objective: consolidate invalidation and dirty-queue planning while keeping
  live graph storage owned by `ViewGraph`.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphInvalidationPlanning.swift`
- Move set:
  - plain invalidation and mark-dirty loop
  - graph-local dirty queueing
  - state-change dirty identity calculation
  - observation-change dirty identity calculation
  - environment-reader dirty identity calculation
- Invariants: dependency index lookups, root fallback when no environment
  readers are found, graph-local dirty frontier eligibility, and checkpoint
  totality remain unchanged.
- Rollback: inline helpers back into `ViewGraph.swift` and delete
  `ViewGraphInvalidationPlanning.swift`.

### Packet 121: Snapshot Renderer Diagnostics Split

- Objective: separate frame/scheduled diagnostics fixture formatting from tree
  and payload snapshot rendering.
- Owned files:
  - `Sources/SwiftTUICore/Pipeline/Snapshots.swift`
  - `Sources/SwiftTUICore/Pipeline/SnapshotRenderer+Diagnostics.swift`
- Move set:
  - `SnapshotRenderer.frameDiagnostics(_:)`
  - `SnapshotRenderer.scheduledFrame(_:)`
  - diagnostics-only identity, duration, generation, and deadline descriptions
- Invariants: public `SnapshotRenderer` API, diagnostics snapshot text,
  scheduled-frame formatting, architecture-layer fixture output, and public API
  inventory remain unchanged.
- Batch gate for Packets 117-121:
  - `bun run test`
- Rollback: move diagnostics formatting back into `Snapshots.swift` and delete
  `SnapshotRenderer+Diagnostics.swift`.

### Packet 122: Frame-Tail Inline Stage Renderer Split

- Objective: keep `FrameTailRenderer` focused on worker policy, retained state,
  and public tail orchestration by moving inline layout/raster stage mechanics
  into a focused helper.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer+InlineStages.swift`
- Move set:
  - inline layout stage construction
  - inline raster tail construction
  - semantics/draw/raster phase extraction
  - raster minimum-size and local timing helpers
- Invariants: layout offload policy, retained baseline placement, animation
  overlay application, presentation damage, worker timing diagnostics, and
  raster output remain unchanged.
- Rollback: move inline stage helpers back into `FrameTailRenderer.swift` and
  delete `FrameTailRenderer+InlineStages.swift`.

### Packet 123: Event Pump Support Split

- Objective: keep `RunLoop+EventPump.swift` focused on stream construction and
  render-event draining by moving buffer/deadline support types into a support
  file.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPump.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPumpSupport.swift`
- Move set:
  - `DeadlineWakeState`
  - event-pump completion coordination
  - event-pump buffer and pointer coalescing support
  - render-event drain payload
  - coalescible pointer event predicate
- Invariants: input/signal stream completion, deadline wake scheduling,
  pointer coalescing, pending-event checks, and render-event drain behavior
  remain unchanged.
- Rollback: move support declarations back into `RunLoop+EventPump.swift` and
  delete `RunLoop+EventPumpSupport.swift`.

### Packet 124: Runtime Issue Reporting Split

- Objective: separate host issue notification from generic runtime support
  helpers so reporting/de-duplication has a single obvious home.
- Owned files:
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeSupport.swift`
  - `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeIssueReporting.swift`
- Move set:
  - single runtime issue reporting with once-per-run-loop de-duplication
  - batch runtime issue reporting
- Invariants: host sink notification, de-duplication set behavior, frame
  diagnostic issue capture, and `.standardError` sink behavior remain unchanged.
- Rollback: move reporting helpers back into `RunLoop+RuntimeSupport.swift` and
  delete `RunLoop+RuntimeIssueReporting.swift`.

### Packet 125: Committed-Frame Diagnostics Builder Split

- Objective: make committed artifact construction easier to review by moving
  diagnostics-specific parameter threading and timing helpers into a sibling
  builder.
- Owned files:
  - `Sources/SwiftTUIRuntime/Rendering/CommittedFrameArtifactBuilder.swift`
  - `Sources/SwiftTUIRuntime/Rendering/CommittedFrameDiagnosticsBuilder.swift`
- Move set:
  - committed-frame diagnostics input bundle
  - `FrameDiagnostics.fromCachedPhaseProducts` mapping
  - phase timing construction
  - completed-frame main-actor timing construction
  - frame-tail commit drop-blocker derivation
- Invariants: artifact fields, diagnostics counts/work/timing metadata,
  runtime registration diagnostics, completed-frame main-actor timing, and
  public API inventory remain unchanged.
- Rollback: inline diagnostics helpers back into
  `CommittedFrameArtifactBuilder.swift` and delete
  `CommittedFrameDiagnosticsBuilder.swift`.

### Packet 126: ViewGraph Lifecycle Event Collection Split

- Objective: isolate lifecycle event collection helpers from ViewGraph's live
  graph mutation paths without reshaping stored graph state.
- Owned files:
  - `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
  - `Sources/SwiftTUICore/Resolve/ViewGraphLifecycleEventCollection.swift`
- Move set:
  - task-cancel and task-start event append helpers
  - duplicate lifecycle event detection
  - own-lifecycle-event ownership predicate
  - frame lifecycle event plan input construction
- Invariants: lifecycle event ordering, task cancel/start duplicate
  suppression, transparent lifecycle owner behavior, viewport lifecycle
  planning, checkpoint totality, and live graph ownership remain unchanged.
- Batch gate for Packets 122-126:
  - `bun run test`
- Rollback: inline lifecycle event helpers back into `ViewGraph.swift` and
  delete `ViewGraphLifecycleEventCollection.swift`.

## Scheduled Central Runtime/Core Batches

Five additional central runtime/core batches are scheduled after packet
122-126, preserving the current aggressive five-packet cadence while keeping
the scope inside `SwiftTUICore` and `SwiftTUIRuntime`.

### Batch 127-131 — COMPLETED

Delivered as five behavior-preserving moves (see `migration_progress.md` for
validation logs):

- Packet 127: terminal mouse coordinate-mode resolution →
  `TerminalMouseCoordinateResolution.swift`.
- Packet 128: frame-tail layout-offload eligibility →
  `FrameTailLayoutOffloadEligibility.swift`.
- Packet 129: pure transition removal injection-point walk-up →
  `AnimationTransitionRemovalPlanning.swift`.
- Packet 130: read-only retained-frame query types →
  `RetainedFrameQueries.swift` (replaced the originally planned
  dependency-snapshot move, which was infeasible without widening ~25 `private`
  `ViewGraph` properties).
- Packet 131: `FrameTailRetainedState` → `FrameTailRetainedState.swift`.

Rollback: each new file's contents inline back into its source file; delete the
new file. No call sites changed.

### Batch 132-136 — COMPLETED

Delivered as five behavior-preserving moves (see `migration_progress.md`):

- Packet 132: DefaultRenderer test-only hooks → `DefaultRenderer+TestingHooks.swift`.
- Packet 133: RunLoop runtime environment-action factories →
  `RunLoop+EnvironmentActions.swift` (deleted `ClipboardWriting.swift`).
- Packet 134: `AnimatableSnapshot` → `AnimatableSnapshot.swift`.
- Packet 135: SnapshotRenderer tree `describe(_:)` formatters →
  `SnapshotRenderer+TreeDescriptions.swift`.
- Packet 136: renamed `RetainedResolveFrame.swift` → `LayoutPassContext.swift`
  to match its post-Packet-130 contents.

Rollback: revert each new file back into its source; reverse the rename.

### Batch 137-141

- Core layout measurement/placement support readability review.
- Runtime render-driver cancellation and issue-reporting support review.
- Animation overlay insertion/removal sampling call-site cleanup.
- ViewGraph runtime registration restoration support review.
- Core pipeline snapshot/testing support final pass before the next re-rank.

### Batch 142-146

- Core frame artifact and diagnostics helper review.
- RunLoop presentation/focus convergence follow-up cleanup.
- Animation removal overlay planning support review.
- ViewGraph dependency/debug snapshot final consolidation pass.
- Central runtime/core re-rank and handoff cleanup.

### Batch 147-151

- Frame-tail retained state and worker-timing readability review.
- RunLoop event pump, acquisition, and diagnostics naming follow-up.
- Animation overlay planning boundary re-rank and lowest-risk extraction.
- ViewGraph lifecycle/dependency support review after packet 126.
- Central runtime/core documentation and handoff cleanup before the next
  checkpoint.

## Human Checkpoints

Stop for approval before:

- Any public API change.
- Any intentional terminal-output, rendering, lifecycle, or frame-drop behavior
  change.
- Any fixture re-recording.
- Any example-app change.
- Any test weakening or broad test rewrite.
