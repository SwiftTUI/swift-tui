# WebHostExample

Smallest localhost-browser host example.

This package imports `SwiftTUIWebHostCLI`, not bare `SwiftTUI`, so the same app
can run as a normal terminal program or launch through the opt-in WebHost
browser runner when `--web` is present.

## Demonstrates

- The combined terminal/WebHost CLI product.
- A single `WindowGroup` with an explicit scene identifier.
- Keeping WebHost support as an app-level opt-in instead of a default dependency
  for every SwiftTUI executable.

## Run

Run in the terminal:

```bash
swiftly run swift run --package-path Examples/WebHostExample WebHostExample
```

Run through the localhost browser host:

```bash
swiftly run swift run --package-path Examples/WebHostExample WebHostExample --web
```

The normal WebHost flags are available here, including `--port`, `--bind`,
`--open`, and `--scene`.

## Test

```bash
swiftly run swift test --package-path Examples/WebHostExample
```

The test pins the intended package boundary: the example imports
`SwiftTUIWebHostCLI` and does not directly wire the lower-level WebHost runner.
