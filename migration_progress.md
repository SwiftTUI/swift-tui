# Production Code Humanization Progress

## Current Status

Started repo-wide production-code humanization on branch `humanize`.

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

## Next Slice

Packet 19: late preference reconciliation extraction. Read-only runtime review
ranked this as the next safest high-value central rendering split after the
input support checkpoint: move late-preference policy, sync/async reconciliation
loop types, and runtime issue helpers out of `DefaultRenderer` into a
same-subsystem helper without moving queued-cancellation or prepared-graph
materialization.

Expected owned files pending local discovery:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/LatePreferenceReconciliation.swift`

Validation:

- `swiftly run swift build`
- `swiftly run swift test --filter SwiftTUITests.BoundedReconciliationTests`
- `swiftly run swift test --filter SwiftTUITests.ToolbarTests`
- `swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests`
- `swiftly run swift test --filter SwiftTUITests.ViewThatFitsSurfaceTests`
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- `bun run test`

## Failed Attempts

None.

## Known Risks

- `TerminalHost.swift`, `TerminalPresentation.swift`,
  `TerminalImageRendering.swift`, `FrameTailRenderer.swift`, and
  `RunLoop+Rendering.swift` are large and heavily tested shared runtime files.
- The checkout path ends in `swift-tui.humanize`; repo docs warn that example
  path dependencies prefer a final path component of `swift-tui`. The baseline
  gate still passed in this checkout.
- Swift incremental build artifacts may become stale; clean build state when
  unexplained crashes or impossible diagnostics appear.
- Rendering fixtures should not change unless an intentional rendering behavior
  change is separately approved.
