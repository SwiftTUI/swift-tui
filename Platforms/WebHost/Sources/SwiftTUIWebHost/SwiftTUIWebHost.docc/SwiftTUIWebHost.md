# ``SwiftTUIWebHost``

Serve a native SwiftTUI app through a localhost browser host.

## Overview

`SwiftTUIWebHost` is the opt-in local-browser host product. It links the
embedded HTTP/WebSocket server and browser resources needed to render a native
SwiftTUI process in a browser tab.

Terminal-only apps should import `SwiftTUI` instead. Apps that intentionally
support both normal terminal launch and `--web` launch should use
`SwiftTUIWebHostCLI`.

## Topics

### Browser Hosting

- ``WebHostRunner``
- ``WebHostRunnerError``
- ``WebHostConfig``
