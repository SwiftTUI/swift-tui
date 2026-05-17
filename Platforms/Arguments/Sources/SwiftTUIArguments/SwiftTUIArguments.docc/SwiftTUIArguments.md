# ``SwiftTUIArguments``

Parse SwiftTUI's standard runtime flags alongside an app's own command-line
surface.

## Overview

Use `SwiftTUIArguments` when a terminal app needs custom flags but still wants
the standard SwiftTUI runtime options for color, accessibility, rendering mode,
scene selection, and WebHost launch configuration.

Most apps get this module through `SwiftTUI` or `SwiftTUIWebHostCLI`. Import it
directly when composing a custom runner around `SwiftTUIRuntime` and
`SwiftTUICLI`.

## Topics

### App Commands

- ``SwiftTUICommand``
- ``SwiftTUIApp``

### Runtime Options

- ``SwiftTUIOptions``
- ``CompletionsCommand``
