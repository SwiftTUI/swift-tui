# ``SwiftTUIWebHostCLI``

Launch one SwiftTUI executable in either terminal or localhost-browser mode.

## Overview

`SwiftTUIWebHostCLI` composes the terminal runner with the WebHost runner. Use
it when one binary must run in the terminal by default. It switches to browser
hosting when the parsed application configuration requests web mode.

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
