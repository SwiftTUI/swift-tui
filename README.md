# SwiftTUI

**SwiftUI semantics, drawn in terminal cells.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Status](https://img.shields.io/badge/beta-0.9.11-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

SwiftTUI is a Swift framework for building terminal user interfaces on macOS,
Linux, and Windows. You write `View` types with `@State`, stacks, controls,
focus, gestures, and animation — the declarative model SwiftUI has proven at
platform scale — and the framework owns layout, input, redraw, and the
terminal itself. The result is one fast native binary.

> [!important]
> **Beta, pre-1.0.** The API has stabilized, but breaking changes may still land
> before `1.0.0`.   
> All changes are documented in the [CHANGELOG](https://github.com/SwiftTUI/swift-tui/blob/main/CHANGELOG.md).  
> Pin with `.upToNextMinor`.

[<img width="545" height="321" alt="counter-demo" src="https://github.com/user-attachments/assets/15cd2cb5-e907-4456-b699-2906dc3682b1" />](https://swifttui.sh/webexample/)
<dl>
  <dt>
    Try it first
  </dt>
  <dd>
This is is a real SwiftTUI app, compiled to WebAssembly and <a href="https://swifttui.sh/webexample/">running live</a>.<br />
The <a href="https://swifttui.sh">guided introduction</a> and <a href="https://swifttui.sh/docs/documentation/">API reference</a> are at <a href="https://swifttui.sh">SwiftTUI.sh</a>
</dd>
</dl>

## The counter

This is the app behind the live demo, without the demo's ripple animation
([full source](https://github.com/SwiftTUI/swift-tui-counter-demo/tree/main/counter)):


```swift
import SwiftTUI

struct CounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(spacing: 1) {
      TextFigure("\(count)", font: .future)
        .frame(minWidth: 14, alignment: .center)
      Button("Increment") { count += 1 }
        .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@main
struct CounterApp: App {
  var body: some Scene {
    WindowGroup("Counter") { CounterView() }
  }
}
```

A frame is a pure function of the view tree and a size proposal, so this is
exactly what that view renders at 40 columns
(`RenderOnce.print(CounterView(), width: 40)`, color off):

```text
                  ┏━┓
                  ┃┃┃
                  ┗━┛

               ╭─────────╮
               │Increment│
               ╰─────────╯
```

Space activates the focused button and the figure redraws — only the cells
that changed. Ctrl-C quits and restores your shell.

### Run it

Any Swift 6.3+ toolchain builds and runs SwiftTUI apps from the command line on
macOS 15+, Linux, and Windows 10 1809+ ([swiftly](https://www.swift.org/swiftly/),
a current Xcode, or the [swift.org installer](https://www.swift.org/install/windows/)).
Add the package, depend on its `SwiftTUI` product, and `swift run`:

```swift
// Package.swift
.package(url: "https://github.com/SwiftTUI/swift-tui", .upToNextMinor(from: "0.9.11")),
// in your executable target:
.product(name: "SwiftTUI", package: "swift-tui"),
```

Or clone [the demo's repo](https://github.com/SwiftTUI/swift-tui-counter-demo) and run its terminal target:  
```sh
git clone https://github.com/SwiftTUI/swift-tui-counter-demo
swift run --package-path counter counter
```

## Why SwiftTUI

- **State in, screen out.** Views are a pure function of your app's state:
  change a value and the runtime recomputes layout and rewrites exactly the
  cells that changed. No draw loop, no buffer diffing, no repaint bookkeeping.
- **The terminal, negotiated for you.** Truecolor, Kitty and Sixel images,
  OSC 8 hyperlinks, and mouse reporting are probed per session and degrade
  gracefully: one binary is correct in kitty, a bare SSH session, or CI. Every
  app also ships `--accessible`, `--cursor-follows-focus`, `--reduce-motion`,
  `--no-color`, and `--ascii`. You write views, not escape codes.
- **One compiled binary, testable without a TTY.** Swift 6 compiles your
  interface into a single executable with checked concurrency, and tests
  render and compare integer-cell frames like the one above with no terminal
  attached.

Coming from SwiftUI? The shape is the same; the terminal-native differences
are deliberate and recorded — read
[Coming from SwiftUI](Sources/SwiftTUIViews/SwiftTUIViews.docc/Coming-From-SwiftUI.md)
and the [divergence register](Sources/SwiftTUIViews/SwiftTUIViews.docc/Divergences-And-Gaps.md).
Choosing between TUI frameworks? See the
[comparison on swifttui.sh](https://swifttui.sh/#why).

## Built with SwiftTUI

| [![GIF Editor](https://swifttui.sh/showcase/gifeditor.png)](https://github.com/SwiftTUI/swift-tui-examples/tree/main/gifeditor) | [![csvui](https://swifttui.sh/showcase/csvui.png)](https://github.com/SwiftTUI/swift-tui-examples/tree/main/csvui) |
| :--: | :--: |
| **GIF Editor** — canvas, layers, a scrubbable timeline, pointer tools, undo, export | **csvui** — a 34,000-row table browsed and edited in place |
| [![Terminal Workspace](https://swifttui.sh/showcase/terminal-workspace.png)](https://github.com/SwiftTUI/swift-tui-examples/tree/main/terminal-workspace) | [![mrkdwn](https://swifttui.sh/showcase/mrkdwn.png)](https://github.com/SwiftTUI/swift-tui-examples/tree/main/mrkdwn) |
| **Terminal Workspace** — tabs, splits, and a command palette over embedded terminals | **mrkdwn** — a responsive Markdown reader, shown reading this README |

Every example runs from a fresh clone of
[`swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples).  
Try `swift run --package-path gallery gallery-demo` for the gallery of SwiftTUI's interactive functionality. 
(See more in the [showcase](https://swifttui.sh/showcase/))

## Beyond the terminal

Terminal first, not terminal only. The same `App` also runs in a browser —
launch it with `--web` to serve it over localhost, or compile it with the
`SwiftTUIWASI` product and ship it as a static bundle with
[`@swifttui/web`](https://github.com/SwiftTUI/swift-tui-web), which is what the
live demo is — and inside native apps through
[`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) (macOS, iOS)
and [`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android)
(arm64 preview). The browser paths paint to the DOM with a real accessibility
tree; none of them is a terminal emulator. For narrower product graphs — the
explicit `SwiftTUICLI` terminal runner, custom hosts, or one committed frame
rendered without a TTY — start from
[Choosing Modules And Platforms](Sources/SwiftTUI/SwiftTUI.docc/Choosing-Modules-And-Platforms.md);
the full platform-by-product matrix (including the Windows notes) is
[Hosts And Platforms](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md).

## Documentation

- Introduction guides: <https://swifttui.sh/guides/>
- DocC documentation: <https://swifttui.sh/docs/documentation/>
- Questions? Join the community on [Discord](https://discord.gg/8j35kYDFxn).

## Contributing

[Open an issue](https://github.com/SwiftTUI/swift-tui/issues/new/choose) for
SwiftUI-style APIs you find missing or anything that gets in your way.

Small, well-scoped issues and pull requests are easiest to review. The repo
uses the pinned Swift 6.3.3 toolchain through `swiftly`: `swiftly run swift
test` for the unit tests. Read [CONTRIBUTING.md](CONTRIBUTING.md)  
Please join the [Discord](https://discord.gg/8j35kYDFxn) to discuss changes.

## License

SwiftTUI first-party code is licensed under the MIT License (`MIT`). Vendored
third-party code under `Vendor/` keeps its own license and provenance notices.
See [LICENSE](LICENSE).
