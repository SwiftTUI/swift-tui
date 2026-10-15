# ``SwiftTUIWebHost``

Serve a native SwiftTUI app through a localhost browser host.

## Overview

`SwiftTUIWebHost` is the local-browser host product. It provides the embedded
HTTP/WebSocket server and browser resources. These components render a native
SwiftTUI process in a browser tab.

The packaged browser resources contain only the Canvas renderer and semantic
accessibility controls. The DOM renderer is experimental and requires an
app-owned browser bundle. Set `RuntimeConfiguration.browserAssetsPath` when
calling `WebHostRunner`, or use `RuntimeConfiguration.builder().browserAssets(at:)`.
The same configuration applies to the combined launcher's terminal companion;
see [Browser Companion](https://swifttui.sh/docs/documentation/swifttuiwebhostcli/browser-companion).

Most apps get this product through `SwiftTUI`. That product includes the
combined terminal and WebHost CLI runner by default. For a custom host-only
launcher, import `SwiftTUIWebHost` directly. For a narrower combined terminal
and WebHost graph, import `SwiftTUIWebHostCLI` directly.

## Topics

### Browser Hosting

- ``WebHostRunner``
- ``WebHostRunnerError``
- ``WebHostConfig``
