# WebHostExample

Smallest localhost-browser host example.

This package imports `SwiftTUI`, so the same app can run as a normal terminal
program or launch through the included WebHost browser runner when `--web` is
present.

## Demonstrates

- The `SwiftTUI` convenience product's combined terminal/WebHost launcher.
- A single `WindowGroup` with an explicit scene identifier.
- The default `--web` path without importing lower-level WebHost products.

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

The test pins the intended package boundary: the example imports `SwiftTUI` and
does not directly wire the lower-level WebHost runner.
