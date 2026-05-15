# `@swifttui/build`

Build-time package for SwiftTUI browser deployment.

This package owns manifest generation, Swift WASI builds, browser
`WebAssembly.compile` validation, and wasm packaging. It intentionally sits
outside `@swifttui/web` so browser runtime imports do not pull in Swift process
spawning, Node filesystem APIs, or wasm packaging helpers.

## API

```ts
import { buildSwiftTUIWebApp } from "@swifttui/build";

await buildSwiftTUIWebApp({
  packagePath: ".",
  product: "MyApp",
  outputDirectory: "dist",
});
```

Toolchain defaults match the repo:

- Swift command: `swiftly run swift` when `swiftly` is on `PATH`, otherwise
  `swift`
- SDK: `swift-6.3.1-RELEASE_wasm`
- Release Swift flags:
  `-Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass`
- Initial memory: `536870912`
- Max memory: `4294967296`
- Stack size: `1048576`

Callers can override `swiftCommand`, `swiftSDK`, `configuration`,
`initialMemory`, `maxMemory`, `stackSize`, `extraSwiftcFlags`,
`extraLinkerFlags`, and `extraSwiftBuildArgs`.

## Scripts

- `bun test`
- `bun run build:manifest -- --app <AppExecutable>`
- `bun run build:wasm -- --app <AppExecutable>`
- `bun run build -- --app <AppExecutable>`
