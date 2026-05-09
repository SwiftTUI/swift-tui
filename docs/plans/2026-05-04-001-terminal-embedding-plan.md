---
title: "feat: terminal-program embedding via TerminalView, with file-previewer example"
type: feature
status: shipped
date: 2026-05-04
completed: 2026-05-05
depends_on:
  - "../proposals/TERMINAL_EMBEDDING.md"
  - "../HOST_PACKAGES.md"
  - "../PUBLIC_SURFACE_POLICY.md"
  - "../decisions/0007-host-packages-are-peers.md"
  - "../decisions/0008-swifttui-library-only-runners-own-main.md"
---

# Terminal Embedding Implementation Plan

> **Status:** Shipped on 2026-05-05. The implementation lives in
> `Platforms/Embedding`, the validation example lives in
> `Examples/file-previewer`, and the durable current-state docs are
> `docs/EMBEDDING.md`, `docs/STATUS.md`, and `docs/SOURCE_LAYOUT.md`. The
> unchecked boxes below are retained as historical execution notes, not active
> work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Keep commits scoped to each task that reaches a green checkpoint.
> Run `swiftly run swift test` (or the targeted filter shown per stage) after
> each implementation step.

**Goal:** Land embedding of external terminal programs as a SwiftTUI `View`,
with a column-view file previewer as the validation example, on an architecture
that does not preclude later multiplexer-grade features (sixel-in-pane, OSC 99
namespacing, render-diff under SSH, Kitty keyboard).

**Architecture:** A new peer package `Platforms/Embedding` ships one library
`SwiftTUITerminal` containing the emulator wrapper (over SwiftTerm), the PTY
process driver, the `TerminalSession` protocol, the `TerminalProcessSession`
actor, and the `TerminalView` widget. `Core` gains exactly one new
`DrawCommand.foreignSurface` variant plus a `ForeignSurfacePayload`/`ForeignGrid`
pair. The existing `Platforms/CLI/PtyPair` and the new PTY-process driver
consolidate onto a shared `openpty` primitive in a new tiny target
`Platforms/Embedding/Sources/SwiftTUIPTYPrimitives`. The validation example is
`Examples/file-previewer`: a Miller-column file browser whose rightmost column
is a `TerminalView` running a configurable previewer command.

**Tech Stack:** Swift 6.3 strict concurrency + strict memory safety, Swift
Testing for new tests, `SwiftTerm` (preconcurrency-imported, actor-isolated),
POSIX `forkpty` and `TIOCSWINSZ`, `DispatchSource.makeProcessSource` for child
exit, the repo's seven-phase pipeline and `RunLoop+EventDispatch`, custom
`Layout` for Miller columns.

---

## Problem Frame

[TERMINAL_EMBEDDING.md](../proposals/TERMINAL_EMBEDDING.md) is the design.
This plan turns it into landed code in a single direction:

1. Add the rasterizer seam first (`Stage 1`) so every later tier produces
   something the existing pipeline already knows how to commit.
2. Build the emulator wrapper second (`Stage 2`) so the PTY driver has a
   consumer for its bytes.
3. Build the PTY driver third (`Stage 3`), consolidating with `PtyPair`.
4. Compose driver + emulator into a session (`Stage 4`).
5. Wrap the session in a SwiftUI-shaped widget (`Stage 5`).
6. Add the input edge cases that real children depend on (`Stage 6`).
7. Build the file-previewer example to validate the whole stack
   (`Stage 7`).
8. Verify the existing commit-phase diff still produces a minimal byte
   stream over a slow link (`Stage 8`).
9. Land docs (`Stage 9`).

Each stage produces a green-checkpoint commit on its own. Stages 1–5 are
load-bearing for the file previewer. Stages 6 and 8 are required for
"multiplexer-grade" claim. Stage 7 is the example. Stage 9 is the writeup.

## Completion Record

Terminal embedding shipped as a peer package on 2026-05-05. The landed surface
includes:

- `SwiftTUIPTYPrimitives` for shared PTY lifecycle, read/write, resize, and CLI
  scene-attachment reuse.
- `SwiftTUITerminal` with the SwiftTerm-backed emulator wrapper, child-process
  driver, `TerminalSession`, `TerminalProcessSession`, `TerminalView`, and
  terminal metadata modifiers.
- `DrawCommand.foreignSurface` and rasterizer support for embedding foreign
  terminal grids inside the existing seven-phase frame pipeline.
- The `Examples/file-previewer` package as the validation app.
- Render-diff, SSH-latency, session lifecycle, input-mode, layout, and
  file-previewer tests in the peer packages.
- Current-state documentation in `docs/EMBEDDING.md`, `docs/STATUS.md`,
  `docs/SOURCE_LAYOUT.md`, and `docs/VISION.md`.

## Non-Goals

- Sixel passthrough *inside* a tiled pane. Full-screen child sixel works
  (Stage 8), tiled does not. Deferred per proposal.
- Kitty graphics protocol. Deferred per proposal.
- Kitty keyboard protocol (`\e[>1u` and friends). v1 ships legacy keyboard
  + bracketed paste only.
- OSC 99 (Kitty notifications) namespacing. Deferred.
- iOS / WASI builds of `Platforms/Embedding`. The package gates on
  `canImport(Darwin) || canImport(Glibc)`.
- A clean-room VT parser. v1 wraps SwiftTerm. The wrapper is the public
  surface so a clean-room replacement is feasible later.
- Plugin system. Out of scope for this plan entirely.
- Public `Process` wrapper. Process spawning is internal to
  `TerminalProcessSession`.

## Files

### Created

- `Platforms/Embedding/Package.swift`
- `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/OpenPTY.swift`
- `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYPair.swift`
- `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYErrors.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulator.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulatorEvents.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulatorKeys.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulatorMouse.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/ChildProcessPty.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalSession.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalProcessSession.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalView.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalViewModifiers.swift`
- `Platforms/Embedding/Sources/SwiftTUITerminal/SwiftTUITerminal.swift` (re-export root)
- `Platforms/Embedding/Tests/SwiftTUIPTYPrimitivesTests/PTYPairTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/EmulatorWrapperTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/ChildProcessPtyTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/SessionLifecycleTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/TerminalViewLayoutTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/TerminalViewInputTests.swift`
- `Platforms/Embedding/Tests/SwiftTUITerminalTests/RenderDiffTests.swift`
- `Platforms/CLI/Sources/SwiftTUICLI/ScenePty.swift` (replaces `PtyPair.swift`)
- `Examples/file-previewer/Package.swift`
- `Examples/file-previewer/Sources/FilePreviewerApp/FilePreviewerApp.swift`
- `Examples/file-previewer/Sources/FilePreviewerApp/ColumnBrowser.swift`
- `Examples/file-previewer/Sources/FilePreviewerApp/MillerLayout.swift`
- `Examples/file-previewer/Sources/FilePreviewerApp/PreviewerRegistry.swift`
- `Examples/file-previewer/Sources/FilePreviewerApp/FileEntry.swift`
- `Examples/file-previewer/Tests/FilePreviewerAppTests/MillerLayoutTests.swift`
- `Examples/file-previewer/Tests/FilePreviewerAppTests/PreviewerRegistryTests.swift`
- `Tests/SwiftTUICoreTests/ForeignSurfaceTests.swift`
- `docs/EMBEDDING.md`
- `Sources/SwiftTUI/SwiftTUI.docc/TerminalEmbedding.md` (DocC article)

### Modified

- `Sources/SwiftTUICore/Draw/DrawTreeTypes.swift` — add
  `DrawCommand.foreignSurface(bounds:, payload:)` plus
  `ForeignSurfacePayload` protocol and `ForeignGrid` struct
- `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift` — add the new switch arm at line ~174
  that blits a foreign grid into `cells`
- `Sources/SwiftTUICore/Draw/DrawExtractor.swift` — pass-through of the new variant
- `Platforms/CLI/Sources/SwiftTUICLI/PtyPair.swift` — **deleted**;
  replaced by `ScenePty.swift`. `ScenePty` is a thin attach-mode
  wrapper over the new shared `PTYPair` actor in
  `SwiftTUIPTYPrimitives`. Public surface migrates: `masterFD`/
  `slavePath`/`hasAttachedClient()`/`close()` remain; raw fd reads
  in `SceneRuntime` move onto `PTYPair` methods.
- `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift` — switch
  raw `read(2)`/`write(2)` calls on `pair.masterFD` to
  `pair.pair.read()` / `pair.pair.write(_:)` (i.e. into the new
  `PTYPair` API). Same observable behavior; cleaner concurrency.
- `Platforms/CLI/Sources/SwiftTUICLI/SocketServer.swift` and
  `AttachProxy.swift` — same migration where they read from or
  write to the master fd.
- `Platforms/CLI/Sources/SwiftTUICLI/PlatformPOSIX.swift` — drop
  pty-related helpers (`scenePtyName`, `sceneConfigureNoSigPipe`)
  now in `SwiftTUIPTYPrimitives`.
- `Platforms/CLI/Package.swift` — add `Platforms/Embedding` path
  dependency for `SwiftTUIPTYPrimitives`.
- `Package.swift` — no changes; `Platforms/Embedding` is a peer package
  that consumers opt into separately
- `docs/STATUS.md` — add embedding to the shipped surface
- `docs/SOURCE_LAYOUT.md` — add `Platforms/Embedding`
- `docs/VISION.md` — add embedding as a confirmed capability
- `Scripts/test_all.sh` — add `Platforms/Embedding` and
  `Examples/file-previewer` to the test surface
- `.cspell/custom-dictionary-workspace.txt` — add domain words

### Vendored (external)

- SwiftTerm pinned to a specific tag, added as an SPM dependency of the
  `SwiftTUITerminal` target only. Not vendored into `Vendor/` because the
  emulator wrapper is the only consumer and SwiftTerm is large.

## Core Invariants

The pipeline contract during and after this plan:

1. `DrawCommand.foreignSurface` is the *only* new draw variant. No new
   pipeline phase, no parallel commit path.
2. The rasterizer copies cells from a foreign grid into its `cells` array
   inside the same loop that handles every other draw command. A foreign
   grid is **not** composited as a separate layer; it competes for the
   same cells as the rest of the draw commands and respects clip bounds.
3. `ForeignSurfacePayload` is `Sendable` and snapshot-shaped. Producing a
   payload must not require mutation of an actor under the rasterizer.
   The session takes a snapshot synchronously off-actor before draw runs.
4. `TerminalProcessSession` is an `@Observable` wrapper that owns one
   `TerminalEmulator` actor and one `ChildProcessPty` actor. Its
   public surface is `Sendable`-safe to share with any number of
   `TerminalView` instances; only one renders at a time per session.
5. Resize is a **layout consequence**, not a separate signal. When
   `TerminalView`'s assigned `CellRect` changes size, it enqueues
   `await session.resize(_:)` on a `.task(id: bounds.size)` lifecycle
   hook. No new runtime mechanism is required.
6. Foundation-free policy is preserved in `SwiftTUICore`/`SwiftTUIViews`/`SwiftTUI`. The
   new `ForeignSurfacePayload` types are pure value/protocol shapes; no
   Foundation imports leak into `Core`. The rest of the work lives in
   `Platforms/Embedding` which is allowed to use Foundation.
7. `AnyView` policy is preserved. `TerminalView<Session>` is generic
   over `Session: TerminalSession`. No `[any TerminalSession]` storage,
   no `AnyTerminalSession`, no builder closures returning erased
   sessions.
