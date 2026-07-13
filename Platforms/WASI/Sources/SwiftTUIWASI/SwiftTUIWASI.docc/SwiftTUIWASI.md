# ``SwiftTUIWASI``

Run SwiftTUI apps as WASI executables for browser deployment.

## Overview

`SwiftTUIWASI` owns WASI app launch and manifest mode. Browser deployments use
this product in the Swift app, then package the resulting WASI build with the
`@swifttui/web` and `@swifttui/build` workspaces from the `swift-tui-web`
repository.

The shared web-surface transport target remains package-only plumbing; external
apps should depend on `SwiftTUIWASI`, not `SwiftTUIWASISurfaceBridge`.

## Topics

### WASI Launch

- ``WASIRunner``
- ``WASIRunnerError``
