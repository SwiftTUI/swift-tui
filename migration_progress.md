# Production Code Humanization Progress

## Current Status

Continuing repo-wide production-code humanization on `main` after the
`humanize` branch was merged at `847ece21`.

Approved constraints:

- Preserve public SwiftUI-like APIs.
- Do not change examples.
- Keep test coverage and repo gate strength intact.
- Begin with primary terminal rendering infrastructure.
- Use subagents and review their work.

## Completed

- Loaded `positive-humanize-existing-code`.
- Loaded batch-refactor and parallel-agent orchestration guidance.
- Confirmed repo branch and absence of existing migration artifacts.
- Reviewed repo guidance in `AGENTS.md`.
- Reviewed architecture, render-pipeline, and development docs.
- Spawned read-only subagents for terminal host, frame pipeline, runtime/CLI
  integration, and validation mapping.
- Created initial scope, plan, progress, and handoff artifacts.
- Packet 1 completed: extracted terminal presentation writer/session state from
  `TerminalHost.swift` into `TerminalPresentationState.swift`.
- Packet 2 completed: extracted terminal presentation emission and metrics
  bookkeeping from `TerminalHost.present(_:damage:)`.
- Packet 3 completed: extracted frame-tail presentation-damage proof logic from
  `FrameTailRenderer.swift` into `FrameTailPresentationDamage.swift`.
- Packet 4 completed: split frame diagnostics and frame context out of
  `FrameArtifacts.swift`.
- Packet 5 completed: decomposed async runtime frame acquisition in
  `RunLoop+Rendering.swift` into mode selection, cancellable rendering, and
  skipped-frame bookkeeping helpers.
- Packet 6 completed: moved committed-frame presentation dispatch, JSON and
  accessible output, cursor-focus presentation, and output metrics into
  `RunLoop+Presentation.swift`.
- Packet 7 completed: extracted Kitty image payload construction, placement
  math, and terminal command encoding from `TerminalImageRendering.swift` into
  `TerminalImageKittyRendering.swift`, while leaving renderer cache ownership in
  the facade.
- Packet 8 completed: extracted Sixel output sizing, palette budgeting, payload
  construction, and command encoding into `TerminalImageSixelRendering.swift`,
  and moved shared image scaling and quantization helpers into
  `TerminalImageSampling.swift`.
- Packet 9 completed: extracted fallback overlay mode selection, cache sizing
  helpers, ANSI/ASCII overlay generation, and raw-glyph manifest ownership into
  `TerminalImageFallbackRendering.swift`, while keeping overlay application and
  cache ownership in `TerminalImageRenderer`.
- Packet 10 completed: moved terminal host graphics and pointer capability
  probing into `TerminalHostCapabilities.swift`.
- Packet 11 completed: extracted terminal host escape sequence construction,
  platform I/O shims, and process-exit cleanup into dedicated terminal runtime
  files.
- Packet 12 completed: extracted internal terminal presentation planning,
  row-batch strategy payloads, graphics replay planning, and dirty-row image
  intersection checks into `TerminalPresentationPlanning.swift`.
- Packet 13 completed: extracted pure animation resolved/placed tree query
  helpers into `AnimationTreeQueries.swift`, leaving mutating transition and
  lifecycle bookkeeping in `AnimationController.swift`.
- Packet 14 completed: extracted resolved-tree removal overlay transforms into
  `AnimationTransitionOverlay.swift`, keeping animation sampling, purge
  decisions, deadlines, and batch bookkeeping in `AnimationController`.
- Packet 15 completed: extracted property animation slot lookup, interpolation
  fallback, and resolved-tree value writeback into
  `AnimationPropertyValueApplication.swift`, keeping controller state,
  scheduling, custom-state writeback, and batch bookkeeping in
  `AnimationController`.
- Packet 16 completed: extracted completed-frame artifact assembly, worker
  timing derivation, and drop-eligibility classification into
  `CompletedFrameArtifactBuilder.swift`, and moved `CompletedFrameCandidate`
  out of `FrameTailRenderer.swift` into completed-frame rendering support.
- Packet 17 completed: extracted run-loop frame diagnostic record construction
  into `RunLoop+FrameDiagnostics.swift`.
- Packet 18 completed: extracted terminal input support types, protocols,
  capability models, and coalescing support out of `InputReader.swift`.
- Packet 19 completed: extracted late-preference reconciliation policy and
  mechanics into `LatePreferenceReconciliation.swift`.
- Packet 20 completed: extracted frame-head transaction and draft support into
  `FrameHeadDraftTransaction.swift`.
- Packet 21 completed: extracted run-loop focus and scroll convergence into
  `RunLoop+FocusSync.swift`.
- Packet 22 completed: extracted async run-loop frame acquisition into
  `RunLoop+FrameAcquisition.swift`.
- Packet 23 completed: renamed completed-frame artifact support to
  `CommittedFrameArtifactBuilder.swift`, shared one-shot and async committed
  artifact assembly, and extracted `DefaultRenderer` commit effects and
  committed-frame publication helpers.
- Packet 24 completed: extracted terminal raw-mode saved state, pointer
  reporting state, and process-exit cleanup registration into
  `TerminalRawModeSession.swift`, leaving terminal byte ordering and POSIX
  mutation in `TerminalHost.swift`.
- Packet 25 completed: extracted repeated control-message filtering and
  terminal parser feeding from `InputReader.swift` into
  `TerminalInputEventDecoding.swift`, leaving WASI polling and DispatchSource
  stream loops in place.
- Packet 26 completed: moved `TerminalInputParser`, `KeyParser`, and private
  parsing helpers from `InputReader.swift` into `TerminalInputParser.swift`,
  leaving concrete stream ownership in `InputReader.swift`.
- Packet 27 completed: extracted platform terminal input read classification
  and nonblocking drain mechanics into `TerminalInputStreamReading.swift`,
  leaving WASI polling and DispatchSource stream ownership in
  `InputReader.swift`.
- Packet 28 completed: extracted placed overlay sampling into
  `PlacedAnimationOverlaySampling.swift`, leaving `AnimationController` as the
  owner of custom-state writeback, completed-key removal, and batch release.
- Packet 29 completed: extracted post-head/pre-commit frame-tail orchestration
  from `DefaultRenderer` into `DefaultRendererFrameTailCoordinator.swift`,
  leaving `DefaultRenderer` as owner of frame-head setup and commit effects.
- Packet 30 completed: extracted stranded animation-completion scheduling and
  pending-drain partitioning into `AnimationCompletionScheduling.swift`, leaving
  `AnimationController` as owner of completion closures, batch ref counts,
  pending empty-batch completions, and frame-head deferral state.
- Packet 31 completed: extracted DefaultRenderer frame-head preparation and
  animation-injection orchestration into
  `DefaultRendererFrameHeadCoordinator.swift`, leaving `DefaultRenderer` as
  owner of live renderer state, commit effects, and cancellation behavior.
- Packet 32 completed: moved async frame-tail job state, cancellable render
  outcome, and the frame-tail cancellation token into
  `FrameTailJobCancellation.swift`, leaving `FrameTailRenderer` focused on
  frame-tail layout, semantics, draw, and raster work.
- Packet 33 completed: extracted `ViewGraph` lifecycle event planning into
  `ViewGraphLifecyclePlanning.swift`, leaving checkpoint/debug snapshots,
  selective evaluation, and mutable graph ownership in `ViewGraph.swift`.
  A patch-review finding that the helper accepted live `ViewNode` storage was
  resolved by passing an ordered change-handler value snapshot instead.
- Packet 34 completed: moved presentation item models and per-family storage
  types into `PresentationItems.swift` and
  `PresentationCoordinatorStorage.swift`, leaving coordinator orchestration,
  registry state, draft coordination, environment keys, and portal composition
  in `PresentationCoordinator.swift`.
- Packet 35 completed: moved the six concrete built-in presentation
  coordinators into `BuiltinPresentationCoordinators.swift`, leaving
  coordinator guards, protocols, environment handles, registry/checkpoint
  ownership, draft state, declaration preferences, and portal composition in
  `PresentationCoordinator.swift`.
- Packet 36 completed: moved `PresentationCoordinatorBox`,
  `AnyPresentationCoordinatorBox`, and `PresentationCoordinatorRegistry` into
  `PresentationCoordinatorRegistry.swift`, leaving environment handles,
  portal state/draft publication, declaration preferences, and portal-root
  composition in `PresentationCoordinator.swift`.
- Packet 37 completed: moved `PresentationPortalState` and
  `PresentationPortalDraft` into `PresentationPortalState.swift`, leaving
  declaration preferences and portal-root composition in
  `PresentationCoordinator.swift`.
