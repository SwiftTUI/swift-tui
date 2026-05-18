# PR Handoff

## Summary

Work in progress: production-code humanization for SwiftTUI, starting with
terminal rendering infrastructure. The goal is approachability and
maintainability while preserving behavior and public API.

## Review First

Packet 1 should be reviewed first:

- `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`

Packet 2 should be reviewed as a same-area continuation:

- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationState.swift`

Packet 3 should be reviewed as the first frame-tail continuation:

- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailPresentationDamage.swift`

Packet 4 should be reviewed as a mechanical core-artifact file split:

- `Sources/SwiftTUICore/Commit/FrameArtifacts.swift`
- `Sources/SwiftTUICore/Commit/FrameDiagnostics.swift`
- `Sources/SwiftTUICore/Commit/FrameContext.swift`

Packet 5 should be reviewed as runtime acquisition control-flow extraction:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`

Packet 6 should be reviewed as runtime presentation handoff extraction:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Presentation.swift`

Packet 7 should be reviewed as Kitty image command extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalImageRendering.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalImageKittyRendering.swift`

Packet 8 should be reviewed as Sixel image command and sampling extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalImageRendering.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalImageSixelRendering.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalImageSampling.swift`

Packet 9 should be reviewed as fallback image overlay extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalImageRendering.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalImageFallbackRendering.swift`
- `Scripts/lib/accessibility_raw_glyph_sources.txt`

Packet 10 should be reviewed as terminal-host capability probing extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalHostCapabilities.swift`

Packet 11 should be reviewed as terminal-host sequence and cleanup extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalHostEscapeSequences.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalPlatformIO.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalProcessExitCleanup.swift`

Packet 12 should be reviewed as terminal presentation planning extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalPresentation.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalPresentationPlanning.swift`

Packet 13 should be reviewed as animation tree-query extraction:

- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationTreeQueries.swift`

Packet 14 should be reviewed as animation transition-overlay extraction:

- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationTransitionOverlay.swift`

Packet 15 should be reviewed as animation property-value application extraction:

- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationPropertyValueApplication.swift`

Packet 16 should be reviewed as completed-frame artifact support extraction:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/CompletedFrameArtifactBuilder.swift`
- `Sources/SwiftTUIRuntime/Rendering/CompletedFrameCandidate.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`

Packet 17 should be reviewed as run-loop frame diagnostics extraction:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnostics.swift`

Packet 18 should be reviewed as input support type extraction:

- `Sources/SwiftTUIRuntime/Input/InputReader.swift`
- `Sources/SwiftTUIRuntime/Input/InputReading.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputEvents.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputCapabilities.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputCoalescing.swift`

Packet 19 should be reviewed as late-preference reconciliation extraction:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/LatePreferenceReconciliation.swift`

Packet 20 should be reviewed as frame-head draft transaction extraction:

- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameHeadDraftTransaction.swift`

Packet 21 should be reviewed as run-loop focus-sync extraction:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FocusSync.swift`

Packet 22 should be reviewed as run-loop frame acquisition extraction:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift`

Packet 23 should be reviewed as renderer commit path consolidation:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/CompletedFrameArtifactBuilder.swift`
- `Sources/SwiftTUIRuntime/Rendering/CommittedFrameArtifactBuilder.swift`

Packet 24 should be reviewed as terminal raw-mode session extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalRawModeSession.swift`

## What Must Stay Stable

- Public SwiftUI-like APIs.
- Terminal rendering output and host lifecycle behavior.
- Rendering pipeline phase contracts and frame artifacts.
- Existing tests, fixtures, and policy checks.
- Example apps.

## Testing

Baseline passed before production-code edits:

```bash
bun run test
```

Full log:

```text
/tmp/swift-tui-test-gate-20260518-023359-77501.log
```

Packet 1 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-024018-4112.log
```

Packet 2 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-024705-20556.log
```

Packet 3 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests
swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-025321-47448.log
```

Packet 4 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests
swiftly run swift test --filter SwiftTUICoreTests.LayoutEngineTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-025909-68455.log
```

Packet 5 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-030508-85414.log
```

Packet 6 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.JSONFrameRendererTests
swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-031025-5025.log
```

Packet 7 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-031747-26286.log
```

Packet 8 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-032834-69653.log
```

Packet 9 validation passed:

```bash
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.ImageSurfaceTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
./Scripts/check_accessibility_guardrails.sh
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-033507-95996.log
```

Packet 10 validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests
swiftly run swift test --filter SwiftTUITests.CellPixelMetricsRefreshTests
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-034357-16939.log
```

Packet 11 validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalHost
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter WebSurfaceTransportTests
swiftly run swift test --filter SwiftTUITerminalTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-040917-13192.log
```

Packet 12 validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-041849-32895.log
```

Packet 13 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests
swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests
swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-042708-50577.log
```

Packet 14 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-043316-68540.log
```

