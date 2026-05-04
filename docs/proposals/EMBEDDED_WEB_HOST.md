# Embedded Web Host

**Status:** Draft. Exploratory research + proposal. No code; this document
captures the design space for "run your SwiftTUI binary locally, view it in a
browser at a localhost URL," along with the architecture, lifecycle, security,
and phasing decisions that need answering before implementation starts. Long
by intent — the goal is to keep the context here rather than scattered
across session notes.

**Owner:** unassigned. Sister proposal: [`ACCESSIBILITY.md`](./ACCESSIBILITY.md)
— accessibility is the headline motivator but not the only one.

---

## Table of contents

1. [Context](#context)
2. [Strategic shape](#strategic-shape)
3. [Principles](#principles)
4. [The landscape](#the-landscape)
   1. [ttyd / GoTTY — terminal-as-web-app](#ttyd--gotty--terminal-as-web-app)
   2. [tmate — pair-programming TTY share](#tmate--pair-programming-tty-share)
   3. [textual-serve — TUI framework owns the bridge](#textual-serve--tui-framework-owns-the-bridge)
   4. [aider --browser / Streamlit — abandon the TUI](#aider---browser--streamlit--abandon-the-tui)
   5. [jupyter notebook / code tunnel — the URL-and-token UX](#jupyter-notebook--code-tunnel--the-url-and-token-ux)
   6. [asciinema — passive replay, not interactive host](#asciinema--passive-replay-not-interactive-host)
   7. [VS Code Server / code-server — the heavy end](#vs-code-server--code-server--the-heavy-end)
   8. [xterm.js as the de facto browser-side renderer](#xtermjs-as-the-de-facto-browser-side-renderer)
5. [What we already have in swift-tui](#what-we-already-have-in-swift-tui)
6. [Architecture options](#architecture-options)
   1. [Option A: A new `Platforms/WebHost` runner peer](#option-a-a-new-platformswebhost-runner-peer)
   2. [Option B: Capability built into every binary](#option-b-capability-built-into-every-binary)
   3. [Option C: Out-of-process attach via SwiftTUICLI](#option-c-out-of-process-attach-via-swifttuicli)
   4. [Option D: Daemonize and reverse-proxy](#option-d-daemonize-and-reverse-proxy)
   5. [Verdict](#verdict)
7. [Server stack](#server-stack)
8. [Wire format](#wire-format)
9. [Browser-side bundle](#browser-side-bundle)
10. [Lifecycle and CLI shape](#lifecycle-and-cli-shape)
11. [Discovery, ports, and URLs](#discovery-ports-and-urls)
12. [Security model](#security-model)
13. [Multiple connections, sessions, and scenes](#multiple-connections-sessions-and-scenes)
14. [Headless rendering and CI](#headless-rendering-and-ci)
15. [Performance and throughput](#performance-and-throughput)
16. [Embedding cost](#embedding-cost)
17. [Proposed design](#proposed-design)
    1. [Package layout](#package-layout)
    2. [Public API](#public-api)
    3. [Wire protocol sketch](#wire-protocol-sketch)
    4. [Boot sequence](#boot-sequence)
    5. [Failure modes](#failure-modes)
18. [Open questions](#open-questions)
19. [Out of scope](#out-of-scope-this-version)
20. [Suggested phasing](#suggested-phasing)
21. [Anti-patterns this proposal commits us to avoiding](#anti-patterns-this-proposal-commits-us-to-avoiding)
22. [Sources](#sources)
23. [Changelog](#changelog)

---

## Context

swift-tui already has a Web rendering target (`Platforms/Web/`), but it is
*WASM-shaped*: the user's view code compiles to WebAssembly, gets shipped to a
browser, and the SwiftTUI runtime executes inside the browser. That is the
right answer for "deploy your TUI as a website."

This proposal is about a different shape. The user has a compiled SwiftTUI
binary on their machine and wants to run it locally while rendering its
output to a web browser at a localhost URL. The binary is the server, the
browser is the client, and HTTP/WebSocket sits between two processes on the
same machine. This is the
[`jupyter notebook`](https://jupyter-notebook.readthedocs.io/en/5.6.0/security.html)
shape, the [`code tunnel`](https://code.visualstudio.com/) shape, the
[`aider --browser`](https://aider.chat/docs/usage/browser.html) shape, and
the [`textual-serve`](https://github.com/Textualize/textual-serve) shape.

Why this matters now:

1. **Accessibility.** The
   [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) proposal lays out why
   blind users on macOS get a structurally weaker terminal screen-reader
   experience than browser users do — Terminal.app and iTerm2 expose only
   a character grid, while the browser DOM offers ARIA, live regions, real
   focus management, and mature screen reader integration. *Run-locally,
   view-in-browser* is the credible workaround for those users without
   asking the framework to also be a web platform.
2. **Pretty rendering.** A browser can render a SwiftTUI surface with
   crisp fonts, sub-pixel anti-aliasing, ligatures, image attachments at
   real resolution, and theme-aware backgrounds — none of which a 1980s
   character grid was designed for.
3. **Persistent sessions.** A binary on a server can keep running while
   you close the laptop, reconnect from anywhere, and pick up where you
   left off. ttyd, gotty, tmate, and code-server have all been built
   around this affordance.
4. **Headless operation.** The same machinery that serves a browser also
   solves "render this TUI without a controlling terminal" for snapshot
   tests, CI screenshots, and `screencast` style demos.
5. **Pair programming and sharing.** Two browsers tailing the same TUI
   session enables `tmate` style remote pairing. Not v1, but a natural
   extension once the server exists.
6. **Mobile.** A QR code on the terminal, scanned from a phone, gets a
   browser-rendered TUI view. That's a delightful demo and a real use case
   for embedded devices.

The motivating user story is the blind macOS developer who can run
`myapp --web`, get a localhost URL, point their browser at it, and have
VoiceOver announce a real DOM tree built from the same `semantics` phase
output that the CLI uses for cursor placement. But the design needs to
serve all six of the above.

This proposal does **not** advocate replacing the WASM `Platforms/Web/`
target. The two are complements:

- **WASM Web** (`Platforms/Web/`) — ship your TUI to the open web. The
  user does not need a binary. Hosted on Cloudflare Pages, Vercel,
  GitHub Pages.
- **Embedded Web Host** (this proposal) — run your binary locally, view it
  in a browser. The user has a binary but wants browser rendering on the
  same machine.

The core insight that makes this cheap to build is that
[`WASISurfaceBridge`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)
already encodes a SwiftTUI raster surface into a JSON-over-stream wire
format and parses input back, all in service of the WASM target. The
bridge does not care that one end is a `wasm` module rather than a native
process. Pointing the *same encoder/parser* at a TCP-WebSocket transport
is the structural shape this proposal proposes.

## Strategic shape

The proposal is **one runner package, one wire format, one browser bundle**.

| Layer | What it is | Where it lives |
|---|---|---|
| **Wire format** | The existing `WASISurfaceBridge` `web-surface` JSON encoding for output, the same input-parser command stream for input | `Platforms/WASI/Sources/WASISurfaceBridge/` (already shipped) |
| **Transport** | HTTP for the static page, WebSocket for the surface/input stream | New: `Platforms/WebHost/` |
| **Server** | An embeddable HTTP+WS host that the runner package starts on a localhost port | New: `Platforms/WebHost/` |
| **Browser bundle** | The same `webhost` TS package used by `Platforms/Web/`, served from the binary | New static asset bundle, derived from `Platforms/Web/dist/` |
| **Runner glue** | `WebHostRunner.run(MyApp.self)` — the analog of `TerminalRunner.run` for browser-targeted launch | `Platforms/WebHost/Sources/SwiftTUIWebHost/` |
| **CLI integration** | `myapp --web`, `--web --open`, `--web --host`, `--web --port` flags handled by the runner package | `Platforms/CLI/` adopts a `--web` mode that delegates to WebHost |

The crucial reuse:

- **`WASISurfaceBridge` already speaks the wire**. We are not designing a
  new protocol; we are adopting the one that exists.
- **`Platforms/Web/` already builds a browser-side renderer**. The
  `webhost` Bun package is the consumer-facing bundle today; an embedded
  variant ships pre-bundled inside the runner package.
- **`HostedSceneSession` already abstracts "run a scene against a custom
  presentation surface"**. The CLI runner uses this; the SwiftUI host uses
  this; the WASI runner uses this; the WebHost runner uses it too.

The result, at a sketch level: a SwiftTUI binary built with the
`SwiftTUIWebHost` runner, when invoked with `--web`, starts a localhost
HTTP server, serves a tiny static page that loads the embedded `webhost`
bundle, and pipes the existing `web-surface` frames over a WebSocket
upgrade. From the browser's perspective it's identical to opening the
WASM-hosted page; from the binary's perspective it's running the scene
runtime against a `WebSocketSurfaceTransport` instead of a stdout pipe.

## Principles

1. **No new wire format.** Reuse `WASISurfaceBridge`'s `web-surface`
   encoder and `WebSurfaceInputParser`. If the WASM target ever needs
   format changes, both targets get them.
2. **Library-only stays library-only.** Per
   [ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md),
   the embedded web host is a *runner package*, peer to
   `SwiftTUICLI` and `SwiftTUIWASI`. The root `SwiftTUI` library never
   gains an HTTP server.
3. **No Foundation in library products.** Per AGENTS.md, the
   `Core`/`View`/`SwiftTUI` library targets are Foundation-free and
   guarded by the `no-foundation-in-library-products` prek hook. The
   server lives in a runner; runners may use Foundation, but should
   avoid it where possible to keep cold-start small.
4. **Localhost-only by default.** Bind to `127.0.0.1` unless the user
   explicitly opts in to a wider bind. Print a warning when binding
   externally. No silent attack surface.
5. **Authenticated by default.** Generate a per-launch random token; the
   URL the user gets is `http://127.0.0.1:PORT/?token=...`. This matches
   `jupyter notebook` and is a 30-year-old convention.
6. **Cheap to compile out.** Authors who don't need the web host should
   not pay for it. The dependency on the HTTP server lives in
   `SwiftTUIWebHost`, not in `SwiftTUI`. If you only `import
   SwiftTUICLI`, you ship no HTTP server.
7. **`--web` is a runner mode, not a view-author concern.** App authors
   write the same view tree they would for the CLI. The runner picks
   how to realize it.
8. **One process, two surfaces — but not at the same time.** The default
   for `myapp --web` is to *not* also paint the terminal. The terminal
   is reserved for printing the URL, optional QR code, log lines, and
   `Ctrl-C`. (See [Lifecycle](#lifecycle-and-cli-shape) for the matrix.)
9. **Multi-client tail, single-client interact.** Multiple browser tabs
   may *view* the same session, but only one is granted input authority
   at a time. This avoids fighting cursors and matches `tmate`'s
   read-only viewer pattern.
10. **Headless and CI are a free byproduct.** A `WebSocketSurfaceTransport`
    that can be *driven without a browser* gives us snapshot fixtures
    and screenshot tests for the same price.

---

## The landscape

There are roughly six well-known shapes for "binary running locally,
browser as the front-end." Each has trade-offs swift-tui can learn from.

### ttyd / GoTTY — terminal-as-web-app

[ttyd](https://github.com/tsl0922/ttyd) and
[GoTTY](https://github.com/yudai/gotty) are the canonical "share your
terminal over HTTP" tools. ttyd is C with libwebsockets and libuv; GoTTY
is Go. Both follow the same architecture:

- A native PTY runs an arbitrary command (`bash`, `htop`, anything).
- The PTY's output bytes are forwarded *raw* over a WebSocket as ANSI
  escape sequences.
- The browser loads [xterm.js](https://xtermjs.org/) and feeds the
  WebSocket bytes directly to the terminal emulator.
- Input events from xterm.js (keystrokes) round-trip back to the PTY's
  stdin.

ttyd defaults to port 7681; GoTTY to 8080.

> "By default, GoTTY starts a web server at port 8080. The tool uses
> WebSocket connections for real-time terminal communication."
>
> ([tecmint.com](https://www.tecmint.com/gotty-share-linux-terminal-in-web-browser/))

GoTTY's threat model is illustrative — it explicitly recommends
**`--credential`** (basic auth), **`--tls`** (since "all connections
between the server and clients are not encrypted" by default), and
**`--random-url`** (a 16-character random URL prefix as a poor-man's
auth token). The fact that they ship *three* security knobs and the
README lists them under "Security Warning" before describing how to use
them is a signal of how easy this category of tool is to misconfigure.

What ttyd/GoTTY teach us:

1. The wire format **can** be a stream of bytes (raw ANSI). xterm.js
   handles the rest. This is the simplest possible thing that works.
2. Per-launch random URL tokens *as a query parameter* are an industry
   standard for "I'm running on localhost but I want some access
   control."
3. Default-binding to `0.0.0.0` (which both tools do) is a footgun.
   We will not make that mistake.
4. Browser-side rendering with xterm.js is well-trodden but it commits
   us to "render via ANSI escapes," which forecloses on the structured
   semantic-tree rendering we want for accessibility. xterm.js *also*
   has an `addon-attach` whose protocol is just bytes-in-bytes-out, with
   a small in-band signal for resize and a stdin-vs-stdout discriminator
   on the first byte of each frame
   ([xtermjs/addon-attach](https://github.com/xtermjs/xterm.js/tree/master/addons/addon-attach)).

### tmate — pair-programming TTY share

[tmate](https://tmate.io/) is a fork of tmux focused on instant terminal
sharing. Its architecture is more sophisticated than ttyd's:

- The user runs `tmate` and gets two URLs printed to their terminal: an
  SSH connection string and an HTML viewer URL. Both are gated by a
  150-bit per-session token.
- The local `tmate` daemon forwards a "replication log stream" to a
  remote proxy daemon. The proxy serves WebSocket clients with the
  replicated stream.
- The proxy is geographically replicated — paper documents 4 datacenters
  for low latency.
- The local tmate server runs in a jail with no file system access and
  its own PID namespace.

The tmate
[paper](https://viennot.com/tmate.pdf) is one of the rare
academic descriptions of "TTY sharing as a system." The model is:

> "all files required during the tmux server execution are opened
> before getting jailed. These measures are in place to limit the
> usefulness of possible exploits."

What tmate teaches us:

1. **Read-only viewers are valuable.** Lots of tmate's audience just
   wants to *watch* a session, not type into it.
2. **The default URL must include a token.** No exception.
3. **The architecture should support a relay**, even if v1 is
   localhost-only. The relay is what enables sharing; if we hardwire
   "the binary is the server" we foreclose on it.
4. **Sandboxing the rendering target matters.** The browser is a sandbox
   for the *viewer*, but the *server* (the SwiftTUI binary) is not
   sandboxed at all. This is the asymmetry that makes "bind to
   localhost" a hard default.

### textual-serve — TUI framework owns the bridge

[`textual-serve`](https://github.com/Textualize/textual-serve) is the most
direct prior art. It's part of the
[Textual](https://github.com/Textualize/textual) ecosystem and is what
Textual recommends as their accessibility story.

> "textual-serve is an open source project which allows you to serve
> and access your Textual app via a browser. The Textual app runs on a
> machine/server under your control, and communicates with the browser
> via a protocol which runs over websocket."
>
> ([textual.textualize.io](https://textual.textualize.io/blog/2024/09/08/towards-textual-web-applications/))

The architecture:

- The user runs `textual serve <module>`.
- `textual-serve` starts an HTTP server.
- When a browser visits, the server **launches the Textual app as a
  subprocess** and pipes stdin/stdout over the WebSocket.
- Bytes flowing browser→server become the subprocess's stdin (escape
  sequences, mouse, paste). Bytes flowing server→browser are the
  subprocess's stdout (ANSI rendered output, which xterm.js renders).

> "Escape codes are sent through websocket to textual-serve and then
> piped to the stdin stream of the Textual app which is running as a
> subprocess... A Textual app writes to the stdout stream, which is
> then read by your emulator and translated into visual output."

This is the cleanest model for a *language ecosystem* host: the
framework provides the bridge, the user's app is unchanged, and the
bridge is generic across every Textual app on disk. It's also the model
that does the *least* with the framework's semantic information — it
sends raw ANSI; the browser only knows what xterm.js can extract.

What textual-serve teaches us:

1. **Subprocess isolation is the right shipping shape**. The bridge does
   not need to be in the same process as the app; piping is enough.
   This means the same `swift-tui-web` binary can host any compiled
   SwiftTUI app, with no rebuild.
2. **It's all stdin/stdout.** The framework didn't have to invent a new
   surface protocol — they reused the PTY one. We can do better
   *because we already have a richer protocol* (the surface JSON), but
   the textual-serve shape is a fallback we can keep available.
3. **The cost of "raw ANSI bytes only" is real.** Textual is publicly
   pursuing this as their accessibility story even though xterm.js
   provides almost no semantic information to screen readers. Our
   surface protocol gives us the chance to do meaningfully better.

### aider --browser / Streamlit — abandon the TUI

[aider](https://aider.chat/docs/usage/browser.html) is an AI pair-programming
CLI that ships *both* a TUI mode and a `--browser` mode. The browser mode
is implemented with [Streamlit](https://streamlit.io/), which is a
Python framework for "build a Tornado-served React frontend by writing
Python." The browser experience is **not the TUI rendered to HTML**; it
is a different UI that happens to share the model layer.

> "You can launch Aider's browser version using the `--browser` flag
> with the command `aider --browser`. This opens a Streamlit-based chat
> window in your default browser, with the same Git integration and
> file editing as the CLI."
>
> ([aider.chat](https://aider.chat/docs/usage/browser.html))

This is the "abandon the TUI in browser mode" pattern, similar to
Charm `huh`'s "drop the TUI" accessibility fallback documented in
[`ACCESSIBILITY.md`](./ACCESSIBILITY.md). It works for aider because
their TUI is essentially a chat log + file picker — both are easy to
re-skin. It works *less well* for a generic TUI framework because the
view trees a user authors are arbitrary.

What aider teaches us:

1. We **do not** want this shape. swift-tui's value proposition is
   "write the SwiftUI-shaped view tree once, render it many ways." A
   web mode that requires authors to write a separate Streamlit-style
   UI defeats the point.
2. But we do want the *option* of a "linear/dom-rebuild" rendering on
   the browser side that does more than render ANSI in xterm.js. This
   ties to the accessibility proposal's "emit real ARIA from the
   semantic phase" recommendation.

### jupyter notebook / code tunnel — the URL-and-token UX

These are the gold standard for "binary on your machine, browser
elsewhere, open this URL."

[Jupyter](https://jupyter-notebook.readthedocs.io/en/5.6.0/security.html)
prints a URL like:

```
http://localhost:8888/?token=c8de56fa4deed24899803e93c227592aef6538f93025fe01
```

> "When you start a notebook server with token authentication enabled
> (default), a token is generated and logged to the terminal so that
> you can copy/paste the URL into your browser."

The flag matrix is small but worth copying:

- `--no-browser` — print the URL, do not open a browser.
- `--port=N` — pick a port; default tries 8888 then increments on
  collision.
- `--ip=0.0.0.0` — bind publicly. Comes with a warning.
- `--NotebookApp.token=''` — explicitly disable auth (also warns).

Importantly, Jupyter generates a *one-time* additional token that lets
the auto-launched browser set a cookie; after the cookie is set, the
single-use token is discarded. This bridges the gap between "URL is
shareable" and "session is sticky."

VS Code's
[`code tunnel`](https://code.visualstudio.com/) takes the same shape but
adds GitHub-OAuth-backed device-pairing — a longer-lived equivalent to
Jupyter's token. For our purposes the Jupyter-shape is sufficient.

What jupyter / code-tunnel teach us:

1. **Print the URL plainly.** Don't bury it in logs. Don't print color
   that breaks copy-paste in some terminals. Print the URL on its own
   line, with a leading `[swifttui]` prefix that's easy to grep.
2. **Token-in-URL is the path of least friction.** Yes, query-string
   tokens leak via referrer and access logs. For *localhost* this is
   acceptable; for `--web-host 0.0.0.0` it becomes a knob the user has
   to turn on with eyes open.
3. **Auto-open the browser is a *flag*, not a default.** Jupyter
   defaults to opening (annoying when you ssh'd in); we should default
   to *not* opening, with `--web --open` available as a one-line
   convenience.
4. **Port collision policy: try the default, then increment.**
   Jupyter does this; ttyd does this. Predictable and ergonomic.

### asciinema — passive replay, not interactive host

[asciinema](https://asciinema.org/) is in this list to be ruled out.
It's terminal **session recording**, not interactive remote control:

> "asciinema captures terminal session output into lightweight
> recording files in the asciicast format (.cast), unlike typical
> screen recording software which records into heavyweight video
> files."

`asciicast v3` uses interval-delta timing and is well-specified.
[`asciinema-player`](https://github.com/asciinema/asciinema-player) is a
JS player that renders these casts.

What asciinema teaches us:

1. **The cast format is a useful sidecar.** A "record this SwiftTUI
   session as it runs" mode (`--record session.cast`) is essentially
   free if we have the surface protocol — and it's a documented public
   format. Worth flagging as a follow-up.
2. **Replay-only mode is not what we want for v1**, but it's a useful
   subset: a "snapshot to HTML" build target falls out for free.

### VS Code Server / code-server — the heavy end

[code-server](https://github.com/coder/code-server) (community port of
VS Code Server) is the "full IDE in a browser" implementation. It's
included here only to mark the upper bound:

- Massive frontend bundle (the whole VS Code UI).
- Service-worker'd offline capability.
- Long-running session reattach.
- File-system access from the browser, multiple terminals, debug
  sessions, etc.

Nothing about that shape is appropriate for "view a TUI in a browser."
It's the cautionary "don't reinvent a remote desktop" example.

### xterm.js as the de facto browser-side renderer

[xterm.js](https://github.com/xtermjs/xterm.js) is the browser-side
terminal emulator that *every* terminal-in-browser tool uses. It ships
its own renderer (DOM, canvas, and WebGL backends), supports VT100/220
escape sequences, mouse reporting, IME, CJK, true color, and has a
mature addon ecosystem (`addon-attach`, `addon-fit`, `addon-search`,
`addon-webgl`, `addon-image`, `addon-ligatures`).

The relevant addon for our case is
[`@xterm/addon-attach`](https://github.com/xtermjs/xterm.js/tree/master/addons/addon-attach):

> "The @xterm/addon-attach attaches to a server running a process via a
> websocket. This module provides methods for attaching a terminal to
> a WebSocket stream."

If we wanted the cheapest possible browser bundle, we would ship
xterm.js + addon-attach and call the wire format "raw ANSI bytes." The
binary stage would emit ANSI to a WebSocket, the browser would render
it, done.

But: this discards the structured `web-surface` protocol that
`Platforms/Web/` already uses, and it costs us the ARIA/semantic
rendering path. The recommendation in this proposal is **don't use
xterm.js** for the default browser-side bundle — reuse the existing
`webhost` TS package which already consumes our structured wire format
and produces canvas/DOM rendering with a richer per-cell record. xterm.js
remains a fallback option for an "ANSI mode" we may add later if real
deployments demand it.

---

## What we already have in swift-tui

The codebase is unusually well-prepared for this work. Files that this
proposal builds on:

- **`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`**.
  Defines `WebSurfaceTransport` (a `PresentationSurface` that emits
  `web-surface` JSON to a file descriptor), `WebSurfaceInputReader`
  (parses input commands from a file descriptor), `WebSurfaceInputParser`
  (the wire-format parser), `WebSurfaceFrameEncoder` (the frame
  encoder), and `WebSurfaceInputControlMessage` (resize / style
  control messages). All `package`-visibility — designed to be reused
  by sibling packages, not just `SwiftTUIWASI`.

- **`Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceTransportTests.swift`**.
  Snapshot tests against fixture surfaces. The fact that the encoder
  output is fixture-tested means we can change the transport (TCP vs
  fd) without changing the wire format and reuse the same fixtures.

- **`Platforms/Web/src/WebHostSurfaceTransport.ts`**.
  The TypeScript decoder for the wire format. Defines
  `WebHostSurfaceCell`, `WebHostSurfaceStyle`, `WebHostSurfaceImageFormat`,
  etc. This is the type contract the browser side speaks today; it does
  not care whether bytes arrive over a postMessage WASI bridge or a
  WebSocket.

- **`Platforms/Web/src/WebHostApp.ts`**, **`WebHostSceneManifest.ts`**,
  **`WebHostSceneRuntime.ts`**, **`browser.ts`**. The browser-side
  rendering and scene-management code. Bundled today by Bun for
  consumption by `Examples/WebExample/`. This is the bundle we want to
  ship inside the runner package.

- **`Sources/SwiftTUI/HostedSceneSession.swift`**. The host-agnostic
  scene-running abstraction. Already used by `StreamingTerminalHost`
  (CLI), and the hooks for swapping the `PresentationSurface` exist
  cleanly.

- **`Platforms/CLI/Sources/SwiftTUICLI/`**.
  `TerminalRunner.run`, `CLIMode.parse`,
  `SocketServer`/`SocketClient` (Unix-domain sockets for scene
  attach), `SceneInfoRegistry`, `PtyPair`. The CLI runner is the
  blueprint to copy.

- **`Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift`**. The WASI
  runner is where `web-surface` is wired up today. The
  `webSurfaceSceneResources()` function constructs a
  `WebSurfaceTransport` against `STDOUT_FILENO` and a
  `WebSurfaceInputReader` against `STDIN_FILENO`. To repoint at a
  WebSocket-backed pair of file descriptors is small.

- **ADR [`0008-swifttui-library-only-runners-own-main`](../decisions/0008-swifttui-library-only-runners-own-main.md)**.
  This proposal composes naturally with that decision: the new web host
  is a runner peer.

- **ADR [`0007-host-packages-are-peers`](../decisions/0007-host-packages-are-peers.md)**.
  Reaffirms the layout convention.

The implication: the wire format exists, the encoder exists, the parser
exists, the browser bundle exists, and the runner pattern exists. The
*missing pieces* are:

1. An HTTP+WebSocket server in Swift, embeddable in a runner.
2. A `PresentationSurface` whose underlying file descriptors are a
   WebSocket pair, not stdin/stdout.
3. A way for the runner package to ship the `webhost` TS bundle as a
   resource served by its embedded HTTP server.
4. CLI flags and lifecycle policy.

That's a sharply-defined work area, not an open-ended re-architecture.

---

## Architecture options

There are four plausible places to put this work. The principles
discussion above already biases toward Option A; this section walks
through the others to make the rejection visible.

### Option A: A new `Platforms/WebHost` runner peer

A new peer to `Platforms/CLI` and `Platforms/WASI`. Authors who want
a web-rendered binary import:

```swift
import SwiftTUI
import SwiftTUIWebHost   // <-- provides the `--web` mode + App.main()

@main
struct MyApp: App { ... }
```

Or, with both:

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIWebHost   // CLI flag --web is delegated to this runner
```

Pros:

- Composes with [ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md) cleanly.
- HTTP server dependency lives in the runner package, not in
  `SwiftTUI`. Authors who don't want it don't pay for it.
- WASI bridge code (`WASISurfaceBridge`) is already a peer-package
  library; the new runner depends on `SwiftTUI` directly *and* on
  `WASISurfaceBridge` for the encoder/parser.
- Independent CI for HTTP/WS code without churning the root package.

Cons:

- Three packages now ship `App.main()` defaults
  (`SwiftTUICLI`, `SwiftTUIWASI`, `SwiftTUIWebHost`). Authors who
  import more than one need to choose explicitly. ADR-0008 already
  imposes this; it just gets one more.
- New surface to maintain.

### Option B: Capability built into every binary

Add the HTTP server directly to `SwiftTUI` so `myapp --web` works
unconditionally.

Pros:

- One import. Zero ceremony.

Cons:

- **Foundation-free constraint**. Every Swift HTTP/WS server we surveyed
  pulls in either Foundation (Hummingbird, FlyingFox dependencies on
  some platforms) or substantial NIO machinery. Putting any of those
  in `SwiftTUI` violates the
  `no-foundation-in-library-products` prek hook.
- **Binary-size cost.** Even a minimal swift-nio HTTP server adds tens
  of MB of dependencies (`SwiftNIO`, `SwiftNIOHTTP1`, `SwiftNIOWebSocket`,
  `SwiftNIOConcurrencyHelpers`, etc.). Authors who don't want the web
  host shouldn't pay for it.
- **Attack surface in every binary.** Even if `--web` defaults to off,
  a critical CVE in the bundled HTTP server now affects every SwiftTUI
  app shipped, regardless of whether they use the feature.
- **Runner-decision creep.** `App.main()` already lives in runner
  packages; pushing some launch behavior back into `SwiftTUI` undoes
  the discipline ADR-0008 imposed for good reason.

Reject.

### Option C: Out-of-process attach via SwiftTUICLI

Reuse the existing `SwiftTUICLI` Unix-domain socket attach mechanism
(`Platforms/CLI/Sources/SwiftTUICLI/SocketServer.swift`,
`AttachProxy.swift`) — but invented for it: ship a separate
`swift-tui-web` *daemon binary* that attaches to a running
SwiftTUI scene over the socket and exposes it as a WebSocket.

Pros:

- The user's binary doesn't need to embed an HTTP server at all.
- The daemon can be installed once and shared across many SwiftTUI
  apps on the machine.
- Mirrors how `tmate` and `code tunnel` separate "the thing being
  shared" from "the thing serving it."

Cons:

- Two binaries to ship. Two binaries to install. The user has to know
  about both.
- Still need a runner package to *start the daemon*, or the user runs
  it manually. Either way we've added a separate-binary install
  problem to a feature whose pitch is "just run `myapp --web`."
- The Unix-domain socket attach protocol in `SwiftTUICLI/SocketServer`
  is currently designed for live-attach to an already-running
  multi-scene CLI session. Reusing it for "render to web" requires
  generalizing the socket protocol *and* would conflate
  attach-from-other-terminal with attach-from-browser.

A hybrid is plausible: ship `swift-tui-web` as an *optional* attach
client, and *also* let any binary self-host the web mode via Option A.
Attach as a v3 follow-up; not now.

Defer; revisit for "shared session" use cases.

### Option D: Daemonize and reverse-proxy

Run a long-lived daemon on the machine that proxies many SwiftTUI
binaries' web modes through one canonical port (`http://localhost:9123/myapp/`),
similar to `pueue` or `mosh-server`.

Pros:

- One port to remember.
- Multiple sessions on one well-known origin.

Cons:

- Wildly over-engineered for v1. We have no users yet for v1, let
  alone for "many binaries on one machine, all served from one port."
- Reverse-proxying a WebSocket through a long-lived daemon adds
  failure modes (daemon crashes, daemon upgrades while sessions are
  open, stale registrations) that aren't worth solving until people
  ask for them.

Reject for now; if "share my session over the open web" becomes a real
ask, it's plausibly a relay server, but that's another whole proposal.

### Verdict

Option A. A new `Platforms/WebHost` runner peer that depends on
`SwiftTUI` for runtime, `WASISurfaceBridge` for encoder/parser, and a
minimal HTTP+WS server for transport. The runner ships the browser
bundle as a resource. Authors opt in by adding a single dependency.

---

## Server stack

The runner needs an embeddable HTTP+WebSocket server. Surveyed options:

| Library | Concurrency model | WS support | Deps | Notes |
|---|---|---|---|---|
| **[`Hummingbird 2`](https://github.com/hummingbird-project/hummingbird)** | async/await + structured concurrency throughout | Yes via `swift-websocket` | swift-nio, swift-async-algorithms, etc. | Mature, batteries included, SwiftNIO-based. Hummingbird 2 (current 2.22 as of Apr 2026) is a complete rewrite around async/await. |
| **[`FlyingFox`](https://github.com/swhitty/FlyingFox)** | async/await on BSD sockets directly (no NIO) | Yes (`WSHandler` AsyncStream of frames) | **Zero package dependencies** | iOS 13+/macOS 10.15+/Linux. Uses kqueue/epoll directly. Minimal surface; this is its primary pitch. |
| **`swift-nio` + `swift-nio-http1` + `swift-nio-websocket`** | EventLoop-based, with async-await wrappers | Yes (`NIOWebSocket`) | NIO core | The substrate Hummingbird is built on. Lower-level; more boilerplate. |
| **`Vapor`** | Full framework (routing, middleware, Leaf templates, etc.) | Yes | Heavy (Fluent ORM, Console, Crypto, etc.) | Massively over-engineered for "serve one HTML page + one WS endpoint." |
| **Hand-rolled HTTP/1.1 + WS upgrade on POSIX sockets** | async/await with custom socket loops | Yes (RFC 6455 is short) | None | Cheapest. Adds a "hand-rolled HTTP" maintenance burden; bug surface. |

Two finalists: **FlyingFox** and **Hummingbird 2**.

**FlyingFox arguments:**

- Zero package dependencies. From the README: "FlyingFox internally uses
  a thin wrapper around standard BSD sockets, with the FlyingSocks
  module providing a cross platform async interface to these sockets."
  No new SwiftPM transitive surface to maintain.
- Built around async/await from day one — fits naturally with the
  swift-tui runtime's structured-concurrency style.
- Smaller binary and faster cold start. The design pitch is "embed me
  in a CLI tool"; that's exactly what we're doing.
- Active development, MIT license, suitable for production embedding.

**Hummingbird 2 arguments:**

- Bigger ecosystem, more documentation, more example code.
- Built on swift-nio, which is the canonical Swift networking stack;
  if we ever needed performance work or a remote-relay version, NIO is
  where that work happens.
- Companion `swift-websocket` package handles WS framing + upgrades
  with first-class async APIs.

For the use case here — **one HTML page, one WebSocket per scene, a
handful of static asset responses, localhost-only by default** —
FlyingFox is the better fit. The dependency cost dominates; we don't
need NIO's throughput, we need cold-start under 100ms and binary-size
overhead in the low single-digit MB.

**Recommendation:** start with FlyingFox. Keep the server abstraction
internal to `SwiftTUIWebHost`, behind a small `WebHostServer` protocol
so the dependency can be swapped if needed. Ship a `Hummingbird` flavor
as an alternative target if real workloads emerge that justify it (e.g.
HTTP/2 push, request rates that benefit from NIO).

If FlyingFox is rejected on review for stability or compliance
reasons, the fallback is Hummingbird 2 + `swift-websocket`. The
hand-rolled option exists as a "we're stuck" plan; we should not start
there.

---

## Wire format

> **Audit correction (2026-05-04):** the section below describes the
> v1 reuse strategy correctly, but the original framing oversold what
> the existing encoder carries. The
> [`WebSurfaceFrameEncoder`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)
> emits **raster cells only** — `[x, character, spanWidth,
> styleIndex]` per visible cell — not semantic data. There are no
> roles, labels, or focus identities in the v1 wire format. For
> accessibility-correct browser rendering (real ARIA) the format
> needs to be **extended** with an `accessibilityTree` field; this
> is laid out as Phase 6 step 1 in
> [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) §"Suggested phasing." See
> [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) Finding 3 for the
> full breakdown. The "third format" subsection below is upgraded
> from "out of scope for v1" to "required before the embedded host
> can deliver its accessibility headline."

This proposal's central reuse: **the existing `web-surface` JSON
encoding from `WASISurfaceBridge`**, *transport-level* — extended for
ARIA when used as the accessibility delivery vehicle.

The encoder (`WebSurfaceFrameEncoder.encode`) emits a record per frame
of the form:

```text
 surface:{"version":1,"width":80,"height":24,"styles":[null, {"fg":"#eceff4ff", ...}], "rows":[[[0,"H",1,0],[1,"i",1,0]], ...], "images":[...]}\n
```

The leading `` (RS, "record separator") and trailing `\n` make
the stream parseable as a series of records; the
`WebSurfaceInputParser` already understands them.

The input direction is similarly already specified:

```text
 key:character:H:0\n
 key:return::0\n
 mouse:down:12.5:3.2:primary:0:0:0\n
 resize:80:24:8:16\n
 paste:hello%20world\n
 style:base64encodedtheme...\n
```

These two streams are **bidirectional and self-framing**. They were
designed to flow over stdin/stdout pipes between a WASI module and a
browser; flowing them over a WebSocket changes nothing about the encoding.

What the WebSocket transport adds:

1. **Framing.** WebSocket already frames messages, so the leading
   `` introducer is technically redundant — but harmless. We
   keep it to maintain bytewise-identical streams across the WASM and
   embedded transports, and to keep the test fixtures shared.
2. **Backpressure.** The wire format is pure-text, easy to coalesce.
   When a client falls behind, the server can drop intermediate frames
   and only send the most recent one (since each frame is a full
   surface state). This mirrors how the existing CLI rasterizer treats
   committed surfaces.
3. **Compression.** WebSocket `permessage-deflate`
   (RFC 7692) compresses well on the JSON payload (often 5-10×).
   On by default unless the user disables it.
4. **Two channels per scene? Or one?** The current bridge multiplexes
   input control messages and key events on the same input stream.
   We keep that. A scene's WebSocket carries inbound input + outbound
   surface frames, just as today.

What this *doesn't* commit us to:

- We are **not** adopting xterm.js. The browser bundle decodes
  structured per-cell records, not ANSI escapes.
- We are **not** inventing a new format. If `web-surface` v2 ships
  one day for the WASM target, embedded gets it for free.

A *secondary* wire format is worth flagging: a future "ANSI fallback
mode" that emits ANSI escape sequences over the same WebSocket and is
consumed by xterm.js. This would let us serve "any ANSI-emitting
process" — not just a SwiftTUI binary — through the same machinery,
which is a credible follow-on. Not in v1.

A **promoted** future format (post-audit, no longer optional for
the accessibility headline) is the ARIA/semantic-tree projection
from [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) §"What the embedded
web host unlocks." Concretely:

- Bump the `version` field in the JSON envelope from `1` to `2`.
- Add an `accessibilityTree` field alongside `rows`, carrying the
  flat `AccessibilityNode` list produced by the audited Phase 3b
  extension to `SemanticExtractor` (see
  [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) Finding 2). Shape:
  `[{id, parentId, role, label, hint, hidden, liveRegion,
  isFocused, rect}, …]`.
- Backward-additive: a v1-aware browser bundle ignores the new
  field; a v2-aware bundle uses it to mount a hidden DOM tree
  alongside the visual grid.

This is the difference between "embedded host that happens to render
in a browser" and "embedded host that is the accessibility delivery
vehicle." The audit upgrades it from v2 to v1 of the embedded
host's accessibility-relevant deliverable. The embedded host is a
strictly better home for ARIA than the WASM target because the
binary has more CPU and memory headroom than the wasm sandbox does;
this argument continues to hold.

A separate **performance** correction (audit Finding 6): the
existing encoder emits a *full surface* per commit (`strategy:
.fullRepaint` on
[`WebSurfaceTransport.swift:251`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)).
For the WebSocket transport at higher refresh rates this is
wasteful; v1 accepts this for correctness, but a diff-based
encoder variant (mirroring the terminal-side `CommitPlanner`) is
worth tracking as an explicit performance phase.

---

## Browser-side bundle

Three options:

### B1. Reuse `Platforms/Web/`'s `webhost` TS package as a static bundle

The runner package builds (or pre-builds) the `webhost` TS package
into a small set of static files (`index.html`, `webhost.js`,
`webhost.css`) and ships them as Swift package resources
(`.process(...)` or `.copy(...)` in `Package.swift`). The embedded HTTP
server serves them on `GET /`.

Pros:

- One implementation of the browser-side renderer for both the WASM
  target and the embedded target.
- `Platforms/Web/`'s test surface (Bun tests against
  `WebHostSurfaceTransport.ts`, `WebHostSceneRuntime.ts`, etc.)
  validates this codepath too.

Cons:

- The bundle has to be pre-built and committed (or built at SwiftPM
  build time, which complicates the build).
- We commit to the `webhost` API as a stable public contract.

This is the recommended path.

### B2. xterm.js + a thin shim

Ship xterm.js + `addon-attach` instead. The wire format becomes ANSI
bytes; the binary either re-uses the existing
`StreamingTerminalHost` and pipes its output, or adds a new
"ANSI for browser" host.

Pros:

- xterm.js is battle-tested; we get true color, mouse, IME, ligatures
  for free.
- Smaller bundle than carrying our own renderer.

Cons:

- Discards the structured surface protocol and forecloses on the ARIA
  rendering path that's the whole accessibility motivation.
- Requires us to *also* maintain the ANSI-rendering path on the
  binary side. Currently `WebSurfaceTransport` doesn't emit ANSI — it
  emits surface JSON. So this is a new emission mode.

Defer. Worth as a future "ANSI compatibility mode" if a real workload
demands it (e.g. running non-SwiftTUI ANSI-emitting tools through the
same machinery).

### B3. Build the bundle on first launch

When the user first runs `myapp --web`, the binary writes a tiny HTML
shim and serves it. No pre-built JS at all — the shim is hand-coded
HTML + a CDN-loaded copy of the `webhost` runtime (or xterm.js).

Pros:

- Zero binary-size cost.

Cons:

- Requires network access at launch; broken on air-gapped machines or
  first-run-offline.
- Loading framework code from a CDN we don't control is a third-party
  trust problem. Hard no.

Reject.

**Recommendation:** B1. Pre-built bundle, shipped as Swift package
resources, served from the embedded HTTP. Bundle size target:
~150 KB gzipped.

---

## Lifecycle and CLI shape

A user runs `myapp` and gets a TUI in their terminal. They run `myapp
--web` and get... what?

### The matrix

| Invocation | Terminal output | Browser behavior |
|---|---|---|
| `myapp` | Full TUI | none |
| `myapp --web` | Status line: `[swifttui] http://127.0.0.1:9123/?token=...` + log | Browser must be opened manually |
| `myapp --web --open` | Same as above | Auto-launches default browser to URL |
| `myapp --web --no-banner` | Just the URL on stdout, nothing else | Manual |
| `myapp --web --terminal` | TUI in terminal **and** WS server (mirrored) | Connect manually |
| `myapp --web --port 4567` | URL with that port; if taken, fail with error | — |
| `myapp --web --host 0.0.0.0` | URL + a warning banner about exposing the binary | — |
| `myapp --web --no-token` | URL + a warning banner about no auth | — |
| `myapp --web --record session.cast` | Same as `--web` plus on-disk asciicast | — |

A few subtle decisions in this matrix worth pulling out:

**Default to "no terminal output during --web mode."** The TUI doesn't
paint the terminal; the terminal is reserved for the URL, the log, and
the user's `Ctrl-C`. If the user wants a mirrored terminal, they pass
`--web --terminal`. This avoids the situation where the same TUI is
both painted in the terminal *and* shown in the browser, with two
diverging input streams. Which surface owns the input? In the default,
the answer is "the browser." If `--terminal` is set, the terminal
keyboard is read too and merged with browser input. (See
[Multiple connections](#multiple-connections-sessions-and-scenes).)

**Default to `--no-open`.** Users who SSH'd in or are running inside
tmux do not want a browser to launch on the server side. Auto-open
must be opt-in. Jupyter's default is the wrong default; `code tunnel`
wisely doesn't auto-open by default.

**Print the URL in the most copy-pasteable form possible.** No color,
no boxes, no bold. Single line, single token, ideally on its own
paragraph after a blank line:

```
[swifttui] Web mode active.

  http://127.0.0.1:9123/?token=hk1bAxK9mZ9pVmA7

Press Ctrl-C to stop.
```

The blank lines around the URL matter — they make it the easiest
target for a triple-click to select.

**`--web --record` is `--web` plus asciicast** — produces an
`asciicast v3` file recording the session. Free when we have the
surface protocol, useful as a deliverable artifact for bug reports
("attach the cast"), and trivially renderable later by
[asciinema-player](https://github.com/asciinema/asciinema-player).

**Lifecycle on disconnect:** when the last browser tab closes, the
binary keeps running. This matches `jupyter notebook` (you can close
the browser, the kernel stays up). Closing the binary requires
`Ctrl-C` in the terminal. If the user passes `--web --exit-on-disconnect`,
the binary exits when the last viewer disconnects (useful for
short-lived demos).

**Lifecycle on second connect:** when a new browser tab connects to a
running session, it joins as a viewer (see Multiple connections). It
does not restart the SwiftTUI scene — it picks up the live state.

### Terminal vs runner ownership

In a binary that imports both `SwiftTUICLI` and `SwiftTUIWebHost`:

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIWebHost

@main
struct MyApp: App { ... }
```

The `--web` flag is owned by `SwiftTUIWebHost`; the absence of
`--web` falls through to `SwiftTUICLI`'s normal terminal-launch. This
needs to be a documented contract in `SwiftTUICLI`'s `CLIMode.parse`
and a clean handoff. The implementation shape:

- `SwiftTUIWebHost` exposes `WebHostRunner.shouldHandle(_ args:)` and
  `WebHostRunner.run(_ app:)`.
- `SwiftTUICLI`'s `App.main()` calls
  `WebHostRunner.shouldHandle(CommandLine.arguments)` first — if
  `SwiftTUIWebHost` is imported, that call resolves; otherwise it's a
  no-op.
- If true, `WebHostRunner.run` takes over and the CLI mode is bypassed.

This is a small "well-known optional dependency" pattern; it requires a
weak reference from `SwiftTUICLI` to a `SwiftTUIWebHost` symbol. The
alternative is to make web mode a separate binary entry point
(`SwiftTUIWebHost.main`), which is cleaner architecturally but worse
ergonomically (the user has to choose at compile time which `@main`
they want). The "weak hook from CLI runner to web-host runner" pattern
is the right trade.

---

## Discovery, ports, and URLs

**Default port:** **9123**. This is high enough to never collide with
privileged services, low enough to be memorable, and not currently used
by any major dev tool we found. Jupyter uses 8888; ttyd uses 7681; gotty
uses 8080; Vite uses 5173. We avoid those.

**Port collision:** if 9123 is bound, increment by 1 until a free port
is found, up to a budget (e.g. 9123–9132, ten attempts). After the
budget, fail with a clear error and recommend `--web --port N`.

**Token:** 128 bits of randomness, base64-url-encoded (22 chars). One
token per process invocation. No tokens are persisted to disk.

**URL printing format:** `http://127.0.0.1:PORT/?token=TOKEN`. The
binary should detect that the user is on macOS / Linux / Windows and
adjust nothing — the URL is a URL.

**Auto-open:** opt-in via `--web --open`. Implementation uses the
platform-native browser-launch mechanism: `open` on macOS, `xdg-open`
on Linux, `start` on Windows. Conditional `#if canImport(...)` blocks,
or a small shell-out, both fine. No need for a Swift package
dependency.

**QR code (optional):** for use cases where a phone is the viewer
(headless server, Raspberry Pi, etc.), printing a QR code of the URL
in the terminal is delightful and well-precedented (`gh auth login`,
`atuin`, `pueue`). Behind `--web --qr`. Implementation can vendor a
small ANSI QR generator; no external dependency.

**`mDNS`/`Bonjour`:** out of scope for v1. Useful as an "advertise on
the LAN as `myapp.local`" follow-up once the basic flow is solid.

---

## Security model

This is the most important section to get right. The proposal's
security defaults must be conservative, and any deviation must require
an explicit flag with an explicit warning.

### Bind address

**Default: `127.0.0.1` (loopback only)**.

Any binary that defaults to `0.0.0.0` exposes the developer machine to
any process on any network interface that can reach it. GoTTY's README
itself flags this as a footgun, and it's the reason the GitHub issue
search for `gotty CVE` returns lessons we don't want to relearn.

`--web --host 0.0.0.0` is available with a banner like:

```
[swifttui] WARNING: binding to 0.0.0.0 — this server is reachable
from any device on your network. Use a token-protected URL only.
```

We do *not* support binding to a specific interface (`--web --host
192.168.1.5`) in v1; loopback or all-interfaces is the choice. Adding
specific-interface support later is straightforward.

### Token authentication

**Default: a per-launch random 128-bit token**, served as
`?token=...` URL parameter. After the first successful HTTP request
with that token, the server sets a session cookie and the URL
parameter becomes optional.

Disabling the token requires `--web --no-token` and prints a banner
saying "this server is unauthenticated; do not expose externally."

Token-in-URL has well-known weaknesses:

- It leaks via the browser's `Referer` header to any external resource
  the page loads.
- It appears in the browser's history.
- It appears in HTTP server access logs.

For loopback connections we accept these costs because (a) there are
no external resources on the page in v1 (the bundle is fully
self-contained, no CDN, no analytics), (b) browser history is the
user's own, (c) we don't ship access logs by default. For
`--web --host 0.0.0.0` the warning banner explicitly notes that the
token-in-URL is not bulletproof and that the user should consider TLS
+ basic auth instead.

### Origin checks

The WebSocket handshake validates the `Origin` header is one of:

- `http://127.0.0.1:PORT` (loopback bind)
- `http://localhost:PORT` (loopback bind, alternate hostname)
- `null` (file:// — should not happen for our serving page)

If the user binds to `0.0.0.0`, an additional `--web --allowed-origin
URL` flag may add origins. Without it, any cross-origin WS upgrade is
rejected.

This blocks
[DNS rebinding](https://en.wikipedia.org/wiki/DNS_rebinding) attacks
where a malicious page tells the browser to resolve some hostname to
`127.0.0.1` and then ride the open localhost server.

### CSRF

The HTTP endpoints are entirely under our control and fall into two
categories:

- `GET /` (the bundle), `GET /static/*`, `GET /scene-manifest.json` —
  read-only. CSRF doesn't apply.
- `WebSocket /scene/<id>` — origin-checked at upgrade. CSRF doesn't
  apply to a WS endpoint that already validates origin and token.

There are no `POST` endpoints in v1.

### TLS

**v1: no TLS.** Localhost-only doesn't need it; LAN with `0.0.0.0`
gets a "use a tunnel" recommendation in the warning banner. Self-signed
certs in v1 are worse than no TLS — they add cargo-cult security
without solving anything.

`--web --cert PATH --key PATH` for users who want HTTPS via a real cert
is a v3 feature.

### File system access from the browser

**None.** The bundle does not expose `/api/files` or anything similar.
The browser is a **rendering surface**; it does not get to read the
user's disk.

This is a hard line. Things like "view the user's files in a Finder-like
panel" are tempting follow-ons; if we go there, it's behind a `--web
--enable-file-api` opt-in *and* a token *and* a separate `--web
--root PATH` chroot. None of that is in v1.

### Scope check

A SwiftTUI binary running with `--web` should be considered as
trustworthy as the binary itself. The web mode does not relax process
boundaries; the `myapp` process can do anything it could do without
`--web`. The point is **the browser must not be able to do more than
view the rendered output and send keyboard/mouse events**. Specifically:

- The browser cannot upload files.
- The browser cannot execute arbitrary shell commands.
- The browser cannot access env vars or process state.
- The browser cannot persist state on the server beyond what the
  TUI's normal data-handling code does.

This is naturally enforced by the wire format: it's just frames and
input events, both bounded.

---

## Multiple connections, sessions, and scenes

The `tmate` model makes the right distinction: many viewers, one driver.

### Default behavior

- **First browser tab to connect: gets input authority.** That tab can
  type, mouse, paste.
- **Second browser tab onward: read-only viewer.** The tab sees the
  same surface frames, but its keystrokes are silently dropped (or
  rejected with a notification).
- **Switching authority:** the read-only tab can request authority
  with a UI control ("take over"); the current driver gets a "another
  viewer is requesting control" notice. Default policy: any viewer
  can take over without confirmation. That's what `tmate` does, and
  the localhost case rarely has more than one human anyway.

### Same-scene vs different-scene

A SwiftTUI app with multiple scenes (multi-window) is allowed under
ADR-0008 and has socket-based scene attach in `SwiftTUICLI`. The
embedded web host extends this:

- A scene picker page (`GET /`) shows the scenes available.
- Each scene has its own URL, like `GET /scene/SceneID/`.
- Each scene has its own WebSocket and its own driver/viewers.

For v1 we ship single-scene support and let multi-scene be a v2
follow-on, since multi-scene CLI behavior is itself still being
shaken out per
[`docs/STATUS.md`](../STATUS.md) signals.

### Lifecycle on disconnect

- Driver disconnects: input authority is released. If a viewer is
  present, they're auto-promoted.
- Last viewer disconnects: scene continues running. The user can
  reconnect from the same URL and pick up the live state.
- Process killed: scene ends; subsequent connections get a clean
  "session no longer running" error page.

### Reconnect after navigation

A browser refresh or a tab close-and-reopen should be transparent. The
session is keyed by token; reconnecting with the same token resumes the
same scene without rebooting the runtime. This implies a small
server-side reconnection grace period (a few seconds) where the surface
state stays warm.

### Same-machine SSH proxy

A user SSHs into a remote machine, runs `myapp --web --host
0.0.0.0`, and connects from the laptop's browser. This works today with
the design proposed: the URL prints with a private IP (or `0.0.0.0`),
the user adapts. Even better, `ssh -L 9123:localhost:9123 host` is the
canonical port-forward and lets the user keep `--web` on its
loopback-only default. We document both flows in the v1 README.

---

## Headless rendering and CI

The same `WebSocketSurfaceTransport` that serves a browser can be
*driven without one*. This unlocks two valuable side channels:

1. **Snapshot tests at the surface level**, not the cell level.
   `Tests/SwiftTUITests/` already has fixture-based assertions; the
   embedded host gives us a way to drive a full app, capture the
   `web-surface` JSON sequence, and diff against a golden file. This
   is more semantically meaningful than diffing rasterized cells
   because the semantic info is preserved.

2. **Screenshot generation for docs and bug reports.** Run `myapp
   --web --headless --screenshot out.png` — the runner spins up the
   server, drives a headless renderer (a small Swift WebKit shim, or
   Puppeteer-driven Chromium, or a server-side surface-to-PNG
   renderer), captures one frame, exits. Useful for the website
   gallery in `Website/` and for regression baselines.

3. **`asciicast` recording.** As above; falls out of the wire format.

The headless story is **not v1** — it depends on having a stable
WebSocket transport first — but the architecture should not foreclose
it. Specifically: `WebHostRunner.run` should accept a "no server"
mode where the surface output is captured to a sink, and the input
events are scripted from a sequence — that's the headless test
harness in seed form.

---

## Performance and throughput

The wire format already pays attention to two important properties:

1. **Per-frame full state**, not deltas. Each `web-surface` frame is
   a full surface description. This makes catch-up trivial when a
   client falls behind — drop intermediate frames, send the latest.
2. **Style table interning.** The encoder maintains a per-frame
   `styles` array and emits style indices in cells, so a screenful of
   uniformly styled text doesn't repeat the style record per cell.

Layered on top, the embedded host adds:

3. **WebSocket `permessage-deflate` compression.** JSON compresses
   well; ~5–10× on typical content.
4. **Per-client coalescing.** When a client's WebSocket send queue is
   non-empty and a new frame arrives, replace the queued frame
   instead of appending. Bounded queue depth = 1 per client per
   scene. Mirrors the way `CommitPlanner` coalesces in the CLI
   target.
5. **Backpressure.** If a viewer is slower than the SwiftTUI runtime
   produces frames, the driver path is unaffected — the slow viewer
   simply lags, and dropped intermediate frames are fine because we
   send full state.

What the proposal does **not** do:

- **Send deltas** (only changed cells). A delta protocol over WS would
  reduce bandwidth in the typical case but complicates reconnect (need
  a base state) and complicates the format. Deferred unless real
  workloads demand it.
- **Use binary WebSocket frames** for the surface. The current format
  is text-JSON; binary would save the JSON parsing cost on the
  browser. Defer; profile first.

Cold-start budget: under 200ms from process launch to "URL printed."
This means the HTTP server must start synchronously (FlyingFox does)
and the bundle must be available without I/O fan-out (resources, not
filesystem reads).

Per-frame budget: under 5ms encoding + WS write on a modest dev
machine, for a typical 80×24 surface. The existing
`WebSurfaceFrameEncoder` already runs comfortably under this on
fixture tests; WS-write overhead is dominated by the kernel.

---

## Embedding cost

What does shipping a SwiftTUI binary with `import SwiftTUIWebHost` add?

| Concern | Estimate | Notes |
|---|---|---|
| Binary size, debug | +3–5 MB | FlyingFox + Swift std synergies; no NIO. |
| Binary size, release-stripped | +1.5–2.5 MB | After `strip(1)` and `-Osize`. |
| Cold start | <50ms additional | FlyingFox socket setup + bundle load. |
| Memory at idle | ~5–10 MB | One scene runtime + one WS connection. |
| Memory per viewer | ~2 MB | Per-WS buffers + style cache. |
| New transitive deps | FlyingFox (zero deps), the `web-surface` bundle as a Swift package resource (~150 KB gzipped). |
| Attack surface | Localhost-only by default; token-gated; FlyingFox is well-reviewed. |

Comparison: Hummingbird 2 + swift-nio + swift-websocket adds
considerably more (15–25 MB unstripped, several transitive deps).
Vapor adds even more. xterm.js (browser side) is ~300 KB minified, but
we're not using it.

The cost is small enough to justify the runner-package opt-in pattern,
but big enough to *not* embed it in `SwiftTUI`. ADR-0008 already
enforces that; this proposal honors it.

---

## Proposed design

### Package layout

```
Platforms/WebHost/
├── Package.swift
├── Sources/
│   ├── SwiftTUIWebHost/
│   │   ├── SwiftTUIWebHost.swift         # @_exported import SwiftTUI
│   │   ├── WebHostRunner.swift           # public entry point
│   │   ├── WebHostMode.swift             # CLI flag parsing for --web*
│   │   ├── WebHostServer.swift           # HTTP+WS server abstraction
│   │   ├── WebHostFlyingFoxServer.swift  # FlyingFox impl
│   │   ├── WebSocketSurfaceTransport.swift # PresentationSurface
│   │   ├── WebSocketInputAdapter.swift   # TerminalInputReading
│   │   ├── WebHostBrowserBundle.swift    # served static resources
│   │   ├── WebHostBanner.swift           # URL/QR/banner printing
│   │   ├── BrowserOpener.swift           # cross-platform `open`
│   │   └── Resources/
│   │       └── browser/                  # built webhost bundle
│   │           ├── index.html
│   │           ├── webhost.js
│   │           └── webhost.css
│   └── SwiftTUIWebHostBundleBuilder/
│       └── (build-time helper to refresh Resources/browser/)
└── Tests/
    └── SwiftTUIWebHostTests/
        ├── WebHostRunnerTests.swift
        ├── WebHostModeTests.swift
        ├── WebHostServerTests.swift          # end-to-end with a test client
        ├── WebSocketSurfaceTransportTests.swift
        └── WebSocketInputAdapterTests.swift
```

`Package.swift` (sketch — Foundation may be allowed in this runner;
following peers' practice):

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "SwiftTUIWebHost",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SwiftTUIWebHost", targets: ["SwiftTUIWebHost"]),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUIWASI", path: "../WASI"),
    .package(url: "https://github.com/swhitty/FlyingFox", from: "0.20.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUIWebHost",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "WASISurfaceBridge", package: "SwiftTUIWASI"),
        .product(name: "FlyingFox", package: "FlyingFox"),
      ],
      resources: [.copy("Resources/browser")]
    ),
    .testTarget(name: "SwiftTUIWebHostTests", dependencies: ["SwiftTUIWebHost"]),
  ]
)
```

### Public API

```swift
import SwiftTUIWebHost
@_exported import SwiftTUI

/// User-facing default `App.main()` for web-hosted SwiftTUI apps.
extension App {
  public static func main() async throws {
    try await WebHostRunner.run(Self.self)
  }
}

/// Public runner entry point.
public enum WebHostRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws

  @MainActor
  public static func run<A: App>(_ app: A) async throws

  /// Used by SwiftTUICLI's `App.main()` to weakly hand off `--web` to
  /// us when both runners are imported.
  public static func shouldHandle(_ args: [String]) -> Bool
}

/// Configuration plucked from CLI args + env vars.
public struct WebHostConfig: Sendable {
  public var bindHost: String = "127.0.0.1"
  public var port: Int = 9123
  public var token: String? = WebHostConfig.generateToken()
  public var openBrowser: Bool = false
  public var mirrorTerminal: Bool = false
  public var qrCode: Bool = false
  public var headless: Bool = false
  public var allowedOrigins: [String] = []
  public var recordPath: String? = nil
}

/// Flags handled (returns `true` if the args trigger web-host mode).
public enum WebHostMode {
  public static func parse(_ args: [String]) -> WebHostConfig?
}
```

The `PresentationSurface` and `TerminalInputReading` implementations
are package-internal:

```swift
package final class WebSocketSurfaceTransport: PresentationSurface,
  Sendable
{
  // Wraps a per-scene WS connection; encodes RasterSurface using
  // WebSurfaceFrameEncoder; writes to the WS write side.
}

package final class WebSocketInputAdapter: TerminalInputReading,
  Sendable
{
  // Reads from a per-scene WS read side; parses with
  // WebSurfaceInputParser; emits InputEvent and control messages.
}
```

### Wire protocol sketch

#### HTTP

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Static page (the bundle's index.html). |
| `GET` | `/static/webhost.js` | Static JS. |
| `GET` | `/static/webhost.css` | Static CSS. |
| `GET` | `/scene-manifest.json` | The scene manifest (ID, title, capabilities). |
| `GET` | `/healthz` | Returns 200 with token-validated, no body. |
| `GET` | `/ws/scene/{id}` | WebSocket upgrade endpoint. |

All endpoints require a valid token (URL `?token=` or cookie),
*except* `/static/*` to keep cache behavior simple. Token is checked
on `/`, `/scene-manifest.json`, and `/ws/scene/*`.

#### WebSocket per scene

After upgrade:

- Server → client: stream of ` surface:{...}\n` frames (the
  existing `WebSurfaceFrameEncoder` output).
- Client → server: stream of ` key:...\n`,
  ` mouse:...\n`, ` resize:...\n`,
  ` paste:...\n`, ` style:...\n` records (the
  existing `WebSurfaceInputParser` input vocabulary).
- New control records for v1:
  - ` hello:1:driver:{nonce}\n` — initial handshake.
  - ` auth:1:{tab-id}\n` — tab-level identity for input
    authority.
  - ` request-control:1\n` — viewer requests driver
    authority.
  - ` grant-control:1\n` / `revoke-control:1` — server's
    response.
  - ` ping:{ts}\n` / `pong:{ts}\n` — keepalive.

The introducer + `\n` framing lines up with the WASM transport's
existing format. The `command:version:...` shape extends naturally.

### Boot sequence

1. `WebHostRunner.run` parses args via `WebHostMode.parse`.
2. If web mode: collect `WindowSceneSelection`s from the app's body
   (same as `WASIRunner`).
3. Bind the HTTP server (FlyingFox) on `bindHost:port`. On collision,
   try `port+1...port+9`; fail if all collide.
4. Generate token if not disabled. Compute URL.
5. Print URL banner to stdout, optionally with QR code.
6. Optionally `BrowserOpener.open(url)` if `--open`.
7. Start serving. Each scene gets registered with a
   `HostedSceneSession` whose `PresentationSurface` is a
   `WebSocketSurfaceTransport` that lazily binds when a client
   connects.
8. Block on the runner's main async task, exit on `SIGINT` /
   process kill.

### Failure modes

| Failure | Behavior |
|---|---|
| Port already in use, no free port in budget | Print actionable error: "tried 9123–9132, all bound; pass `--web --port N`." Exit 1. |
| No browser available for `--open` | Log warning, fall back to URL-only. Don't fail. |
| Browser disconnects mid-frame | Server logs "viewer disconnected"; scene continues. |
| Scene crashes | WS connection sends a close frame with reason; browser shows "session ended unexpectedly." Exit 1. |
| User runs `--web` on a non-Darwin/Linux platform | Compile-time `#if canImport(...)` ensures the runner is only buildable where socket APIs exist. |
| Token validation fails | HTTP 403 with a small "invalid token" page. WS upgrades with bad token are rejected at handshake. |
| WS frame too large | Configurable max (default 8 MB for image attachments); larger payloads close the connection. |

---

## Open questions

(Things to decide before implementation. These aren't accepted positions; each
includes a "Lean" indicating where the proposal currently sits.)

1. **FlyingFox vs Hummingbird 2 as the server.** Argued above for
   FlyingFox on dependency-cost grounds.
   **Lean:** FlyingFox. If the package is judged too small/young or
   doesn't pass review for production embedding, fall back to
   Hummingbird 2 + `swift-websocket`. Either way, the dependency
   should be hidden behind an internal `WebHostServer` protocol so
   it can be swapped.

2. **Default port 9123, or another?** Jupyter's 8888 is iconic but
   collides with anything else trying to be Jupyter-like. `--port 0`
   (kernel-picked) is more correct but worse to print.
   **Lean:** 9123 with auto-increment to 9132 on collision.
   `--web --port N` for explicit choice. `--web --port 0` to let the
   kernel pick.

3. **Should `--web` also print a QR code by default?** Delightful for
   mobile, useless on a remote SSH session.
   **Lean:** off by default; `--web --qr` to opt in.

4. **`--web` and terminal output coexistence.** Default is
   browser-only. But what about tools whose users absolutely want
   both? "I want to see it in my terminal *and* on a phone."
   **Lean:** `--web --terminal` opt-in with the caveat that input
   events from both are merged — last-event-wins. Document it as
   "expert mode."

5. **What about Windows?** Swift on Windows is increasingly viable;
   FlyingFox does not ship Windows support today (it relies on
   kqueue/epoll). If we want Windows in v1, we need either Hummingbird
   2 (Windows-supported via NIO) or a hand-rolled Windows winsock path.
   **Lean:** Windows out of scope for v1 of this runner. macOS + Linux
   in v1; Windows when there's a real ask.

6. **Process model: one binary, in-process server (current proposal),
   or one binary that forks a server child?** In-process is simpler
   and gives us shared state for free. Forked server gives us a
   security boundary.
   **Lean:** in-process for v1. The browser is the
   sandbox; the *server* doesn't need additional sandboxing for
   localhost workloads.

7. **Authentication beyond token-in-URL.** Cookies? HMAC-signed
   cookies? Basic auth? OAuth?
   **Lean:** v1 is "token in URL → cookie set on first request →
   cookie checked on subsequent requests." Anything fancier waits for
   a real ask. For `--web --host 0.0.0.0` with sensitive data, the
   recommendation is "use an SSH tunnel."

8. **TLS in v1.** Self-signed certs are noise; real certs require
   either ACME plumbing or BYO cert flags.
   **Lean:** No TLS in v1. `--web --cert PATH --key PATH` is a
   straightforward v3 add. For LAN/internet exposure today, use a
   tunnel (`ssh -L`, `tailscale serve`, or
   [pinggy](https://pinggy.io/)).

9. **How does this compose with `SwiftTUICLI`'s socket-based attach
   protocol** (`Platforms/CLI/Sources/SwiftTUICLI/SocketServer.swift`)?
   In a binary with both runners, can a CLI `attach` peek at a
   running `--web` session?
   **Lean:** orthogonal in v1. The Unix-domain socket attach is
   designed for terminal-attaches; the WS server is its own thing.
   Cross-listening is a v3 idea ("attach to a running web session
   from another terminal") and probably belongs in a different proposal.

10. **Bundle building.** Pre-built and committed, or built at SPM
    build time?
    **Lean:** pre-built and committed (with a `Scripts/build-webhost-bundle.sh`
    that regenerates from `Platforms/Web/`). SPM build hooks for
    JS bundles are fragile and slow; "the bundle is a checked-in
    binary asset" is the simpler shape, even if it adds a manual
    step. The CI guard: a check that ensures the committed bundle
    matches a fresh build of `Platforms/Web/dist/`.

11. **Multi-scene support in v1.** ADR-0008 enables multi-scene; the
    CLI runner has scene-management. Does the WS bridge in v1 ship
    with scene-picker UI?
    **Lean:** v1 ships single-scene only; multi-scene is v2. Avoids
    coupling this proposal to multi-scene CLI work that is itself
    still settling.

12. **xterm.js fallback mode.** "ANSI mode" wherein the browser side
    is xterm.js and the binary emits ANSI escapes over the WS, useful
    for piping non-SwiftTUI processes too.
    **Lean:** out of scope for this proposal. Useful for a follow-up
    that turns swift-tui into a generic "CLI-in-browser" tool, but
    distracts from the actual ask: render *SwiftTUI* in a browser.

13. **Asciicast recording.** `--web --record session.cast`.
    **Lean:** worth flagging in the v1 design but ship in v2. Trivial
    once the wire format is stable; not load-bearing for the
    motivating use case.

14. **What does input look like with multiple scenes?** Each scene
    has its own focus model. In v1 single-scene, this is a non-issue.
    For v2 multi-scene, focus is per-scene and the URL routes to the
    scene; one focused scene per browser tab.
    **Lean:** defer. Tied to whatever multi-scene web shape we pick.

15. **Theme handoff.** The CLI runner sniffs the user's terminal
    theme; what does the browser look like by default? Light? Dark?
    System-following?
    **Lean:** follow `prefers-color-scheme` by default; the binary
    can pass an override via `WebHostConfig`. The
    `WebHostTerminalStyle` machinery in `Platforms/Web/` already
    handles this; we reuse it.

---

## Out of scope (this version)

- TLS support (`--cert`, `--key`).
- Multi-scene/multi-window.
- File system access from the browser.
- Authentication beyond per-launch token + cookie.
- `0.0.0.0` exposure with anything other than the warning banner.
- `mDNS`/`Bonjour` advertising.
- Asciicast recording (`--record`).
- Reverse-proxy / external-relay support.
- xterm.js / ANSI fallback mode.
- Windows support.
- Programmatic Puppeteer/Playwright headless renderer for screenshot
  generation. (The transport supports it; the renderer is a separate
  story.)
- Sharing a session between machines (only loopback + LAN with
  warning).
- Sub-millisecond delta protocol; we ship full-state JSON in v1.
- Browser-side audio capture/playback bridge for hypothetical
  TUI-emits-bell scenarios.
- Full WCAG 2.2 AA browser-side rendering; that's a follow-on tied to
  the [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) Web target work.
- ARIA-tree projection from the `semantics` phase; same — that's the
  follow-on accessibility wins, not a v1 item.

---

## Suggested phasing

(Sketch only — order is argued for, not committed to.)

1. **Phase 1 — Plumbing.** Stand up `Platforms/WebHost/` with a
   `WebHostRunner` that ignores all CLI args except `--web`, listens on
   a hardcoded loopback port, accepts a single WebSocket connection,
   and round-trips a hello/echo. Establish the package layout, the
   FlyingFox dependency, and the `WebHostServer` protocol. No browser
   bundle yet.

2. **Phase 2 — Surface bridge.** Wire
   `WebSocketSurfaceTransport` and `WebSocketInputAdapter` into a
   `HostedSceneSession`. Run a fixture scene end-to-end with a
   command-line WS client (e.g. `wscat`) feeding canned input and
   capturing surface frames. This validates the transport without
   requiring a browser.

3. **Phase 3 — Browser bundle.** Build the static bundle from
   `Platforms/Web/`, ship as Swift package resources, serve from
   `GET /`. Visit the URL in a browser, see the rendered TUI. No auto-
   open, no token, no banner yet — just "it works in a browser."

4. **Phase 4 — Lifecycle and CLI.** Add `WebHostMode.parse`, port
   collision handling, token generation, URL printing, banner,
   `--port`, `--host`, `--no-token`, `--open`. Cross-platform
   browser opener.

5. **Phase 5 — Security hardening.** Origin checks at WS upgrade,
   cookie session, `--allowed-origin` flag, `0.0.0.0` warning banner,
   token rotation policy.

6. **Phase 6 — Multi-viewer.** Driver/viewer model, per-tab
   identity, `take-control` UI hook in the bundle.

7. **Phase 7 — Tests + fixtures.** Snapshot tests for the URL banner,
   the bundle, the WS handshake, and end-to-end scene-running tests
   with a programmatic client.

8. **Phase 8 — `SwiftTUICLI` integration.** Weak hand-off so binaries
   that import both runners get `--web` from `SwiftTUIWebHost` and
   the default terminal launch from `SwiftTUICLI`.

9. **Phase 9 — Polish.** QR code (`--qr`), `--no-banner`,
   `--mirror-terminal`, `--exit-on-disconnect`. Docs update,
   `Examples/WebHostExample/` analogous to `Examples/WebExample/`.

10. **Phase 10 — Asciicast and headless.** `--record session.cast`,
    headless mode driving the transport without a server, snapshot
    tests at the surface level.

Each phase is independently shippable and has a clear demo:

- After Phase 3 the demo is "open the URL, see the TUI."
- After Phase 4 the demo is "run `myapp --web --open` and your browser
  pops with the TUI."
- After Phase 6 the demo is "open two tabs, watch both update."
- After Phase 10 the demo is "record an asciicast of your TUI from
  your terminal and email it as a bug report."

Phase 1–5 are v1 of the proposal. 6+ is v2.

---

## Anti-patterns this proposal commits us to avoiding

- **Binding to `0.0.0.0` by default.** GoTTY does this; we will not.
- **Default-no-auth.** Anyone can connect, no questions asked. Both
  GoTTY and ttyd require an opt-in flag for auth; we make
  authentication mandatory and require an opt-out flag instead.
- **Auto-opening the browser by default.** Annoying for SSH/CI/tmux
  users.
- **Filesystem access from the browser.** No `/api/files`,
  no `Bun.file`-shaped reads, nothing.
- **Embedding the HTTP server in `SwiftTUI`.** ADR-0008 already
  forbids this; we honor it explicitly.
- **Reinventing the wire format.** We reuse `web-surface`. Same
  fixtures, same encoder, same parser.
- **xterm.js as the default browser bundle.** Discards our structured
  surface protocol and forecloses ARIA/semantic rendering. Worth as a
  fallback mode much later, not as a default.
- **Loading bundle code from a CDN.** No network on first run, no
  third-party trust burden.
- **Self-signed certs in v1.** Cargo-cult security; either real
  certs (later) or no TLS.
- **A daemon process model in v1.** Adds install complexity for no
  v1 win.
- **A general-purpose ANSI terminal sharing tool.** This is a
  SwiftTUI-specific runner; it is not "ttyd written in Swift." If
  we want that, it's a different product.

---

## Sources

The full research archive is in this document. Primary sources by theme.

### Peer architectures (terminal-as-web-app / TUI-over-web)

- ttyd — [tsl0922/ttyd](https://github.com/tsl0922/ttyd) (the C
  implementation), [tsl0922.github.io/ttyd](https://tsl0922.github.io/ttyd/)
  (project page), [ttyd man page](https://manpages.ubuntu.com/manpages/jammy/man1/ttyd.1.html)
- GoTTY — [yudai/gotty](https://github.com/yudai/gotty) (original),
  [sorenisanerd/gotty](https://github.com/sorenisanerd/gotty) (maintained
  fork), [Tecmint walkthrough](https://www.tecmint.com/gotty-share-linux-terminal-in-web-browser/)
- tmate — [tmate.io](https://tmate.io/), [tmate paper (Viennot, 2014)](https://viennot.com/tmate.pdf),
  [linuxhandbook overview](https://linuxhandbook.com/tmate/)
- Textual `serve` — [Textualize/textual-serve](https://github.com/Textualize/textual-serve),
  [PyPI: textual-serve](https://pypi.org/project/textual-serve/),
  [Textual blog: Towards Textual Web Applications](https://textual.textualize.io/blog/2024/09/08/towards-textual-web-applications/)
- aider `--browser` — [Aider docs: Aider in your browser](https://aider.chat/docs/usage/browser.html),
  [DeepWiki: Streamlit Web GUI for Aider](https://deepwiki.com/Aider-AI/aider/5.2-streamlit-web-gui)
- Streamlit architecture — [Streamlit architecture docs](https://docs.streamlit.io/develop/concepts/architecture/architecture),
  [DeepWiki: Streamlit core architecture](https://deepwiki.com/streamlit/streamlit/3-core-architecture)
- asciinema — [asciinema.org](https://asciinema.org/),
  [asciinema/asciinema](https://github.com/asciinema/asciinema),
  [asciinema/asciinema-server](https://github.com/asciinema/asciinema-server),
  [asciinema/asciinema-player](https://github.com/asciinema/asciinema-player),
  [asciicast v3 announcement](https://blog.asciinema.org/post/three-point-o/)
- Jupyter notebook URL/token UX —
  [Jupyter notebook security docs](https://jupyter-notebook.readthedocs.io/en/5.6.0/security.html),
  [issue #1980: clearer token URL with --no-browser](https://github.com/jupyter/notebook/issues/1980),
  [issue #2254: token discussion](https://github.com/jupyter/notebook/issues/2254)
- VS Code `code tunnel` — [code.visualstudio.com](https://code.visualstudio.com/)

### Browser-side terminal emulators

- xterm.js — [xtermjs.org](https://xtermjs.org/),
  [xtermjs/xterm.js](https://github.com/xtermjs/xterm.js/),
  [`@xterm/addon-attach` source](https://github.com/xtermjs/xterm.js/tree/master/addons/addon-attach),
  [npm: xterm-addon-attach](https://www.npmjs.com/package/xterm-addon-attach),
  [Presidio: building a browser-based terminal](https://www.presidio.com/technical-blog/building-a-browser-based-terminal-using-docker-and-xtermjs/)

### Swift HTTP/WS server libraries

- swift-nio — [apple/swift-nio](https://github.com/apple/swift-nio),
  [swift-nio HTTP1Server example](https://github.com/apple/swift-nio/tree/main/Sources/NIOHTTP1Server),
  [Swift.org: Oblivious HTTP support in Swift](https://www.swift.org/blog/introducing-swift-nio-oblivious-http/)
- Hummingbird — [hummingbird-project/hummingbird](https://github.com/hummingbird-project/hummingbird),
  [hummingbird.codes](https://hummingbird.codes/),
  [Hummingbird 2 announcement](https://hummingbird.codes/news/hummingbird-2/),
  [What's new in Hummingbird 2](https://swiftonserver.com/whats-new-in-hummingbird-2/),
  [Using WebSockets in Hummingbird](https://swiftonserver.com/websockets-tutorial-using-swift-and-hummingbird/),
  [hummingbird-project/swift-websocket](https://github.com/hummingbird-project/swift-websocket)
- FlyingFox — [swhitty/FlyingFox](https://github.com/swhitty/FlyingFox),
  [FlyingFox README](https://github.com/swhitty/FlyingFox/blob/main/README.md),
  [Swift Package Index: FlyingFox](https://swiftpackageindex.com/swhitty/FlyingFox)

### Lifecycle / URL printing / discovery

- [Pinggy: sharing Jupyter notebooks from localhost](https://pinggy.io/blog/share_jupyter_notebook_from_localhost/)
- [DigitalOcean: connect to Jupyter Notebook on a remote server](https://www.digitalocean.com/community/tutorials/how-to-install-run-connect-to-jupyter-notebook-on-remote-server)

### Cross-platform browser opening from Swift

- [oliveroneill/WebBrowser — small Swift library for opening URLs in default browser](https://github.com/oliveroneill/WebBrowser)
- [Bekk Christmas: Cross-platform CLIs with Swift](https://www.bekk.christmas/post/2021/17/cross-platform-clis-with-swift)
- [sindresorhus/open — JS reference for the same surface](https://github.com/sindresorhus/open)

### Standards / RFCs

- WebSocket Protocol — [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455)
- WebSocket per-message deflate — [RFC 7692](https://www.rfc-editor.org/rfc/rfc7692)
- DNS rebinding background — [Wikipedia: DNS rebinding](https://en.wikipedia.org/wiki/DNS_rebinding)

### Internal references

- [`AGENTS.md`](../../AGENTS.md) — repository constraints, especially
  Foundation-free libraries and the `no-foundation-in-library-products`
  prek hook.
- [`docs/proposals/ACCESSIBILITY.md`](./ACCESSIBILITY.md) — sister
  proposal; the accessibility motivation for this work.
- [`docs/decisions/0007-host-packages-are-peers.md`](../decisions/0007-host-packages-are-peers.md) — peer-package layout convention.
- [`docs/decisions/0008-swifttui-library-only-runners-own-main.md`](../decisions/0008-swifttui-library-only-runners-own-main.md) — runners-own-`main()` decision.
- [`docs/decisions/0010-crash-guard-in-cli-runner-not-swifttui.md`](../decisions/0010-crash-guard-in-cli-runner-not-swifttui.md) — analogous "this lives in the runner, not the library" precedent.
- [`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift) — the wire format encoder/parser this proposal reuses.
- [`Platforms/Web/`](../../Platforms/Web/) — the browser bundle this proposal embeds.
- [`Platforms/CLI/Sources/SwiftTUICLI/`](../../Platforms/CLI/Sources/SwiftTUICLI/) — the runner-shape blueprint.
- [`Examples/WebExample/`](../../Examples/WebExample/) — the existing WASM-targeted example.

---

## Changelog

- 2026-05-04: Draft created from research findings on the
  `accessibility-investigation` branch. Proposes a new
  `Platforms/WebHost/` runner peer that reuses the existing
  `WASISurfaceBridge` wire format and the `Platforms/Web/` browser
  bundle to render a SwiftTUI binary's output in a localhost browser,
  motivated by the accessibility proposal's "the web is the strongest
  a11y story" finding plus pretty-rendering, persistent-session,
  pair-programming, and headless-CI follow-ons.
- 2026-05-04: Substrate-audit corrections applied. See
  [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md). Specifically: the
  existing `WebSurfaceFrameEncoder` is raster-only and does not
  carry semantic data; the wire-format extension required for ARIA
  rendering is now spelled out as a v1→v2 envelope bump with an
  added `accessibilityTree` field, and is **promoted** from "future
  third format" to "required for the embedded host's accessibility
  headline." A separate performance correction notes that the
  existing encoder emits a full surface per commit; a diff-based
  encoder is worth tracking as an explicit performance phase.