- Packet 38 completed: extracted value-only structural child removal planning
  into `ViewGraphStructuralReconciliation.swift`, leaving `ViewGraph` as owner
  of live node storage, subtree teardown, lifecycle side effects, dependency
  cleanup, and alias cleanup.
- Packet 39 completed: extracted selective dirty-evaluation target planning
  into `ViewGraphDirtyEvaluationPlanning.swift`, leaving `ViewGraph` as owner
  of target dirty-bit mutation, dirty-set mutation, live node storage, lifecycle
  owner registration, and `DirtyEvaluationPlan` construction.
- Packet 40 completed: extracted terminal host presentation emission assembly
  into `TerminalHost+PresentationEmission.swift`, leaving `TerminalHost` as
  owner of raw-mode/session sequencing, presentation writer drain/drop recovery,
  graphics capability probing, synchronized-output wrapping, and retained
  surface publication.
- Packet 41 completed: moved the Web runner style transport codec and its
  private JSON/base64 helpers into `TerminalRenderStyleCodec.swift`, leaving
  `TerminalControlMessages.swift` focused on control-message framing and
  resize/style dispatch.
- Packets 42-81 completed in later batches; detailed batch summaries and gate
  logs are recorded below.
- Packets 82-86 completed: decomposed built-in stack support into axis,
  lazy-allocation, metric, space-allocation, and minimum-size files.
- Packets 87-91 completed: split diagnostics TSV formatting, terminal style
  transport JSON/Base64, frame-tail model types, and POSIX terminal control
  into focused runtime files.

## Baseline Validation

Passed before production-code edits:

- `bun run test`
- Full log: `/tmp/swift-tui-test-gate-20260518-023359-77501.log`
- Result: PASS

Packet 1 validation:

- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-024018-4112.log`
  - Result: PASS

Packet 2 validation:

- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-024705-20556.log`
  - Result: PASS

Packet 3 validation:

- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-025321-47448.log`
  - Result: PASS

Packet 4 validation:

- `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-025909-68455.log`
  - Result: PASS

Packet 5 validation:

- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-030508-85414.log`
  - Result: PASS

Packet 6 validation:

- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.JSONFrameRendererTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-031025-5025.log`
  - Result: PASS

Packet 7 validation:

- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-031747-26286.log`
  - Result: PASS

Packet 8 validation:

- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-032834-69653.log`
  - Result: PASS

Packet 9 validation:

- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-033507-95996.log`
  - Result: PASS

Packet 10 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.CellPixelMetricsRefreshTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-034357-16939.log`
  - Result: PASS

Packet 11 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalHost`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - Result: PASS
- `swiftly run swift test --filter WebSurfaceTransportTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITerminalTests`
  - Result: PASS across 5 consecutive stabilization runs after removing the
    short-lived `/bin/echo` fixture race.
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-040917-13192.log`
  - Result: PASS

Packet 12 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-041849-32895.log`
  - Result: PASS

Packet 13 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-043316-68540.log`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-042708-50577.log`
  - Result: PASS

Packet 14 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS

Packet 15 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS
- `swiftly run swift test --filter AnimationController`
  - Result: PASS, 64 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-044249-87972.log`
  - Result: PASS

Packet 16 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-045323-8675.log`
  - Result: PASS

Packet 17 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS, 22 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-050134-20208.log`
  - Result: PASS

Packet 18 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
  - Result: PASS, 1 test
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-051003-41466.log`
  - Result: PASS

Packet 19 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.BoundedReconciliationTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.ToolbarTests`
  - Result: PASS, 19 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.ViewThatFitsSurfaceTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-051542-56825.log`
  - Result: PASS

Packet 20 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests
- `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - Result: PASS, 4 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-052405-85109.log`
  - Result: PASS

Packet 21 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AppRuntimeTests`
  - Result: PASS, 24 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests`
  - Result: PASS, 73 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests
- `swiftly run swift test --filter SwiftTUICoreTests.FocusTrackerTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUICoreTests.LocalScrollPositionRegistryTests`
  - Result: PASS, 8 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-053009-4450.log`
  - Result: PASS

Packet 22 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS, 22 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-053644-24624.log`
  - Result: PASS

Packet 23 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests
- `swiftly run swift test --filter SwiftTUITests.DirtyTrackingCoherenceTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1305 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-054930-58630.log`
  - Result: PASS

Packet 24 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalCapabilityProfileApplyingTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS, 28 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests`
  - Result: PASS, 73 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-055729-85446.log`
  - Result: PASS

Packet 25 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
  - Result: PASS, 1 test
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-060611-5894.log`
  - Result: PASS

Packet 26 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputParserModifierTests`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/keyParserParsesExpectedSequences`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalInputParserDecodesMixedMouseStreams`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests/terminalPixelMouseInputReachesDragGestureAsFractionalLocation`
  - Result: PASS, 1 test
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-061130-23411.log`
  - Result: PASS

Packet 27 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick`
  - Result: PASS, 1 test
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-065523-66925.log`
  - Result: PASS

Packet 28 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/matchedGeometryTriggersTranslationAnimation`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/matchedGeometryRendersAtSourceAtProgressZero`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/insertionOffsetAnimationCompletes`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/removalOverlaysDoNotAccumulateAcrossTickFrames`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/transitionRemovalIsInjectedAtPlacedLevel`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests/insertionOffsetTranslatesPlacedBounds`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadKeepsTransitionAnimationsDraftOwnedUntilCommit`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS, 18 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS, 17 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-083720-85404.log`
  - Result: PASS

Packet 29 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)`
  - Result: PASS, 75 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedBuiltInLayoutQueuesInputWithoutCommittingAhead`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests/hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-093634-11184.log`
  - Result: PASS

Packet 30 validation:

- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS, 18 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortKeepsAnimationCompletionsUncommitted`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadDefersAnimationCompletionUntilCommit`
  - Result: PASS, 1 test
- `swiftly run swift test --filter AnimationController`
  - Result: PASS, 64 tests
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-100620-73481.log`
  - Result: PASS
- Patch review subagent found one process issue: the new helper was untracked
  and missing from plain `git diff`. Resolved with `git add -N` so the file now
  appears in review diffs without creating a commit.
- `git diff --check`
  - Result: PASS

Packet 31 validation:

- `swiftly run swift build`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift Sources/SwiftTUIRuntime/SwiftTUI.swift`
  - Result: PASS
- `swiftly run swift test --filter 'SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)'`
  - Result: PASS, 75 tests
- `swiftly run swift test --filter 'SwiftTUITests\.(ResolvePurityTests|Phase4ObservationAndEnvironmentTests)'`
  - Result: PASS, 27 tests
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests/frameHeadTransactionDefersBatchCompletionUntilCommit`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AppRuntimeTests/optionalFocusStateTracksRuntimeFocusChanges`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests on rerun
- Patch review subagent found one low-severity surface issue: a renderer-only
  helper had become module-internal. Resolved by keeping
  `renderPipelineTree(from:)` private in `SwiftTUI.swift` and passing it to the
  coordinator as a closure.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-102231-97496.log`
  - Result: PASS

Packet 32 validation:

- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter 'SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|RenderDriverInstrumentationCostTests)'`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior, access-control, concurrency, or API
  issue in the moved cancellation code. It noted the broader worktree also
  contains previous Packet 30 and 31 changes, so Packet 32 review should stay
  scoped to `FrameTailRenderer.swift` and `FrameTailJobCancellation.swift`.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-103156-25687.log`
  - Result: PASS

Packet 33 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS, 14 tests
- `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortRestoresBroadResetState`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/lazyForEachRowsEmitViewportLifecycleTransitions`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/runLoopEmitsViewportLifecycleTransitionsForFullLazyRows`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found one medium-severity state-boundary issue: the
  first helper shape accepted the live `nodesByIdentity` map. Resolved by
  keeping `ViewNode` access in `ViewGraph` and passing
  `changeHandlerIDsByIdentity` as ordered value data.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-104315-68488.log`
  - Result: PASS

Packet 34 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift Sources/SwiftTUIViews/Presentation/PresentationItems.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift Sources/SwiftTUIViews/Presentation/PresentationItems.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUIViewsTests`
  - Result: PASS, 98 tests
- `swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationEscapeDismissTests|PopoverPresentationTests|OverlayStackTests|DismissStackTests)'`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal`
  - Result: PASS, 1 test
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift, access-control broadening,
  actor-isolation drift, public API change, or move-scope issue. The review
  confirmed the diff is mechanical and keeps the `fileprivate` checkpoint
  fields colocated with storage users.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-105218-92507.log`
  - Result: PASS