8. **PTY consolidation (Option D, deep merge).** The shared *type*
   is `PTYPair`, an actor in `SwiftTUIPTYPrimitives` that owns
   `masterFD`, `slavePath`, `read()` (`AsyncStream<[UInt8]>`),
   `write(_:)`, `resize(_:)`, and `close()`. Two role-specific
   wrappers compose around it:
   - `ScenePty` (in `Platforms/CLI`, replaces today's `PtyPair`):
     adds `hasAttachedClient()` polling, no spawn. Used by
     `SceneRuntime`/`SocketServer`/`AttachProxy`.
   - `ChildProcessPty` (in `Platforms/Embedding`): adds child `pid`,
     spawn (inlined `forkpty`: open the pty, fork, `login_tty` in
     child, `execve`), `sendSignal(_:)`, and exit waitpid via a
     per-child `DispatchSource.makeProcessSource`. Used by
     `TerminalProcessSession`.
   This is *not* a single unified type with a mode flag — the
   wrappers' state has different *kinds*, not just different values.
   It *is* a real merge: the shared type does fd lifecycle and I/O,
   not just a single libc call.

---

## Stage 0: Baseline Characterization

**Why first:** The existing `PtyPair` is consumed by `SceneRuntime` and
`SocketServer`. Before extracting the `openpty` primitive, lock down
what `PtyPair` is doing today so the extraction does not regress
secondary-scene attach.

**Files:**
- Create: `Platforms/CLI/Tests/SwiftTUICLITests/PtyPairCharacterizationTests.swift`

- [ ] **Step 0.1: Write a characterization test for `PtyPair.init`**

```swift
import Testing
@testable import SwiftTUICLI

@Suite("PtyPair characterization")
struct PtyPairCharacterizationTests {
  @Test("init opens a usable master fd and slave path")
  func initOpensUsableFds() throws {
    let pair = try PtyPair()
    defer { pair.close() }
    #expect(pair.masterFD >= 0)
    #expect(!pair.slavePath.isEmpty)
    #expect(pair.slavePath.hasPrefix("/dev/"))
  }

  @Test("hasAttachedClient returns false when no client has opened the slave")
  func hasAttachedClientFalseInitially() throws {
    let pair = try PtyPair()
    defer { pair.close() }
    #expect(pair.hasAttachedClient() == false)
  }
}
```

- [ ] **Step 0.2: Run the test, expect PASS**

```bash
swiftly run swift test --package-path Platforms/CLI \
  --filter SwiftTUICLITests.PtyPairCharacterizationTests
```

Expected: 2 tests pass. This is the baseline; the same tests must pass
after Stage 3 consolidation without source changes.

- [ ] **Step 0.3: Commit the characterization tests**

```bash
git add Platforms/CLI/Tests/SwiftTUICLITests/PtyPairCharacterizationTests.swift
git commit -m "test: add PtyPair characterization tests as Stage 0 baseline"
```

---

## Stage 1: Foreign Cell Rectangles in Core

**Why second:** This is the smallest landable change that proves the
seam works. Once `DrawCommand.foreignSurface` rasterizes correctly, every
later stage can produce one and trust the commit pipeline to render it.

**Files:**
- Modify: `Sources/SwiftTUICore/Draw/DrawTreeTypes.swift:41` (the
  `DrawCommand` enum) — add new case
- Create: `Sources/SwiftTUICore/Draw/ForeignSurface.swift` — protocol + grid types
- Modify: `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift` — add switch arm at the
  command dispatch loop (the third `while let frame = stack.popLast()`
  block in `Rasterizer+Paint.swift`, currently at line 174)
- Modify: `Sources/SwiftTUICore/Draw/DrawExtractor.swift` — pass-through
- Create: `Tests/SwiftTUICoreTests/ForeignSurfaceTests.swift`

- [ ] **Step 1.1: Define the foreign-surface types (Foundation-free)**

Create `Sources/SwiftTUICore/Draw/ForeignSurface.swift`:

```swift
public protocol ForeignSurfacePayload: Sendable {
  var grid: ForeignGrid { get }
}

public struct ForeignGrid: Sendable, Equatable {
  public var size: CellSize
  public var cells: [[RasterCell]]

  public init(size: CellSize, cells: [[RasterCell]]) {
    self.size = size
    self.cells = cells
  }

  public static let empty = ForeignGrid(size: CellSize(width: 0, height: 0), cells: [])
}
```

- [ ] **Step 1.2: Add `DrawCommand.foreignSurface` case**

In `Sources/SwiftTUICore/Draw/DrawTreeTypes.swift`, extend the
`DrawCommand` enum (currently ending at line ~118 with `case clip`):

```swift
case foreignSurface(bounds: CellRect, payload: any ForeignSurfacePayload)
```

`Equatable` conformance: the `DrawCommand` enum already has manual
`==`. Add a case comparing `bounds` only (foreign surfaces are
identity-irrelevant for equality; the rasterizer reads `payload.grid`
each draw).

- [ ] **Step 1.3: Write a failing rasterizer test for foreign surface blit**

Create `Tests/SwiftTUICoreTests/ForeignSurfaceTests.swift`:

```swift
import Testing
@testable import SwiftTUICore

@Suite("Foreign surface rasterization")
struct ForeignSurfaceTests {
  struct StaticPayload: ForeignSurfacePayload {
    let grid: ForeignGrid
  }

  @Test("foreign surface cells appear at the right bounds")
  func foreignSurfaceBlit() {
    let cells: [[RasterCell]] = [
      [RasterCell(character: "A"), RasterCell(character: "B")],
      [RasterCell(character: "C"), RasterCell(character: "D")],
    ]
    let payload = StaticPayload(grid: ForeignGrid(size: CellSize(width: 2, height: 2), cells: cells))
    let command: DrawCommand = .foreignSurface(
      bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 2, height: 2)),
      payload: payload
    )

    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(
      DrawNode(
        identity: .root,
        bounds: CellRect(origin: .zero, size: CellSize(width: 4, height: 4)),
        commands: [command]
      )
    )

    #expect(surface.cells[1][1].character == "A")
    #expect(surface.cells[1][2].character == "B")
    #expect(surface.cells[2][1].character == "C")
    #expect(surface.cells[2][2].character == "D")
    #expect(surface.cells[0][0].character == RasterCell.empty.character)
  }
}
```

- [ ] **Step 1.4: Run the test, expect FAIL with "missing case .foreignSurface"**

```bash
swiftly run swift test --filter SwiftTUICoreTests.ForeignSurfaceTests
```

Expected: compile error in `Rasterizer.swift` for non-exhaustive switch
on `DrawCommand`.

- [ ] **Step 1.5: Add the rasterizer switch arm**

In `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift` inside the
dispatch loop (the third `while let frame = stack.popLast()` block,
currently at line 174), add a new switch arm next to the existing
`.canvas` arm at the bottom of the switch:

```swift
case .foreignSurface(let bounds, let payload):
  guard bounds.size.width > 0, bounds.size.height > 0 else { continue }
  let grid = payload.grid
  let effectiveClip = frame.clip ?? bounds
  for row in 0..<min(grid.size.height, bounds.size.height) {
    let y = bounds.origin.y + row
    if y < effectiveClip.origin.y || y >= effectiveClip.origin.y + effectiveClip.size.height {
      continue
    }
    guard row < grid.cells.count else { break }
    let sourceRow = grid.cells[row]
    for col in 0..<min(grid.size.width, bounds.size.width) {
      let x = bounds.origin.x + col
      if x < effectiveClip.origin.x || x >= effectiveClip.origin.x + effectiveClip.size.width {
        continue
      }
      guard col < sourceRow.count else { break }
      guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else { continue }
      cells[y][x] = sourceRow[col]
    }
  }
```

- [ ] **Step 1.6: Add `DrawExtractor` pass-through**

In `Sources/SwiftTUICore/Draw/DrawExtractor.swift`, the foreign-surface variant has
no extracted children — it is a leaf. Find the command-walking switch
and add:

```swift
case .foreignSurface:
  break  // leaf; no decomposition or transformation
```

- [ ] **Step 1.7: Run all Core tests, expect PASS**

```bash
swiftly run swift test --filter SwiftTUICoreTests
```

- [ ] **Step 1.8: Commit Stage 1**

```bash
git add Sources/SwiftTUICore/Draw/ForeignSurface.swift \
        Sources/SwiftTUICore/Draw/DrawTreeTypes.swift \
        Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift \
        Sources/SwiftTUICore/Draw/DrawExtractor.swift \
        Tests/SwiftTUICoreTests/ForeignSurfaceTests.swift
git commit -m "feat(core): add DrawCommand.foreignSurface for embedded grids"
```

---

## Stage 2: Embedding Package Skeleton + Emulator Wrapper

**Why third:** With the rasterizer seam in place, build the smallest
useful producer of a `ForeignGrid`: an emulator that takes bytes and
exposes a grid snapshot.

**Files:**
- Create: `Platforms/Embedding/Package.swift`
- Create: `Platforms/Embedding/Sources/SwiftTUITerminal/SwiftTUITerminal.swift`
- Create: `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulator.swift`
- Create: `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulatorEvents.swift`
- Create: `Platforms/Embedding/Tests/SwiftTUITerminalTests/EmulatorWrapperTests.swift`

- [ ] **Step 2.1: Create `Platforms/Embedding/Package.swift`**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "swift-tui-embedding",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SwiftTUIPTYPrimitives", targets: ["SwiftTUIPTYPrimitives"]),
    .library(name: "SwiftTUITerminal", targets: ["SwiftTUITerminal"]),
  ],
  dependencies: [
    .package(path: "../.."),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUIPTYPrimitives",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
        .defaultIsolation(.none),
      ]
    ),
    .target(
      name: "SwiftTUITerminal",
      dependencies: [
        "SwiftTUIPTYPrimitives",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
        .defaultIsolation(.none),
      ]
    ),
    .testTarget(
      name: "SwiftTUITerminalTests",
      dependencies: ["SwiftTUITerminal"],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .strictMemorySafety(),
      ]
    ),
  ]
)
```

- [ ] **Step 2.2: Define the emulator event types**

Create `TerminalEmulatorEvents.swift`:

```swift
import SwiftTUICore  // for CellSize

public enum TerminalEmulatorEvent: Sendable, Equatable {
  case titleChanged(String)
  case workingDirectoryChanged(String)
  case clipboardWriteRequested([UInt8])
  case hyperlinkChanged(String?)
  case bell
  case mouseModeChanged(TerminalMouseMode)
  case clientReply([UInt8])
  case bufferActivated(TerminalBufferKind)
  case sizeReported(CellSize)
}

public enum TerminalBufferKind: Sendable, Equatable {
  case normal
  case alternate
}

public enum TerminalMouseMode: Sendable, Equatable {
  case disabled
  case x10
  case button
  case anyEvent
  case sgr
}
```

- [ ] **Step 2.3: Write a failing wrapper test**

Create `EmulatorWrapperTests.swift`:

```swift
import Testing
@testable import SwiftTUITerminal
import SwiftTUICore

@Suite("TerminalEmulator wrapper")
struct EmulatorWrapperTests {
  @Test("emulator initializes at requested size")
  func initSize() async {
    let emulator = TerminalEmulator(size: CellSize(width: 80, height: 24))
    let snapshot = await emulator.snapshot()
    #expect(snapshot.size == CellSize(width: 80, height: 24))
  }

