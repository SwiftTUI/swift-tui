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

Required repo gate before completion:

```bash
bun run test
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
Revert newest-first if a terminal output, raster reuse, frame-tail,
diagnostics, async-cancellation, cursor-focus, JSON/accessibility output,
image-protocol, fallback image, raw-glyph manifest, SGR-pixels policy, cell
pixel metrics refresh, input precision propagation, raw-mode cleanup,
WebSurface full-repaint byte accounting, presentation damage planning, Kitty
graphics replay planning, matched-geometry traversal, removal subtree lookup,
or public API regression appears.

## AI Assistance Disclosure

AI assistance was used for planning, analysis, and drafting/refactoring portions
of this change. A human contributor should review all changed lines, validate
behavior, and run the checks listed in this handoff.