Packet 15 validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests
swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests
swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests
swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter AnimationController
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-044249-87972.log
```

Packet 16 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropDroppabilityTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-045323-8675.log
```

Packet 17 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-050134-20208.log
```

Packet 18 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InputParserModifierTests
swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-051003-41466.log
```

Packet 19 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.BoundedReconciliationTests
swiftly run swift test --filter SwiftTUITests.ToolbarTests
swiftly run swift test --filter SwiftTUITests.LayoutDependentContainerHardeningTests
swiftly run swift test --filter SwiftTUITests.ViewThatFitsSurfaceTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-051542-56825.log
```

Packet 20 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-052405-85109.log
```

Packet 21 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AppRuntimeTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUICoreTests.FocusTrackerTests
swiftly run swift test --filter SwiftTUICoreTests.LocalScrollPositionRegistryTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-053009-4450.log
```

Packet 22 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests
swiftly run swift test --filter SwiftTUITests.PipelineDriverParityTests
swiftly run swift test --filter SwiftTUITests.RenderDriverInstrumentationCostTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-053644-24624.log
```

Packet 23 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.DirtyTrackingCoherenceTests
swiftly run swift test --filter SwiftTUITests.RenderPipelineStructureTests
swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests
swiftly run swift test --filter SwiftTUITests.TimingDiagnosticsTests
swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests
swiftly run swift test --filter SwiftTUITests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-054930-58630.log
```

Packet 24 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TerminalHostProcessExitCleanupTests
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalCapabilityProfileApplyingTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-055729-85446.log
```

One earlier Packet 23 full-gate attempt failed in `SwiftTUITests` with three
`AsyncLifecycleGenerationTests` readiness timeouts. The suite passed in
isolation immediately after, the full `SwiftTUITests` target passed, and the
full repo gate passed on rerun. Failed gate log:

```text
/tmp/swift-tui-test-gate-20260518-054640-45870.log
```

## Risks

The first focus area is central runtime infrastructure. Review should be strict
about behavioral drift, output drift, concurrency changes, and fixture churn.

## Rollback

Each packet should be independently revertible. Packets 1 and 2 are same-area
terminal presentation changes. Packet 3 is a frame-tail damage-resolution split.
Packet 4 is a core artifact file split. Packet 5 is a runtime acquisition
control-flow extraction. Packet 6 is a runtime presentation handoff extraction.
Packet 7 is a Kitty image command extraction. Packet 8 is a Sixel image command
and shared sampling extraction. Packet 9 is fallback image overlay extraction.
Packet 10 is terminal-host capability probing extraction. Packet 11 is
terminal-host escape sequence, platform I/O shim, and process-exit cleanup
extraction. Packet 12 is terminal presentation planning extraction.
Packet 13 is animation tree-query extraction.
Packet 14 is animation transition-overlay extraction.
Packet 15 is animation property-value application extraction.
Packet 16 is completed-frame artifact support extraction.
Packet 17 is run-loop frame diagnostics extraction.
Packet 18 is input reader pure support type extraction.
Packet 19 is late-preference reconciliation extraction.
Packet 20 is frame-head draft transaction extraction.
Packet 21 is run-loop focus-sync convergence extraction.
Packet 22 is run-loop frame acquisition extraction.
Packet 23 is renderer commit path consolidation.
Packet 24 is terminal raw-mode session extraction.
Revert newest-first if a terminal output, raster reuse, frame-tail,
diagnostics, async-cancellation, cursor-focus, JSON/accessibility output,
image-protocol, fallback image, raw-glyph manifest, SGR-pixels policy, cell
pixel metrics refresh, input precision propagation, raw-mode cleanup,
WebSurface full-repaint byte accounting, presentation damage planning, Kitty
graphics replay planning, matched-geometry traversal, removal subtree lookup,
removal overlay transient marking, removal offset composition, removal
reinjection ordering, property animation writeback, flexible-frame dimension
slot preservation, shape-style destination routing, completed-frame preview
side-effect isolation, completed-frame drop classification, diagnostics timing
fields, skipped-frame diagnostic record, render-suspension input counting, or
public input-event/protocol surface, late-preference pass budget, toolbar
runtime issue, layout-dependent realization, frame-head checkpoint restore,
draft commit/discard, one-shot abort precondition, focus-sync rerender budget,
focused-value propagation, default-focus request, scroll-position convergence,
focus-sync lifecycle carry-forward, queued-tail cancellation, dropped-completed
frame diagnostics, cancelled-intent replay, async-no-cancel, async-no-drop,
committed-frame artifact diagnostics, one-shot worker timing, prepared-state
materialization, committed scroll geometry, retained baseline placement, or
presentation dismiss-stack, raw-mode saved state, process-exit cleanup
registration, terminal control-mode transition, enable-failure rollback, or
pointer-hover cleanup reset regression appears.

## AI Assistance Disclosure

AI assistance was used for planning, analysis, and drafting/refactoring portions
of this change. A human contributor should review all changed lines, validate
behavior, and run the checks listed in this handoff.
