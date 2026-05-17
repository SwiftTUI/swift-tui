# ``SwiftTUIWebHostCLI``

Launch one SwiftTUI executable in either terminal or localhost-browser mode.

## Overview

`SwiftTUIWebHostCLI` composes the terminal runner with the WebHost runner. Use
it when one binary should run in the terminal by default but switch to browser
hosting when the app's parsed configuration requests web mode.

Importing this product is a compile-time choice; terminal-only apps should keep
using `SwiftTUI`.

## Topics

### Combined Launch

- ``WebHostCLIRunner``
