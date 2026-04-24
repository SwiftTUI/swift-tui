# Layouts Example

56 focused layout examples of the public `TerminalUI` surface,
reachable from a full-screen push/pop picker. Each layout is pinned
with a smoke test; `.behaviour`-tagged layouts add targeted
behaviour tests that pin the specific measure/place rule the layout
is meant to demonstrate.

Design and taxonomy live in
[../../docs/plans/2026-04-24-001-layouts-example-plan.md](../../docs/plans/2026-04-24-001-layouts-example-plan.md).

## Run

```bash
cd Examples/layouts
swift run layouts-demo
```

The app launches directly into the picker. `↑↓` move, `⏎` opens a
layout, `esc` pops back, `⌃C` quits.

## Test

```bash
cd Examples/layouts
swift test
```