Packet 35 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PopoverPresentationTests|MenuSurfaceTests|PaletteSheetAbsorptionTests|PresentationActionScopeTests)'`
  - Result: PASS, 30 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift, access-control broadening,
  actor-isolation drift, public API change, modal/z-index drift, or move-scope
  issue. It confirmed the registry still uses the same concrete coordinator
  types and reads `C.zIndex`, `C.overlayKindName`, and
  `coordinator.modalPolicy(for:)`.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-105849-10257.log`
  - Result: PASS

Packet 36 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter 'SwiftTUITests\.(PresentationEscapeDismissTests|PopoverPresentationTests|OverlayStackTests|DismissStackTests|PresentationSurfaceTests)'`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal`
  - Result: PASS, 1 test
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift, access-control broadening,
  actor-isolation drift, public API change, registry order/restore-order drift,
  environment handle drift, draft publication drift, or move-scope issue.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-110638-29651.log`
  - Result: PASS

Packet 37 validation:

- `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationPortalState.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationContinuityTests|PresentationEscapeDismissTests|PopoverPresentationTests|PortalPrimitiveTests)'`
  - Result: PASS, 28 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal`
  - Result: PASS, 1 test
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift, package-access broadening,
  actor-isolation drift, public API change, or draft commit/discard lifetime
  issue. It confirmed the moved types preserve the prior checkpoint and
  publication behavior.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-111454-47956.log`
  - Result: PASS

Packet 38 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS, 14 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUICoreTests.StructuralDiffTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUICoreTests`
  - Result: PASS, 387 tests
- `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift in removal planning, index
  guards, or committed-snapshot selection. It found one misleading helper
  comment about non-removal operations; the comment was tightened to state that
  matched, moved, and inserted children are owned by the later commit/reuse/
  install materialization paths.
- `git diff --check`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-112550-packet38.log`
  - Result: PASS

Packet 39 validation:

- `swiftly run swift build`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphDirtyEvaluationPlanning.swift`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `git diff --check`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS, 14 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests
- `swiftly run swift test --filter SwiftTUICoreTests`
  - Result: PASS, 387 tests
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift in graph-known invalidation
  filtering, dirty-frontier ancestor suppression and ordering, lifecycle-owner
  promotion, duplicate evaluator collapse, or evaluator fallback. It confirmed
  `markDirty()` and `DirtyEvaluationPlan` construction stayed in `ViewGraph`.
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-113708-packet39.log`
  - Result: PASS

Packet 40 validation:

- `swiftly run swift build`
  - Result: PASS. Existing strict-memory-safety warnings appeared in unrelated
    SwiftUI host files.
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS, 28 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `git diff --check`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift in full repaint ordering,
  incremental row ordering, Kitty transmitted-image cache mutation, graphics
  replay metrics, erase-to-end lowering, or synchronized-output boundaries. It
  found no new concurrency risk.
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-114635-packet40.log`
  - Result: PASS

Packet 41 validation:

- `swiftly run swift build`
  - Result: PASS. Existing strict-memory-safety warnings appeared in unrelated
    SwiftUI host files.
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter WASISurfaceBridgeTests`
  - Result: PASS, 19 tests
- `swiftly run swift test --filter SwiftTUIWebHostTests`
  - Result: PASS, 39 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `git diff --check`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift: the codec body remained
  byte-for-byte identical, SPI/public surface and schema comment were preserved,
  `ControlMessageParser` still calls `decodeBase64`, no Foundation import was
  added, and invalid input behavior stayed intact.
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-115536-packet41.log`
  - Result: PASS

Packet 42 selected and completed:

- Scope: split terminal cell text rendering, style lowering, terminal-control
  sanitization, ASCII glyph degradation, OSC 8 hyperlink emission, and ANSI16
  palette matching out of `TerminalPresentation.swift` into
  `TerminalCellTextRenderer`.
- Production files changed:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
- Behavior preserved:
  - full repaint and incremental row spans still share render state across
    adjacent spans and close state once at batch end
  - OSC 8 destinations still strip terminal-control and C1 bytes
  - terminal control scalars in displayed text still become replacement
    characters
  - ASCII profile degradation, SGR ordering, color lowering, and hyperlink
    open/close behavior remain unchanged
  - no public or SPI API was added

Packet 42 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS. Existing strict-memory-safety warnings appeared in unrelated
    SwiftUI host files.
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCellTextRenderer.swift`
  - Result: PASS
- `git diff --check`
  - Result: PASS before the broader runtime suite
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS, 28 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.Phase1PresentationIntegrationTests`
  - Result: PASS, 7 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- Patch review subagent found no behavior drift: full-row and incremental
  row-batch behavior were preserved, row-span render state is carried across
  spans and closed once, OSC 8 sanitization and control-scalar replacement are
  intact, ASCII degradation and SGR ordering are unchanged, and no public or
  SPI surface was added.
- First `bun run test` attempt:
  - Full log: `/tmp/swift-tui-test-gate-20260518-120728-packet42.log`
  - Result: FAIL in `Check accessibility guardrails` only. All build and test
    targets in the gate passed. The raw-glyph manifest still pointed at
    `TerminalPresentation.swift` after the reviewed raw-glyph mappings moved
    to `TerminalCellTextRenderer.swift`.
- `Scripts/lib/accessibility_raw_glyph_sources.txt`
  - Result: updated to move the accepted raw-glyph source entry from
    `TerminalPresentation.swift` to `TerminalCellTextRenderer.swift`.
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- Per the 2026-05-18 batching adjustment, Packet 42 will be included in the
  next three-packet full repo gate instead of rerunning `bun run test`
  immediately after the manifest-only correction.

## Next Slice

Packet 43 selected and completed:

- Scope: split incremental terminal row-damage span detection, row-batch
  rendering, wide-glyph span normalization, and changed-cell accounting from
  `TerminalPresentation.swift` into `TerminalSurfaceDamageRendering.swift`.
- Production files changed:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift`
- Behavior preserved:
  - `TerminalSurfaceRenderer` keeps the same internal forwarding methods used
    by package tests and package-internal callers
  - span sorting, cursor-forward gaps, shared row-batch render state, and the
    final state close remain unchanged
  - candidate range limiting, damage clamping, `.empty` out-of-bounds cells,
    wide-glyph continuation normalization, and `cellsChanged` metrics remain
    unchanged
  - no public or SPI API was added

Packet 43 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS. Existing strict-memory-safety warnings appeared in unrelated
    SwiftUI host files.
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.Phase1PresentationIntegrationTests`
  - Result: PASS, 7 tests
- Read-only review subagent found no behavior drift in forwarding signatures,
  span sorting, wide-glyph continuation normalization, candidate range
  clamping/limiting, row-batch render-state close, cursor-forward gaps, or
  `cellsChanged` width accounting.

Packet 44 selected and completed:

- Scope: move the public `TerminalCapabilityProfile` type and
  `RuntimeConfiguration` overlay application from `TerminalPresentation.swift`
  to `TerminalCapabilityProfile.swift`.
- Production files changed:
  - `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
  - `Sources/SwiftTUIRuntime/Terminal/TerminalCapabilityProfile.swift`
- Behavior preserved:
  - public struct, nested enums, stored properties, initializer defaults,
    static profiles, `detect`, and `applying(_:)` remain unchanged
  - UTF-8 locale detection, `NO_COLOR`, non-TTY/`dumb` fallback,
    rich-terminal term list, synchronized-output/mouse/hyperlink support, and
    RuntimeConfiguration overlay semantics remain unchanged
  - no Foundation import or new dependency was introduced

Packet 44 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCapabilityProfile.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift Sources/SwiftTUIRuntime/Terminal/TerminalCapabilityProfile.swift Sources/SwiftTUIRuntime/Terminal/TerminalSurfaceDamageRendering.swift`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalCapabilityProfileApplyingTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `swiftly run swift test --filter SwiftTUITests.RuntimeConfigurationTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.RuntimeConfigurationBuilderTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.EnvironmentResolverTests`
  - Result: PASS, 27 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS, 28 tests
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `git diff --check`
  - Result: PASS
- First Packet 42-44 `bun run test` batch attempt:
  - Full log: `/tmp/swift-tui-test-gate-20260518-121658-packet42-44.log`
  - Result: FAIL in full `SwiftTUITests` only. All policy checks and all other
    test targets passed. The failing test was
    `AsyncLifecycleGenerationTests/injectedInputReaderIgnoresStaleStreamTeardownAfterReplacement`,
    timing out while waiting for the first input consumer to become ready.
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests/injectedInputReaderIgnoresStaleStreamTeardownAfterReplacement`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests`
  - Result: PASS, 1309 tests
