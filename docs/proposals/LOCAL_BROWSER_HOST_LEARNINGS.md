# Local Browser Host Learnings

**Status:** Investigation draft. This is not an approved implementation plan.
It captures external-consumer and open-source-pattern learnings for the
native-binary-to-localhost-browser story around `SwiftTUIWebHost` and
`SwiftTUIWebHostCLI`.

**Owner:** unassigned.

**Related docs:** [EMBEDDED_WEB_HOST.md](EMBEDDED_WEB_HOST.md),
[HOST_PACKAGES.md](../HOST_PACKAGES.md),
[TERMINOLOGY.md](../TERMINOLOGY.md),
[PUBLIC_PRODUCTS_DRAFT.md](PUBLIC_PRODUCTS_DRAFT.md),
[PLATFORMS_WEB_CONSUMABLE_PACKAGES.md](PLATFORMS_WEB_CONSUMABLE_PACKAGES.md).

## Scope

This document is about the local-browser shape:

```text
native SwiftTUI binary -> localhost HTTP/WebSocket server -> browser renderer
```

It is not about static web deployment, where SwiftTUI app code is compiled to
WASI and shipped to a browser. That separate track is covered in
[PLATFORMS_WEB_CONSUMABLE_PACKAGES.md](PLATFORMS_WEB_CONSUMABLE_PACKAGES.md).

The local-browser user has a binary on their machine and wants a browser view
for accessibility, richer rendering, local demos, screen sharing, or headless
operation. The binary owns execution. The browser is a presentation client.

## Current SwiftTUI Shape

The current repo already has a viable v1:

- `SwiftTUIWebHost` is an opt-in root SwiftPM product for web-only local
  browser launch.
- `SwiftTUIWebHostCLI` is the import replacement for binaries that should run
  normally in the terminal but route `--web` through the WebHost runner.
- Terminal-only apps that import `SwiftTUI` do not link FlyingFox, WebSocket
  server code, or browser resources.
- The native WebHost serves a bundled browser runtime from SwiftPM resources
  and drives it with the shared `web-surface` v2 protocol over WebSocket.
- The v1 runner supports exactly one authored scene.

External feasibility was checked with a throwaway package outside this repo:
an app depending on the local `swift-tui` package and importing
`SwiftTUIWebHostCLI` built successfully with SwiftPM. That means the native
local-browser surface is not repo-only. The remaining question is product
polish, not basic external buildability.

## What The Local-Browser Surface Is Good At

The current shape is strongest for:

- a Swift-only terminal app that wants an optional browser view via `--web`
- accessibility workarounds where browser ARIA is materially better than a
  terminal character grid
- demos where the app should keep native process access but render in a browser
- local workflows where the URL can be copied, opened, or shared on the same
  machine
- headless or CI-adjacent rendering experiments where a browser client can
  inspect the same semantic frame stream

It is weaker for:

- public static websites, because a server process is still required
- multi-scene browser apps, because v1 serves one scene
- multi-viewer sessions, because connection ownership and input control are
  not yet a product contract
- remote hosting, TLS, auth beyond launch tokens, reverse proxies, and server
  lifecycle management

## Learnings From Comparable Projects

### Textual Serve

