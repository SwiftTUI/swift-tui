# ``SwiftTUIWebHost``

Serve a native SwiftTUI app through a localhost browser host.

## Overview

`SwiftTUIWebHost` is the local-browser host product. It provides the embedded
HTTP/WebSocket server and browser resources. These components render a native
SwiftTUI process in a browser tab.

Most apps get this product through `SwiftTUI`. That product includes the
combined terminal and WebHost CLI runner by default. For a custom host-only
launcher, import `SwiftTUIWebHost` directly. For a narrower combined terminal
and WebHost graph, import `SwiftTUIWebHostCLI` directly.

## Topics

### Browser Hosting

- ``WebHostRunner``
- ``WebHostRunnerError``
- ``WebHostConfig``