- The failed gate matches the earlier transient full-suite timeout pattern and
  is not in the changed terminal presentation/capability code path.
- Second Packet 42-44 `bun run test` batch attempt:
  - Full log: `/tmp/swift-tui-test-gate-20260518-122001-packet42-44-rerun.log`
  - Result: PASS

Packet 45 selected and completed:

- Scope: split TabView style hosting, layout slot metadata, style type-erasure
  boxes, hosted strip/overflow views, and package identity helpers from
  `TabViewStyles.swift` into `TabViewStyleHosting.swift`.
- Production files changed:
  - `Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift`
  - `Sources/SwiftTUIViews/NavigationViews/TabViewStyleHosting.swift`
- Behavior preserved:
  - public style protocols and concrete style declarations remain unchanged
  - `AnyTabViewStyle` still erases through the same private stored box
  - active `DeferredPayloadView` resolution, hosted strip layout slot
    metadata, overflow trigger/menu placement, and tab/overflow identity
    helpers remain unchanged
  - literal, underline, and powerline tab chrome plus reviewed raw glyphs stay
    in `TabViewStyles.swift`

Packet 45 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift Sources/SwiftTUIViews/NavigationViews/TabViewStyleHosting.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift Sources/SwiftTUIViews/NavigationViews/TabViewStyleHosting.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS after fixing the new file import to preserve package access
    without adding a public import warning.
- `swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests`
  - Result: PASS, 17 tests
- `swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests`
  - Result: PASS, 5 tests
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `git diff --check`
  - Result: PASS
- Read-only review subagent found no behavior drift in style type erasure,
  hosted strip/overflow resolution, layout slot metadata, package identity
  helpers, active content payload resolution, overflow placement, or raw
  glyph/chrome ownership.

Packet 46 selected and completed:

- Scope: split accessibility node extraction and accessibility warning
  emission from the main semantic extractor into
  `SemanticAccessibilityExtraction.swift`.
- Production files changed:
  - `Sources/SwiftTUICore/Semantics/Semantics.swift`
  - `Sources/SwiftTUICore/Semantics/SemanticAccessibilityExtraction.swift`
- Behavior preserved:
  - parent/child emission and emitted-parent identity threading remain
    two-pass and unchanged
  - hidden descendant propagation, focus identity relevance, text-input cursor
    anchor hoisting, role/label inference, visual-content warnings, and
    transient/hidden filtering remain unchanged
  - `semanticBounds` remains the single offset-aware geometry helper, now
    module-internal so both semantic extractor files can call it
  - no public consumer API changed

Packet 46 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Semantics/Semantics.swift Sources/SwiftTUICore/Semantics/SemanticAccessibilityExtraction.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Semantics/Semantics.swift Sources/SwiftTUICore/Semantics/SemanticAccessibilityExtraction.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUICoreTests.FocusPresentationTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - Result: PASS, 14 tests
- `swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.ContentShapeTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS, 8 tests
- Read-only review subagent found no behavior regression. It flagged the
  initial duplicated offset-bounds helper as a coverage/maintenance risk; the
  patch was tightened to share `semanticBounds` before the final focused
  accessibility reruns.

Packet 47 selected and completed:

- Scope: split `TextLayoutCache` storage, metrics, generation refresh, and LRU
  eviction bookkeeping from `TextLayout.swift` into `TextLayoutCache.swift`.
- Production files changed:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutCache.swift`
- Test files changed:
  - `Tests/SwiftTUITests/TextLayoutCacheTests.swift`
- Behavior preserved:
  - public text layout types and `layoutText` remain unchanged
  - `layoutText` still routes through `TextLayoutCache.shared`
  - cache key shape, metrics counters, generation refresh, access-order
    records, and eviction loop remain unchanged
  - the uncached string layout helper is module-internal only so the extracted
    cache can call it
  - added one focused eviction test to pin refreshed-entry retention

Packet 47 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutCache.swift Tests/SwiftTUITests/TextLayoutCacheTests.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutCache.swift Tests/SwiftTUITests/TextLayoutCacheTests.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS after making the uncached string layout helper
    module-internal rather than private.
- `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.RenderedTextFixtureSupportTests`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - Result: PASS, 188 tests
- Read-only review subagent found no material findings and confirmed the
  extraction preserved cache key/metrics/order/generation/eviction behavior,
  shared cache routing, and concurrency posture. Its recommended explicit
  eviction coverage was added.

Packet 45-47 batch validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-123452-43677.log`
  - Result: PASS

## Next Slice

Packet 48 selected and completed:

- Scope: split word-boundary text wrapping, continuation-marker wrapping,
  cluster fallback wrapping, whitespace/token classification, and the existing
  wrapping test hook from `TextLayout.swift` into `TextLayoutWrapping.swift`.
- Production files changed:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutWrapping.swift`
- Test files changed:
  - `Tests/SwiftTUITests/TextLayoutTests.swift`
- Behavior preserved:
  - nil width, zero width, and empty text still produce the same single-line
    shapes
  - leading whitespace, separator whitespace consumption, oversized word-like
    continuation markers, narrow-width cluster fallback, and wide cluster
    wrapping remain unchanged
  - no public or package consumer API changed
  - added one guard-path characterization test after review

Packet 48 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - Result: PASS, 9 tests after the guard-path characterization was added
- `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - Result: PASS, 188 tests
- Read-only review subagent found no behavior drift. It noted missing direct
  coverage for nil width, zero width, and empty string guard paths; the focused
  characterization test was added and rerun.

Packet 49 selected and completed:

- Scope: split line-limit truncation and head/middle/tail fitting helpers from
  `TextLayout.swift` into `TextLayoutTruncation.swift`.
- Production files changed:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextLayoutTruncation.swift`
- Behavior preserved:
  - nil-width and non-forced truncation still return the source line
  - zero-width, one-cell ellipsis, head, tail, and middle truncation width
    accounting remain unchanged
  - fitting helpers remain private to the truncation file
  - no public or package consumer API changed

Packet 49 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift Sources/SwiftTUICore/Content/TextLayoutTruncation.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift Sources/SwiftTUICore/Content/TextLayoutTruncation.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - Result: PASS, 188 tests
- Read-only review subagent found no material findings. The review also ran
  the focused SwiftUI truncation test.

Packet 50 selected and completed:

- Scope: split terminal cell-width classification from `TextLayout.swift` into
  `TextCellWidth.swift` and remove the now-unused private `textClusters`
  helper.
- Production files changed:
  - `Sources/SwiftTUICore/Content/TextLayout.swift`
  - `Sources/SwiftTUICore/Content/TextCellWidth.swift`
- Behavior preserved:
  - package `cellWidth(of:)` visibility remains unchanged
  - ASCII/NUL fast path, multi-scalar fallback, emoji presentation, VS16,
    wide CJK/emoji ranges, zero-width marks, and empty-character behavior
    remain unchanged
  - border, tile style, raster, text input, and text layout call sites still
    use the same package function
- Review response:
  - read-only review subagent found no behavior drift or public API exposure
  - it flagged one imprecise comment; the wording was corrected to cover
    multi-scalar and non-ASCII input
  - it noted `uncachedTextLayout(for:options:)` is module-internal after
    Packet 47 so the extracted cache can call it; this remains non-public and
    non-package API

Packet 50 validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextCellWidth.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift Sources/SwiftTUICore/Content/TextLayoutTruncation.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - Result: PASS
- `swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Content/TextLayout.swift Sources/SwiftTUICore/Content/TextCellWidth.swift Sources/SwiftTUICore/Content/TextLayoutWrapping.swift Sources/SwiftTUICore/Content/TextLayoutTruncation.swift Tests/SwiftTUITests/TextLayoutTests.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TextLayoutTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter TileStyle`
  - Result: PASS, 23 tests