  @Test("feeding plain ASCII produces visible cells")
  func feedAscii() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    _ = await emulator.feed(Array("hello".utf8))
    let snapshot = await emulator.snapshot()
    let firstRow = snapshot.cells[0].prefix(5).map { $0.character }
    #expect(firstRow == ["h", "e", "l", "l", "o"])
  }

  @Test("OSC 0 title changes are reported as events")
  func titleEvent() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let oscTitle = Array("\u{1B}]0;hello-world\u{07}".utf8)
    let events = await emulator.feed(oscTitle)
    #expect(events.contains(.titleChanged("hello-world")))
  }
}
```

- [ ] **Step 2.4: Run the test, expect FAIL with "TerminalEmulator not defined"**

- [ ] **Step 2.5: Implement `TerminalEmulator` actor wrapping SwiftTerm**

Create `TerminalEmulator.swift`. Notes for the implementer:

- `import` SwiftTerm with `@preconcurrency` — its `Sendable`
  annotations are incomplete in the version we depend on.
- The emulator owns one `SwiftTerm.Terminal` instance and one
  `EmulatorDelegate` class that buffers events into the actor.
- `snapshot()` walks SwiftTerm's `Buffer` once per call. The grid is
  copied into a `ForeignGrid`. Color/style mapping from SwiftTerm's
  `Attribute` to our `RasterCell.style` is the largest piece — see
  the matrix below.

```swift
@preconcurrency import SwiftTerm
import SwiftTUICore

public actor TerminalEmulator {
  private let terminal: Terminal
  private let delegate: EmulatorDelegate
  private var pendingEvents: [TerminalEmulatorEvent] = []

  public init(size: CellSize) {
    let delegate = EmulatorDelegate()
    self.delegate = delegate
    self.terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: size.width, rows: size.height))
    delegate.attach(forwarding: { [weak self] event in
      Task { await self?.append(event) }
    })
  }

  public func feed(_ bytes: [UInt8]) -> [TerminalEmulatorEvent] {
    terminal.feed(byteArray: bytes)
    let events = pendingEvents
    pendingEvents.removeAll(keepingCapacity: true)
    return events
  }

  public func snapshot() -> ForeignGrid {
    let buffer = terminal.buffer
    let cols = terminal.cols
    let rows = terminal.rows
    var cells: [[RasterCell]] = []
    cells.reserveCapacity(rows)
    for y in 0..<rows {
      let line = buffer.lines[buffer.yBase + y]
      var row: [RasterCell] = []
      row.reserveCapacity(cols)
      for x in 0..<cols {
        let charData = line[x]
        row.append(Self.rasterCell(from: charData))
      }
      cells.append(row)
    }
    return ForeignGrid(size: CellSize(width: cols, height: rows), cells: cells)
  }

  public func resize(_ size: CellSize) {
    terminal.resize(cols: size.width, rows: size.height)
  }

  public func encode(key: TerminalEmulatorKey) -> [UInt8] {
    // Implemented in Stage 6.
    return key.legacyByteSequence
  }

  private func append(_ event: TerminalEmulatorEvent) {
    pendingEvents.append(event)
  }

  private static func rasterCell(from charData: CharData) -> RasterCell {
    // Body lands in Step 2.7 when the SGR mapping table is filled in.
    // Until then this method does not exist; the wrapper does not
    // compile. Step 2.7 is part of Stage 2 and must land in the same
    // commit as this file.
    return RasterCell(character: charData.getCharacter())
  }
}

private final class EmulatorDelegate: TerminalDelegate {
  private var forward: (@Sendable (TerminalEmulatorEvent) -> Void)?

  func attach(forwarding: @escaping @Sendable (TerminalEmulatorEvent) -> Void) {
    self.forward = forwarding
  }

  func setTerminalTitle(source: Terminal, title: String) {
    forward?(.titleChanged(title))
  }
  func hostCurrentDirectoryUpdated(source: Terminal, directory: String?) {
    if let directory { forward?(.workingDirectoryChanged(directory)) }
  }
  func send(source: Terminal, data: ArraySlice<UInt8>) {
    forward?(.clientReply(Array(data)))
  }
  func bell(source: Terminal) {
    forward?(.bell)
  }
  // ...other delegate methods forward to .clipboardWriteRequested,
  // .hyperlinkChanged, .mouseModeChanged, .bufferActivated.
}
```

- [ ] **Step 2.6: Define `TerminalEmulatorKey` placeholder**

Create `TerminalEmulatorKeys.swift`:

```swift
public struct TerminalEmulatorKey: Sendable, Equatable, Hashable {
  public enum Code: Sendable, Equatable, Hashable {
    case character(Character)
    case enter
    case backspace
    case escape
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)  // F1..F12
  }

  public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
  }

  public var code: Code
  public var modifiers: Modifiers

  public init(code: Code, modifiers: Modifiers = []) {
    self.code = code
    self.modifiers = modifiers
  }

  // Stub: legacy encoding only. Stage 6 fills in mode-aware variants.
  public var legacyByteSequence: [UInt8] {
    switch code {
    case .character(let c): return Array(String(c).utf8)
    case .enter: return [0x0D]
    case .backspace: return [0x7F]
    case .escape: return [0x1B]
    case .tab: return [0x09]
    case .arrowUp: return [0x1B, 0x5B, 0x41]
    case .arrowDown: return [0x1B, 0x5B, 0x42]
    case .arrowRight: return [0x1B, 0x5B, 0x43]
    case .arrowLeft: return [0x1B, 0x5B, 0x44]
    case .home: return [0x1B, 0x5B, 0x48]
    case .end: return [0x1B, 0x5B, 0x46]
    case .pageUp: return [0x1B, 0x5B, 0x35, 0x7E]
    case .pageDown: return [0x1B, 0x5B, 0x36, 0x7E]
    case .function(let n) where (1...4).contains(n):
      return [0x1B, 0x4F, UInt8(0x50 + n - 1)]  // SS3 P/Q/R/S for F1-F4
    case .function(let n):
      let codes: [Int: [UInt8]] = [5: [0x35,0x7E], 6: [0x37,0x7E], 7: [0x38,0x7E], 8: [0x39,0x7E],
                                   9: [0x32,0x30,0x7E], 10: [0x32,0x31,0x7E],
                                   11: [0x32,0x33,0x7E], 12: [0x32,0x34,0x7E]]
      return [0x1B, 0x5B] + (codes[n] ?? [])
    }
  }
}
```

- [ ] **Step 2.7: Implement the SGR-attribute → `ResolvedTextStyle` mapping**

This is the largest non-obvious piece in the wrapper. SwiftTerm's
`CharData.attribute` is a packed `Int32`. Map it as:

| SwiftTerm bit          | RasterCell.style field           |
|------------------------|----------------------------------|
| FG color (8/16/256/RGB)| `ResolvedTextStyle.foreground`  |
| BG color (8/16/256/RGB)| `ResolvedTextStyle.background`  |
| Bold                   | `.bold`                          |
| Italic                 | `.italic`                        |
| Underline              | `.underline`                     |
| Inverse                | swap fg/bg                       |
| Hidden                 | replace character with space     |
| Strikethrough          | `.strikethrough` (if available)  |

Implement as a free function `rasterCell(from charData: CharData) -> RasterCell`
in `TerminalEmulator.swift`. Test cases:

```swift
@Test("plain ASCII has nil style")
func plainCharStyle() async {
  let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
  _ = await emulator.feed(Array("x".utf8))
  let cell = (await emulator.snapshot()).cells[0][0]
  #expect(cell.character == "x")
  #expect(cell.style == nil)
}

@Test("SGR red foreground produces a red cell")
func sgrRedForeground() async {
  let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
  // CSI 31m (red) ; "x" ; CSI 0m
  _ = await emulator.feed(Array("\u{1B}[31mx\u{1B}[0m".utf8))
  let cell = (await emulator.snapshot()).cells[0][0]
  #expect(cell.style?.foreground == .ansi(.red))
}
```

- [ ] **Step 2.8: Run all emulator tests, expect PASS**

```bash
swiftly run swift test --package-path Platforms/Embedding \
  --filter SwiftTUITerminalTests.EmulatorWrapperTests
```

- [ ] **Step 2.9: Commit Stage 2**

```bash
git add Platforms/Embedding/Package.swift \
        Platforms/Embedding/Sources/SwiftTUITerminal/ \
        Platforms/Embedding/Tests/SwiftTUITerminalTests/EmulatorWrapperTests.swift
git commit -m "feat(embedding): add SwiftTUITerminal package with emulator wrapper"
```

---

## Stage 3: PTY Consolidation (Option D — shared `PTYPair` core)

**Why fourth:** With the emulator able to consume bytes, give it a real
byte source. Same stage promotes today's `PtyPair` into a richer shared
`PTYPair` actor that owns fd lifecycle and I/O, and adds two role-
specific wrappers: `ScenePty` (attach mode, replaces today's `PtyPair`
in CLI) and `ChildProcessPty` (spawn mode, used by the embedding
session). The CLI runtime migrates onto the new `PTYPair` API in the
same stage so secondary-scene attach is fully exercised under the new
shape before any embedding work depends on it.

**Sub-stage ordering** (each substage commits at a green checkpoint):

- 3.A — primitive: `openPTY()` returning `PTYHandles { masterFD,
  slaveFD, slavePath }` (both fds, caller-managed close)
- 3.B — `PTYPair` actor with read/write/resize/close
- 3.C — `ScenePty` wrapper + CLI migration (delete `PtyPair.swift`,
  rewrite `SceneRuntime` / `SocketServer` / `AttachProxy` callers,
  re-run Stage 0 characterization tests)
- 3.D — `ChildProcessPty` wrapper (spawn via inlined `forkpty`)
- 3.E — final verification across both packages

**Files:**
- Create: `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/OpenPTY.swift`
- Create: `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYPair.swift`
- Create: `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYErrors.swift`
- Create: `Platforms/Embedding/Tests/SwiftTUIPTYPrimitivesTests/PTYPairTests.swift`
- Create: `Platforms/CLI/Sources/SwiftTUICLI/ScenePty.swift`
- Delete: `Platforms/CLI/Sources/SwiftTUICLI/PtyPair.swift`
- Modify: `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift`
- Modify: `Platforms/CLI/Sources/SwiftTUICLI/SocketServer.swift`,
  `AttachProxy.swift` (raw fd ops → `PTYPair` methods)
- Modify: `Platforms/CLI/Sources/SwiftTUICLI/PlatformPOSIX.swift`
  (drop pty helpers)
- Modify: `Platforms/CLI/Package.swift` (path dep on Embedding)
- Modify: `Platforms/CLI/Tests/SwiftTUICLITests/PtyPairCharacterizationTests.swift`
  (rename target type from `PtyPair` to `ScenePty`)
- Create: `Platforms/Embedding/Sources/SwiftTUITerminal/ChildProcessPty.swift`
- Create: `Platforms/Embedding/Tests/SwiftTUITerminalTests/ChildProcessPtyTests.swift`

---

### Sub-stage 3.A: `openPTY()` primitive returning both fds

The earlier draft of `openPTY()` closed the slave fd before returning.
That works for attach mode (the future client `open(slavePath)`s its
own slave fd) but is wrong for spawn mode (the child needs the
existing slave fd alive at `fork` time so `login_tty` can dup it onto
0/1/2). The shared primitive must hand back both fds and let each
wrapper close what it doesn't need.

- [ ] **Step 3.A.1: Create `OpenPTY.swift`**

```swift
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct PTYHandles: Sendable {
  public let masterFD: Int32
  public let slaveFD: Int32
  public let slavePath: String
}

