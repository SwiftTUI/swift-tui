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

Packet 25 should be reviewed as input event decoding extraction:

- `Sources/SwiftTUIRuntime/Input/InputReader.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputEventDecoding.swift`

Packet 26 should be reviewed as terminal input parser file split:

- `Sources/SwiftTUIRuntime/Input/InputReader.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputParser.swift`

Packet 27 should be reviewed as terminal input descriptor-reading extraction:

- `Sources/SwiftTUIRuntime/Input/InputReader.swift`
- `Sources/SwiftTUIRuntime/Input/TerminalInputStreamReading.swift`
- `Tests/SwiftTUITests/InputBatchingResponsivenessTests.swift`

Packet 28 should be reviewed as placed animation overlay sampling extraction:

- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/PlacedAnimationOverlaySampling.swift`

Packet 29 should be reviewed as DefaultRenderer frame-tail coordination
extraction:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameTailCoordinator.swift`

Packet 30 should be reviewed as animation completion scheduling extraction:

- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationCompletionScheduling.swift`

Packet 31 should be reviewed as DefaultRenderer frame-head coordination
extraction:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift`

Previous Packet 67-71 should be reviewed as the Core layout/raster and Charts
support decomposition:

- `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkStack.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkItems.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementResultStack.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+MeasuredNodeBuilding.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackMeasurementScheduling.swift`
- `Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkStack.swift`
- `Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkItems.swift`
- `Sources/SwiftTUICore/Place/LayoutEngine+PlacementResultStack.swift`
- `Sources/SwiftTUICore/Place/LayoutEngine+PlacementRequests.swift`
- `Sources/SwiftTUICore/Place/LayoutEngine+StackPlacementRequests.swift`
- `Sources/SwiftTUICore/Resolve/ViewNode.swift`
- `Sources/SwiftTUICore/Resolve/ViewNodeHandlerDebugSnapshots.swift`
- `Sources/SwiftTUICore/Resolve/ViewNodeCommittedAccessors.swift`
- `Sources/SwiftTUICore/Raster/Rasterizer+Borders.swift`
- `Sources/SwiftTUICore/Raster/Rasterizer+LayoutBorders.swift`
- `Sources/SwiftTUICharts/LineChartSupport.swift`
- `Sources/SwiftTUICharts/LineChartDomainSupport.swift`
- `Sources/SwiftTUICharts/LineChartRasterization.swift`
- `Sources/SwiftTUICharts/LineChartAxisTickSupport.swift`
- `Sources/SwiftTUICharts/LineChartSeriesComposition.swift`

Previous Packet 72-81 should be reviewed as the constrained central
runtime/core decomposition:

- `Sources/SwiftTUICore/Semantics/Semantics.swift`
- `Sources/SwiftTUICore/Semantics/SemanticPayloadRouting.swift`
- `Sources/SwiftTUICore/Pipeline/Snapshots.swift`
- `Sources/SwiftTUICore/Pipeline/SnapshotRenderer+StyleDescriptions.swift`
- `Sources/SwiftTUICore/Draw/CanvasDrawing.swift`
- `Sources/SwiftTUICore/Draw/CanvasPixelGridDrawing.swift`
- `Sources/SwiftTUICore/Draw/CanvasPayload.swift`
- `Sources/SwiftTUICore/Styling/Styling.swift`
- `Sources/SwiftTUICore/Styling/GradientStyles.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoopSessionTypes.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHandling.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHitTesting.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHover.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeSupport.swift`
- `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsLogger.swift`
- `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticRecord.swift`
- `Sources/SwiftTUIRuntime/Terminal/ImageAssetRepository.swift`
- `Sources/SwiftTUIRuntime/Terminal/ImageAssetModels.swift`
- `Scripts/lib/accessibility_raw_glyph_sources.txt`

Previous Packet 82-91 should be reviewed as the next constrained central
runtime/core decomposition:

- `Sources/SwiftTUICore/Measure/LayoutEngine+Stack.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackAxisSupport.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackLazyAllocation.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackMetrics.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackSpaceAllocation.swift`
- `Sources/SwiftTUICore/Measure/LayoutEngine+StackMinimums.swift`
- `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsLogger.swift`
- `Sources/SwiftTUIRuntime/Diagnostics/FrameDiagnosticsTSVFormatting.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalStyleTransportJSON.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalStyleTransportBase64.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailModels.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalPOSIXController.swift`

Review notes for previous packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols.
- Subagent scouts ranked stack axis/lazy helpers, stack flexibility/minimum
  sizing, diagnostics TSV formatting, render-style transport, frame-tail models,
  and terminal POSIX control as safe high-value central runtime/core packets.
- `LayoutEngine+Stack.swift` is deleted because it became an empty placeholder;
  the stack implementation now lives in the five focused `LayoutEngine+Stack*`
  files listed above.
- The frame-tail model extraction widened helper declarations only to
  module-internal visibility so cross-file runtime code could keep using them;
  no public API surface was added.
- Terminal host presentation lifecycle movement was intentionally deferred
  because it would require broader private-state movement than this batch
  needed.

Latest Packet 122-126 should be reviewed as the newest constrained central
runtime/core decomposition:

- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer+InlineStages.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPump.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventPumpSupport.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeSupport.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RuntimeIssueReporting.swift`
- `Sources/SwiftTUIRuntime/Rendering/CommittedFrameArtifactBuilder.swift`
- `Sources/SwiftTUIRuntime/Rendering/CommittedFrameDiagnosticsBuilder.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphLifecycleEventCollection.swift`

Review notes for latest packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols.
- Frame-tail inline stages, event-pump support, runtime issue reporting,
  committed-frame diagnostics assembly, and ViewGraph lifecycle event
  collection moved into focused files while preserving behavior.
- The packet intentionally avoided async cancellation policy, completed-frame
  drop eligibility, lifecycle ordering, and retained-layout baseline changes.
- A read-only review subagent found no material runtime/core issues and
  independently ran focused checks for the batch.
- The next five scheduled five-packet batches now run through packet 151 for a
  later continuation.

Previous Packet 117-121 should be reviewed as the prior constrained central
runtime/core decomposition:

- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PostCommitSupport.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnostics.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnosticRecordAssembly.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationResolvedTreeDiffing.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphInvalidationPlanning.swift`
- `Sources/SwiftTUICore/Pipeline/Snapshots.swift`
- `Sources/SwiftTUICore/Pipeline/SnapshotRenderer+Diagnostics.swift`

Review notes for previous packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols.
- Post-commit presentation support, frame diagnostic record assembly,
  animation identity/matched-geometry diff planning, ViewGraph invalidation
  planning, and snapshot diagnostics formatting moved into focused files while
  preserving behavior.
- The full removal-overlay animation loop was intentionally deferred because it
  combines tree lookup, opacity sampling, batch release, and placed snapshot
  lookup in one behavior-heavy path.
- A read-only review subagent found no material runtime/core issues.

Previous Packet 112-116 should be reviewed as the prior constrained central
runtime/core decomposition:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/DefaultRendererRuntimeSubsystems.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+ResolveContext.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisitionOutcome.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationControllerStateSnapshots.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphCheckpointing.swift`

Review notes for previous packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols.
- Renderer subsystem/debug declarations, run-loop resolve-context assembly,
  frame-acquisition outcome reporting, animation snapshot type declarations,
  and ViewGraph node checkpoint map construction/restoration moved into
  focused files while preserving behavior.
- A read-only scout agreed the packet split boundaries were low-risk and called
  out only that the newly added files must be included with the batch.
- The next five scheduled five-packet batches now run through packet 141 before
  the next re-rank.

Previous Packet 107-111 should be reviewed as the prior constrained central
runtime/core decomposition:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`
- `Sources/SwiftTUIRuntime/Rendering/DefaultRenderer+CompletedFrameCandidates.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+RenderDriverSupport.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationPlacedTreeCapture.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphDebugSnapshots.swift`
- `Tests/SwiftTUICoreTests/Graph/ViewGraphCheckpointTotalityTests.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailWorkerExecutor.swift`
- `Tests/SwiftTUITests/RenderPipelineStructureTests.swift`

Review notes for previous packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols.
- Completed-frame candidate preview/drop/commit coordination moved out of the
  public renderer entry file into a focused extension. The existing
  source-structure guard was updated to inspect the moved helper body instead
  of weakening the assertion.
- Run-loop render-driver support, animation placed-tree capture, ViewGraph
  debug snapshot declarations, and frame-tail worker execution/timing moved into
  focused files while preserving behavior.
- A read-only review subagent found no material issues in packets 107-111.

Previous Packet 92-106 should be reviewed as the prior constrained central
runtime/core decomposition:

- `Sources/SwiftTUICore/Styling/Styling.swift`
- `Sources/SwiftTUICore/Styling/ShapeStyles.swift`
- `Sources/SwiftTUICore/Styling/Theme.swift`
- `Sources/SwiftTUICore/Styling/StrokeStyles.swift`
- `Sources/SwiftTUICore/Styling/ShapePayload.swift`
- `Sources/SwiftTUICore/Styling/ResolvedTextStyle.swift`
- `Sources/SwiftTUICore/Draw/RenderMetadataTypes.swift`
- `Sources/SwiftTUICore/Draw/DrawPayload.swift`
- `Sources/SwiftTUICore/Draw/TextStyle.swift`
- `Sources/SwiftTUICore/Draw/DrawMetadata.swift`
- `Sources/SwiftTUICore/Draw/SelectionTag.swift`
- `Sources/SwiftTUICore/Draw/ListPayload.swift`
- `Sources/SwiftTUIRuntime/Scenes/App.swift`
- `Sources/SwiftTUIRuntime/Scenes/SceneBuilder.swift`
- `Sources/SwiftTUIRuntime/Scenes/WindowSceneConfiguration.swift`
- `Sources/SwiftTUIRuntime/Scenes/WindowSceneSelection.swift`
- `Sources/SwiftTUIRuntime/Scenes/HostedRasterSurface.swift`
- `Sources/SwiftTUIRuntime/Scenes/HostedRasterSurfaceState.swift`
- `Sources/SwiftTUIRuntime/Accessibility/LinearAccessibilityRenderer.swift`
- `Sources/SwiftTUIRuntime/Accessibility/AccessibilityTextSanitizer.swift`
- `Scripts/lib/accessibility_color_state_sources.txt`