- `swiftly run swift test --filter BorderSet`
  - Result: PASS, 20 tests. The narrower
    `SwiftTUICoreTests.BorderSetTests` filter matched no tests, so the broader
    filter was used.
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS, 40 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests`
  - Result: PASS, 188 tests

Packet 48-50 batch validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `bun run test`
  - Full log: `/tmp/swift-tui-test-gate-20260518-124933-79782.log`
  - Result: PASS

## Next Slice

Packet 51-53 selected and completed:

- Scope: decompose the remaining prompt/toast presentation implementation in
  `PresentationModifiers.swift` into dedicated files while preserving the
  public SwiftUI-shaped presentation APIs.
- Production files changed:
  - `Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift`
  - `Sources/SwiftTUIViews/Presentation/PromptPresentationEntrypoints.swift`
  - `Sources/SwiftTUIViews/Presentation/PromptPresentationSurface.swift`
  - `Sources/SwiftTUIViews/Presentation/ToastPresentation.swift`
- Policy files changed:
  - `Scripts/lib/public_documentation_ratchet.txt`
  - `Scripts/lib/accessibility_raw_glyph_sources.txt`
  - `Scripts/lib/accessibility_color_state_sources.txt`
- Behavior preserved:
  - prompt public overloads, presentation tokens, default dismiss labels, and
    authoring-context capture remain unchanged
  - prompt surface chrome, focus-scope metadata, menu intrinsic sizing, and
    close-button behavior remain unchanged
  - toast public styles/modifiers, semantic icons, default auto-dismiss
    duration, lifecycle task registration, and bottom-left overlay placement
    remain unchanged
  - public documentation ratchet entries and accessibility raw-glyph/color-state
    guardrails follow the moved declarations and glyph/color usage

Packet 51 focused validation and review:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift Sources/SwiftTUIViews/Presentation/PromptPresentationEntrypoints.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - Result: PASS, 5 tests
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- Read-only review subagent found no material findings.

Packet 52 focused validation and review:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift Sources/SwiftTUIViews/Presentation/PromptPresentationSurface.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests`
  - Result: PASS, 7 tests
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS after adding the moved prompt surface color-state source
- Read-only review subagent found the move behavior-preserving but recommended
  `package import SwiftTUICore` for `PromptPresentationSurface.swift`. Direct
  target builds with the warning-free plain import passed for `SwiftTUIViews`
  and `SwiftTUIRuntime`; changing back to `package import` produced an unused
  package-import warning, so the plain import was retained.

Packet 53 focused validation and review:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationModifiers.swift Sources/SwiftTUIViews/Presentation/ToastPresentation.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.PresentationEscapeDismissTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/toastAutoDismissRegistersLifecycleTask`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput`
  - Result: PASS, 1 test
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS after moving the raw-glyph/color-state manifest entries to
    `ToastPresentation.swift`
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `git diff --check`
  - Result: PASS
- Read-only review subagent found no material findings.

Packet 51-53 batch validation:

- First `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-130620-packet51-53.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-130832-8813.log`
  - Result: FAIL, only in `Run SwiftTUI runtime tests`, with three
    `AsyncLifecycleGenerationTests` readiness timeouts.
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - Result: PASS, 3 tests, immediately after the failed full gate.
- Rerun `bun run test`
  - User tee log:
    `/tmp/swift-tui-test-gate-20260518-131050-packet51-53-rerun.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-131048-20030.log`
  - Result: PASS

## Next Slice

Packet 54-56 selected and completed under the more aggressive three-packet
cadence:

- Scope: decompose `ResolvedNode.swift`, a central `SwiftTUICore` resolve-layer
  file, without moving the `ResolvedNode` stored fields or changing public API.
- Production files changed:
  - `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedSemanticMetadata.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedLifecycleMetadata.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedMatchedGeometry.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedIndexedChildSupport.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedNodeTraversal.swift`
  - `Sources/SwiftTUICore/Resolve/ResolvedNodeEquivalence.swift`
- Behavior preserved:
  - semantic metadata merge behavior, focus flags, accessibility labels/live
    regions/cursor anchors, tab item display strings, and interaction
    availability stay unchanged
  - lifecycle metadata and matched-geometry public value types keep their
    signatures and defaults
  - indexed-child worker snapshotting, custom-layout fallback summaries, and
    retained-reuse indexed-source decisions stay unchanged
  - resolved-node traversal order, lifecycle collection order, measurement and
    placement equivalence, type-discriminator compatibility, and equality stay
    unchanged

Packet 54 focused validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ResolvedNode.swift Sources/SwiftTUICore/Resolve/ResolvedSemanticMetadata.swift`
  - Result: PASS
- `swiftly run swift build`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests`
  - Result: PASS, 14 tests

Packet 55 focused validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ResolvedNode.swift Sources/SwiftTUICore/Resolve/ResolvedIndexedChildSupport.swift Sources/SwiftTUICore/Resolve/ResolvedLifecycleMetadata.swift Sources/SwiftTUICore/Resolve/ResolvedMatchedGeometry.swift`
  - Result: PASS
- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUICoreTests.ChildDescriptorTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter matchedGeometry`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter LayoutEngineTests`
  - Result: PASS, 32 tests
- `swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests`
  - Result: PASS, 1 test

Packet 56 focused validation:

- `swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ResolvedNode.swift Sources/SwiftTUICore/Resolve/ResolvedIndexedChildSupport.swift Sources/SwiftTUICore/Resolve/ResolvedNodeTraversal.swift Sources/SwiftTUICore/Resolve/ResolvedNodeEquivalence.swift`
  - Result: PASS
- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - Result: PASS, 22 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ChildDescriptorTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS, 22 tests
- `swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
  - Result: PASS, 1 test

Packet 54-56 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 54-56 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-132300-packet54-56.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-132341-40611.log`
  - Result: PASS

Packet 57-61 completed under the updated five-packet cadence:

- Scope: decompose the central SwiftTUIViews modifier surface and custom-layout
  infrastructure without changing public SwiftUI-shaped consumer APIs.
- Production files changed:
  - `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewMetadataModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewLifecycleModifiers.swift`
  - `Sources/SwiftTUIViews/Modifiers/ViewLayoutModifiers.swift`
  - `Sources/SwiftTUIViews/Layout/CustomLayout.swift`
  - `Sources/SwiftTUIViews/Layout/StackLayouts.swift`
  - `Scripts/check_public_surface_policies.sh`
- Behavior preserved:
  - identity, metadata, accessibility, focus, environment, layout values, and
    alignment guides keep the same public signatures and merge behavior
  - lifecycle modifiers keep task actor inheritance, task-id replacement, local
    lifecycle registration, and imperative authoring-context capture unchanged
  - safe-area, padding, frame, border, overlay/background, offset/position, and
    matched-geometry modifiers keep their layout/raster/transition behavior
  - built-in stack layouts keep spacing, alignment, `AnyLayout` identity, and
    built-in layout-behavior detection unchanged
  - custom layouts keep cache scoping, placement fallback, worker-safe
    `SendableLayout` execution, and custom-layout stack-minimum behavior
    unchanged

Packet 57 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUIViewsTests.ViewModifierAlgebraTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUIViewsTests.DependencyTrackingTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUIViewsTests.EnvironmentTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReadsLayoutValuesAndPlacesSubviews`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/alignmentGuideOverridesFeedStackPlacement`
  - Result: PASS, 1 test

Packet 58 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.Phase2LifecycleFixtureTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/onChangeDefersExecutionUntilCommitAndTracksOldAndNewValues`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.ImperativeAuthoringContextDispatchTests`
  - Result: PASS, 21 tests
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS

Packet 59 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SafeAreaSurfaceTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.BorderModifierLayoutTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.BorderRenderingTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.GeometryReaderSurfaceTests`
  - Result: PASS, 13 tests
- `swiftly run swift test --filter matchedGeometry`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests/reducedMotionSuppressesMatchedGeometryTranslation`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/overlayAlignmentUsesPrimaryGuides`
  - Result: PASS, 1 test

Packet 60 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/zStackLayoutMirrorsZStackPlacement`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/anyLayoutPreservesIdentityAcrossSwitches`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/anyLayoutFlattensForEachChildren`
  - Result: PASS, 1 test
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 61 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReadsLayoutValuesAndPlacesSubviews`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/customLayoutReusesCacheBetweenMeasurementAndPlacement`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sharedAnyLayoutInstancesKeepCacheScopedPerContainer`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/publicSendableLayoutOptInRunsLayoutOnFrameTailWorker`
  - Result: PASS, 1 test
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 57-61 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 57-61 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-134540-packet57-61.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-134540-77000.log`
  - Result: PASS

## Packet 62-66 Batch: ViewGraph Helpers And View Control Style Splits

Scope completed:

- Extracted ViewGraph dependency-index maintenance and runtime-registration
  restoration into explicit helpers that receive private graph state as inputs.
- Kept public TabView style declarations in `TabViewStyles.swift` and moved
  built-in style conformances plus terminal chrome helpers to
  `BuiltinTabViewStyles.swift`.
- Split `CollectionStyles.swift` into `ListStyles.swift` and
  `OutlineStyles.swift`, updating the public documentation ratchet anchors.