public func openPTY() throws(PTYError) -> PTYHandles {
  var masterFD: Int32 = -1
  var slaveFD: Int32 = -1
  guard unsafe openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
    throw .allocationFailed(errno: errno)
  }
  configureNoSigPipe(masterFD)
  configureNoSigPipe(slaveFD)
  guard let slavePath = ttyName(slaveFD) else {
    closeFD(masterFD)
    closeFD(slaveFD)
    throw .slavePathUnavailable
  }
  // Both fds are returned alive. The caller closes the slave when its
  // role allows: ScenePty closes immediately (an attaching client will
  // reopen the slave path); ChildProcessPty keeps it until after fork.
  return PTYHandles(masterFD: masterFD, slaveFD: slaveFD, slavePath: slavePath)
}

public func ptyResize(masterFD: Int32, cols: Int, rows: Int) throws(PTYError) {
  var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
  guard unsafe ioctl(masterFD, TIOCSWINSZ, &ws) == 0 else {
    throw .resizeFailed(errno: errno)
  }
}

public func closeFD(_ fd: Int32) {
  if fd >= 0 { _ = unsafe close(fd) }
}

private func configureNoSigPipe(_ fd: Int32) {
  #if canImport(Darwin)
  _ = unsafe fcntl(fd, F_SETNOSIGPIPE, 1)
  #endif
  // Linux uses MSG_NOSIGNAL on writes; nothing to set fd-side.
}

private func ttyName(_ fd: Int32) -> String? {
  guard let cString = unsafe ttyname(fd) else { return nil }
  return unsafe String(cString: cString)
}
```

- [ ] **Step 3.A.2: Create `PTYErrors.swift`**

```swift
public enum PTYError: Error, CustomStringConvertible, Sendable {
  case allocationFailed(errno: Int32)
  case slavePathUnavailable
  case spawnFailed(errno: Int32)
  case resizeFailed(errno: Int32)
  case writeFailed(errno: Int32)
  case readFailed(errno: Int32)
  case alreadyStarted
  case notStarted

  public var description: String {
    switch self {
    case .allocationFailed(let e): "openpty failed: errno=\(e)"
    case .slavePathUnavailable:    "ttyname returned nil for slave fd"
    case .spawnFailed(let e):      "fork/execve failed: errno=\(e)"
    case .resizeFailed(let e):     "TIOCSWINSZ failed: errno=\(e)"
    case .writeFailed(let e):      "write failed: errno=\(e)"
    case .readFailed(let e):       "read failed: errno=\(e)"
    case .alreadyStarted:          "PTY has already been started"
    case .notStarted:              "PTY has not been started"
    }
  }
}
```

- [ ] **Step 3.A.3: Commit Sub-stage 3.A**

```bash
git add Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/OpenPTY.swift \
        Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYErrors.swift \
        Platforms/Embedding/Package.swift
git commit -m "feat(embedding): add openPTY primitive returning both fds"
```

---

### Sub-stage 3.B: `PTYPair` actor

Shared core that both wrappers compose. Owns the master fd, optional
slave fd (held only until the wrapper says to close it), the slave
path, an at-most-one `AsyncStream` consumer, and a non-blocking
read loop driven by `DispatchSource.makeReadSource`.

- [ ] **Step 3.B.1: Write a failing `PTYPair` test**

Create `Platforms/Embedding/Tests/SwiftTUIPTYPrimitivesTests/PTYPairTests.swift`:

```swift
import Testing
@testable import SwiftTUIPTYPrimitives
import SwiftTUICore

@Suite("PTYPair")
struct PTYPairTests {
  @Test("init from handles exposes masterFD and slavePath")
  func initFromHandles() async throws {
    let handles = try openPTY()
    let pair = PTYPair(handles: handles, retainSlaveFD: false)
    #expect(await pair.rawMasterFD >= 0)
    #expect(await pair.slavePath == handles.slavePath)
    await pair.close()
  }

  @Test("write to master is readable on the slave")
  func writeMasterReadSlave() async throws {
    let handles = try openPTY()
    let pair = PTYPair(handles: handles, retainSlaveFD: true)
    defer { Task { await pair.close() } }
    try await pair.write(Array("hello".utf8))
    // Read the slave fd directly (synchronous test helper)
    var buffer = [UInt8](repeating: 0, count: 16)
    let n = unsafe buffer.withUnsafeMutableBufferPointer { buf in
      unsafe read(handles.slaveFD, buf.baseAddress, buf.count)
    }
    #expect(n >= 5)
    let received = Array(buffer.prefix(Int(n)))
    #expect(received.starts(with: Array("hello".utf8)))
  }

  @Test("resize updates the kernel winsize")
  func resize() async throws {
    let handles = try openPTY()
    let pair = PTYPair(handles: handles, retainSlaveFD: true)
    defer { Task { await pair.close() } }
    try await pair.resize(CellSize(width: 132, height: 50))
    var ws = winsize()
    _ = unsafe ioctl(handles.masterFD, TIOCGWINSZ, &ws)
    #expect(ws.ws_col == 132)
    #expect(ws.ws_row == 50)
  }
}
```

- [ ] **Step 3.B.2: Run the test, expect FAIL with "PTYPair not defined"**

- [ ] **Step 3.B.3: Implement `PTYPair`**

Create `Platforms/Embedding/Sources/SwiftTUIPTYPrimitives/PTYPair.swift`:

```swift
import SwiftTUICore
#if canImport(Darwin)
import Darwin
import Dispatch
#elseif canImport(Glibc)
import Glibc
import Dispatch
#endif

public actor PTYPair {
  public let slavePath: String

  private var masterFD: Int32
  private var retainedSlaveFD: Int32  // -1 if already released
  private var readSource: DispatchSourceRead?
  private var readContinuation: AsyncStream<[UInt8]>.Continuation?
  private var didStartReading = false

  public init(handles: PTYHandles, retainSlaveFD: Bool) {
    self.masterFD = handles.masterFD
    self.slavePath = handles.slavePath
    self.retainedSlaveFD = retainSlaveFD ? handles.slaveFD : -1
    if !retainSlaveFD { closeFD(handles.slaveFD) }
    Self.setNonblocking(handles.masterFD)
  }

  public var rawMasterFD: Int32 { masterFD }

  /// Releases the retained slave fd to the caller. The caller is now
  /// responsible for closing it. Used by `ChildProcessPty` to hand
  /// the slave to the child via `login_tty`.
  public func releaseSlaveFD() -> Int32 {
    let fd = retainedSlaveFD
    retainedSlaveFD = -1
    return fd
  }

  /// Closes the retained slave fd, if any. Used by `ScenePty` and
  /// after a spawn has consumed the slave.
  public func releaseAndCloseSlaveFD() {
    if retainedSlaveFD >= 0 {
      closeFD(retainedSlaveFD)
      retainedSlaveFD = -1
    }
  }

  public func resize(_ size: CellSize) throws(PTYError) {
    guard masterFD >= 0 else { throw .notStarted }
    try ptyResize(masterFD: masterFD, cols: size.width, rows: size.height)
  }

  public func write(_ bytes: [UInt8]) throws(PTYError) {
    guard masterFD >= 0 else { throw .notStarted }
    var offset = 0
    while offset < bytes.count {
      let written = unsafe bytes.withUnsafeBufferPointer { buf -> Int in
        unsafe Foundation_writeRetrying(masterFD, buf.baseAddress! + offset, bytes.count - offset)
      }
      if written < 0 {
        if errno == EINTR { continue }
        throw .writeFailed(errno: errno)
      }
      offset += written
    }
  }

  public func read() -> AsyncStream<[UInt8]> {
    AsyncStream { continuation in
      Task { await self.startReading(continuation: continuation) }
    }
  }

  public func close() {
    readSource?.cancel()
    readSource = nil
    readContinuation?.finish()
    readContinuation = nil
    if masterFD >= 0 { closeFD(masterFD); masterFD = -1 }
    if retainedSlaveFD >= 0 { closeFD(retainedSlaveFD); retainedSlaveFD = -1 }
  }

  // ... private helpers: startReading, drainAvailable, setNonblocking,
  //     and a small Foundation_writeRetrying free function in the
  //     same file (file-private)
}
```

The `Foundation_writeRetrying` helper is a small free function that
calls `write(2)` once and returns the result; the actor's `write(_:)`
loop handles EINTR/EAGAIN. The helper exists so `write(_:)` keeps
its `unsafe` block short.

- [ ] **Step 3.B.4: Run `PTYPairTests`, expect PASS**

```bash
swiftly run swift test --package-path Platforms/Embedding \
  --filter SwiftTUIPTYPrimitivesTests.PTYPairTests
```

- [ ] **Step 3.B.5: Commit Sub-stage 3.B**

```bash
git commit -m "feat(embedding): add PTYPair actor with read/write/resize"
```

---

### Sub-stage 3.C: `ScenePty` and CLI migration

`ScenePty` is a thin wrapper around `PTYPair` for the attach-mode
role. It replaces today's `PtyPair` class. Public surface stays
nearly identical so the SceneRuntime/SocketServer migration is
mechanical.

- [ ] **Step 3.C.1: Create `ScenePty.swift`**

```swift
import SwiftTUIPTYPrimitives

/// Attach-mode wrapper around `PTYPair`: opens a pty, closes the
/// slave fd immediately, exposes the slave path for an attaching
/// client to open. Replaces the original `PtyPair` class.
public final class ScenePty: Sendable {
  public let pair: PTYPair
  public let slavePath: String

  public init() throws(PTYError) {
    let handles = try openPTY()
    self.slavePath = handles.slavePath
    self.pair = PTYPair(handles: handles, retainSlaveFD: false)
  }

  public func hasAttachedClient() async -> Bool {
    let fd = await pair.rawMasterFD
    return _hasAttachedClient(masterFD: fd)
  }

  public func close() async {
    await pair.close()
  }
}

