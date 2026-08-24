# ``SwiftTUIWASI``

Run SwiftTUI apps as WASI executables for browser deployment.

## Overview

`SwiftTUIWASI` owns WASI app launch and manifest mode. Browser deployments use
this product in the Swift app, then package the resulting WASI build with the
`@swifttui/web` and `@swifttui/build` workspaces from the `swift-tui-web`
repository.

The shared web-surface transport target is package-only infrastructure.
External apps must depend on `SwiftTUIWASI`, not
`SwiftTUIWASISurfaceBridge`.

## Topics

### Deployment

- <doc:Deploying-To-The-Browser>

### WASI Launch

- ``WASIRunner``
- ``WASIRunnerError``