- Kept public button style declarations in `ButtonStyles.swift` and moved
  built-in chrome resolution plus concrete style-body views to
  `ButtonStyleChrome.swift`.
- Split `AdjustableValueControls.swift` into `Stepper.swift`, `Slider.swift`,
  and `AdjustableControlValueSupport.swift`.

Behavior preserved:

- `ViewGraph` dependency cleanup, observation/environment invalidation, and
  alias runtime-registration replay behavior remain unchanged.
- Public TabView, Button, List, Outline, Stepper, and Slider APIs remain
  unchanged.
- Tab overflow, tab raw glyph/color review, list/table style presentation,
  outline connector presentation, button focus/pressed/role chrome, stepper
  key/pointer handling, slider fractional pointer math, and accessibility roles
  remain covered by focused checks.

Packet 62 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS, 14 tests

Packet 63 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests`
  - Result: PASS, 17 tests
- `swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/literalTabOverflowUpdatesOnSIGWINCHWithoutAdditionalInput`
  - Result: PASS, 1 test
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS

Packet 64 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.CollectionSupportTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.OutlineSurfaceTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/listUsesTagsAndArrowKeys`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/listAndTableRenderEditingChromeDirectlyFromFocus`
  - Result: PASS, 1 test

Packet 65 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ButtonFocusStabilityTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter SwiftTUITests.ButtonSystemHintTests`
  - Result: PASS, 7 tests
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries

Packet 66 focused validation:

- `swiftly run swift build --target SwiftTUIViews`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/stepperDispatchesAndClamps`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sliderHandlesArrowKeysAndRendersTrack`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/doubleAdjustableControlsRenderCleanFractionalValues`
  - Result: PASS, 1 test
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/sliderTrackUsesFractionalPointerLocations`
  - Result: PASS, 1 test
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS after removing the deleted combined file from the raw-glyph
    manifest and keeping only the guardrail-detected color-state sources.

Packet 62-66 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 62-66 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-140917-packet62-66.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-140917-98579.log`
  - Result: PASS

## Packet 67-71 Batch: Layout Work Stacks, ViewNode Helpers, Borders, And Charts

Scope completed:

- Split measurement work-stack support into measurement work items, result
  stack helpers, measured-node building, and stack measurement scheduling.
- Split placement work-stack support into placement work items, result-stack
  helpers, placement request construction, and stack placement request support.
- Moved `NodeHandlers` debug snapshot helpers and `ViewNode` committed-field
  forwarding accessors out of `ViewNode.swift`, while keeping mutable
  `ViewNode` storage private.
- Moved layout-border rasterization helpers from `Rasterizer+Borders.swift` to
  `Rasterizer+LayoutBorders.swift`.
- Split `LineChartSupport.swift` into domain, rasterization, axis tick, and
  series composition support files, and updated the raw-glyph guardrail
  manifest for chart rasterization.

Behavior preserved:

- Measurement and placement traversal order, stack-safety behavior, cache reuse,
  retained placement, and custom-layout placement behavior remain unchanged.
- `ViewNode` debug snapshot output and committed-node read behavior remain
  unchanged.
- Border and gradient raster output remains covered by focused runtime tests.
- Public line chart APIs, domain calculation, rendered glyphs, axis labels,
  series composition, and legend behavior remain unchanged.

Subagent input:

- Read-only scouts recommended layout work-stack support, `ViewNode` debug and
  accessor cleanup, layout border rasterization, and line-chart support as
  high-value remaining production packets.
- The same scouts advised deferring more coupled animation and raw-mode host
  changes for a later batch.

Packet 67 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - Result: PASS, 32 tests
- `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - Result: PASS, 22 tests

Packet 68 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - Result: PASS, 32 tests
- `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - Result: PASS, 22 tests

Packet 69 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS, 2 tests
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS, 14 tests

Packet 70 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.BorderRenderingTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.BorderGradientTests`
  - Result: PASS, 5 tests

Packet 71 focused validation:

- `swiftly run swift build --target SwiftTUICharts`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LineChartDomainTests`
  - Result: PASS, 7 tests
- `swiftly run swift test --filter SwiftTUITests.LineChartRasterTests`
  - Result: PASS, 0 tests because the filter did not match the test suite name.
- `swiftly run swift test --filter LineChart`
  - Result: PASS, 32 tests across 9 suites

Packet 67-71 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 67-71 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-142822-packet67-71.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-142822-14676.log`
  - Result: PASS

Next likely focus: continue from the largest remaining production files after
the layout and chart split, with likely candidates in styling/semantic support,
remaining `ViewNode` or `ViewGraph` helpers, runtime animation support, and
smaller runtime terminal helpers selected by the next debt scan.

## Packet 72-76 Batch: Central Semantics, Pointer, RunLoop, Snapshot, And Image Models

Scope completed:

- Split semantic payload routing out of the semantic extraction driver.
- Split pointer hit-testing/focus routing and pointer hover state out of the
  mouse event dispatch file.
- Split run-loop session and support types out of `RunLoop.swift`.
- Split snapshot style/shape description helpers out of `Snapshots.swift`.
- Split image pixel/decoded-image model types out of `ImageAssetRepository`.

Behavior preserved:

- Semantic snapshots, accessibility extraction, focus regions, interaction
  routes, scroll routes, pointer dispatch, hover delivery, run-loop exit
  behavior, snapshot diagnostics, and image rendering semantics remain
  unchanged.
- Public API inventory stayed at 669 top-level public symbols.
- The public documentation ratchet stayed at 70 entries.

Subagent input:

- A read-only scout recommended the semantics, pointer, run-loop support, and
  image-model splits as low-risk central runtime/core packets, with a warning
  not to move stored `RunLoop` state or designated initializers.
- A follow-up read-only review found no runtime correctness issue. It flagged
  stale imports and widened snapshot helper visibility; the stale imports were
  removed and helper visibility was tightened where cross-file snapshot entry
  points allowed.

Packet 72 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests`
  - Result: PASS, 11 tests
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS, 8 tests
- `swiftly run swift test --filter SwiftTUITests.ScrollIndicatorDraggingTests`
  - Result: PASS, 1 test

Packet 73 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests`
  - Result: PASS, 5 tests
- `swiftly run swift test --filter SwiftTUITests.PointerHoverTests`
  - Result: PASS, 3 tests
- `swiftly run swift test --filter SwiftTUITests.ScrollIndicatorDraggingTests`
  - Result: PASS, 1 test

Packet 74 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS

Packet 75 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS, 22 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests with the existing 2 disabled tests skipped

Packet 76 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests`
  - Result: PASS, 6 tests
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS, 28 tests

Packet 72-76 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 72-76 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-145417-packet72-76.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-145417-59626.log`
  - Result: PASS

## Packet 77-81 Batch: Canvas, Diagnostics, Gradients, And RunLoop Runtime Support

Scope completed:

- Split canvas pixel-grid mode/drawing support out of the canvas drawing
  protocol/context file.
- Split canvas payload and type-erased drawing equality out of
  `CanvasDrawing.swift`.
- Split `FrameDiagnosticRecord` out of the diagnostics logger.
- Split gradient style model declarations out of `Styling.swift`.
- Split run-loop runtime support helpers out of `RunLoop.swift`.

Behavior preserved:

- Canvas full-cell and half-block rendering, canvas payload equality, diagnostic
  logging, gradient animatable/style behavior, runtime issue reporting, wake
  scheduling, termination dispatch, focus presentation, and pipeline contracts
  remain unchanged.
- The raw-glyph guardrail manifest was updated for the mechanical movement of
  half-block glyph sources from `CanvasDrawing.swift` to
  `CanvasPixelGridDrawing.swift`.
- Public API inventory stayed at 669 top-level public symbols.
- The public documentation ratchet stayed at 70 entries.

Subagent input:

- Read-only scouts recommended the canvas pixel grid, canvas payload, frame
  diagnostic record, gradient style, and run-loop support splits as the highest
  value remaining central runtime/core packets with low behavior risk.
- The subagent review cleanup from the previous batch was included before this
  gate.

Packet 77 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.CanvasViewTests`
  - Result: PASS, 17 tests
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS after updating the raw-glyph source manifest for the moved
    half-block glyph source file.

Packet 78 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.CanvasViewTests`
  - Result: PASS, 17 tests

Packet 79 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS, 52 tests

Packet 80 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter gradient`
  - Result: PASS, 6 tests
- `swiftly run swift test --filter RadialGradient`
  - Result: PASS, 8 tests

Packet 81 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminationRequestTests`
  - Result: PASS, 4 tests
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS, 9 tests
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS, 10 tests with the existing 2 disabled tests skipped