#if canImport(Darwin) || canImport(Glibc)
private func _hasAttachedClient(masterFD fd: Int32) -> Bool {
  // Same poll(POLLHUP) check as today's PtyPair.hasAttachedClient.
  guard fd >= 0 else { return false }
  var descriptor = pollfd(fd: fd, events: Int16(POLLHUP | POLLOUT), revents: 0)
  let result = unsafe poll(&descriptor, 1, 0)
  guard result > 0 else { return false }
  return (descriptor.revents & Int16(POLLHUP)) == 0
}
#endif
```

- [ ] **Step 3.C.2: Migrate `SceneRuntime.swift`, `SocketServer.swift`, `AttachProxy.swift`**

For each call site that currently does raw `read(masterFD, ...)` or
`write(masterFD, ...)`:

- Replace with `await scenePty.pair.write(bytes)` for writes.
- Replace blocking-read loops with the async stream from
  `scenePty.pair.read()` consumed in a `for await` task.
- Replace `pair.close()` with `await scenePty.close()`.

The migration is substantial in code volume but mechanical in
shape — there is no concurrency rethink, just method substitution.

- [ ] **Step 3.C.3: Delete `PtyPair.swift`, drop pty helpers from `PlatformPOSIX.swift`**

```bash
git rm Platforms/CLI/Sources/SwiftTUICLI/PtyPair.swift
```

Drop `scenePtyName`, `sceneConfigureNoSigPipe`, and any other
`scene*` helpers from `PlatformPOSIX.swift` that exist only because
`PtyPair.swift` used them. They are now in `SwiftTUIPTYPrimitives`.

- [ ] **Step 3.C.4: Update `PtyPairCharacterizationTests.swift`**

Rename the file to `ScenePtyCharacterizationTests.swift`. Update the
type references from `PtyPair` to `ScenePty`. The semantics under
test (master fd is opened; `hasAttachedClient()` is `false`
initially) do not change.

```swift
@Suite("ScenePty characterization")
struct ScenePtyCharacterizationTests {
  @Test("init opens a usable master fd and slave path")
  func initOpensUsableFds() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }
    let fd = await pty.pair.rawMasterFD
    #expect(fd >= 0)
    #expect(!pty.slavePath.isEmpty)
    #expect(pty.slavePath.hasPrefix("/dev/"))
  }

  @Test("hasAttachedClient returns false when no client has opened the slave")
  func hasAttachedClientFalseInitially() async throws {
    let pty = try ScenePty()
    defer { Task { await pty.close() } }
    let attached = await pty.hasAttachedClient()
    #expect(attached == false)
  }
}
```

- [ ] **Step 3.C.5: Run the full CLI test surface, expect PASS**

```bash
swiftly run swift test --package-path Platforms/CLI
```

The existing secondary-scene attach tests must pass without
modification beyond the type rename.

- [ ] **Step 3.C.6: Commit Sub-stage 3.C**

```bash
git commit -m "refactor(cli): migrate PtyPair → ScenePty over shared PTYPair core"
```

---

### Sub-stage 3.D: `ChildProcessPty`

The spawn-mode wrapper. It owns a `PTYPair` (created with
`retainSlaveFD: true`), forks, sets up the child's controlling
terminal in the child path via `login_tty`, then `execve`s. The
parent path closes the retained slave fd and registers a
`DispatchSource.makeProcessSource` on the child pid for exit
notification.

- [ ] **Step 3.D.1: Write a failing `ChildProcessPtyTests`**

```swift
import Testing
@testable import SwiftTUITerminal
import SwiftTUIPTYPrimitives
import SwiftTUICore

@Suite("ChildProcessPty")
struct ChildProcessPtyTests {
  @Test("spawn /bin/echo and read its output through the shared pair")
  func spawnEcho() async throws {
    let pty = ChildProcessPty(
      executable: "/bin/echo",
      arguments: ["hello"],
      environment: nil,
      workingDirectory: nil,
      initialSize: CellSize(width: 80, height: 24)
    )
    try await pty.start()
    var collected: [UInt8] = []
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    for await chunk in await pty.pair.read() {
      collected.append(contentsOf: chunk)
      if collected.contains(UInt8(ascii: "\n")) { break }
      if ContinuousClock.now > deadline { break }
    }
    #expect(String(decoding: collected, as: UTF8.self).contains("hello"))
    let exit = await pty.waitForExit()
    #expect(exit == .exited(code: 0))
  }

  @Test("resize forwards through PTYPair to the child")
  func resize() async throws {
    let pty = ChildProcessPty(
      executable: "/bin/cat",
      arguments: [],
      environment: nil,
      workingDirectory: nil,
      initialSize: CellSize(width: 10, height: 5)
    )
    try await pty.start()
    try await pty.pair.resize(CellSize(width: 100, height: 30))
    try await pty.pair.write(Array("\u{04}".utf8))  // Ctrl-D / EOF
    let exit = await pty.waitForExit()
    #expect(exit == .exited(code: 0))
  }

  @Test("sendSignal terminates the child")
  func sendSignal() async throws {
    let pty = ChildProcessPty(
      executable: "/bin/sleep",
      arguments: ["10"],
      environment: nil,
      workingDirectory: nil,
      initialSize: CellSize(width: 80, height: 24)
    )
    try await pty.start()
    try await pty.sendSignal(SIGTERM)
    let exit = await pty.waitForExit()
    #expect(exit == .signalled(signal: SIGTERM))
  }
}
```

- [ ] **Step 3.D.2: Run the test, expect FAIL with "ChildProcessPty not defined"**

- [ ] **Step 3.D.3: Implement `ChildProcessPty`**

Create `Platforms/Embedding/Sources/SwiftTUITerminal/ChildProcessPty.swift`:

```swift
import Foundation
import SwiftTUIPTYPrimitives
import SwiftTUICore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public actor ChildProcessPty {
  public enum ExitStatus: Sendable, Equatable {
    case exited(code: Int32)
    case signalled(signal: Int32)
    case unknown
  }

  public private(set) var pair: PTYPair!
  public private(set) var pid: pid_t = 0

  private let executable: String
  private let arguments: [String]
  private let environment: [String: String]?
  private let workingDirectory: String?
  private let initialSize: CellSize
  private var exitContinuation: CheckedContinuation<ExitStatus, Never>?
  private var exitSource: DispatchSourceProcess?
  private var hasStarted = false

  public init(
    executable: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
    self.initialSize = initialSize
  }

  public func start() throws(PTYError) {
    guard !hasStarted else { throw .alreadyStarted }
    hasStarted = true

    let handles = try openPTY()
    let pair = PTYPair(handles: handles, retainSlaveFD: true)
    self.pair = pair

    // Fork. In the child, perform `login_tty(slaveFD)` (which calls
    // setsid, makes the slave the controlling terminal, dups it onto
    // 0/1/2, and closes the original slave fd). Then chdir / execve.
    // In the parent, close the retained slave fd (the child owns it
    // now) and install a process-exit DispatchSource.
    let slaveFD = handles.slaveFD
    let pid = unsafe fork()
    if pid < 0 {
      throw .spawnFailed(errno: errno)
    }
    if pid == 0 {
      // Child path. Anything past here that fails calls _exit(127).
      Self.executeChildPath(
        slaveFD: slaveFD,
        executable: executable,
        arguments: arguments,
        environment: environment,
        workingDirectory: workingDirectory
      )
    }

    // Parent path.
    self.pid = pid
    Task { await pair.releaseAndCloseSlaveFD() }
    try? await pair.resize(initialSize)
    installExitSource(pid: pid)
  }

  public func waitForExit() async -> ExitStatus {
    await withCheckedContinuation { continuation in
      Task { await self.attach(continuation: continuation) }
    }
  }

  public func sendSignal(_ signal: Int32) throws(PTYError) {
    guard pid > 0 else { throw .notStarted }
    if unsafe kill(-pid, signal) != 0 && unsafe kill(pid, signal) != 0 {
      throw .spawnFailed(errno: errno)
    }
  }

  // ... private helpers: executeChildPath (the post-fork execve path),
  //     installExitSource, attach (continuation handoff)
}
```

The child path (`executeChildPath`) is the most failure-prone code
in the stage. It runs after `fork` and before `execve`, so async-
signal-safety rules apply. Notes for the implementer:

- Call `login_tty(slaveFD)` first — that's `setsid()`, then
  `ioctl(TIOCSCTTY, slaveFD)`, then `dup2(slaveFD, 0/1/2)`, then
  `close(slaveFD)`. On Linux and Darwin, `<util.h>` /
  `<utmp.h>` exposes `login_tty`.
- After `login_tty`, the child has a clean controlling terminal.
- `chdir(workingDirectory)` if set; on failure, `_exit(127)`.
- Build `argv` and `envp` C arrays. Use `posix_spawn`-style
  ownership: copy each `String` to a `strdup`'d C string.
- `execve(executable, argv, envp)`. On any failure here,
  `_exit(127)`. Do not throw, do not call Swift runtime functions,
  do not allocate Foundation types.

- [ ] **Step 3.D.4: Run `ChildProcessPtyTests`, expect PASS**

```bash
swiftly run swift test --package-path Platforms/Embedding \
  --filter SwiftTUITerminalTests.ChildProcessPtyTests
```

- [ ] **Step 3.D.5: Commit Sub-stage 3.D**

```bash
git commit -m "feat(embedding): add ChildProcessPty over shared PTYPair core"
```

---

### Sub-stage 3.E: Cross-package verification

- [ ] **Step 3.E.1: Run the full repo test surface**

```bash
bun run test
```

Both `ScenePtyCharacterizationTests` (CLI) and the new
`PTYPairTests` / `ChildProcessPtyTests` (Embedding) must pass. The
existing secondary-scene attach tests in CLI must pass unchanged
beyond the type rename.

- [ ] **Step 3.E.2: Run the perf evaluation pipeline against CLI**

```bash
Scripts/perf-evaluation.sh --baseline main --target embedding --suite cli
```

The CLI migration moved fd reads from synchronous `read(2)` calls
to `DispatchSource`-driven async streams. The perf gate must show
no regression in secondary-scene attach latency or scene-switch
time.

- [ ] **Step 3.E.3: Lock in Stage 3 with a final no-op commit if needed**

If 3.E.1 / 3.E.2 surface any fixups, commit them with subject
`fix(embedding): ...`. Otherwise no commit; Stage 3 is done.

---

## Stage 4: TerminalSession + TerminalProcessSession

**Files:**
- Create: `TerminalSession.swift`, `TerminalProcessSession.swift`
- Create: `Tests/.../SessionLifecycleTests.swift`

- [ ] **Step 4.1: Define the `TerminalSession` protocol**

```swift
import SwiftTUICore

public protocol TerminalSession: AnyObject, Sendable {
  func snapshot() async -> ForeignGrid
  func currentTitle() async -> String?
  func currentWorkingDirectory() async -> String?
  func currentLifecycle() async -> TerminalLifecycle
  func send(key: TerminalEmulatorKey) async
  func send(paste: String) async
  func resize(_ size: CellSize) async throws
  func events() -> AsyncStream<TerminalEmulatorEvent>
}

public enum TerminalLifecycle: Sendable, Equatable {
  case notStarted
  case running
  case exited(reason: TerminalExitReason)
}

