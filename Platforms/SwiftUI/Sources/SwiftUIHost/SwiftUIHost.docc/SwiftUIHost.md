# ``SwiftUIHost``

Embed SwiftTUI scenes inside native SwiftUI apps.

## Overview

`SwiftUIHost` retains SwiftTUI scenes inside a native SwiftUI lifecycle. It owns
the native surface bridge, scene switching chrome, style mapping, clipboard
integration, accessibility overlay, and platform announcement bridge.

Use this product from Apple-platform apps that want SwiftTUI content inside an
existing SwiftUI app shell.

## Topics

### Native Host Views

- ``SwiftUIHostAppView``

### Host State

- ``SwiftUIHostAppState``
- ``SwiftUIHostSceneDescriptor``

### Styling

- ``SwiftUIHostTerminalStyle``
- ``SwiftUIHostTerminalPalette``
- ``SwiftUIHostCursorStyle``