Packet 77-81 shared pre-gate validation:

- `git diff --check`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS, 669 top-level public symbols. The script emitted the
    existing SwiftPM synthetic package-test symbol graph warning and ignored it.

Packet 77-81 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-150340-packet77-81.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-150340-86962.log`
  - Result: PASS

## Packet 82-86 Batch: Stack Layout Decomposition

Scope completed:

- Split stack axis proposal and main/cross dimension helpers into
  `LayoutEngine+StackAxisSupport.swift`.
- Split lazy stack child sourcing, allocation snapshots, and visible-range
  lookup into `LayoutEngine+StackLazyAllocation.swift`.
- Split stack spacing and cross-axis alignment metrics into
  `LayoutEngine+StackMetrics.swift`.
- Split extra-space distribution and priority-aware compression into
  `LayoutEngine+StackSpaceAllocation.swift`.
- Split minimum-size derivation, flexible-subtree detection, and stack
  remeasurement no-op detection into `LayoutEngine+StackMinimums.swift`.
- Removed the now-empty `LayoutEngine+Stack.swift` placeholder after focused
  build/test checks proved SwiftPM did not need it.

Behavior preserved:

- Stack proposal axes, spacing, alignment metrics, lazy stack visible ranges,
  spacer/flexible child expansion, priority compression, stack minimum sizing,
  retained placement behavior, and diagnostics snapshots remain unchanged.
- No public SwiftUI-like API changes were introduced.

Subagent input:

- Read-only scouts re-ranked the constrained central runtime/core surface and
  identified stack axis/lazy helpers plus stack flexibility/minimum sizing as
  the highest-value primary-core packets after the 72-81 batches.

Packet 82-86 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 82-86 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-153444-packet82-86.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-153444-16744.log`
  - Result: PASS

## Packet 87-91 Batch: Runtime Diagnostics, Style Transport, Frame Tail Models, And POSIX Control

Scope completed:

- Split diagnostics TSV header and row formatting out of
  `FrameDiagnosticsLogger.swift` into
  `FrameDiagnosticsTSVFormatting.swift`.
- Split terminal render-style JSON transport parsing/serialization out of
  `TerminalRenderStyleCodec.swift` into
  `TerminalStyleTransportJSON.swift`.
- Split terminal render-style Base64 transport encoding/decoding out of
  `TerminalRenderStyleCodec.swift` into
  `TerminalStyleTransportBase64.swift`.
- Split frame-tail retained state, typed tail phase models, worker result,
  generation sequencer, and render-suspension hooks into
  `FrameTailModels.swift`.
- Split the POSIX terminal controller protocol and implementation out of
  `TerminalHost.swift` into `TerminalPOSIXController.swift`.

Behavior preserved:

- Diagnostics TSV columns and placeholders, style transport round-trips,
  invalid transport rejection, retained frame-tail input, async/sync tail
  behavior, worker timing diagnostics, terminal descriptor reads/writes,
  raw-mode attribute calls, file-status flag handling, and cell-pixel metrics
  remain unchanged.
- The frame-tail model extraction widened a few helper model declarations only
  to module-internal visibility so cross-file runtime code could keep using
  them; no public API surface was added.

Subagent input:

- The runtime scout ranked diagnostics formatting, render-style transport,
  frame-tail models, and terminal POSIX control as safe high-value packets.
  Terminal host presentation lifecycle work was left for a later decision
  because it would require wider private-state movement.

Packet 87-91 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 87-91 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-154406-packet87-91.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-154406-32556.log`
  - Result: PASS

## Packet 92-96 Batch: Core Styling Decomposition

Scope completed:

- Split shape-style roles, protocols, type erasure, and opacity erasure into
  `ShapeStyles.swift`.
- Split theme and terminal render-style state into `Theme.swift`.
- Split stroke/border helpers into `StrokeStyles.swift`.
- Split shape draw payload models into `ShapePayload.swift`.
- Split resolved text style and color resolution helpers into
  `ResolvedTextStyle.swift`.
- Removed the now-empty `Styling.swift` source and updated public-surface policy
  paths for the moved `ShapeStyle` declarations.

Behavior preserved:

- Shape-style erasure, theme overrides, terminal render-style codec behavior,
  border defaults, shape payloads, resolved text style, and public API inventory
  remained unchanged.

Packet 92-96 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- Focused style/rendering tests for color/gradient/tile/border/radial-gradient,
  terminal render-style codec, gradient animation integration, and theme
  override behavior
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 92-96 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-155625-packet92-96.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-155625-58962.log`
  - Result: PASS

## Packet 97-101 Batch: Draw Metadata Decomposition

Scope completed:

- Split `DrawPayload` into `DrawPayload.swift`.
- Split authored text-style metadata into `TextStyle.swift`.
- Split resolved draw metadata and merge helpers into `DrawMetadata.swift`.
- Split type-erased selection identity into `SelectionTag.swift`.
- Split list payload models into `ListPayload.swift`.
- Deleted the old `RenderMetadataTypes.swift` source and updated the
  accessibility color-state manifest for the moved list payload file.

Behavior preserved:

- Draw payload equality, text style merging, draw metadata propagation,
  selection tag matching, list row/section separator behavior, table/list
  payload use, accessibility manifest coverage, and public API inventory
  remained unchanged.

Packet 97-101 focused validation:

- `swiftly run swift build --target SwiftTUICore`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `swiftly run swift test --filter SwiftTUITests.CollectionSupportTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/additionalInlineTextStylesMapIntoTypedDrawMetadata`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/list`
  - Result: PASS
- `swiftly run swift test --filter table`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 97-101 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-160339-packet97-101.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-160339-76975.log`
  - Result: PASS

## Packet 102-106 Batch: Scene, Hosted Surface, And Accessibility Runtime Decomposition

Scope completed:

- Split scene builder artifacts and `AnyScene` into `SceneBuilder.swift`.
- Split window scene configuration and root host layout support into
  `WindowSceneConfiguration.swift`.
- Split selected-window scene collection and runner plumbing into
  `WindowSceneSelection.swift`.
- Split hosted raster surface state and waiter models into
  `HostedRasterSurfaceState.swift`.
- Split linear accessibility output sanitization into
  `AccessibilityTextSanitizer.swift`.

Behavior preserved:

- Scene-builder ordering and branch behavior, default scene selection, hosted
  scene lookup, full-canvas window layout, focus-scope behavior, hosted frame
  sequence/waiter resumption, damage metrics, clipboard writes, accessibility
  linear output, and public API inventory remained unchanged.

Packet 102-106 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_stable_doc_source_paths.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `swiftly run swift test --filter SwiftTUITests.SceneBuilderBackboneTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.SceneManifestTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AppRuntimeTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests`
  - Result: PASS
- `swiftly run swift test --filter HostedSurfaceRegressionTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftUIHostAccessibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.JSONFrameRendererTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 102-106 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-161124-packet102-106.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-161124-95992.log`
  - Result: PASS

## Packet 107-111 Batch: Renderer, Run-Loop, Animation, ViewGraph, And Frame-Tail Support

Scope completed:

- Split completed-frame candidate construction, preview, drop, and commit
  coordination into `DefaultRenderer+CompletedFrameCandidates.swift`.
- Split render-driver support types and small shared helpers into
  `RunLoop+RenderDriverSupport.swift`.
- Split animation placed-tree capture and matched-geometry lookup collection
  into `AnimationPlacedTreeCapture.swift`.
- Split ViewGraph debug snapshot declarations into
  `ViewGraphDebugSnapshots.swift` and updated the source-level totality test to
  follow the moved type.
- Split frame-tail worker queueing/timing/cancellation-start wrappers into
  `FrameTailWorkerExecutor.swift`.

Behavior preserved:

- Completed-frame preview purity, completed-frame drop classification, ordered
  commit side effects, run-loop sync/async driver parity, render-intent
  diagnostics, gesture deadline drains, matched-geometry placed-tree capture,
  ViewGraph checkpoint/debug totality, frame-tail retained state serialization,
  layout worker cancellation, and worker timing diagnostics remained unchanged.