public enum TerminalExitReason: Sendable, Equatable {
  case normal(code: Int32)
  case signal(Int32)
  case sessionClosed
}
```

- [ ] **Step 4.2: Write a failing session lifecycle test**

```swift
@Suite("TerminalProcessSession lifecycle")
struct SessionLifecycleTests {
  @Test("session reaches .running after start, .exited after child exits")
  func runToExit() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "echo hi; exit 0"],
      initialSize: CellSize(width: 40, height: 10)
    )
    try await session.start()

    // Wait up to 2s for exit
    let deadline = Date().addingTimeInterval(2.0)
    while Date() < deadline {
      if case .exited = await session.currentLifecycle() { break }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    if case .exited(let reason) = await session.currentLifecycle() {
      #expect(reason == .normal(code: 0))
    } else {
      Issue.record("session never exited")
    }
  }

  @Test("snapshot reflects child output")
  func snapshotShowsOutput() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "printf hi; sleep 0.5"],
      initialSize: CellSize(width: 10, height: 1)
    )
    try await session.start()
    try await Task.sleep(nanoseconds: 200_000_000)
    let snap = await session.snapshot()
    let firstTwo = snap.cells[0].prefix(2).map { $0.character }
    #expect(firstTwo == ["h", "i"])
  }
}
```

- [ ] **Step 4.3: Implement `TerminalProcessSession`**

```swift
public final class TerminalProcessSession: TerminalSession {
  private let pty: ChildProcessPty
  private let emulator: TerminalEmulator
  private let lifecycleStorage: LifecycleStorage  // an actor wrapping current state
  private let eventBroadcaster: EventBroadcaster  // multicasts emulator events
  private var pumpTask: Task<Void, Never>?

  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: String? = nil,
    initialSize: CellSize
  ) {
    self.pty = ChildProcessPty(
      executable: command,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      initialSize: initialSize
    )
    self.emulator = TerminalEmulator(size: initialSize)
    self.lifecycleStorage = LifecycleStorage()
    self.eventBroadcaster = EventBroadcaster()
  }

  public func start() async throws {
    try await pty.start()
    await lifecycleStorage.set(.running)
    pumpTask = Task { [emulator, pty, eventBroadcaster, lifecycleStorage] in
      // ChildProcessPty does not own a read stream itself; the shared
      // PTYPair core does. Reach through `pty.pair` for I/O.
      let pair = await pty.pair!
      let stream = await pair.read()
      for await chunk in stream {
        let events = await emulator.feed(chunk)
        for event in events {
          await eventBroadcaster.publish(event)
          if case .clientReply(let bytes) = event {
            try? await pair.write(bytes)
          }
        }
      }
      let exit = await pty.waitForExit()
      await lifecycleStorage.set(.exited(reason: Self.reason(from: exit)))
    }
  }

  // ...rest of TerminalSession conformance — `resize(_:)` forwards to
  // `pty.pair.resize(_:)`, `send(key:)` writes to `pty.pair.write(_:)`
  // after asking `emulator.encode(key:)` for the byte sequence.
}
```

- [ ] **Step 4.4: Run session tests, expect PASS**

- [ ] **Step 4.5: Commit Stage 4**

```bash
git commit -m "feat(embedding): add TerminalSession protocol and TerminalProcessSession actor"
```

---

## Stage 5: TerminalView Widget

**Files:**
- Create: `TerminalView.swift`, `TerminalViewModifiers.swift`
- Create: `Tests/.../TerminalViewLayoutTests.swift`,
  `Tests/.../TerminalViewInputTests.swift`

- [ ] **Step 5.1: Write a failing layout test**

```swift
@Suite("TerminalView layout")
struct TerminalViewLayoutTests {
  @Test("TerminalView accepts the parent's full proposal")
  func acceptsProposal() {
    let session = StubSession(grid: ForeignGrid.empty)
    let view = TerminalView(session: session)
    let renderer = DefaultRenderer()
    let frame = renderer.render(view, proposal: .init(width: 40, height: 12))
    #expect(frame.size.width == 40)
    #expect(frame.size.height == 12)
  }

  @Test("draw emits exactly one foreignSurface command at the assigned bounds")
  func emitsForeignSurface() {
    let row = Array(repeating: RasterCell(character: "x"), count: 4)
    let grid = ForeignGrid(
      size: CellSize(width: 4, height: 2),
      cells: Array(repeating: row, count: 2)
    )
    let session = StubSession(grid: grid)
    let view = TerminalView(session: session)
    let renderer = DefaultRenderer()
    let frame = renderer.render(view, proposal: .init(width: 4, height: 2))
    let surfaces = frame.drawTree.flattenedCommands.filter {
      if case .foreignSurface = $0 { return true } else { return false }
    }
    #expect(surfaces.count == 1)
  }
}
```

`StubSession` is a test-only `TerminalSession` whose `snapshot()`
returns a fixed grid.

- [ ] **Step 5.2: Implement `TerminalView<Session>`**

```swift
import SwiftTUI
import SwiftTUICore

public struct TerminalView<Session: TerminalSession>: View {
  private let session: Session
  private let onTitleChange: ((String) -> Void)?
  private let onExit: ((TerminalExitReason) -> Void)?

  public init(
    session: Session,
    onTitleChange: ((String) -> Void)? = nil,
    onExit: ((TerminalExitReason) -> Void)? = nil
  ) {
    self.session = session
    self.onTitleChange = onTitleChange
    self.onExit = onExit
  }

  public var body: some View {
    TerminalSurfaceLeaf(session: session)
      .focusable()
      .task(id: ObjectIdentifier(session)) {
        do { try await session.start() } catch { /* surfaced via lifecycle */ }
      }
      .task {
        for await event in session.events() {
          switch event {
          case .titleChanged(let title): onTitleChange?(title)
          default: break
          }
        }
      }
  }
}

struct TerminalSurfaceLeaf<Session: TerminalSession>: View, ResolvableView {
  let session: Session
  // ResolvableView produces a DrawNode whose commands include
  // `.foreignSurface(bounds:, payload: SessionGridPayload(session: session))`
}

private struct SessionGridPayload<Session: TerminalSession>: ForeignSurfacePayload {
  let session: Session
  var grid: ForeignGrid {
    // Snapshot must be sync at draw time. The session caches its last
    // snapshot in a Sendable box that the actor publishes after each feed.
    session.cachedSnapshot
  }
}
```

The `cachedSnapshot` field is updated whenever the pump task in
`TerminalProcessSession` finishes a feed batch — that's the *one*
extra piece of state that has to live outside the actor boundary so
the rasterizer can read it without `await`. Use `Mutex<ForeignGrid>`
(from `Synchronization`) to keep it `Sendable`-safe.

- [ ] **Step 5.3: Add the resize lifecycle hook**

Wrap the leaf in `.task(id: bounds.size)` that calls
`await session.resize(size)`. The task identity tracks bounds — when
SwiftTUI assigns a new `CellRect`, the task restarts and resize fires
exactly once per resize.

- [ ] **Step 5.4: Add input forwarding**

Subscribe to focused `keyCommand`-equivalent dispatch through
`LocalKeyHandlerRegistry` (already in Core for built-in widgets). On
each key, call `await session.send(key: ...)`. When unfocused, the
view registers no key handler and keys propagate to surrounding scope.

Test (failing first):

```swift
@Test("focused TerminalView forwards a character to the session")
func forwardCharacter() async {
  let session = RecordingSession()
  let view = TerminalView(session: session).focusable()
  await runHarness(view: view, focusing: true) { harness in
    await harness.send(key: .character("a"))
  }
  #expect(session.received == [TerminalEmulatorKey(code: .character("a"))])
}
```

- [ ] **Step 5.5: Implement input forwarding**

`TerminalSurfaceLeaf` registers a focus-scoped key handler in
`semantics` phase. `RecordingSession` is a test-only `TerminalSession`
whose `send(key:)` appends to a `Mutex<[TerminalEmulatorKey]>` so the
test can read what the view forwarded.

```swift
extension TerminalSurfaceLeaf {
  func semanticsContribution(for proposal: ProposedSize) -> SemanticsContribution {
    var contribution = SemanticsContribution()
    contribution.localKeyHandlers.append(LocalKeyHandler { event in
      guard let key = TerminalEmulatorKey(event: event) else { return .notHandled }
      Task { await session.send(key: key) }
      return .handled
    })
    return contribution
  }
}
```

The `TerminalEmulatorKey(event:)` initializer maps the runtime's
`KeyEvent` (defined in `Sources/SwiftTUI/Input/InputReader.swift`) to the
emulator's key vocabulary. Unmappable keys (e.g. SwiftTUI-internal
focus-traversal keys) return `nil` and are not forwarded.

- [ ] **Step 5.6: Run all TerminalView tests, expect PASS**

- [ ] **Step 5.7: Commit Stage 5**

```bash
git commit -m "feat(embedding): add TerminalView with layout, draw, resize, focus integration"
```

---

## Stage 6: Mouse, Paste, Minimum OSC

**Files:**
- Create: `Platforms/Embedding/Sources/SwiftTUITerminal/TerminalEmulatorMouse.swift`
- Modify: `TerminalEmulator.swift`, `TerminalView.swift`,
  `TerminalViewModifiers.swift`

- [ ] **Step 6.1: Mouse mode tracking + SGR encoding**

The emulator already receives mouse-mode-change events from
SwiftTerm's delegate (Step 2.5). Cache the active mode in the actor.
Add `send(mouse: TerminalEmulatorMouse)` that encodes per the active
mode (X10 / 1000 / 1002 / SGR).

Tests: feed `\e[?1006h` to enable SGR mouse, then send a click,
verify the emitted bytes match `\e[<0;5;3M` (SGR press at col 5 row 3).

- [ ] **Step 6.2: Bracketed paste**

When the emulator advertises bracketed-paste (`\e[?2004h`), wrap
`session.send(paste:)` content in `\e[200~ ... \e[201~`. Test:

```swift
@Test("paste is bracketed when the child requests bracketed-paste")
func bracketedPaste() async {
  let session = TerminalProcessSession(
    command: "/bin/sh",
    arguments: ["-c", "printf '\\e[?2004h'; cat"],
    initialSize: CellSize(width: 40, height: 5)
  )
  try await session.start()
  try await Task.sleep(nanoseconds: 200_000_000)  // wait for ?2004h to apply
  await session.send(paste: "hello")
  // Verify via a recording wrapper around `ChildProcessPty.pair.write`
  // that the bytes actually written to the master are
  // \e[200~hello\e[201~.
}
```

- [ ] **Step 6.3: OSC 0/2 (title), OSC 7 (cwd)**

Already plumbed via emulator events (Stage 2). Surface them through
two `View` modifiers in `TerminalViewModifiers.swift`:

```swift
extension View {
  public func terminalTitleChanged(_ handler: @escaping (String) -> Void) -> some View
  public func terminalWorkingDirectoryChanged(_ handler: @escaping (String) -> Void) -> some View
}
```

- [ ] **Step 6.4: OSC 8 (hyperlinks) pass-through**

Hyperlinks are stored as a per-cell attribute in SwiftTerm's
`CharData`. Map to `RasterCell.hyperlink: String?` in Step 2.7's
attribute mapping. The existing `TerminalPresentation.swift`
already emits OSC 8 when committing cells with `hyperlink != nil`,
so no further work is needed here once the cell carries the URL.

- [ ] **Step 6.5: Run Stage 6 tests, expect PASS**

- [ ] **Step 6.6: Commit Stage 6**

```bash
git commit -m "feat(embedding): add mouse modes, bracketed paste, OSC 0/2/7/8"
```

---

## Stage 7: File Previewer Example

**Files:**
- Create: `Examples/file-previewer/Package.swift`
- Create: all sources under `Examples/file-previewer/Sources/FilePreviewerApp/`
- Create: tests under `Examples/file-previewer/Tests/FilePreviewerAppTests/`

The app: a Miller-column file browser. Left column lists the current
directory. Right column is a `TerminalView` running a previewer command
selected by file extension. Arrow keys navigate; the previewer respawns
on selection change.

- [ ] **Step 7.1: Define `FileEntry` and `PreviewerRegistry`**

```swift
public struct FileEntry: Sendable, Hashable {
  public var url: URL
  public var isDirectory: Bool
}

public struct PreviewCommand: Sendable {
  public var executable: String
  public var arguments: (URL) -> [String]
}

public struct PreviewerRegistry: Sendable {
  public var byExtension: [String: PreviewCommand]
  public var fallback: PreviewCommand

  public func command(for url: URL) -> PreviewCommand {
    let ext = url.pathExtension.lowercased()
    return byExtension[ext] ?? fallback
  }
}

extension PreviewerRegistry {
  public static let defaults = PreviewerRegistry(
    byExtension: [
      "md":   PreviewCommand(executable: "/usr/bin/env", arguments: { ["glow", "-s", "dark", $0.path] }),
      "json": PreviewCommand(executable: "/usr/bin/env", arguments: { ["jq", "-C", ".", $0.path] }),
      "yaml": PreviewCommand(executable: "/usr/bin/env", arguments: { ["bat", "--color=always", $0.path] }),
      "yml":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["bat", "--color=always", $0.path] }),
      "toml": PreviewCommand(executable: "/usr/bin/env", arguments: { ["bat", "--color=always", $0.path] }),
      "swift":PreviewCommand(executable: "/usr/bin/env", arguments: { ["bat", "--color=always", $0.path] }),
      "png":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["chafa", "--symbols=block", $0.path] }),
      "jpg":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["chafa", "--symbols=block", $0.path] }),
      "gif":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["chafa", "--symbols=block", $0.path] }),
      "zip":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["unzip", "-l", $0.path] }),
      "tar":  PreviewCommand(executable: "/usr/bin/env", arguments: { ["tar", "-tvf", $0.path] }),
    ],
    fallback: PreviewCommand(executable: "/usr/bin/env", arguments: { ["bat", "--color=always", $0.path] })
  )
}
```

- [ ] **Step 7.2: Write `MillerLayoutTests`**

Two-column case, three-column case, column-width allocation rule
(left columns fixed at 30 cells, rightmost column gets the rest).

- [ ] **Step 7.3: Implement `MillerLayout: Layout`**

Custom `Layout` conforming to SwiftTUI's `Layout` protocol. Splits the
proposal horizontally: each non-last column is `min(30, proposal/N)`
cells; the last column gets the remainder.

- [ ] **Step 7.4: Implement `ColumnBrowser`**

```swift
struct ColumnBrowser: View {
  @State private var path: [URL]  // breadcrumb of selected directories
  @State private var selection: [URL: URL?]  // per-column highlight
  @State private var previewSession: TerminalProcessSession?
  let registry: PreviewerRegistry

