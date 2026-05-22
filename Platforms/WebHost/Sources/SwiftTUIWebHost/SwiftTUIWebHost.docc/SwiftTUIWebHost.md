# ``SwiftTUIWebHost``

Serve a native SwiftTUI app through a localhost browser host.

## Overview

`SwiftTUIWebHost` is the local-browser host product. It links the embedded
HTTP/WebSocket server and browser resources needed to render a native SwiftTUI
process in a browser tab.

Most apps get this through `SwiftTUI`, which includes the combined terminal and
WebHost CLI runner by default. Import `SwiftTUIWebHost` directly for a custom
host-only launcher, or `SwiftTUIWebHostCLI` directly for a narrower combined
terminal/WebHost graph.

## Topics

### Browser Hosting

- ``WebHostRunner``
- ``WebHostRunnerError``
- ``WebHostConfig``
