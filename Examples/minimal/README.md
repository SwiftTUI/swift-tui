# minimal

Smallest checked-in rendering example.

Unlike the app examples, this one does not use `App`, `Scene`, `RunLoop`,
`TerminalRunner`, or SwiftTUI argument parsing. It renders a single view through
`DefaultRenderer`, converts the raster surface to terminal text with
`TerminalSurfaceRenderer`, and prints the result.

## Demonstrates

- Snapshot rendering without an interactive runtime.
- The lowest public rendering layer used by higher-level runners.
- Explicit terminal capability selection for rendered output.

## Run

```bash
swiftly run swift run --package-path Examples/minimal minimal
```

This example has no test target. Use it as a compact reference for one-shot
rendering and documentation snippets.
