# argparse

Focused command-line integration example for `SwiftTUICommand`.

The app shows how a SwiftTUI `App` can own consumer-specific flags while also
exposing the framework's standard runtime options through `SwiftTUIOptions`.
It is intentionally small so the argument-parsing shape is easy to copy.

## Demonstrates

- `App` plus `SwiftTUICommand` in the same type.
- Consumer flags such as `--widgets` and `--show-ids`.
- Standard SwiftTUI flags such as `--no-color`, `--ascii`, `--reduce-motion`,
  `--debug`, `--json`, and accessibility options.
- The built-in completions subcommand from Swift Argument Parser.

## Run

```bash
swiftly run swift run --package-path Examples/argparse argparse-demo
swiftly run swift run --package-path Examples/argparse argparse-demo --widgets 8 --show-ids
swiftly run swift run --package-path Examples/argparse argparse-demo --help
```

This example has no test target; it is covered by the root command-surface tests
and by the source-level shape documented in the root README.
