# ``SwiftTUIWebHostCLI``

Launch one SwiftTUI executable in either terminal or localhost-browser mode.

## Overview

`SwiftTUIWebHostCLI` composes the terminal runner with the WebHost runner. Use
it when one binary should run in the terminal by default but switch to browser
hosting when the app's parsed configuration requests web mode.

Most apps get this through the `SwiftTUI` convenience product. Import
`SwiftTUIWebHostCLI` directly when you want the combined launcher without
`SwiftTUI`'s animated-image convenience surface.

## Topics

### Combined Launch

- ``WebHostCLIRunner``