  var body: some View {
    MillerLayout {
      ForEach(path, id: \.self) { dir in
        FileColumn(directory: dir, selection: Binding(
          get: { selection[dir] ?? nil },
          set: { newValue in
            selection[dir] = newValue
            advanceOrPreview(directory: dir, selected: newValue)
          }
        ))
      }
      if let session = previewSession {
        TerminalView(session: session)
      } else {
        Text("(no preview)")
      }
    }
  }

  private func advanceOrPreview(directory: URL, selected: URL?) {
    guard let selected else { previewSession = nil; return }
    if selected.hasDirectoryPath {
      path = path.prefix { $0 != directory } + [directory, selected]
      previewSession = nil
    } else {
      let command = registry.command(for: selected)
      previewSession = TerminalProcessSession(
        command: command.executable,
        arguments: command.arguments(selected),
        initialSize: CellSize(width: 80, height: 40)
      )
    }
  }
}
```

- [ ] **Step 7.5: Wire `App` and `WindowGroup`**

```swift
import SwiftTUICLI
import SwiftTUITerminal

@main
struct FilePreviewerApp: App {
  var body: some Scene {
    WindowGroup("File Previewer") {
      ColumnBrowser(
        path: [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)],
        registry: .defaults
      )
    }
  }
}
```

- [ ] **Step 7.6: Manual smoke test**

```bash
cd Examples/file-previewer
swiftly run swift run FilePreviewerApp
```

Expected: arrow keys navigate; selecting a `.md` file launches `glow`
in the right column; resizing the terminal resizes the previewer
column; navigating away kills the previewer.

- [ ] **Step 7.7: Commit Stage 7**

```bash
git commit -m "feat(examples): add file-previewer column-view example"
```

---

## Stage 8: Render-Diff Validation

**Files:**
- Create: `Platforms/Embedding/Tests/SwiftTUITerminalTests/RenderDiffTests.swift`

The proposal flagged this as the v1 risk: a foreign-surface payload
that produces a fully new grid every emulator tick must still hit
the existing commit-phase diff so the outer terminal receives a
minimal byte stream over a slow link.

- [ ] **Step 8.1: Write a "byte budget" test**

```swift
@Test("running `cat large.txt` does not blow the byte budget")
func catLargeFile() async throws {
  let recorder = RecordingTerminalHost()
  let session = TerminalProcessSession(
    command: "/bin/cat",
    arguments: [generatedFixturePath],
    initialSize: CellSize(width: 80, height: 24)
  )
  let app = HarnessApp { TerminalView(session: session) }
  try await runHarness(app: app, host: recorder, until: .sessionExited(session))
  #expect(recorder.bytesEmittedToTerminal < 200_000)  // 24-row terminal: 200KB cap
}
```

The fixture is a 1MB text file. A naive full-redraw pipeline would
emit `~1MB * (full_grid_in_bytes)` per scroll. The diff in
`Sources/SwiftTUI/Terminal/TerminalPresentation.swift` should keep it under
~200KB end-to-end.

- [ ] **Step 8.2: If the test fails, profile and decide**

If it fails, the foreign-surface dispatch in the rasterizer is
producing per-tick churn that the commit diff cannot deduplicate.
Two paths:

1. Stamp foreign-surface-derived `RasterCell` values with a
   per-cell sequence/identity hint so the existing diff sees them
   as equal across ticks unless the source grid actually changed.
2. Add a per-foreign-surface "dirty seqno" — `ForeignSurfacePayload`
   gains `var version: UInt64`, the rasterizer skips reblit when
   the version matches the last frame and the bounds match.

Path (2) is cheaper but adds a public field. Decide based on what
profiling shows. **Document the decision in
`docs/proposals/TERMINAL_EMBEDDING.md` under "Open Questions
resolved."**

- [ ] **Step 8.3: SSH-realistic latency test**

```swift
@Test("interactive scrolling under 50ms RTT stays responsive")
func interactiveScrollUnderLatency() async throws {
  // Wrap the recording host with a 50ms artificial delay. Run `vim` for
  // 5 seconds of synthesized scroll events. Assert no frame takes
  // >100ms wall-clock to commit.
}
```

This requires a `LatencyInjectingTerminalHost` test helper. Build it
from existing `RecordingTerminalHost` infrastructure.

- [ ] **Step 8.4: Run perf evaluation**

```bash
Scripts/perf-evaluation.sh --baseline main --target embedding
```

(See [PERFORMANCE_EVALUATION.md](../PERFORMANCE_EVALUATION.md) for
the operator guide. The perf tool is already in-repo.)

- [ ] **Step 8.5: Commit Stage 8**

```bash
git commit -m "test(embedding): add render-diff and SSH-latency validation"
```

---

## Stage 9: Documentation

**Files:**
- Create: `docs/EMBEDDING.md`
- Create: `Sources/SwiftTUI/SwiftTUI.docc/TerminalEmbedding.md`
- Modify: `docs/STATUS.md`, `docs/SOURCE_LAYOUT.md`, `docs/VISION.md`,
  `Scripts/test_all.sh`, `.cspell/custom-dictionary-workspace.txt`

- [ ] **Step 9.1: Author `docs/EMBEDDING.md`**

Sections: Overview, Authoring (`TerminalView` + `TerminalProcessSession`
walk-through), Custom Sessions (the `TerminalSession` protocol),
Modifiers (`terminalTitleChanged`, etc.), Capabilities Today, Deferred
to v2 (sixel-in-pane, Kitty graphics, Kitty kbd, OSC 99, OSC 52
clipboard), Internals (link to the proposal).

- [ ] **Step 9.2: Author `Sources/SwiftTUI/SwiftTUI.docc/TerminalEmbedding.md`**

DocC article visible from the SwiftTUI module page. Same content as
`EMBEDDING.md` but in DocC format with `<doc:>` cross-links.

- [ ] **Step 9.3: Update `docs/STATUS.md`**

Under "Shipped surface", add:

```markdown
### Terminal embedding (peer package)

- `TerminalView<Session>`, `TerminalSession` protocol,
  `TerminalProcessSession` for spawned children
- Mouse mode translation (X10 / 1000 / 1002 / SGR), bracketed paste,
  OSC 0/2 (title), OSC 7 (cwd), OSC 8 (hyperlinks)
- Lives in `Platforms/Embedding`; macOS and Linux only
```

Under "Current Constraints", add:

```markdown
- Sixel and Kitty graphics inside an embedded pane are not supported;
  only full-screen child graphics work today
- Kitty keyboard protocol and OSC 99 notifications are not intercepted for
  embedded children in v1; OSC 52 clipboard writes are forwarded to the
  surrounding host clipboard action
- `Platforms/Embedding` does not build for iOS or WASI
```

- [ ] **Step 9.4: Update `docs/SOURCE_LAYOUT.md`**

Add `Platforms/Embedding` section listing the two library targets.

- [ ] **Step 9.5: Update `docs/VISION.md`**

Under "Confirmed deviations today", add a bullet: terminal-program
embedding via `TerminalView`. Cross-reference the proposal.

- [ ] **Step 9.6: Update `Scripts/test_all.sh`**

Add `Platforms/Embedding` and `Examples/file-previewer` to the test
loop. On Linux, gate appropriately.

- [ ] **Step 9.7: Add domain words to `cspell` dictionary**

Words: `forkpty`, `openpty`, `TIOCSWINSZ`, `Bracketed`,
`previewer`, `Miller`, `multiplexer`, `SwiftTerm`, `Zellij`,
`Kitty` (already present?), `Sixel`, `OSC`.

- [ ] **Step 9.8: Run the full test surface**

```bash
bun run test
```

Must pass without warnings.

- [ ] **Step 9.9: Commit Stage 9**

```bash
git commit -m "docs: document TerminalView embedding and update STATUS/SOURCE_LAYOUT"
```

---

## Review Checklist

Before declaring the plan complete, verify:

- [ ] `DrawCommand.foreignSurface` is the only new draw variant; no
  parallel rendering pipeline emerged.
- [ ] `Sources/SwiftTUICore` still compiles without `import Foundation` (the
  prek hook will block any regression).
- [ ] `TerminalView<Session>` is generic, never erased; no
  `[any TerminalSession]` storage anywhere in the public surface.
- [ ] `ScenePty` characterization tests (renamed from
  `PtyPairCharacterizationTests` in Stage 3.C.4) still pass.
- [ ] `Platforms/CLI`'s `SceneRuntime` and `SocketServer` paths
  continue to work — secondary scenes attach and detach.
- [ ] Foreign-surface byte budget under `cat large.log` stays under
  the configured cap.
- [ ] No `@unchecked Sendable` or `nonisolated(unsafe)` introduced
  (the prek hook will block this).
- [ ] All new tests are Swift Testing (`import Testing`, `@Test`,
  `#expect`), not XCTest.
- [ ] `bun run test` is green on macOS.
- [ ] On Linux, `DISABLE_EXPLICIT_PLATFORMS=1 bun run test` is green.
  (The new package gates `iOS`/`WASI` via `canImport`.)
- [ ] `swift format format -i --configuration .swift-format.json
  Sources/ Tests/ Platforms/Embedding/Sources/
  Platforms/Embedding/Tests/ Examples/file-previewer/Sources/
  Examples/file-previewer/Tests/` produces no diff.
- [ ] DocC builds (`swiftly run swift package generate-documentation`)
  without warnings on the new article.