Review notes for previous packets:

- No SwiftUI-like public API was intentionally changed; public API inventory
  stayed at 669 top-level public symbols across all three batch gates.
- `Styling.swift` and `RenderMetadataTypes.swift` were deleted after becoming
  empty broad buckets; their declarations now live in focused files named for
  style, payload, metadata, selection, and list responsibilities.
- Scene builder artifacts, window scene configuration, selected-scene runner
  plumbing, hosted raster state, and accessibility text sanitization moved out
  of larger runtime files without changing scene collection or hosted-frame
  behavior.
- A read-only review subagent found no code regressions in packets 92-101 and
  flagged only that the migration artifacts needed this update.

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

Latest constrained batches passed:

```bash
bun run test
bun run test
bun run test
bun run test
bun run test
bun run test
bun run test
```

Latest batch logs:

```text
/tmp/swift-tui-test-gate-20260518-145417-packet72-76.log
/tmp/swift-tui-test-gate-20260518-145417-59626.log
/tmp/swift-tui-test-gate-20260518-150340-packet77-81.log
/tmp/swift-tui-test-gate-20260518-150340-86962.log
/tmp/swift-tui-test-gate-20260518-153444-packet82-86.log
/tmp/swift-tui-test-gate-20260518-153444-16744.log
/tmp/swift-tui-test-gate-20260518-154406-packet87-91.log
/tmp/swift-tui-test-gate-20260518-154406-32556.log
/tmp/swift-tui-test-gate-20260518-155625-packet92-96.log
/tmp/swift-tui-test-gate-20260518-155625-58962.log
/tmp/swift-tui-test-gate-20260518-160339-packet97-101.log
/tmp/swift-tui-test-gate-20260518-160339-76975.log
/tmp/swift-tui-test-gate-20260518-161124-packet102-106.log
/tmp/swift-tui-test-gate-20260518-161124-95992.log
/tmp/swift-tui-test-gate-20260518-162436-packet107-111.log
/tmp/swift-tui-test-gate-20260518-162436-14895.log
/tmp/swift-tui-test-gate-20260518-163254-packet112-116.log
/tmp/swift-tui-test-gate-20260518-163254-34322.log
/tmp/swift-tui-test-gate-20260518-164649-packet117-121.log
/tmp/swift-tui-test-gate-20260518-164649-55780.log
/tmp/swift-tui-test-gate-20260518-170129-packet122-126.log
/tmp/swift-tui-test-gate-20260518-170129-78413.log
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

Packet 25 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InputParserModifierTests
swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests
swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-060611-5894.log
```

Packet 26 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.InputParserModifierTests
swiftly run swift test --filter SwiftTUITests.BracketedPasteParserTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/keyParserParsesExpectedSequences
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/terminalInputParserDecodesMixedMouseStreams
swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests/terminalPixelMouseInputReachesDragGestureAsFractionalLocation
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-061130-23411.log
```

Packet 27 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.InputBatchingResponsivenessTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderDrainsPointerBurstsAcrossMultipleReads
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/inputReaderCoalescesStaggeredPointerBursts
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/realInputReaderScrollBurstsUpdateVisibleGalleryPaneBeforeFollowUpClick
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-065523-66925.log
```

Packet 28 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/matchedGeometryTriggersTranslationAnimation
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/matchedGeometryRendersAtSourceAtProgressZero
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/insertionOffsetAnimationCompletes
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/removalOverlaysDoNotAccumulateAcrossTickFrames
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests/transitionRemovalIsInjectedAtPlacedLevel
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests/insertionOffsetTranslatesPlacedBounds
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadKeepsTransitionAnimationsDraftOwnedUntilCommit
swiftly run swift test --filter SwiftTUITests.AnimationControllerSnapshotTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests
swiftly run swift test --filter SwiftTUITests.AnimationControllerRemovalTests
swiftly run swift test --filter SwiftTUITests.AnimationPipelineIntegrationTests
swiftly run swift test --filter SwiftTUITests.AnimationTickVisibilityTests
swiftly run swift test --filter SwiftTUITests.GradientAnimationIntegrationTests
swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter SwiftTUITests.MotionAndProgressPolicyTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-083720-85404.log
```

Packet 29 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedBuiltInLayoutQueuesInputWithoutCommittingAhead
swiftly run swift test --filter SwiftTUITests.HostedSceneSessionTests/hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents
swiftly run swift test --filter SwiftTUITests
bun run test
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-093634-11184.log
```

Packet 30 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests
swiftly run swift test --filter SwiftTUITests.AnimationRepeatForeverGrowthTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortKeepsAnimationCompletionsUncommitted
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadDefersAnimationCompletionUntilCommit
swiftly run swift test --filter AnimationController
bun run test
git diff --check
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-100620-73481.log
```

Packet 30 patch review:

```text
Read-only subagent review found no behavior or API issues. It flagged that the
new helper file was not visible in plain git diff while untracked; that was
resolved with git add -N so review diffs include the file.
```

Packet 31 focused validation passed:

```bash
swiftly run swift build
swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift Sources/SwiftTUIRuntime/SwiftTUI.swift
swiftly run swift test --filter 'SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|PipelineContractTests|AsyncFrameTailRenderingTests|BoundedReconciliationTests|RenderDriverCharacterizationTests|RenderDriverInstrumentationCostTests)'
swiftly run swift test --filter 'SwiftTUITests\.(ResolvePurityTests|Phase4ObservationAndEnvironmentTests)'
swiftly run swift test --filter SwiftTUITests.AnimationControllerPropertyTests/frameHeadTransactionDefersBatchCompletionUntilCommit
swiftly run swift test --filter SwiftTUITests.AppRuntimeTests/optionalFocusStateTracksRuntimeFocusChanges
swiftly run swift test --filter SwiftTUITests
git diff --check
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-102231-97496.log
```

The first Packet 31 full `SwiftTUITests` attempt failed once in
`AppRuntimeTests/optional FocusState equals bindings track runtime focus changes across controls`.
That specific test passed immediately in isolation, and the full
`SwiftTUITests` target passed on rerun with 1309 tests.

Packet 31 patch review:

```text
Read-only subagent review found no behavior or API issues. It flagged one
low-severity surface issue where a renderer-only helper had become
module-internal; that was resolved by keeping renderPipelineTree(from:) private
in SwiftTUI.swift and passing it into the coordinator as a closure.
```

Packet 32 is planned as frame-tail job cancellation and outcome type
extraction:

- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
- `Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift`

Packet 32 focused validation passed:

```bash
swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter 'SwiftTUITests\.(RuntimeRenderPipelineTests|RenderPipelineStructureTests|RenderDriverInstrumentationCostTests)'
swiftly run swift test --filter SwiftTUITests
git diff --check
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-103156-25687.log
```

Packet 32 patch review:

```text
Read-only subagent review found no behavior, access-control, concurrency, or
API issue in the moved cancellation code. It noted that the broader worktree
also includes previous Packet 30 and 31 changes, so Packet 32 review should
stay scoped to FrameTailRenderer.swift and FrameTailJobCancellation.swift.
```

Packet 33 is ViewGraph lifecycle planning extraction:

- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift`

Packet 33 focused validation passed:

```bash
swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift
swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphLifecyclePlanning.swift
swiftly run swift build
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/preparedFrameHeadAbortRestoresBroadResetState
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/lazyForEachRowsEmitViewportLifecycleTransitions
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/runLoopEmitsViewportLifecycleTransitionsForFullLazyRows
swiftly run swift test --filter SwiftTUITests
git diff --check
```

Packet 33 patch review:

```text
Read-only subagent review found one medium-severity state-boundary issue: the
first helper shape accepted the live ViewNode map. This was resolved by keeping
ViewNode access in ViewGraph and passing changeHandlerIDsByIdentity as ordered
value data into the planner.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-104315-68488.log
```

Packet 34 is presentation item and storage model extraction:

- `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
- `Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift`
- `Sources/SwiftTUIViews/Presentation/PresentationItems.swift`

Packet 34 focused validation passed:

```bash
swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift Sources/SwiftTUIViews/Presentation/PresentationItems.swift
swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorStorage.swift Sources/SwiftTUIViews/Presentation/PresentationItems.swift
swiftly run swift build
swiftly run swift test --filter SwiftTUIViewsTests
swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationEscapeDismissTests|PopoverPresentationTests|OverlayStackTests|DismissStackTests)'
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal
./Scripts/generate_public_api_inventory.sh --check
swiftly run swift test --filter SwiftTUITests
git diff --check
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 34 patch review:

```text
Read-only subagent review found no behavior drift, access-control broadening,
Sendable or actor-isolation drift, public API change, or move-scope issue. It
confirmed the diff is mechanical and keeps fileprivate checkpoint fields
colocated with storage users.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-105218-92507.log
```

Packet 35 is being audited as built-in presentation coordinator extraction:

- `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
- `Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift`

Packet 35 focused validation passed:

```bash
swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift
swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/BuiltinPresentationCoordinators.swift
swiftly run swift build
swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PopoverPresentationTests|MenuSurfaceTests|PaletteSheetAbsorptionTests|PresentationActionScopeTests)'
./Scripts/generate_public_api_inventory.sh --check
swiftly run swift test --filter SwiftTUITests
git diff --check
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 35 patch review:

```text
Read-only subagent review found no behavior drift, z-index or modal-policy
drift, mutation-message drift, access-control broadening, Sendable or
actor-isolation issue, public API issue, or move-scope creep. It confirmed the
registry still uses the same concrete coordinator types.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-105849-10257.log
```

Packet 36 is planned as presentation registry support extraction:

- `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
- `Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift`

The read-only audit selected this as the next safe state-boundary move. Move
`PresentationCoordinatorBox`, `AnyPresentationCoordinatorBox`, and
`PresentationCoordinatorRegistry` together. Keep portal state/draft
publication, declaration preferences, and portal-root composition in
`PresentationCoordinator.swift`.

Packet 36 focused validation passed:

```bash
swift format format -i --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift
swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationCoordinatorRegistry.swift
swiftly run swift build
swiftly run swift test --filter 'SwiftTUITests\.(PresentationEscapeDismissTests|PopoverPresentationTests|OverlayStackTests|DismissStackTests|PresentationSurfaceTests)'
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal
./Scripts/generate_public_api_inventory.sh --check
swiftly run swift test --filter SwiftTUITests
git diff --check
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 36 patch review:

```text
Read-only subagent review found no behavior drift, registry order drift,
checkpoint construction or restore-order drift, reconciliation or overlay
sorting drift, dismiss-stack derivation drift, handle-injection drift,
access-control broadening, actor-isolation issue, public API issue, or
move-scope creep.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-110638-29651.log
```

Packet 37 is presentation portal state transaction extraction:

- `Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift`
- `Sources/SwiftTUIViews/Presentation/PresentationPortalState.swift`

The read-only audit selected moving only `PresentationPortalState` and
`PresentationPortalDraft` together. Keep declaration preferences,
`PresentationPortalRoot`, `reconcilePresentationDeclarations`, and
`composePresentationPortalTree` in `PresentationCoordinator.swift`.

Packet 37 focused validation passed:

```bash
swift format lint --configuration .swift-format.json Sources/SwiftTUIViews/Presentation/PresentationCoordinator.swift Sources/SwiftTUIViews/Presentation/PresentationPortalState.swift
swiftly run swift build
swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationContinuityTests|PresentationEscapeDismissTests|PopoverPresentationTests|PortalPrimitiveTests)'
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftSheetOutOfEscapeDismissal
./Scripts/generate_public_api_inventory.sh --check
swiftly run swift test --filter SwiftTUITests
git diff --check
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 37 patch review:

```text
Read-only subagent review found no behavior drift, package-access broadening,
actor-isolation issue, public API issue, or draft commit/discard lifetime issue.
It confirmed the moved types preserve the prior checkpoint and publication
behavior.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-111454-47956.log
```

Packet 38 is ViewGraph structural removal planning extraction:

- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift`

The fresh production debt scan selected `ViewGraph` over adjacent presentation
cleanup because it remains a central infrastructure file with dirty
evaluation, structural reconciliation, dependency indexing, alias cleanup, and
lifecycle side effects. Packet 38 keeps the slice narrow: only value-only
removed-child planning moved out of `ViewGraph`; live node mutation and subtree
teardown stayed in `ViewGraph`.

Packet 38 focused validation passed:

```bash
swift format format -i --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift
swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphStructuralReconciliation.swift
swiftly run swift build
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests
swiftly run swift test --filter SwiftTUICoreTests.StructuralDiffTests
swiftly run swift test --filter SwiftTUICoreTests
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
./Scripts/generate_public_api_inventory.sh --check
swiftly run swift test --filter SwiftTUITests
git diff --check
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 38 patch review:

```text
Read-only subagent review found no behavior drift in removal planning, index
guards, or committed-snapshot selection. It found one misleading helper comment
about non-removal operations; the comment was tightened to state that matched,
moved, and inserted children are owned by later commit/reuse/install
materialization paths.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-112550-packet38.log
```

Packet 39 is ViewGraph dirty-evaluation planning extraction:

- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`
- `Sources/SwiftTUICore/Resolve/ViewGraphDirtyEvaluationPlanning.swift`

The fresh production scan kept focus on `ViewGraph` because selective dirty
evaluation was still central, high-risk infrastructure: graph-known
invalidation checks, dirty-frontier discovery, lifecycle-owner promotion,
evaluator fallback, target de-duplication, and graph mutation lived together in
one method. Packet 39 extracts the value-selection work and leaves live graph
mutation in `ViewGraph`.

Packet 39 focused validation passed:

```bash
swiftly run swift build
swift format lint --configuration .swift-format.json Sources/SwiftTUICore/Resolve/ViewGraph.swift Sources/SwiftTUICore/Resolve/ViewGraphDirtyEvaluationPlanning.swift
./Scripts/generate_public_api_inventory.sh --check
git diff --check
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests
swiftly run swift test --filter SwiftTUICoreTests.ViewGraphCheckpointTotalityTests
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUICoreTests
swiftly run swift test --filter SwiftTUITests
```

The public API inventory check passed with 669 top-level public symbols. The
script emitted and ignored its existing SwiftPM synthetic package-test symbol
graph warning.

Packet 39 patch review:

```text
Read-only subagent review found no behavior drift in graph-known invalidation
filtering, dirty-frontier ancestor suppression and ordering, lifecycle-owner
promotion, duplicate evaluator collapse, or evaluator fallback. It also
confirmed target `markDirty()` and `DirtyEvaluationPlan` construction remained
in `ViewGraph`.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-113708-packet39.log
```

Packet 40 is TerminalHost presentation emission builder extraction:

- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift`

The terminal-runtime audit selected this over adjacent platform-host and style
codec cleanup because it stays in the core terminal rendering path:
`TerminalHost` still mixed raw-mode/session sequencing with frame emission,
edit-operation lowering, incremental row output, and Kitty replay. Packet 40
moves emission assembly behind `TerminalHostPresentationEmissionBuilder` while
passing the transmitted Kitty image-id cache by `inout`; `TerminalHost` still
owns probing, writer drain/drop recovery, synchronized-output wrapping, and
retained-surface publication.

Packet 40 focused validation passed:

```bash
swiftly run swift build
swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift
swiftly run swift test --filter SwiftTUITests.TerminalHostPresentationBatchingTests
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.TerminalGraphicsProtocolTests
./Scripts/generate_public_api_inventory.sh --check
git diff --check
swiftly run swift test --filter SwiftTUITests
```

The build emitted existing strict-memory-safety warnings in unrelated SwiftUI
host files. The public API inventory check passed with 669 top-level public
symbols and ignored the existing SwiftPM synthetic package-test symbol graph
warning.

Packet 40 patch review:

```text
Read-only subagent review found no behavior drift in full repaint ordering,
incremental row ordering, Kitty transmitted-image cache mutation, graphics
replay metrics, erase-to-end lowering, or synchronized-output boundaries. It
found no new concurrency risk.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-114635-packet40.log
```

Packet 41 is Terminal render-style codec file split:

- `Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift`
- `Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift`

The Packet 41 audit compared the remaining `TerminalSurfaceRenderer`
style/sanitization and row-diff seams with the control-message style transport
codec. The codec split was selected first because it is lower risk: it keeps
the Web/runner style transport behavior byte-stable while making
`TerminalControlMessages.swift` about command framing and dispatch again.

Packet 41 focused validation passed:

```bash
swiftly run swift build
swift format lint --configuration .swift-format.json Sources/SwiftTUIRuntime/Terminal/TerminalControlMessages.swift Sources/SwiftTUIRuntime/Terminal/TerminalRenderStyleCodec.swift
swiftly run swift test --filter SwiftTUITests.TerminalRenderStyleCodecTests
swiftly run swift test --filter SwiftTUITests.InputReaderControlMessageTests
swiftly run swift test --filter SwiftTUITests.InjectedTerminalInputReaderTests
swiftly run swift test --filter WASISurfaceBridgeTests
swiftly run swift test --filter SwiftTUIWebHostTests
./Scripts/generate_public_api_inventory.sh --check
git diff --check
swiftly run swift test --filter SwiftTUITests
```

The build emitted existing strict-memory-safety warnings in unrelated SwiftUI
host files. The public API inventory check passed with 669 top-level public
symbols and ignored the existing SwiftPM synthetic package-test symbol graph
warning.

Packet 41 patch review:

```text
Read-only subagent review found no behavior drift: the codec body stayed
byte-for-byte identical, SPI/public surface and schema comment were preserved,
ControlMessageParser still calls decodeBase64, no Foundation import was added,
and invalid input behavior stayed intact.
```

Slice gate log:

```text
/tmp/swift-tui-test-gate-20260518-115536-packet41.log
```

Packets 42-47 continue the same production-humanization track:

- Packet 42: `TerminalCellTextRenderer` split from `TerminalPresentation`
  for terminal cell text rendering, SGR lowering, OSC 8 sanitization, ASCII
  glyph degradation, and ANSI16 palette matching.
- Packet 43: `TerminalSurfaceDamageRendering` split for row-damage span
  detection, wide-glyph continuation normalization, row-batch rendering, and
  changed-cell accounting.
- Packet 44: `TerminalCapabilityProfile` split from terminal presentation
  rendering, preserving public capability profile API and environment/runtime
  overlay behavior.
- Packet 45: `TabViewStyleHosting` split for TabView type-erasure, hosted
  strip/overflow views, layout slot metadata, and package identity helpers.
- Packet 46: `SemanticAccessibilityExtraction` split for accessibility node
  extraction and warning emission, with shared `semanticBounds` retained as
  the single offset-aware bounds helper.
- Packet 47: `TextLayoutCache` split for layout cache storage, metrics,
  generation refresh, and LRU eviction bookkeeping.

Packet 45-47 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests
swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests
swiftly run swift test --filter SwiftTUICoreTests.FocusPresentationTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests
swiftly run swift test --filter SwiftTUITests.ContentShapeTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUITests.TextLayoutTests
swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests
swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests
swiftly run swift test --filter SwiftTUITests.RenderedTextFixtureSupportTests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests
./Scripts/generate_public_api_inventory.sh --check
./Scripts/check_accessibility_guardrails.sh
git diff --check
```

Packet 45, 46, and 47 each received read-only subagent review. Reviews found no
material behavior drift. Packet 46 was tightened after review to share the
existing semantic bounds helper instead of duplicating offset geometry; Packet
47 added one focused cache-eviction test to pin refreshed-entry retention.

Packet 45-47 batch gate:

```text
/tmp/swift-tui-test-gate-20260518-123452-43677.log
```

Result: PASS.

Packets 48-50 continue the core text-layout decomposition:

- Packet 48: `TextLayoutWrapping` split for word-boundary wrapping,
  whitespace/token classification, oversized word-like continuation markers,
  cluster fallback wrapping, and the existing wrapping test hook.
- Packet 49: `TextLayoutTruncation` split for line-limit truncation and
  head/middle/tail fitting helpers.
- Packet 50: `TextCellWidth` split for package terminal cell-width policy
  shared by text layout, text input, borders, tile style, and terminal
  presentation support.

Packet 48-50 focused validation passed:

```bash
swiftly run swift build
swiftly run swift test --filter SwiftTUITests.TextLayoutTests
swiftly run swift test --filter SwiftTUITests.TextLayoutCacheTests
swiftly run swift test --filter SwiftTUITests.TextFigureSurfaceTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUIViewsTests.TextInputLayoutMapTests
swiftly run swift test --filter TileStyle
swiftly run swift test --filter BorderSet
swiftly run swift test --filter SwiftTUITests.TerminalPresentationTests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests
./Scripts/generate_public_api_inventory.sh --check
./Scripts/check_accessibility_guardrails.sh
git diff --check
```

Packet 48, 49, and 50 each received read-only subagent review. Reviews found
no material behavior drift. Packet 48 added guard-path text layout coverage for
nil width, zero width, and empty text after review. Packet 50 corrected a
comment to cover multi-scalar ASCII clusters as well as non-ASCII clusters.
The review noted the module-internal `uncachedTextLayout(for:options:)`
visibility introduced by the cache split; it remains non-public and
non-package API.

Packet 48-50 batch gate:

```text
/tmp/swift-tui-test-gate-20260518-124933-79782.log
```

Result: PASS.

Packet 51-53 completed the next three-packet presentation split:

- Packet 51 moved prompt presentation specs and public `.alert(...)`,
  `.confirmationDialog(...)`, and `.sheet(...)` entrypoints into
  `PromptPresentationEntrypoints.swift`.
- Packet 52 moved `HostedPromptPresentation` and `PromptPresentationSurface`
  into `PromptPresentationSurface.swift`.
- Packet 53 moved toast styles, public `.toast(...)` entrypoints,
  `ToastModifier`, `ToastCoordinatorBodyView`, and `ToastPresentationView`
  into `ToastPresentation.swift`.

Public API shape was preserved. `Scripts/lib/public_documentation_ratchet.txt`
now follows the moved prompt/toast declarations. Accessibility guardrails now
track prompt-surface color-state styling in `PromptPresentationSurface.swift`
and toast raw glyph/color-state usage in `ToastPresentation.swift`.

Packet 51-53 focused validation passed:

```bash
swiftly run swift build
swiftly run swift build --target SwiftTUIViews
swiftly run swift build --target SwiftTUIRuntime
swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests
swiftly run swift test --filter SwiftTUITests.PresentationActionScopeTests
swiftly run swift test --filter SwiftTUITests.PopoverPresentationTests
swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests
swiftly run swift test --filter SwiftTUITests.PresentationEscapeDismissTests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/toastAutoDismissRegistersLifecycleTask
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests/toastAutoDismissRerendersWithoutAdditionalInput
./Scripts/check_public_documentation_ratchet.sh
./Scripts/check_accessibility_guardrails.sh
./Scripts/check_public_surface_policies.sh
git diff --check
```

Packet 51 and Packet 53 read-only reviews found no material findings. Packet 52
review found the prompt-surface move behavior-preserving but recommended
`package import SwiftTUICore`; direct `SwiftTUIViews` and `SwiftTUIRuntime`
target builds passed with the warning-free plain import, while `package import`
produced an unused package-import warning, so the plain import was retained.

Packet 51-53 batch gate:

```text
/tmp/swift-tui-test-gate-20260518-131048-20030.log
```

Result: PASS.

The first Packet 51-53 full-gate attempt failed only in `SwiftTUITests` with
three `AsyncLifecycleGenerationTests` readiness timeouts:

```text
/tmp/swift-tui-test-gate-20260518-130832-8813.log
```

The failed suite passed immediately in isolation with:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncLifecycleGenerationTests
```

Packet 54-56 completed a three-packet `ResolvedNode.swift` decomposition:

- Packet 54 moved `TabItemLabel`, `AccessibilityVisualContent`,
  `SemanticMetadata`, and `TextInputAccessibilityCursorAnchor` into
  `ResolvedSemanticMetadata.swift`.
- Packet 55 moved lifecycle metadata, matched-geometry value types, indexed
  child support, custom-layout fallback summaries, and
  `usesIndexedChildSource` into dedicated resolve support files.
- Packet 56 moved traversal/lifecycle collection helpers and
  measurement/placement/equality logic into `ResolvedNodeTraversal.swift` and
  `ResolvedNodeEquivalence.swift`.

Public API shape was preserved. `ResolvedNode.swift` now keeps the resolved
node stored phase data, initializers, and private derived-state maintenance in
one 302-line file; helper declarations live in named files.

Packet 54-56 focused validation passed:

```bash
swiftly run swift build
swiftly run swift build --target SwiftTUICore
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests
swiftly run swift test --filter SwiftTUICoreTests.ChildDescriptorTests
swiftly run swift test --filter matchedGeometry
swiftly run swift test --filter LayoutEngineTests
swiftly run swift test --filter SwiftTUITests.FrameTailWorkerFallbackTests
swiftly run swift test --filter SwiftTUITests.ResolveReuseIndexingTests
swiftly run swift test --filter SwiftTUICoreTests.StackSafetyRegressionTests
swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
git diff --check
./Scripts/check_public_documentation_ratchet.sh
./Scripts/check_accessibility_guardrails.sh
./Scripts/check_public_surface_policies.sh
./Scripts/generate_public_api_inventory.sh --check
```

Read-only scout subagents reviewed the candidate split and found the semantic,
support-value, traversal, and equivalence moves appropriate as mechanical
extractions. They warned not to move `ResolvedNode` stored fields because
`ResolvedNodePhaseOwnershipTests` parses the exact source path; that invariant
was preserved.

Packet 54-56 batch gate:

```text
/tmp/swift-tui-test-gate-20260518-132341-40611.log
```

Result: PASS. Tee log:

```text
/tmp/swift-tui-test-gate-20260518-132300-packet54-56.log
```

One earlier Packet 23 full-gate attempt failed in `SwiftTUITests` with three
`AsyncLifecycleGenerationTests` readiness timeouts. The suite passed in
isolation immediately after, the full `SwiftTUITests` target passed, and the
full repo gate passed on rerun. Failed gate log:

```text
/tmp/swift-tui-test-gate-20260518-054640-45870.log
```

One Packet 27 final-candidate full-gate attempt failed in
`SwiftTUITerminalTests` on `running cat over a large file stays within the byte
budget` with a timeout. The target passed immediately in isolation, and the
full repo gate passed on rerun. Failed gate log:

```text
/tmp/swift-tui-test-gate-20260518-062300-55078.log
```

One Packet 29 full-gate attempt failed in the full `SwiftTUITests` runtime
target with two timeout issues:
`HostedSceneSessionTests/hostedSurfaceSessionPublishesRasterSurfaceAndAcceptsDirectInputEvents`
and
`AsyncFrameTailRenderingTests/blockedBuiltInLayoutQueuesInputWithoutCommittingAhead`.
Both tests passed immediately in isolation, the full `SwiftTUITests` target
passed, and the full repo gate passed on rerun. Failed gate log:

```text
/tmp/swift-tui-test-gate-20260518-090939-98987.log
```

## Earlier Review Packet: 57-61

The latest batch follows the updated five-packet cadence and focuses on the
remaining central SwiftTUIViews modifier/layout infrastructure.

Production scope:

- `ViewModifiers.swift` is now a small resolver/`AnyView` utility file.
- Metadata/identity/accessibility/focus/environment modifiers moved to
  `ViewMetadataModifiers.swift`.
- Lifecycle modifiers moved to `ViewLifecycleModifiers.swift`, and the
  public-surface guard now checks `.task` actor inheritance in that file.
- Layout/decorative modifiers moved to `ViewLayoutModifiers.swift`.
- The previous `Layout.swift` custom-layout bridge was renamed to
  `CustomLayout.swift`.
- Built-in stack layouts and stack/overlay helper math moved to
  `StackLayouts.swift`.

Behavior intentionally preserved:

- No SwiftUI-shaped public consumer API signatures changed.
- Public API inventory remained at 669 top-level public symbols.
- `.task` keeps `@_inheritActorContext` and the `task(id:)` overload guard.
- Layout values, alignment guides, safe areas, borders, overlays,
  backgrounds, matched geometry, stack placement, `AnyLayout` cache scoping,
  and `SendableLayout` worker execution were covered by focused tests.

Focused validation highlights:

- `swiftly run swift build --target SwiftTUIViews` passed after each packet.
- Metadata checks passed:
  `SwiftTUIViewsTests.AccessibilityMetadataModifierTests`,
  `SwiftTUIViewsTests.ViewModifierAlgebraTests`,
  `SwiftTUIViewsTests.DependencyTrackingTests`,
  `SwiftTUIViewsTests.EnvironmentTests`,
  `SwiftTUITests.SwiftUISurfaceTests/customLayoutReadsLayoutValuesAndPlacesSubviews`,
  and
  `SwiftTUITests.SwiftUISurfaceTests/alignmentGuideOverridesFeedStackPlacement`.
- Lifecycle checks passed:
  `SwiftTUITests.Phase2LifecycleFixtureTests`,
  `SwiftTUITests.AsyncLifecycleGenerationTests`,
  `SwiftTUITests.LifecycleSelectiveEvaluationTests`,
  `SwiftTUITests.SwiftUISurfaceTests/onChangeDefersExecutionUntilCommitAndTracksOldAndNewValues`,
  and `SwiftTUITests.ImperativeAuthoringContextDispatchTests`.
- Layout/decorative checks passed:
  `SwiftTUITests.SafeAreaSurfaceTests`,
  `SwiftTUITests.BorderModifierLayoutTests`,
  `SwiftTUITests.BorderRenderingTests`,
  `SwiftTUITests.GeometryReaderSurfaceTests`, `matchedGeometry`,
  `SwiftTUITests.MotionAndProgressPolicyTests/reducedMotionSuppressesMatchedGeometryTranslation`,
  and
  `SwiftTUITests.SwiftUISurfaceTests/overlayAlignmentUsesPrimaryGuides`.
- Stack/custom-layout checks passed:
  `SwiftTUITests.SwiftUISurfaceTests/zStackLayoutMirrorsZStackPlacement`,
  `SwiftTUITests.SwiftUISurfaceTests/anyLayoutPreservesIdentityAcrossSwitches`,
  `SwiftTUITests.SwiftUISurfaceTests/anyLayoutFlattensForEachChildren`,
  `SwiftTUITests.SwiftUISurfaceTests/customLayoutReusesCacheBetweenMeasurementAndPlacement`,
  `SwiftTUITests.SwiftUISurfaceTests/sharedAnyLayoutInstancesKeepCacheScopedPerContainer`,
  and
  `SwiftTUITests.AsyncFrameTailRenderingTests/publicSendableLayoutOptInRunsLayoutOnFrameTailWorker`.

Shared pre-gates:

- `git diff --check`: PASS
- `./Scripts/check_public_documentation_ratchet.sh`: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`: PASS
- `./Scripts/check_public_surface_policies.sh`: PASS
- `./Scripts/generate_public_api_inventory.sh --check`: PASS, 669 top-level
  public symbols, with the known ignored SwiftPM synthetic package-test
  symbolgraph warning

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-134540-packet57-61.log
Runner log: /tmp/swift-tui-test-gate-20260518-134540-77000.log
Result: PASS
```

## Previous Review Packet: 62-66

This batch follows the five-packet cadence and focuses on remaining central
Core graph helpers plus SwiftTUIViews style/control files.

Production scope:

- `ViewGraph.swift` now delegates dependency indexing and runtime-registration
  restoration to `ViewGraphDependencyIndexing.swift` and
  `ViewGraphRuntimeRegistrationRestoration.swift`.
- Public TabView style declarations remain in `TabViewStyles.swift`; built-in
  conformances and terminal chrome moved to `BuiltinTabViewStyles.swift`.
- `CollectionStyles.swift` was split into `ListStyles.swift` and
  `OutlineStyles.swift`.
- Public button style declarations remain in `ButtonStyles.swift`; built-in
  chrome resolution and style-body views moved to `ButtonStyleChrome.swift`.
- `AdjustableValueControls.swift` was split into `Stepper.swift`,
  `Slider.swift`, and `AdjustableControlValueSupport.swift`.

Behavior intentionally preserved:

- No SwiftUI-shaped public consumer API signatures changed.
- Public API inventory remained at 669 top-level public symbols.
- `ViewGraph` private stored state remains private; helpers receive explicit
  dictionary/set inputs.
- Tab overflow/chrome, list/outline style presentations, button focus/pressed
  chrome, stepper actions, slider pointer math, and accessibility guardrails
  are covered by focused checks.

Focused validation highlights:

- `swiftly run swift build --target SwiftTUICore` passed for Packet 62.
- `swiftly run swift build --target SwiftTUIViews` passed for Packets 63-66.
- ViewGraph checks passed:
  `SwiftTUICoreTests.ViewGraphCheckpointTotalityTests` and
  `SwiftTUICoreTests.ViewGraphTests`.
- TabView checks passed:
  `SwiftTUITests.TabViewSurfaceTests`,
  `SwiftTUITests.TabViewLifecycleTests`, and
  `SwiftTUITests.InteractiveRuntimeTests/literalTabOverflowUpdatesOnSIGWINCHWithoutAdditionalInput`.
- Collection checks passed:
  `SwiftTUITests.CollectionSupportTests`,
  `SwiftTUITests.OutlineSurfaceTests`,
  `SwiftTUITests.SwiftUISurfaceTests/listUsesTagsAndArrowKeys`, and
  `SwiftTUITests.SwiftUISurfaceTests/listAndTableRenderEditingChromeDirectlyFromFocus`.
- Button checks passed:
  `SwiftTUITests.ButtonFocusStabilityTests` and
  `SwiftTUITests.ButtonSystemHintTests`.
- Adjustable-control checks passed:
  `SwiftTUITests.SwiftUISurfaceTests/stepperDispatchesAndClamps`,
  `SwiftTUITests.SwiftUISurfaceTests/sliderHandlesArrowKeysAndRendersTrack`,
  `SwiftTUITests.SwiftUISurfaceTests/doubleAdjustableControlsRenderCleanFractionalValues`,
  and
  `SwiftTUITests.SwiftUISurfaceTests/sliderTrackUsesFractionalPointerLocations`.

Shared pre-gates:

- `git diff --check`: PASS
- `./Scripts/check_public_documentation_ratchet.sh`: PASS, 70 entries
- `./Scripts/check_accessibility_guardrails.sh`: PASS
- `./Scripts/check_public_surface_policies.sh`: PASS
- `./Scripts/generate_public_api_inventory.sh --check`: PASS, 669 top-level
  public symbols, with the known ignored SwiftPM synthetic package-test
  symbolgraph warning

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-140917-packet62-66.log
Runner log: /tmp/swift-tui-test-gate-20260518-140917-98579.log
Result: PASS
```

