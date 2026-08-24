# Testing Your App

Assert on rendered frames with Swift Testing, from one-shot strings to real
terminal journeys.

## Overview

A SwiftTUI frame is a pure function of the view tree and a size proposal.
That makes your app's output directly testable: render one frame, compare
text. The framework ships three surfaces for this, from lightest to heaviest:

- [`RenderOnce`](https://swifttui.sh/docs/documentation/swifttuiterminalcli/renderonce)
  renders a view tree to a terminal-encoded string with no runtime.
- `DefaultRenderer` returns the committed `RenderSnapshot` so tests can
  assert on plain raster lines below the terminal encoding.
- `SwiftTUITestSupport` drives real terminal sessions over a PTY and waits
  for output without polling.

The examples use Swift Testing (`@Test` / `#expect`), the same style as the
framework's own suites. Add the products you need to your test target; see
<doc:Choosing-Modules-And-Platforms> for the product map.

```swift
.testTarget(
  name: "MyAppTests",
  dependencies: [
    "MyAppViews",
    .product(name: "SwiftTUICLI", package: "swift-tui"),
    .product(name: "SwiftTUIArguments", package: "swift-tui"),
    .product(name: "SwiftTUITestSupport", package: "swift-tui"),
  ]
)
```

## Render One Frame With RenderOnce

`RenderOnce` ships in the `SwiftTUICLI` product. Unlike the interactive
runtime it does not grab the alternate screen, install signal handlers, or
enter a run loop: it resolves, measures, places, draws, and rasterizes the
tree once and returns the frame as text. `RenderOnce.print` writes to
stdout; `RenderOnce.render` returns the string, which is the form tests
want.

Every environmental input is a parameter, so a test can pin all of them:

```swift
import SwiftTUIArguments
import SwiftTUICLI

let frame = RenderOnce.render(
  StatusView(),
  width: 40,
  options: try SwiftTUIOptions.parse([]),
  environment: ["LANG": "en_US.UTF-8", "NO_COLOR": "1"],
  isStdoutTTY: false
)
```

- `width` pins the proposal. Unpinned, it falls back to the live terminal
  width, then `$COLUMNS`, then 80 — different on every machine.
- `options` supplies the parsed color/glyph/motion policy; `parse([])` is
  the defaults-only instance, and flags like `--no-color` or `--ascii` can
  be parsed in explicitly.
- `environment` replaces the process environment for capability detection.
  `NO_COLOR: "1"` keeps escape sequences out of the string, and `LANG`
  pins the Unicode glyph policy, so the frame is stable plain text.
- `isStdoutTTY: false` fixes TTY detection instead of inheriting whatever
  descriptor the test runner happens to hold.

## Snapshot Tests Against A Recorded Frame

With those inputs pinned, frame equality is an ordinary string comparison.
The framework tests itself this way: the repository's
`Platforms/CLI/Tests/SwiftTUICLITests/READMECounterFixtureTests.swift`
renders the README's counter sample and compares it to the README's fenced
frame, character for character. The same shape works for an app fixture:

```swift
import Foundation
import SwiftTUIArguments
import SwiftTUICLI
import Testing

@MainActor
struct CounterFrameTests {
  @Test("the counter renders its recorded frame")
  func matchesRecordedFrame() throws {
    let fixture = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/counter-40col.txt")
    let expected = try String(contentsOf: fixture, encoding: .utf8)

    let rendered = RenderOnce.render(
      CounterView(),
      width: 40,
      options: try SwiftTUIOptions.parse([]),
      environment: ["LANG": "en_US.UTF-8", "NO_COLOR": "1"],
      isStdoutTTY: false
    )
    #expect(withoutTrailingNewlines(rendered) == withoutTrailingNewlines(expected))
  }

  private func withoutTrailingNewlines(_ frame: String) -> String {
    var trimmed = Substring(frame)
    while trimmed.last == "\n" { trimmed.removeLast() }
    return String(trimmed)
  }
}
```

To record the fixture the first time, run the same `RenderOnce.render`
call once and write its result to the fixture file, then review the frame
before committing it. Trim trailing newlines on both sides, as above:
editors and renderers disagree about the final newline, and nothing else.

## Render-Level Tests With DefaultRenderer

For assertions below the terminal encoding, use `DefaultRenderer` from
`SwiftTUIRuntime` directly — `RenderOnce` itself is a thin wrapper around
it. Its `render(_:context:proposal:frameInstant:)` method returns a
`RenderSnapshot` whose `rasterSurface.lines` are plain glyph rows with no
escape sequences (styling lives separately in `styleRuns`), so there is no
color policy to pin at all:

```swift
import SwiftTUIRuntime
import Testing

@MainActor
struct BadgeRenderTests {
  @Test("the badge shows its unread count")
  func badgeShowsUnreadCount() {
    let snapshot = DefaultRenderer().render(
      BadgeView(unread: 3),
      proposal: ProposedSize(width: 20, height: nil)
    )
    let rendered = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("3"))
  }
}
```

Know what this path is: one frame, no runtime. There is no run loop and no
invalidator behind a `DefaultRenderer` snapshot, so a `@State` write after
the call schedules nothing and no second frame appears. It is a snapshot
tool, not an interaction tool: in particular, focus and press state are
runtime side fields, so do not assert interactive focus or press output
across successive `render` calls on the same renderer. Drive interactive
behavior through the run loop instead — which is what the next section's
journey drivers are for.

## Deterministic Output In CI

Two conventions keep frames byte-stable on CI runners. First, `NO_COLOR`
(and the wider `CLICOLOR`/`FORCE_COLOR`/`TERM` family) controls escape
sequences, and `NO_COLOR` always wins over `FORCE_COLOR`. Second,
`SWIFTTUI_STABLE_OUTPUT`
disables built-in animation so captured frames show its static form:

```bash
SWIFTTUI_STABLE_OUTPUT=1 swift test
```

You rarely need to set it: when the variable is unset, `CI=true` or a
non-TTY stdout enables stable output automatically, and both hold on
common CI systems. Tests that pass an explicit `environment:` dictionary
to `RenderOnce` are immune to the ambient environment either way, which
is the most reproducible arrangement. The full variable reference is the
[Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables)
article.

## The SwiftTUITestSupport Product

`Package.swift` exports one more product for tests: `SwiftTUITestSupport`
(sources under `Tests/Support/`), the toolkit the framework's own suites
use to wait for runtime state without polling a predicate on a timer. Its
entire surface is `@_spi(Testing)` — test scaffolding, deliberately outside
the supported public API, and its API reference is not yet published on
swifttui.sh. Expect it to move faster than the framework surface. What it
offers today:

- **Poll-free signals** — `AsyncEvent` for one-shot occurrences,
  `MainActorConditionSignal` and `ConditionSignal` for main-actor and
  lock-guarded state. Waiters suspend until a producer notifies; a starved
  CI core delays a test instead of failing it.
- **Stage budgets** — `StageClock`, `ProgressBudget`, and
  `withStageBudget` bound a wait in units of runtime progress rather than
  wall-clock seconds, so the bound is identical on fast and slow machines.
- **Real-terminal journey drivers** — `RealTerminalPTYPair` opens a PTY,
  `writeAllBytes` feeds input, `ANSIVisibleScreen` models what the bytes
  actually put on screen, and `waitForANSIVisibleScreen` waits on readable
  edges (with an explicit deadline) until the visible screen satisfies a
  condition.

A journey test runs your real app against the PTY's slave end and asserts
on the visible screen, adapted from the repository's own journey suites:

```swift
import Dispatch
import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Testing

@Suite
struct GreetingJourneyTests {
  @Test("the app greets, then reacts to a keypress")
  func greetingAppearsOnScreen() async throws {
    let size = CellSize(width: 40, height: 12)
    let pty = try RealTerminalPTYPair.open(size: size)
    defer { pty.close() }

    // Launch the app under test with pty.slave as its terminal
    // (for example, spawn the executable with the slave as stdio).
    launchAppUnderTest(terminal: pty.slave)

    var screen = ANSIVisibleScreen(size: size)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(10)
    ) { rendered in
      rendered.contains("Hello")
    }

    // Keypresses are bytes written to the master end.
    try writeAllBytes(Array(" ".utf8), to: pty.master)
    _ = try await waitForANSIVisibleScreen(
      on: pty.master,
      screen: &screen,
      deadline: .now() + .seconds(10)
    ) { rendered in
      rendered.contains("Pressed")
    }
  }
}
```

`RealTerminalPTYPair.open` throws on platforms without PTY support
(Windows today), so gate journey suites accordingly. Start with
`RenderOnce` fixtures for everything a single frame can prove, reach for
`DefaultRenderer` when you need raster lines without terminal encoding,
and keep the PTY journeys for the interactive paths only a live run loop
exercises.
