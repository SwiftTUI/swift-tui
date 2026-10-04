# ``SwiftTUIWebHostCLI``

Launch one SwiftTUI executable with a terminal and browser companion, or in browser-only mode.

## Overview

`SwiftTUIWebHostCLI` composes the terminal runner with the WebHost runner. Use
it when one binary runs in the terminal with a default loopback browser companion.
It switches to browser-only hosting when the configuration requests `--web`.
See <doc:Browser-Companion> for discovery, opt-out, and SSH forwarding.

Most apps get this through the `SwiftTUI` convenience product. Import
`SwiftTUIWebHostCLI` directly when you want the combined launcher without
`SwiftTUI`'s animated-image convenience surface.

For a custom `main`, call ``WebHostCLIRunner`` to install the web backend and
launch the app. The portable `SwiftTUILauncher` routes to an already-installed
backend; replacing this facade with that name alone does not install web
support. Both entry points remain supported.

## Topics

### Combined Launch

- ``WebHostCLIRunner``