## Previous Review Packet: 67-71

This batch follows the five-packet cadence and focuses on remaining central
Core layout/raster files plus SwiftTUICharts support.

Production scope:

- Measurement work-stack support moved into work-item, result-stack,
  measured-node building, and stack scheduling files.
- Placement work-stack support moved into work-item, result-stack, placement
  request, and stack placement request files.
- `ViewNode.swift` now delegates debug snapshot helpers and committed-field
  forwarding accessors to focused files, without widening mutable node storage.
- Layout-border rasterization moved to `Rasterizer+LayoutBorders.swift`,
  leaving shape stroke and rule drawing in `Rasterizer+Borders.swift`.
- `LineChartSupport.swift` now keeps view-body and legend/x-axis formatting
  support; domain, rasterization, tick, and series helpers moved to focused
  files.

Behavior intentionally preserved:

- No SwiftUI-shaped public consumer API signatures changed.
- Public API inventory remained at 669 top-level public symbols.
- Measurement and placement stack order, retained placement, custom-layout
  placement, `ViewNode` debug output, border raster output, line-chart domain
  math, chart glyphs, axis labels, and series composition are covered by
  focused checks.

Focused validation highlights:

- `swiftly run swift build --target SwiftTUICore` passed for Packets 67-70.
- `swiftly run swift build --target SwiftTUICharts` passed for Packet 71.
- Layout work-stack checks passed:
  `SwiftTUICoreTests.LayoutEngineTests` and
  `SwiftTUICoreTests.StackSafetyRegressionTests`.
- ViewNode checks passed:
  `SwiftTUICoreTests.ViewGraphCheckpointTotalityTests` and
  `SwiftTUICoreTests.ViewGraphTests`.
- Border checks passed:
  `SwiftTUITests.BorderRenderingTests` and
  `SwiftTUITests.BorderGradientTests`.
- LineChart checks passed:
  `SwiftTUITests.LineChartDomainTests` and `LineChart`.
  A mistyped `SwiftTUITests.LineChartRasterTests` filter matched 0 tests and
  was replaced by the broader `LineChart` filter.

Shared pre-gates:

- `git diff --check`: PASS
- `./Scripts/check_accessibility_guardrails.sh`: PASS
- `./Scripts/check_public_documentation_ratchet.sh`: PASS, 70 entries
- `./Scripts/check_public_surface_policies.sh`: PASS
- `./Scripts/generate_public_api_inventory.sh --check`: PASS, 669 top-level
  public symbols, with the known ignored SwiftPM synthetic package-test
  symbolgraph warning

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-142822-packet67-71.log
Runner log: /tmp/swift-tui-test-gate-20260518-142822-14676.log
Result: PASS
```

## Recent Review Packet: 72-81

This pair of five-packet batches begins the current constrained central
runtime/core pass.

Production scope:

- Semantic payload routing moved out of `Semantics.swift`.
- Pointer hit-testing and hover routing moved out of pointer dispatch.
- Run-loop session/support types moved out of `RunLoop.swift`.
- Snapshot style descriptions, image asset models, canvas pixel-grid drawing,
  canvas payloads, diagnostics records, gradient styles, and run-loop runtime
  support moved to focused files.

Behavior intentionally preserved:

- Semantic snapshots, pointer dispatch, hover delivery, run-loop exit behavior,
  snapshot diagnostics, image rendering, canvas rendering, diagnostic logging,
  gradient styling, and runtime issue/wake/focus support are covered by focused
  checks.
- Public API inventory remained at 669 top-level public symbols.

Batch gates:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-145417-packet72-76.log
Runner log: /tmp/swift-tui-test-gate-20260518-145417-59626.log
Result: PASS

bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-150340-packet77-81.log
Runner log: /tmp/swift-tui-test-gate-20260518-150340-86962.log
Result: PASS
```

## Latest Review Packets: 82-91

This pair of five-packet batches continues the constrained central
runtime/core pass.

Production scope:

- Built-in stack support was decomposed into axis support, lazy allocation,
  metrics, space allocation, and minimum-size files.
- Diagnostics TSV formatting moved out of the file logger.
- Terminal render-style JSON and Base64 transport helpers moved out of the
  style codec.
- Frame-tail retained state, typed tail products, worker result, generation
  sequencer, and hooks moved out of `FrameTailRenderer.swift`.
- POSIX terminal descriptor control moved out of `TerminalHost.swift`.

Behavior intentionally preserved:

- Stack sizing/allocation/minimums, diagnostics TSV output, style transport
  payloads, frame-tail retained input and diagnostics, terminal descriptor I/O,
  raw-mode mutation, and cell-pixel metrics are covered by focused checks.
