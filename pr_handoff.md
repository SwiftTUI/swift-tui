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
control-flow extraction. Revert newest-first if a terminal output, raster reuse,
frame-tail, diagnostics, async-cancellation, or public API regression appears.

## AI Assistance Disclosure

AI assistance was used for planning, analysis, and drafting/refactoring portions
of this change. A human contributor should review all changed lines, validate
behavior, and run the checks listed in this handoff.