[`textual-serve`](https://github.com/Textualize/textual-serve) is the closest
architecture match. It keeps the TUI framework responsible for the browser
bridge rather than exposing a raw terminal emulator. The important lesson is
not its exact Python API, but the product boundary:

- small local server entrypoint
- browser client speaks a framework-specific protocol
- app authors do not redesign their app for the browser
- local browser serving is a first-class framework mode, not a demo-only
  wrapper

SwiftTUI is already aligned with this direction. `SwiftTUIWebHostCLI` is the
compile-time opt-in equivalent of "this binary can serve itself to a browser."
The gap is mostly v1 polish and external docs.

### Jupyter Server

Jupyter is the reference for URL-and-token localhost UX:

- print a copy-pasteable local URL
- include a per-launch token
- convert the token to a browser cookie after first successful request
- make the default bind local-only
- require explicit user action for wider binds

SwiftTUI already follows the important pieces: local bind by default, tokenized
URL, cookie handoff, and `--open` as opt-in browser launch. The next learning is
operational polish: discoverability, clearer warnings, and possible
`server list`-style support if persistent sessions ever become a goal.

### ttyd And GoTTY

[`ttyd`](https://github.com/tsl0922/ttyd) and
[`GoTTY`](https://github.com/yudai/gotty) represent the terminal-as-web-app
model. They run a command under a PTY and expose terminal bytes through a
browser terminal, commonly via xterm.js.

This is useful for shell sharing, but it is not SwiftTUI's best local-browser
model. SwiftTUI has a semantic render pipeline, structured accessibility tree,
focus state, pointer records, image attachments, and host-owned style payloads.
Flattening that to ANSI and then reinterpreting ANSI in a browser would lose
the biggest reason to have a framework-owned web host.

The lesson is to keep a terminal-emulator fallback as a possible future
escape hatch, not as the main local-browser architecture.

### xterm.js

[`xterm.js`](https://github.com/xtermjs/xterm.js) is the packaging benchmark
for browser terminal components:

- public npm package
- typed browser API
- CSS asset contract
- add-on ecosystem
- clear separation between frontend terminal rendering and backend process
  ownership

SwiftTUI's local browser host should not become an xterm.js clone. But the
browser package serving the local WebHost should eventually have similarly
clean packaging: stable JS exports, generated types, CSS or style entrypoints,
and no accidental dependency on repo-local build scripts.

### Carton

[`carton`](https://github.com/swiftwasm/carton) is mainly relevant as a Swift
developer-experience precedent. Its historical `dev` and `bundle` commands
made SwiftWasm web work feel like a single SwiftPM-managed workflow.

That matters even for local-browser work: Swift developers respond well to
`swift run tool dev` or `swift package plugin ...` flows. If SwiftTUI adds more
local-browser lifecycle commands, they should be reachable from SwiftPM and not
only from the repo's Bun workspace.

Carton is not the current SwiftWasm endpoint. JavaScriptKit's plugin and
package-to-JS direction is the fresher pattern for static browser deployment.
But Carton remains a useful ergonomics reference.

## Design Principles For SwiftTUI

1. Keep local-browser serving separate from static web deployment.

   Local-browser serving runs a native Swift process and presents it in a
   browser. Static deployment ships a WASI module and a browser package. They
   share protocol and renderer code, but they should not share one confused
   command surface.

2. Keep WebHost compile-time opt-in.

   A normal `import SwiftTUI` app should not link a server. The opt-in
   boundary is valuable and already tested.

3. Prefer framework-native protocol over terminal emulation.

   `web-surface` preserves semantics, accessibility, structured input,
   style, images, and runtime issues. ANSI-in-browser should be fallback or
   compatibility work, not the default.

4. Treat runner and host wording as public API.

   `SwiftTUIWebHostCLI` is a runner composition. The browser shell is a host.
   Docs should use those terms consistently because external users will copy
   the architecture.

5. Keep the trivial path trivial.

   The ideal local-browser adoption path remains:

   ```swift
   import SwiftTUIWebHostCLI

   @main
   struct MyApp: App {
     var body: some Scene { ... }
   }
   ```

   Then:

   ```bash
   my-app --web
   ```

## Options

### Option A: Polish The Existing V1

Document the external consumer flow, keep single-scene behavior, and add one
outside-repo fixture or example that proves:

- `SwiftTUIWebHostCLI` builds from a separate SwiftPM package
- `--web` starts the server
- terminal-only imports still reject `--web`
- the copied browser resource bundle is present in a release build

This is the lowest-risk next step.

### Option B: Add Local-Browser Lifecycle Features

Keep the current product graph but add lifecycle polish:

- `--port 0` or a documented ephemeral-port mode
- QR code output for phone/tablet testing
- clearer external-bind warning text
- structured machine-readable startup output
- optional server discovery or "list running WebHost sessions"

This should wait until the v1 external docs are clean. Otherwise lifecycle
features will make an unclear product surface larger.

### Option C: Multi-Scene Browser Host

Lift the v1 single-scene restriction and let the browser host manage scene
selection, one retained session per scene, and style propagation across scenes.

This aligns with the WASI/browser deployment model, but it is more than polish:
input ownership, resource use, session retention, and UI chrome become product
contracts.

### Option D: Remote Or Shared Sessions

Add multi-viewer support, driver/viewer control transfer, TLS or reverse proxy
support, and persistent server lifecycle.

This is strategically plausible, but it changes the threat model and should be
tracked separately from the local-only accessibility/demo story.

## Open Questions

- Should `SwiftTUIWebHost` remain single-scene until the browser package split
  is done?
- Should local-browser startup expose a machine-readable mode for editor
  integrations and tests?
- Is QR-code output valuable enough to add before multi-scene support?
- Should `--open` stay opt-in permanently, or become configurable by an app
  author policy?
- Do we want a server-list/discovery concept, or is every WebHost process
  intentionally short-lived?
- Should WebHost expose any public configuration beyond bind, port, and
  browser opening before remote sharing is in scope?

## Suggested Investigation Tasks

- Add an external fixture package in `Tests` or `Examples` that mirrors a real
  consumer's `Package.swift` rather than relying only on in-repo path examples.
- Run a timed `--web --port 0` smoke, if `--port 0` is supported or once it is
  intentionally specified.
- Audit the WebHost banner and terminal-only `--web` rejection text against the
  final external docs.
- Decide whether local-browser multi-scene should reuse the static web host's
  scene picker model or remain intentionally simpler.

## Non-Goals For This Investigation Draft

- No implementation is approved by this document.
- No package renames are proposed here.
- No static web deployment changes are proposed here.
- No remote-sharing security model is approved here.
