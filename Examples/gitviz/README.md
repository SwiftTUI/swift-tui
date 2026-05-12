# gitviz

A non-interactive CLI example app that visualizes a git repository using
`SwiftTUICharts`. Every chart primitive in the module is exercised by at
least one subcommand.

## Run

```bash
cd Examples/gitviz
swiftly run swift run gitviz                  # index of subcommands
swiftly run swift run gitviz info             # repo summary
swiftly run swift run gitviz activity         # GitHub-style calendar heatmap
swiftly run swift run gitviz deltas           # insertions / deletions line chart
swiftly run swift run gitviz dashboard        # everything back-to-back
```

All subcommands accept `--path <repo>` to point at a different working tree
and inherit the framework's `--no-color`, `--ascii`, `--reduce-motion`,
`--plain` flags from `SwiftTUIOptions`.

## Subcommand roster

| Subcommand | Chart(s) |
|---|---|
| `info` | `Meter` + `ProgressView` + `Timeline` |
| `activity` | `CalendarHeatmap` |
| `cadence` | `HeatStrip` |
| `tempo` | `Sparkline` × top-N authors |
| `deltas` | `LineChart` (2 series, `.line`) |
| `loc` | `LineChart` (1 series, `.area`) |
| `volatility` | `BarChart` |
| `kinds` | `ColumnChart` |
| `kinds-share` | `StackedBarChart` |
| `pulse` | `BulletChart` |
| `recent-vs-all` | `ComparisonChart` |
| `health` | `ThresholdGauge` |
| `concentration` | `Meter` + `StackedBarChart` |
| `releases` | `Timeline` |
| `dag` | plain `Text` rows (pre-laid-out by `GraphLayout`) |
| `dashboard` | everything above |

See `docs/proposals/GITVIZ_EXAMPLE.md` and
`docs/proposals/CALENDAR_HEATMAP_AND_LINE_CHART.md` for the full design
discussion.