- No public SwiftUI-shaped API was intentionally changed.

Batch gates:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-153444-packet82-86.log
Runner log: /tmp/swift-tui-test-gate-20260518-153444-16744.log
Result: PASS

bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-154406-packet87-91.log
Runner log: /tmp/swift-tui-test-gate-20260518-154406-32556.log
Result: PASS
```

## Latest Review Packets: 92-106

These three five-packet batches continue the constrained central runtime/core
pass.

Production scope:

- Core styling was split into shape styles, theme/render style, stroke helpers,
  shape payloads, and resolved text style files.
- Core draw metadata was split into draw payload, text style, draw metadata,
  selection tag, and list payload files.
- Runtime scene builder artifacts, window scene configuration, selected-scene
  runner plumbing, hosted raster surface state, and accessibility text
  sanitization were extracted into focused files.

Behavior intentionally preserved:

- Shape/style resolution, terminal render-style payloads, draw metadata
  propagation, list/table selection behavior, scene builder ordering, hosted
  scene lookup, hosted frame waiter behavior, damage metrics, and linear
  accessibility output are covered by focused checks.
- No public SwiftUI-shaped API was intentionally changed.

Batch gates:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-155625-packet92-96.log
Runner log: /tmp/swift-tui-test-gate-20260518-155625-58962.log
Result: PASS

bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-160339-packet97-101.log
Runner log: /tmp/swift-tui-test-gate-20260518-160339-76975.log
Result: PASS

bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-161124-packet102-106.log
Runner log: /tmp/swift-tui-test-gate-20260518-161124-95992.log
Result: PASS
```

## Latest Review Packets: 122-126

This five-packet batch continues the constrained central runtime/core pass.

Production scope:

- Frame-tail inline layout/raster stage mechanics moved into
  `FrameTailRenderer+InlineStages.swift`.
- Event-pump timing, buffering, drain, completion, and deadline helper types
  moved into `RunLoop+EventPumpSupport.swift`.
- Runtime issue reporting moved into `RunLoop+RuntimeIssueReporting.swift`.
- Committed-frame diagnostic input and assembly moved into
  `CommittedFrameDiagnosticsBuilder.swift`.
- ViewGraph lifecycle event collection and frame-plan input construction moved
  into `ViewGraphLifecycleEventCollection.swift`.

Behavior intentionally preserved:

- Retained baseline placement, decorated placed-tree consumers,
  deadline/acquisition event-pump semantics, runtime issue de-duping,
  diagnostics timing values, and lifecycle ordering/checkpoint storage are
  covered by focused checks.
- No public SwiftUI-shaped API was intentionally changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-170129-packet122-126.log
Runner log: /tmp/swift-tui-test-gate-20260518-170129-78413.log
Result: PASS
```

## Latest Review Packets: 127-131

This five-packet batch continues the constrained central runtime/core pass.
Every packet is a behavior-preserving move; no logic was rewritten.

Production scope:

- Packet 127 — terminal mouse coordinate-mode resolution split out of
  `TerminalHostCapabilities.swift` into `TerminalMouseCoordinateResolution.swift`
  (`TerminalHostCapabilities.swift`, `TerminalMouseCoordinateResolution.swift`).
  Review note: `baselineGraphicsCapabilities()` was widened `private` →
  file-internal — the only visibility change in the batch.
- Packet 128 — layout-offload eligibility split out of `FrameTailRenderer.swift`
  into `FrameTailLayoutOffloadEligibility.swift` (`FrameTailRenderer.swift`,
  `FrameTailLayoutOffloadEligibility.swift`). The three `contains*` scans became
  file-internal so `renderLayoutAsync` keeps reusing them.
- Packet 129 — pure transition removal injection-point walk-up extracted from
  `AnimationController.swift` into `AnimationTransitionRemovalPlanning.swift`
  (`AnimationController.swift`, `AnimationTransitionRemovalPlanning.swift`).
- Packet 130 — read-only retained-frame query types split out of
  `RetainedResolveFrame.swift` into `RetainedFrameQueries.swift`
  (`RetainedResolveFrame.swift`, `RetainedFrameQueries.swift`).
- Packet 131 — `FrameTailRetainedState` extracted from the `FrameTailModels.swift`
  value-type grab-bag into `FrameTailRetainedState.swift`
  (`FrameTailModels.swift`, `FrameTailRetainedState.swift`).

Behavior intentionally preserved:

- SGR-pixels trust resolution, graphics-protocol probing, layout-worker offload
  decisions, transition overlay injection points, retained-frame
  indexing/invalidation queries, and frame-tail retained-state storage are all
  unchanged and covered by focused checks.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-175110-packet127-131.log
Runner log: /tmp/swift-tui-test-gate-20260518-175110-42380.log
Result: PASS
```

## Latest Review Packets: 132-136

This five-packet batch continues the constrained central runtime/core pass.
Every packet is a behavior-preserving move; no logic was rewritten.

Production scope:

- Packet 132 — test-only pipeline-stage hooks moved out of `SwiftTUI.swift`
  into `DefaultRenderer+TestingHooks.swift`. Review note: `frameTailCoordinator`
  and `prepareFrameHead` widened `private` → file-internal.
- Packet 133 — RunLoop runtime environment-action factories consolidated into
  `RunLoop+EnvironmentActions.swift` from `RunLoop+ResolveContext.swift` and
  `Support/ClipboardWriting.swift`; `ClipboardWriting.swift` deleted.
- Packet 134 — `AnimatableSnapshot` split out of `AnimationModels.swift` into
  `AnimatableSnapshot.swift`.
- Packet 135 — `SnapshotRenderer` tree `describe(_:)` formatters split out of
  `Snapshots.swift` into `SnapshotRenderer+TreeDescriptions.swift` (dropped
  `private`, matching the existing `+StyleDescriptions` convention).
- Packet 136 — `Commit/RetainedResolveFrame.swift` renamed to
  `Commit/LayoutPassContext.swift` to match its contents.

Behavior intentionally preserved:

- Test-hook semantics, environment-action wiring, animatable-slot extraction,
  snapshot text-fixture output, and layout-pass context behavior are unchanged
  and covered by focused checks.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-182040-packet132-136.log
Runner log: /tmp/swift-tui-test-gate-20260518-182040-24464.log
Result: PASS
```

## Latest Review Packets: 137-141

This five-packet batch continues the constrained central runtime/core pass.
Every packet is a behavior-preserving move; no logic was rewritten.

Production scope:

- Packet 137 — special-case placement-request builders →
  `LayoutEngine+SpecialPlacementRequests.swift` (three helpers widened
  `private` → file-internal).
- Packet 138 — ANSI color-code resolution →
  `TerminalCellTextRenderer+ColorCodes.swift` (three lookups widened
  `private` → file-internal; cache/palette stay `private`).
- Packet 139 — animation runtime-state types (`AnimationKind`,
  `ActiveAnimation`, `AnimationTickResult`, `RemovalEntry`) →
  `AnimationRuntimeState.swift`.
- Packet 140 — bulk registration operations →
  `RuntimeRegistrationSet+Operations.swift`.
- Packet 141 — `CompletedFrameImpact` nested type →
  `FrameDropEligibility+CompletedFrameImpact.swift`.

Behavior intentionally preserved:

- Placement geometry, ANSI color resolution, animation runtime state,
  registration reset/restore semantics, and frame-drop impact classification
  are unchanged and covered by focused checks.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-183437-packet137-141.log
Runner log: /tmp/swift-tui-test-gate-20260518-183437-57793.log
Result: PASS
```

## Latest Review Packets: 142-146

This five-packet batch continues the constrained central runtime/core pass.
Every packet is a behavior-preserving move; no logic was rewritten.

Production scope:

- Packet 142 — `FrameDiagnostic*` component structs → `FrameDiagnosticComponents.swift`.
- Packet 143 — `FocusSyncRerenderBudget` → `FocusSyncRerenderBudget.swift`.
- Packet 144 — frame-head phase helpers → `FrameHeadCoordinatorPhaseSupport.swift`
  (`withAnimationDraftSinks`/`measurePhase` widened `private` → file-internal).
- Packet 145 — `ViewNode.DebugTotalStateSnapshot` type declaration →
  `ViewNodeDebugSnapshots.swift` (the building method stays in `ViewNode.swift`).
- Packet 146 — lifecycle planning contract types →
  `ViewGraphLifecyclePlanningTypes.swift`.

Behavior intentionally preserved:

- Frame diagnostics field shape, focus-sync convergence budgeting, frame-head
  phase timing, ViewNode debug snapshot contents, and lifecycle event planning
  are unchanged and covered by focused checks.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-184640-packet142-146.log
Runner log: /tmp/swift-tui-test-gate-20260518-184640-86536.log
Result: PASS
```

## Latest Review Packets: 147-151

This batch closes the central runtime/core phase. Packets 147-150 are
behavior-preserving moves; packet 151 is documentation/handoff only.

Production scope:

- Packet 147 — frame-drop blocker derivation →
  `RunLoop+FrameDropBlockerDerivation.swift`.
- Packet 148 — completed-frame candidate support types →
  `CompletedFrameCandidateTypes.swift`.
- Packet 149 — `PlacedAnimationOverlaySamplingResult` →
  `PlacedAnimationOverlaySamplingResult.swift`.
- Packet 150 — zero-artifact diagnostic record builder + shared value
  formatters → `RunLoop+ZeroArtifactDiagnosticRecord.swift`.
- Packet 151 — migration artifact updates only; no source change.

Behavior intentionally preserved:

- Drop-blocker derivation, completed-frame candidate resolution, placed-overlay
  sampling, and zero-artifact diagnostic record assembly are unchanged and
  covered by focused checks.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-185750-packet147-151.log
Runner log: /tmp/swift-tui-test-gate-20260518-185750-12943.log
Result: PASS
```

This completes the central runtime/core phase (packets 1-151). Continued
humanization moves to other production code per the repo-wide scope.

## Latest Review Packets: 152-156 (SwiftTUIViews)

First batch of the other-production-code phase. All behavior-preserving moves
in `Sources/SwiftTUIViews`; public API inventory unchanged (669 symbols).