Packet 107-111 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_stable_doc_source_paths.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.RenderDriverCharacterizationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 107-111 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-162436-packet107-111.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-162436-14895.log`
  - Result: PASS

Review:

- A read-only review subagent found no material issues in packet 107-111. The
  only residual confidence gap called out before completion was the full repo
  gate, which passed.

## Packet 112-116 Batch: Runtime Subsystem, Resolve Context, Acquisition, Animation, And ViewGraph Support

Scope completed:

- Split renderer subsystem/debug support declarations into
  `DefaultRendererRuntimeSubsystems.swift`.
- Split run-loop reset-focus, resolve-context assembly, and proposal derivation
  into `RunLoop+ResolveContext.swift`.
- Split async frame-acquisition outcome reporting, cancelled/dropped logging
  support, and completed-frame drop blockers into
  `RunLoop+FrameAcquisitionOutcome.swift`.
- Split animation checkpoint and debug snapshot type declarations into
  `AnimationControllerStateSnapshots.swift`.
- Split ViewGraph node checkpoint map construction/restoration into
  `ViewGraphCheckpointing.swift`.

Behavior preserved:

- Runtime subsystem snapshots, presentation portal content-root extraction,
  Escape dismiss-stack storage, resolve environment values, terminal size and
  capability propagation, runtime motion/no-progress policy, reset-focus
  invalidation, async skipped-frame diagnostics, cancelled-intent replay,
  focus/scroll/animation drop blockers, animation frame-head checkpoint
  behavior, and ViewGraph checkpoint/debug totality remained unchanged.

Packet 112-116 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_stable_doc_source_paths.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `swiftly run swift test --filter SwiftTUITests.ResolvePurityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DirtyTrackingCoherenceTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AppRuntimeTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.EnvironmentRuntimeStateTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.RenderDriverCharacterizationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 112-116 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-163254-packet112-116.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-163254-34322.log`
  - Result: PASS

Review:

- A read-only scout reviewed the packet 112-116 split boundaries and agreed
  the active split shape is the safe low-risk boundary. It called out that the
  new files must be included with the batch, which the active worktree does.

## Packet 117-121 Batch: Post-Commit, Diagnostics, Animation Diffing, ViewGraph, And Snapshots

Scope completed:

- Split run-loop post-commit support helpers into
  `RunLoop+PostCommitSupport.swift`.
- Split committed and zero-artifact frame diagnostic record assembly into
  `RunLoop+FrameDiagnosticRecordAssembly.swift`.
- Split low-risk animation resolved-tree identity and matched-geometry
  planning into `AnimationResolvedTreeDiffing.swift`.
- Split ViewGraph invalidation and dirty-queue planning into
  `ViewGraphInvalidationPlanning.swift`.
- Split snapshot renderer frame diagnostics and scheduled-frame formatting into
  `SnapshotRenderer+Diagnostics.swift`.

Behavior preserved:

- Focus-sync presentation damage behavior, presentation timing diagnostics,
  post-action invalidations, repeat animation wake scheduling, diagnostics TSV
  field values/order, matched-geometry consumed-key semantics, ViewGraph dirty
  and environment invalidation behavior, and snapshot renderer output remained
  unchanged.

Packet 117-121 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_stable_doc_source_paths.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.FocusTransitionTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DirtyTrackingCoherenceTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUIViewsTests.DependencyTrackingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS
- `git diff --check`
  - Result: PASS

Packet 117-121 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-164649-packet117-121.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-164649-55780.log`
  - Result: PASS

Review:

- A read-only review subagent found no material runtime/core issues. It
  confirmed diagnostics field ordering/values, matched-geometry planning,
  ViewGraph dirty/invalidation behavior, and snapshot renderer public members
  remained stable.

## Packet 122-126 Batch: Frame-Tail, Event Pump, Runtime Issues, Diagnostics, And Lifecycle Collection

Scope completed:

- Split frame-tail inline layout/raster stage mechanics into
  `FrameTailRenderer+InlineStages.swift`.
- Split run-loop event-pump support types and pointer coalescing support into
  `RunLoop+EventPumpSupport.swift`.
- Split run-loop runtime issue reporting into
  `RunLoop+RuntimeIssueReporting.swift`.
- Split committed-frame diagnostics mapping and timing helpers into
  `CommittedFrameDiagnosticsBuilder.swift`.
- Split ViewGraph lifecycle event collection helpers into
  `ViewGraphLifecycleEventCollection.swift`.

Behavior preserved:

- Layout/raster worker policy, retained baseline placement, animation overlay
  application, pointer event coalescing, deadline wake scheduling, runtime
  issue de-duplication, committed-frame diagnostics fields, lifecycle event
  ordering, transparent lifecycle owner behavior, and checkpoint totality
  remained unchanged.

Packet 122-126 focused validation:

- `swiftly run swift build --target SwiftTUIRuntime`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.ToolbarTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.BoundedReconciliationTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests`
  - Result: PASS
- `swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests`
  - Result: PASS
- `./Scripts/check_public_surface_policies.sh`
  - Result: PASS
- `./Scripts/check_public_documentation_ratchet.sh`
  - Result: PASS
- `./Scripts/check_accessibility_guardrails.sh`
  - Result: PASS
- `./Scripts/check_stable_doc_source_paths.sh`
  - Result: PASS
- `./Scripts/generate_public_api_inventory.sh --check`
  - Result: PASS; 669 top-level public symbols
- `git diff --check`
  - Result: PASS

Packet 122-126 batch validation:

- `bun run test`
  - User tee log: `/tmp/swift-tui-test-gate-20260518-170129-packet122-126.log`
  - Runner log: `/tmp/swift-tui-test-gate-20260518-170129-78413.log`
  - Result: PASS

Review:

- A read-only scout ranked the packet boundaries and warned not to change
  async cancellation, completed-frame drop eligibility, lifecycle ordering, or
  retained-layout baseline identity.
- A read-only review subagent found no material issues in the scoped runtime
  and core files. It independently ran build, format lint, diff check, and the
  highest-risk focused tests for this batch.

Next scheduled focus: stop after this batch as requested. The migration plan
now schedules five future five-packet central runtime/core batches from
127-151 for a later continuation.

## Failed Attempts

- Packet 51-53 first full `bun run test` attempt failed in the full
  `SwiftTUITests` runtime target with three
  `AsyncLifecycleGenerationTests` readiness timeouts. The failed gate log was
  `/tmp/swift-tui-test-gate-20260518-130832-8813.log`.
- `swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests`
  passed immediately after, and the final full repo gate passed at
  `/tmp/swift-tui-test-gate-20260518-131048-20030.log`.
- Packet 23 first full `bun run test` attempt failed in the full
  `SwiftTUITests` runtime suite with three `AsyncLifecycleGenerationTests`
  readiness timeouts. The failed gate log was
  `/tmp/swift-tui-test-gate-20260518-054640-45870.log`.
- The failed suite passed immediately in isolation, the full `SwiftTUITests`
  target then passed, and the final full repo gate passed at
  `/tmp/swift-tui-test-gate-20260518-054930-58630.log`.
- Packet 27 final-candidate `bun run test` attempt failed once in
  `SwiftTUITerminalTests` on `running cat over a large file stays within the
  byte budget` with a timeout. The failed gate log was
  `/tmp/swift-tui-test-gate-20260518-062300-55078.log`.
- `swiftly run swift test --filter SwiftTUITerminalTests` passed immediately
  after, and the final full repo gate passed at
  `/tmp/swift-tui-test-gate-20260518-065523-66925.log`.
- Packet 29 first full `bun run test` attempt failed in the full
  `SwiftTUITests` runtime target with two timeout issues:
  `HostedSceneSessionTests/hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents`
  and
  `AsyncFrameTailRenderingTests/blockedBuiltInLayoutQueuesInputWithoutCommittingAhead`.
  The failed gate log was
  `/tmp/swift-tui-test-gate-20260518-090939-98987.log`.
- Both failed tests passed immediately in isolation, the full `SwiftTUITests`
  target passed, and the final full repo gate passed at
  `/tmp/swift-tui-test-gate-20260518-093634-11184.log`.
- Packet 31 first full `SwiftTUITests` attempt failed once in
  `AppRuntimeTests/optional FocusState equals bindings track runtime focus changes across controls`
  when the final frame still showed the first focused field. The specific test
  passed immediately in isolation, and the full `SwiftTUITests` target passed
  on rerun with 1309 tests.

## Known Risks

- `TerminalHost.swift`, `TerminalPresentation.swift`,
  `TerminalImageRendering.swift`, `FrameTailRenderer.swift`, and
  `RunLoop+Rendering.swift` are large and heavily tested shared runtime files.
- Current checkout path is `/Users/adamz/Developer/repos/swift-tui`; the older
  `swift-tui.humanize` path-dependency warning no longer applies to this run.
- Swift incremental build artifacts may become stale; clean build state when
  unexplained crashes or impossible diagnostics appear.
- Rendering fixtures should not change unless an intentional rendering behavior
  change is separately approved.
