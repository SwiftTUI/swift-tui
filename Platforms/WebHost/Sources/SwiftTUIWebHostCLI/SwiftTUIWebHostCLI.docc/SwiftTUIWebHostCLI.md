# ``SwiftTUIWebHostCLI``

Launch one SwiftTUI executable in either terminal or localhost-browser mode.

## Overview

`SwiftTUIWebHostCLI` composes the terminal runner with the WebHost runner. Use
it when one binary must run in the terminal by default. It switches to browser
hosting when the parsed application configuration requests web mode.

Most apps get this through the `SwiftTUI` convenience product. Import
`SwiftTUIWebHostCLI` directly when you want the combined launcher without
`SwiftTUI`'s animated-image convenience surface.

## Topics

### Combined Launch

- ``WebHostCLIRunner``