Production scope:

- Packet 152 — environment action types + keys + accessors →
  `EnvironmentActions.swift`.
- Packet 153 — resolve-tracking reference types → `ResolveWorkTracking.swift`.
- Packet 154 — picker selection-tag matching → `PickerSelectionSupport.swift`.
- Packet 155 — popover tip vocabulary → `PopoverTip.swift`.
- Packet 156 — foundational view protocols → `ViewProtocols.swift`.

Review note: `Scripts/check_public_surface_policies.sh` greps fixed source
paths for the `View` protocol and `OpenLinkAction` `@MainActor` invariants.
Packets 152 and 156 updated those two paths to the new files. The guardrail
checks are unchanged and still fail-closed.

Behavior intentionally preserved:

- Environment action wiring, resolve tracking, picker optional-selection
  matching, popover tips, and view-protocol dispatch are unchanged.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-195632-packet152-156.log
Runner log: /tmp/swift-tui-test-gate-20260518-195632-54551.log
Result: PASS
```

## Latest Review Packets: 157-161 (SwiftTUIViews)

Second batch of the other-production-code phase. All behavior-preserving moves
in `Sources/SwiftTUIViews`; public API inventory unchanged (669 symbols).

Production scope:

- Packet 157 — authoring-context types, identity helpers, and imperative
  snapshot → `State/AuthoringContext.swift` (leaves `State.swift` focused on
  the `@State` property wrapper and its backing storage).
- Packet 158 — layout modifier implementation types (`PaddingModifier`,
  `FrameModifier`, `OverlayModifier`, …) + their two private resolution
  helpers → `Modifiers/ViewLayoutModifierTypes.swift` (leaves
  `ViewLayoutModifiers.swift` as the public `extension View` modifier API).
- Packet 159 — navigation-destination preference/declaration types →
  `NavigationViews/NavigationDestinationPreferences.swift`
  (`navigationDestinationPopAction` stays — it needs the file-scoped
  `private` `scopeDepth`).
- Packet 160 — `ScrollViewLayout` + its reuse-signature extension →
  `ScrollView/ScrollViewLayout.swift`. One documented access widening:
  `private struct` → file-internal `struct`, so `ScrollView.resolve` can
  still construct it across files.
- Packet 161 — toolbar style vocabulary (`ToolbarStyle`, `ToolbarPlacement`,
  `Default{Top,Bottom}ToolbarStyle`) → `ActionScopes/ToolbarStyle.swift`.

Review note: moving `public protocol ToolbarStyle` required updating two
path-pinned guardrails in the same packet — `check_public_surface_policies.sh`
(the `ToolbarStyle` invariant) and `Scripts/lib/public_documentation_ratchet.txt`
(the `ToolbarStyle` / `DefaultTopToolbarStyle` / `DefaultBottomToolbarStyle`
doc-summary entries). Both guardrails are unchanged in substance and still
fail-closed; only the file paths follow the moved declarations.

Behavior intentionally preserved:

- `@State` storage and binding resolution, layout modifier lowering,
  navigation-destination preference plumbing, scroll-view layout/clamping, and
  toolbar styling are unchanged.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
First attempt FAILED: doc ratchet flagged the three moved ToolbarStyle
entries (stale paths in public_documentation_ratchet.txt).
Fixed the ratchet paths, re-ran.
User tee log: /tmp/swift-tui-test-gate-20260518-210648-packet157-161-rerun.log
Runner log: /tmp/swift-tui-test-gate-20260518-210648-12881.log
Result: PASS
```

## Latest Review Packets: 162-166 (SwiftTUIViews)

Third batch of the other-production-code phase. All behavior-preserving moves
in `Sources/SwiftTUIViews`; public API inventory unchanged (669 symbols).

Production scope:

- Packet 162 — `ResolveContext` + extensions → `Environment/ResolveContext.swift`.
  One documented access widening: `EnvironmentValues.applying(to:reuseStyle:)`
  `fileprivate` → `package`, so the moved file can fold environment edits back
  into a snapshot.
- Packet 163 — gesture-recognizer decorator classes →
  `Gestures/GestureModifierDecorators.swift`.
- Packet 164 — `PopoverAttachmentAnchor` + `attachmentRect` →
  `Presentation/PopoverAttachmentAnchor.swift`.
- Packet 165 — tab metadata-peeking protocols/conformances →
  `NavigationViews/TabMetadataPeeking.swift`.
- Packet 166 — `Section` view → `Collections/Section.swift`.

Review note: no path-pinned guardrail needed updating this batch — none of
the moved declarations are pinned by `check_public_surface_policies.sh` or the
doc ratchet. The one access change (`EnvironmentValues.applying`,
`fileprivate` → `package`) does not affect the public surface; the inventory
held at 669 symbols.

Behavior intentionally preserved:

- Resolve-context construction/derivation, gesture-recognizer decoration,
  popover anchor resolution, tab metadata peeking, and section resolution are
  unchanged.