- [ ] The proposal's "Open Questions" section is updated to record
  decisions made during implementation (Stage 8 in particular).

## What "Done" Looks Like

A user clones the repo, runs `swiftly run swift run --package-path
Examples/file-previewer FilePreviewerApp`, gets a column-view file
browser. Arrow keys navigate. Selecting a `README.md` launches `glow`
in the right column. Resizing the terminal resizes the preview pane
and `glow` reflows. Selecting a `.png` launches `chafa` and an image
appears. Pressing `q` (or `Ctrl-C`) inside the preview pane sends
that key to the previewer process; the previewer exits; the column
goes blank; navigating to another file launches a fresh previewer.

The proposal's claim — that SwiftTUI can host external terminal
programs as ordinary `View`s, on a foundation that does not preclude
multiplexer-grade features later — is now backed by code, tests, and
a working example.

---

# Future Stages (Speculative)

The plan above ships terminal embedding as a self-contained capability
and stops there. This section sketches what *could* come next, why
those stages aren't in the current plan, and what would have to be
true for them to be scheduled.

These stages are **not commitments**. They are decision artifacts
preserved here so the next person to think about plugins or about
`AnyView`'s identity story can see what was already considered, what
was deliberately deferred, and on what conditions the deferral
should be revisited. Cross-reference:
[decisions/0005-anyview-anyscene-as-escape-hatches.md](../decisions/0005-anyview-anyscene-as-escape-hatches.md).

## The pseudo-symmetry that motivates these stages

A core observation surfaced during the embedding planning discussion:
the infrastructure required to make `AnyView` a first-class identity-
preserving citizen of the pipeline is *structurally the same* as the
infrastructure required for a `View`-level plugin system to work.
Both need:

- a stable identity stamp that survives a transparent wrapper at
  resolve time
- lifecycle metadata bound to inner identity, not to the wrapper
- resolve-phase awareness that the wrapper is opaque-but-identified,
  not a leaf
- a way to distinguish identity-preserving erasure from
  intentionally-erasing erasure

The current framework provides none of these. `AnyView` is a leaf
from the resolver's perspective. That has been *acceptable* up to now
because authored code mostly avoids `AnyView`, and the typed-view
authoring path keeps identity intact through ordinary structure.

Plugins are the place this stops being acceptable. A plugin boundary
is, by definition, a transparent wrapper: the host can't see the
plugin's internal type tree, but it must continue to track identity,
lifecycle, and focus across the boundary. Any serious plugin system
runs into the same wall `AnyView` runs into — and the path through
that wall is the same regardless of which problem motivates it.

This section captures what work that path consists of and what
gating conditions justify undertaking it.

## Stage 10: In-process view-plugin experiment

**Goal:** Answer whether `View` is a viable plugin ABI by adding a
typed previewer registry to TerminalFinder, with one in-tree
implementation that exercises the host's lifecycle, focus, and
ActionScope features.

**Approach:** A `FilePreviewer` protocol; a `PreviewerRegistry`
parameterized over a variadic-generic plugin pack so no `AnyView`
is needed; one concrete implementation (likely a JSON tree viewer
with collapse/expand, scroll-position retention, and syntax styling).

**What it proves (the four questions from the prior discussion):**

1. Does a typed registry survive the `AnyView` policy?
2. Does composition with the host actually deliver felt value?
3. Does the runtime contract hold across plugin instantiation churn?
4. What dependency surface does a useful plugin actually need?

**Scope of work:** Modest. A new protocol, one example
implementation, integration into the existing TerminalFinder
registry, tests for plugin lifecycle. Probably 2 weeks.

**When to schedule:** After Stages 1–9 ship and TerminalFinder is
real. Before any plugin distribution, sandboxing, or out-of-process
work — those questions don't have meaningful answers until Stage 10
has answered the four above.

**What this stage explicitly does *not* tackle:** distribution,
sandboxing, hot reload, runtime loading, third-party authoring,
flexible (non-compile-time-known) registries, wire-format design.
All of those are downstream of Stage 10's outcome.

**Possible Stage 10 outcomes:**

- *The protocol shape is workable.* The variadic-generic registry
  composes, the JSON viewer feels meaningfully better than `jq |
  bat`, lifecycle holds. Justifies further plugin work; opens the
  door to Stage 11 if flexibility becomes the bottleneck.
- *The protocol shape is workable but the value is marginal.* The
  registry composes, but the JSON viewer doesn't justify the
  authoring cost over a shell command. Stage 11 is not justified;
  the existing `TerminalProcessSession` (the "ANSI plugin" path
  inherited from this plan) handles real demand. Stop here.
- *The protocol shape doesn't work.* `AnyView` leaks despite the
  variadic-generic approach, or the registry can't be expressed
  ergonomically, or lifecycle has unfixable seams. Document the
  negative result; do not pursue Stage 11; treat this as evidence
  that view-level plugins are not a fit for this framework today.

## Stage 11: Identity-preserving erasure substrate

**Goal:** Build the resolve-phase capability for transparent
wrappers to preserve identity continuity. This is the substrate
both flexible plugin registries and `AnyView`'s identity story
depend on.

**Approach:** Introduce a new type along the lines of
`IdentityPreservingErasure<Subtree>` (name TBD) that is structurally
erasing at the type level but carries an identity stamp through
resolution. Update the resolve phase to treat such wrappers as
opaque-but-identified rather than as leaves. Update lifecycle
metadata binding so `.task`, `.onAppear`, `.onDisappear`, focus
participation, and action scope membership track the inner
identity through the wrapper. Add test fixtures that prove
transparent wrappers preserve `.task` continuity, focus chain
membership, and action scope inheritance across renders.

`AnyView` itself does *not* need to consume the substrate
immediately. The substrate exists alongside `AnyView`; load-bearing
surfaces (plugins, future framework internals) opt in. As a side
effect — or as a deliberate later step — `AnyView` could be migrated
onto the substrate and quietly lose its identity-loss bug class
without changing public role.

**Scope of work:** Substantial. The resolve phase is one of the most
heavily-tested parts of the codebase. The lifecycle-selective-
evaluation work (see [plans/2026-05-03-001-lifecycle-selective-
evaluation-plan.md](2026-05-03-001-lifecycle-selective-evaluation-plan.md))
already addresses *one* class of transparent-wrapper identity bug
for `Group`; this stage generalizes that pattern to a public
mechanism. Probably 4–6 weeks, including the test surface and a
characterization pass against existing transparent-wrapper sites.

**When to schedule:** Conditional on *all* of:

- Stage 10 lands and proves the protocol shape is workable
- Real demand surfaces for *flexible* plugin registries — sets of
  plugins not known at compile time, third-party plugins added
  after build, etc. (Stage 10's typed-registry approach is
  sufficient for many real use cases; only commit to the substrate
  when its absence is the actual blocker, not just a theoretical
  limitation.)
- The pseudo-symmetry argument (above) is accepted as load-bearing,
  not as one-time observation. The substrate is a real change to
  the framework's identity story; the doctrine should evolve to
  match.

**What this stage explicitly does *not* tackle:** out-of-process
plugin transport, sandboxing, distribution, hot reload, plugin
discovery. Those are Stage 12 territory.

**Side effects of landing Stage 11:**

- `AnyView` becomes migratable onto the substrate — separate
  follow-up, not part of the stage itself.
- `AnyView` retains its policy role as a smell signal regardless
  of whether it is migrated. The SwiftUI-cultural rationale for
  preferring typed views — compile-time clarity, refactor safety,
  legibility — is independent of the runtime identity story.
- ADR-0005's "What this ADR does not decide" section becomes
  resolvable; the ADR may need a successor noting which questions
  are now answered.
- `Group` and other transparent wrappers can be re-evaluated against
  the substrate, potentially superseding parts of the lifecycle-
  selective-evaluation work.

## Stage 12: Out-of-process plugin tier (deeply speculative)

**Goal:** Wire-format plugin authoring. Plugins author SwiftTUI views;
the host runs `resolve` on the plugin's tree; the resolved tree is
serialized across a process boundary; events round-trip via stable
closure handles. Plugins can be sandboxed (WASM) or trusted
(subprocess) per the deployment model.

**Approach:** A wire format derived from the resolve-phase output
(probably the post-resolve `DrawNode` graph plus serializable
identity stamps). A closure-handle registry: every event handler
in the plugin's authored tree gets a stable ID; events on the host
side dispatch by ID via RPC; plugin runs the closure, emits a
new tree (or a tree diff). The pattern resembles React Server
Components, Phoenix LiveView, and Jetpack Compose's HTML target.

**Scope of work:** Very large. New peer package. Wire format
specification. Closure-handle registry. RPC protocol. Cross-
language (or at least cross-process) testing surface. A plugin
runtime — likely WASM via `wasmtime` for sandboxing.
Realistically 3+ months of focused work.

**When to schedule:** Only after Stages 10 *and* 11 land *and*
there is a concrete product motivation. Specifically, *all* of:

- A security-sensitive use case requiring plugin sandboxing (the
  in-process model gives plugins host-equivalent privilege; if
  third-party plugin authors are real, that's not acceptable)
- A distribution model — registry, marketplace, install/uninstall
  flow — that justifies the wire-format work over the "compile
  plugins in" model that Stage 10 enables
- A non-Swift plugin author audience, or a hot-reload requirement
  that the in-process model cannot satisfy

If those don't exist, Stage 12 doesn't either. The existing
`TerminalProcessSession` (which plays the "ANSI plugin" role from
the Zellij comparison in
[../proposals/TERMINAL_EMBEDDING.md](../proposals/TERMINAL_EMBEDDING.md))
already handles the use cases that don't need view-level plugin
participation — file previewers shelling out to `bat`, `glow`,
`chafa`, etc. View-level out-of-process is a strictly more
expensive answer to a question the byte-level path already answers
adequately for many scenarios.

**Important property of this stage:** it is the only stage where
SwiftTUI would offer something Zellij cannot. The Zellij plugin
model is byte-level — view participation in the host is impossible
by construction. A SwiftTUI Stage 12 plugin tier would let
sandboxed third-party code participate in the host's layout, focus,
action scopes, and state — the strongest possible version of "views,
not bytes." Whether that property is worth the work is a product
question, not an engineering question, and the answer is unknowable
before Stages 10 and 11 settle.

## Sequencing summary

```
Stages 0–9 (this plan)         ──→  embedding capability ships
       │
       ├──(if there's appetite for plugins)──→
       │
Stage 10  in-process view-plugin experiment  ──→  answer "is View a viable plugin ABI?"
       │
       ├──(if Stage 10 succeeds AND flexibility is the bottleneck)──→
       │
Stage 11  identity-preserving erasure substrate
       │   └─ side effect: AnyView's identity story can be fixed
       │
       ├──(if Stages 10+11 land AND there's a real distribution/sandboxing case)──→
       │
Stage 12  out-of-process plugin tier
```

Each transition is a *decision*, not a deliverable. The plan
deliberately preserves the option to stop at any node. The most
expensive mistake would be undertaking Stage 11 or Stage 12 without
the gating evidence — at which point the framework has paid for
infrastructure with no real consumer.

The least expensive mistake is failing to undertake Stage 10 when
plugin demand is real. Stage 10 is small, isolated, and produces a
binary answer; deferring it once embedding ships is a reasonable
default but should not become permanent if real authoring needs
push against the limits of the in-tree previewer registry.