- No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
User tee log: /tmp/swift-tui-test-gate-20260518-213611-packet162-166.log
Runner log: /tmp/swift-tui-test-gate-20260518-213611-44263.log
Result: PASS
```

## Latest Review Packets: 167-171 (SwiftTUICharts)

Fourth batch of the other-production-code phase. `ChartSupport.swift` (618
lines of `internal` per-chart-family free functions) split cleanly by family;
public API inventory unchanged (669 symbols).

Production scope:

- Packet 167 — shared/timeline/legend helpers → `ChartCommonSupport.swift`.
- Packet 168 — comparison-chart helpers → `ComparisonChartSupport.swift`.
- Packet 169 — stacked-bar-chart helpers → `StackedBarChartSupport.swift`.
- Packet 170 — threshold-gauge helpers → `ThresholdGaugeSupport.swift`.
- Packet 171 — bullet-chart helpers → `BulletChartSupport.swift`.

Review note: every extracted function is byte-identical and `internal`, so
there is no access widening. The batch did require regenerating the
accessibility source manifests (`accessibility_color_state_sources.txt`,
`accessibility_raw_glyph_sources.txt`) via
`check_accessibility_guardrails.sh --update`, because color/glyph-bearing
chart code moved to new files. The manifests only relabel file paths — no new
accessibility risk; the code was already accepted in `ChartSupport.swift`.

Behavior intentionally preserved:

- All chart-support functions are byte-identical to their previous form; only
  their file location changed. No public SwiftUI-shaped API, fixture, or test
  was changed.

Batch gate:

```text
bun run test
First attempt FAILED: accessibility manifests changed (color/glyph chart code
moved to new files). Regenerated with check_accessibility_guardrails.sh
--update, re-ran.
User tee log: /tmp/swift-tui-test-gate-20260518-214925-packet167-171-rerun.log
Runner log: /tmp/swift-tui-test-gate-20260518-214925-77602.log
Result: PASS
```

## Latest Review Packets: 172-174 (Platforms)

Fifth batch of the other-production-code phase — a three-packet batch in
`Platforms/*/Sources`. Public API inventory unchanged (669 symbols).

Production scope:

- Packet 172 — `WebSurfaceInputParser` → `WebSurfaceInputParser.swift`
  (zero widening).
- Packet 173 — `TerminalWorkspaceSplitLayout` →
  `TerminalWorkspaceSplitLayout.swift` (one documented `private` →
  file-internal widening).
- Packet 174 — `App.main()` launch entry points + `exitLaunch` →
  `App+TerminalLaunch.swift`.

Review note: Packet 174 repathed the `public static func main() async` row in
`public_documentation_ratchet.txt` to follow the moved declaration. A first
attempt at a fourth packet (`NativeTerminalMetrics`) was reverted —
`NativeTerminalSurfaceView.swift` is entangled via file-private platform
typealiases — so the batch closed at three.

Behavior intentionally preserved:

- Web-surface input parsing, workspace split layout, and terminal app launch
  are unchanged. No public SwiftUI-shaped API, fixture, or test was changed.

Batch gate:

```text
bun run test
First attempt FAILED: doc ratchet flagged the moved App.main() (stale
TerminalRunner.swift path). Repathed the ratchet row, re-ran.
User tee log: /tmp/swift-tui-test-gate-20260518-220532-packet172-174.log
Runner log: /tmp/swift-tui-test-gate-20260518-220532-9354.log
Result: PASS
```

## Migration Status

The production-code humanization ran through 174 behavior-preserving packets
(1-151 central runtime/core; 152-174 other production code). A **revisited
phase** then followed: the task owner authorized visibility adjustments where
they improve maintainability, and the seven previously-skipped large files
were re-analyzed (one read-only analysis agent each). Six are being split with
documented low-cost widening; one (`BuiltinTabViewStyles.swift`) stays skipped
with a detailed rationale. See `migration_plan.md` → "Revisited Phase".

Revisited-phase batches:

- **Batch 175-179** (done): `SelectionAndValueSupport.swift` → 3 focused files
  + `PointerRouteView.swift` rename (zero widening);
  `WebSurfaceFrameEncoder.swift` → `WebSurfaceImageEncoder.swift` (3
  `private`→`package` widenings, all namespaced under the enum). No public API
  (669 symbols), fixture, or test changed; accessibility manifests regenerated
  for the relocated glyphs.
- **Batch 180-184** (done): `PickerRendering.swift` → 3 picker-style files +
  `PickerSharedRendering.swift` (2 `private`→`internal` widenings);
  `CustomLayout.swift` part 1 → `CustomLayoutPlacementGeometry.swift` (4
  `private`→`internal` widenings). No public API (669), fixture, or test
  changed.
- **Batch 185-188** (done): `CustomLayout.swift` part 2 →
  `CustomLayoutErasure.swift` (type-erasure engine, 7 widenings);
  `BoxDrawingRenderer.swift` → 3 `+Lines`/`+Blocks`/`+Braille` files (9
  widenings, all namespaced under the enum). Also corrected a latent
  over-broad `public import` in `ToolbarStyle.swift`. No public API (669),
  fixture, or test changed.
- Batch 189+ (planned): `NativeTerminalSurfaceView.swift`.

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
Packet 25 is input event decoding extraction.
Packet 26 is terminal input parser file split.
Packet 27 is terminal input descriptor-reading extraction.
Packet 28 is placed animation overlay sampling extraction.
Packet 29 is DefaultRenderer frame-tail coordination extraction.
Packet 30 is animation completion scheduling extraction.
Packet 31 is DefaultRenderer frame-head coordination extraction.
Packet 32 is frame-tail job cancellation and outcome type extraction.
Packet 33 is ViewGraph lifecycle planning extraction.
Packet 34 is presentation item and storage model extraction.
Packet 35 is built-in presentation coordinator extraction.
Packet 36 is presentation registry support extraction.
Packet 37 is presentation portal state transaction extraction.
Packet 38 is ViewGraph structural removal planning extraction.
Packet 39 is ViewGraph dirty-evaluation planning extraction.
Packet 40 is TerminalHost presentation emission builder extraction.
Packet 41 is Terminal render-style codec file split.
Packet 42 is Terminal cell text rendering and sanitization extraction.
Packet 43 is Terminal surface damage/span rendering extraction.
Packet 44 is Terminal capability-profile file split.
Packet 45 is TabView style host split.
Packet 46 is semantic accessibility extraction.
Packet 47 is text layout cache extraction.
Packet 48 is text layout wrapping extraction.
Packet 49 is text layout truncation extraction.
Packet 50 is text cell-width policy extraction.
Packet 51 is prompt presentation entrypoint extraction.
Packet 52 is prompt presentation surface extraction.
Packet 53 is toast presentation extraction.
Packet 54 is resolved semantic metadata extraction.
Packet 55 is resolved lifecycle, matched-geometry, and indexed-child support
type extraction.
Packet 56 is resolved-node traversal and equivalence extraction.
Packet 57 is metadata, identity, accessibility, focus, environment, layout-value,
and alignment-guide modifier extraction.
Packet 58 is lifecycle modifier extraction and the `.task` policy guard path
update.
Packet 59 is layout/decorative modifier extraction.
Packet 60 is built-in stack layout extraction.
Packet 61 is custom-layout bridge rename to `CustomLayout.swift`.
Packet 62 is ViewGraph dependency-index and runtime-registration helper
extraction.
Packet 63 is built-in TabView style chrome extraction.
Packet 64 is list/outline style family splitting.
Packet 65 is button style chrome extraction.
Packet 66 is Stepper/Slider adjustable-control splitting.
Packet 67 is measurement work-stack support decomposition.
Packet 68 is placement work-stack support decomposition.
Packet 69 is ViewNode debug and committed-accessor splitting.
Packet 70 is layout-border raster extraction.
Packet 71 is LineChart support decomposition.
Packet 72 is semantic payload routing extraction.
Packet 73 is pointer hit-testing and hover splitting.
Packet 74 is run-loop session type extraction.
Packet 75 is snapshot style-description extraction.
Packet 76 is image asset model extraction.
Packet 77 is canvas pixel-grid drawing extraction.
Packet 78 is canvas payload extraction.
Packet 79 is frame diagnostic record extraction.
Packet 80 is gradient style family extraction.
Packet 81 is run-loop runtime support extraction.
Packet 82 is stack axis support extraction.
Packet 83 is stack lazy allocation extraction.
Packet 84 is stack metrics extraction.
Packet 85 is stack space allocation extraction.
Packet 86 is stack minimum-size extraction.
Packet 87 is frame diagnostics TSV formatting extraction.
Packet 88 is terminal style JSON transport extraction.
Packet 89 is terminal style Base64 transport extraction.
Packet 90 is frame-tail model extraction.
Packet 91 is terminal POSIX controller extraction.
Packet 92 is shape style family extraction.
Packet 93 is theme and terminal render-style extraction.
Packet 94 is stroke style and shape payload extraction.
Packet 95 is resolved text style extraction.
Packet 96 is styling policy path cleanup.
Packet 97 is draw payload extraction.
Packet 98 is text style metadata extraction.
Packet 99 is draw metadata extraction.
Packet 100 is selection tag extraction.
Packet 101 is list payload extraction.
Packet 102 is scene builder artifact extraction.
Packet 103 is window scene configuration extraction.
Packet 104 is window scene selection extraction.
Packet 105 is hosted raster surface state extraction.
Packet 106 is accessibility text sanitizer extraction.
Packet 107 is completed-frame candidate coordination extraction.
Packet 108 is run-loop render-driver support extraction.
Packet 109 is animation placed-tree capture extraction.
Packet 110 is ViewGraph debug snapshot extraction.
Packet 111 is frame-tail worker executor extraction.
Packet 112 is DefaultRenderer runtime subsystem support extraction.
Packet 113 is run-loop resolve-context support extraction.
Packet 114 is frame-acquisition outcome support extraction.
Packet 115 is animation controller snapshot type extraction.
Packet 116 is ViewGraph node checkpointing support extraction.
Packet 117 is run-loop post-commit support extraction.
Packet 118 is frame diagnostic record assembly extraction.
Packet 119 is animation resolved-tree diffing support extraction.
Packet 120 is ViewGraph invalidation planning extraction.
Packet 121 is snapshot renderer diagnostics extraction.
Packet 122 is frame-tail inline stage renderer extraction.
Packet 123 is event pump support extraction.
Packet 124 is runtime issue reporting extraction.
Packet 125 is committed-frame diagnostics builder extraction.
Packet 126 is ViewGraph lifecycle event collection extraction.
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
pointer-hover cleanup reset, input control-message ordering, keyboard-only
input filtering, mouse-coordinate snapshot, pending mouse flush, or
DispatchSource/WASI stream-finish, terminal byte parser buffering, SGR mouse
coordinate decoding, bracketed-paste envelope, key parser regression, read
would-block/EOF classification, drained-bytes-before-EOF behavior, or
non-would-block input failure handling, placed removal overlay sampling,
insertion offset sampling, matched-geometry offset sampling, animation
custom-state writeback, animation batch release, stranded completion deadline,
repeat-forever completion suppression, frame-head completion deferral,
late-preference reconciliation, prepared-state materialization, queued-tail
cancellation, or frame-tail raster handoff
or frame-head preparation ordering, resolve input handoff, observation draft
visibility, presentation portal identity, animation-injection stage separation,
worker indexed-child snapshotting, frame-tail job-state raw values, pre-start
cancellation transition, queued waiter resumption, or cancellable render outcome
diagnostics, lifecycle event ordering, viewport lifecycle visibility, lazy
indexed viewport transitions, lifecycle preview purity, dirty-state clearing,
structural child-removal planning, subtree teardown order, committed removal
snapshots, dependency cleanup, row-span render-state carry, terminal text
control-scalar replacement, ASCII glyph degradation, SGR style lowering, OSC 8
destination sanitization, hyperlink close ordering, row-damage span sorting,
cursor-forward gap emission, candidate range clamping, wide-glyph continuation
normalization, changed-cell span-width accounting, UTF-8 capability detection,
NO_COLOR handling, non-TTY/dumb fallback, rich-terminal capability flags, or
RuntimeConfiguration terminal capability overlays, TabView hosted strip or
overflow placement, tab/overflow identity stability, accessibility node
parent/hidden/cursor-anchor output, visual-content warning output, text-layout
cache hit/miss/eviction counters, text-layout cache retention order,
word-boundary wrapping, continuation-marker output, truncation ellipsis
placement, terminal cell-width classification, public text layout API behavior,
prompt public overload, presentation attachment token, default dismiss title,
prompt authoring-context capture, prompt surface chrome, prompt focus-scope
metadata, menu intrinsic sizing, close-button behavior, toast public overload,
toast semantic icon, toast auto-dismiss lifecycle task, toast overlay
placement, toast hit-testing behavior, or presentation accessibility guardrail
coverage, resolved semantic metadata merge/focus/accessibility behavior,
lifecycle metadata public behavior, matched-geometry key/config behavior,
indexed-child worker snapshotting, custom-layout fallback summaries,
resolved-node traversal order, lifecycle collection order, measurement or
placement equivalence, type-discriminator compatibility, or `ResolvedNode`
equality, view metadata/identity/environment/accessibility/focus modifier
behavior, layout-value or alignment-guide propagation, lifecycle event/task
registration, task actor-inheritance, safe-area propagation, border layout or
raster behavior, frame/padding/overlay/background behavior, offset or
matched-geometry transition contribution, stack layout spacing/alignment, built-in
layout-behavior detection, `AnyLayout` cache scoping, custom-layout placement
fallbacks, `SendableLayout` worker execution, or custom-layout stack-minimum
behavior, ViewGraph dependency indexing, runtime-registration alias replay,
TabView style overflow/chrome, List/Outline style presentation, Button
focus/pressed/role chrome, Stepper key or pointer handling, Slider key or
fractional pointer handling, adjustable-control accessibility-role behavior,
measurement or placement work-stack ordering, retained/custom placement,
`ViewNode` debug snapshots or committed accessors, layout-border raster output,
line-chart domain calculation, line-chart raw glyph output, axis tick labels,
line-chart series composition, semantic payload routing, pointer hit-testing,
hover transitions, run-loop session semantics, snapshot style descriptions,
image asset model behavior, canvas pixel-grid output, canvas payload equality,
frame diagnostic record schema, gradient shape-style behavior, run-loop runtime
support, stack axis conversion, lazy stack visible ranges, stack spacing,
stack surplus allocation, stack minimum sizing, diagnostics TSV output,
terminal style JSON/Base64 transport, frame-tail retained state/model wiring,
POSIX terminal descriptor control, completed-frame candidate construction,
ordered candidate commit effects, render-intent coalescing diagnostics,
animation wake clamping, gesture deadline draining, matched-geometry placed
tree capture, ViewGraph debug snapshot totality, frame-tail worker timing, or
layout-worker cancellation start behavior
appears.

## AI Assistance Disclosure

AI assistance was used for planning, analysis, and drafting/refactoring portions
of this change. A human contributor should review all changed lines, validate
behavior, and run the checks listed in this handoff.
