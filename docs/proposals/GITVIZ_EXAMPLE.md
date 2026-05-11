# gitviz Example

A non-interactive CLI example app that visualizes information about a
git repository, exercising every chart primitive in `SwiftTUICharts`
including the `CalendarHeatmap` and `LineChart` introduced in
[CALENDAR_HEATMAP_AND_LINE_CHART.md](CALENDAR_HEATMAP_AND_LINE_CHART.md).

The example is structured as an `swift-argument-parser` command tree
of one-shot subcommands. Each subcommand fetches data from the local
git repository, runs it through a small adapter into a chart-entry
type, builds a `SwiftTUICharts` view, and renders that view to stdout
via a new `RenderOnce` helper added to `SwiftTUICLI`. The default
(no-args) invocation prints a labeled index of available subcommands.

The example doubles as a chart cookbook: every chart type in the
module is exercised by at least one subcommand, and the data-to-chart
adapters live in their own files so they can be read, tested, and
copied independently of the CLI plumbing.

## Render-once helper (small public addition to `SwiftTUICLI`)

The existing `SwiftTUICLI` runtime is built for full-screen interactive
scenes (alt-screen, signal handlers, runloop). For non-interactive
examples we add a narrowly scoped helper that renders a view tree
once, emits the result to stdout as ANSI-decorated text, and returns.

```swift
public enum RenderOnce {
  /// Resolve / measure / place / draw / raster the view tree once at the
  /// requested width (defaulting to the current terminal width, then 80),
  /// emit the resulting cell buffer as ANSI-decorated text to stdout, and
  /// return. Does not grab the alternate screen, does not install signal
  /// handlers, does not enter a runloop. Honors `options` for color/style.
  public static func print(
    _ view: some View,
    width: Int? = nil,
    options: SwiftTUIOptions = .init()
  )

  /// Same as `print` but returns the string instead of writing to stdout.
  /// Used by tests.
  public static func render(
    _ view: some View,
    width: Int? = nil,
    options: SwiftTUIOptions = .init()
  ) -> String
}
```

Internally it calls the existing `Renderer.renderFrame(root:context:)`
pipeline from `SwiftTUICore` with a one-shot `FrameContext`, then
walks the resulting `RasterSurface` row by row emitting cells plus
SGR escapes. Style resolution honors `SwiftTUIOptions` (notably the
existing `--no-color` flag) and the `NO_COLOR` / `CLICOLOR_FORCE`
environment variables / `isatty(STDOUT_FILENO)` (see "TTY and color
policy" below).

Terminal scrollback is preserved — output streams out naturally and
survives piping to `less`, `tee`, or files.

`SwiftTUICLI` is the right home for this: it already owns ANSI
emission, terminal-width detection, and color policy for the
interactive path. Future non-interactive examples reuse the same
entry point.

## Git data layer

A small `Sendable` struct that shells out to `git` via Foundation
`Process`. All methods are `throws` and synchronous — this is a CLI
script, not a long-running app.

```swift
struct GitRepo: Sendable {
  let workingDirectory: URL

  init(workingDirectory: URL = .currentDirectory()) throws  // verifies .git exists

  func info() throws -> RepoInfo                                  // commits, contributors, first/last date, current branch
  func commits(since: Date? = nil, until: Date? = nil,
               max: Int? = nil) throws -> [Commit]
  func shortlog() throws -> [AuthorTally]                         // git shortlog -s -n -e
  func tags() throws -> [Tag]
  func dailyCommitCounts(in: ClosedRange<Date>) throws -> [DateValue]
  func numstat(since: Date? = nil) throws -> [CommitDelta]        // [(commit, ins, del, files)]
  func fileChangeCounts() throws -> [FileTally]                   // for volatility ranking
  func revList(reachableFrom ref: String = "HEAD",
               max: Int = 200,
               graph: Bool = false) throws -> [GraphCommit]       // for DAG view
}

struct RepoInfo: Sendable { /* path, branch, commitCount, contributorCount,
                              firstCommitDate, lastCommitDate, tagCount */ }
struct Commit: Sendable { /* sha, date, author, subject, parents,
                            insertions, deletions */ }
struct CommitDelta: Sendable { /* sha, date, insertions, deletions, filesChanged */ }
struct AuthorTally: Sendable { /* name, email, commits */ }
struct FileTally: Sendable { /* path, changeCount */ }
struct Tag: Sendable { /* name, sha, date, isAnnotated */ }
struct GraphCommit: Sendable { /* sha, parents, subject, lane (Int), glyphRow (String) */ }
```

Underlying `git` invocations are deliberately boring:

- `git log --pretty=format:... --numstat`
- `git shortlog -s -n -e`
- `git for-each-ref refs/tags --format=...`
- `git rev-list --topo-order --parents <ref>`

No flags that exist only on recent git. Targets git ≥ 2.30
(Ubuntu 22.04 baseline).

`CommitKind` inference — `feat` / `fix` / `hotfix` / `refactor` /
`revert` / `docs` / `test` / `chore` / `perf` / `ci` / `other` — is a
pure function over `Commit.subject`: Conventional-Commits prefix
first, then a keyword regex fallback (`hotfix`, `revert`, `bump`).
Lives in `CommitKind.swift` with unit tests.

### DAG layout is offline

`GraphCommit.lane` and `glyphRow` are computed at parse time in
`GraphLayout.swift`, not at render time. A topological DAG layout
(which lanes diverge, which converge, where merges land) is a classic
offline computation — doing it in the data layer keeps the chart-level
code free of layout state and lets a simple `ForEach(rows) { Text(...) }`
produce the output. This is the same separation `git log --graph`
enforces internally.

## Subcommand roster

Every existing chart type in `SwiftTUICharts` is exercised by at least
one subcommand, and the two new primitives (`CalendarHeatmap`,
`LineChart`) anchor the two motivating screenshots.

| Subcommand | What it shows | Primary chart(s) | Notes |
|---|---|---|---|
| `index` (default) | Labeled list of subcommands grouped into Basics / Activity / Code / People / Diagnostics | plain `Text` + `VStack` + `Legend` | Stays tiny; one screen, no charts. |
| `info` | Branch, commit/contributor counts, first/last commit date, tag count, scanned-share progress | `Meter` + `ProgressView` + `Text` + `Timeline` | `Timeline` shows last 4–6 milestones (first commit, oldest still-active branch, most recent tag, HEAD). `ProgressView` shows `scanned / total` when `--max-commits` truncates the scan. |
| `activity` | Daily commit count over last 12 months (GitHub-style) | **`CalendarHeatmap`** | The motivating screenshot. Optional `--year YYYY`. |
| `cadence` | Commit activity by hour-of-day (single 24-cell strip) | **`HeatStrip`** | Reveals "are these night commits or 9–5 commits?" |
| `tempo` | Weekly commits per top-N author, one row per author | **`Sparkline`** ×N + `Legend` | Each author gets a labeled sparkline; row layout via `VStack`. |
| `deltas` | Insertions and deletions over time | **`LineChart`** (2 series, `.line`) | Two-series, classic green-up / red-down. Date X axis. |
| `loc` | Net LOC trend over time (cumulative ins − del) | **`LineChart`** (1 series, `.area`) | Single area series, `.chartBaseline(.zero)`. |
| `volatility` | Top-N most-changed files (lifetime change count) | **`BarChart`** | Horizontal bars with file-path labels truncated. |
| `kinds` | Commit-type counts (`feat`/`fix`/`refactor`/…) | **`ColumnChart`** + `Legend` | One column per kind, color-toned per category. |
| `kinds-share` | Quarterly share of each commit kind | **`StackedBarChart`** per quarter | One stacked bar per quarter, last 8 quarters. |
| `pulse` | Current week's commits vs trailing 4-week median target | **`BulletChart`** | Bullet target marker is the trailing median; "are we above pace?" |
| `recent-vs-all` | Top-N authors' last-30-days share vs all-time share | **`ComparisonChart`** | Existing primitive's exact use case. |
| `health` | "% of code <1yr old" gauge with thresholds | **`ThresholdGauge`** | Bands at e.g. 30 / 60 / 80 — uses `ThresholdBand` literally. |
| `concentration` | Bus factor / author concentration | **`Meter`** + `StackedBarChart` | `Meter` shows the bus-factor integer; stack shows the share distribution. |
| `releases` | Tag/release history (last N) | **`Timeline`** | Annotated tags get a different tone than lightweight ones. |
| `dag` | `git log --graph` style DAG of last N commits | plain `Text` rows (no chart) | Renders pre-laid-out `GraphCommit.glyphRow` strings; uses tone for branch lanes. Covers the "DAG display" requirement without inventing a new chart primitive. |
| `dashboard` | Runs activity, deltas, kinds, volatility, releases back-to-back | every chart above | Explicit opt-in. Long output. |

That's 14 chart-bearing subcommands plus `index`, `dag`, and
`dashboard`, covering all chart types in `SwiftTUICharts` —
`BarChart`, `ColumnChart`, `Sparkline`, `HeatStrip`, `Meter`,
`ThresholdGauge`, `BulletChart`, `ComparisonChart`, `StackedBarChart`,
`Timeline`, `Legend` — plus both new ones (`CalendarHeatmap`,
`LineChart`). The `info` subcommand also exercises `ProgressView`,
which ships from `SwiftTUI` itself and is cross-listed in the
`SwiftTUICharts` documentation as a metric view.

### Common flags

Inherited via an `OptionGroup` on every subcommand:

```swift
struct GitVizOptions: ParsableArguments {
  @Option(name: .long, help: "Repository path (defaults to cwd).")
  var path: String = "."

  @Option(name: .long, help: "Only consider commits since this date (YYYY-MM-DD).")
  var since: String?

  @Option(name: .long, help: "Only consider commits until this date (YYYY-MM-DD).")
  var until: String?

  @Option(name: .long, help: "Limit to last N commits per scan (default: 10000).")
  var maxCommits: Int = 10000

  @Option(name: .long, help: "Output width in cells (defaults to terminal width).")
  var width: Int?

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions   // brings in --no-color, --reduce-motion, etc.
}
```

Subcommands that rank or filter additionally take `--top N` (default
10) and, where relevant, `--year YYYY`.

### Per-subcommand shape

Every subcommand is two layers thick:

1. A thin **data-to-series adapter** in `Sources/GitViz/Adapters/`
   that turns `GitRepo` output into a chart-entry type. Pure function,
   individually testable with synthetic input.
2. A thin **command body** that parses opts, fetches data, runs the
   adapter, builds a chart, and calls `RenderOnce.print`.

A worked example — `gitviz deltas`:

```swift
let repo = try GitRepo(workingDirectory: opts.resolvedPath)
let deltas = try repo.numstat(since: opts.sinceDate)
let (insSeries, delSeries) = LineChartSeries.dailyDeltas(deltas)

let chart = LineChart(
  "Insertions vs Deletions",
  series: [insSeries, delSeries],
  height: 8
)
.chartXAxis(.dates(every: .week, format: .dateTime.month(.abbreviated).day()))
.chartYAxis(.values(count: 5, format: .number.notation(.compactName)))
.chartLegend(.bottom)

RenderOnce.print(chart, width: opts.width, options: opts.swiftTUIOptions)
```

That's the whole command body — 5–15 lines for every subcommand.
The interesting logic lives in the adapter (in this case
`LineChartSeries.dailyDeltas(_:)`), which is where tests focus.

## File layout

```text
Examples/gitviz/
  Package.swift
  Package.resolved
  README.md                       # one-screen "what is this and how do I run it"
  Sources/GitViz/
    GitVizApp.swift               # @main + AsyncParsableCommand wiring
    Options.swift                 # GitVizOptions (shared OptionGroup)
    Commands/
      IndexCommand.swift          # default subcommand
      InfoCommand.swift
      ActivityCommand.swift
      CadenceCommand.swift
      TempoCommand.swift
      DeltasCommand.swift
      LocCommand.swift
      VolatilityCommand.swift
      KindsCommand.swift
      KindsShareCommand.swift
      PulseCommand.swift
      RecentVsAllCommand.swift
      HealthCommand.swift
      ConcentrationCommand.swift
      ReleasesCommand.swift
      DagCommand.swift
      DashboardCommand.swift
    Git/
      GitRepo.swift               # public façade; init + version detection
      GitProcess.swift            # internal Process invoker, output streamer
      GitParsers.swift            # log/numstat/shortlog/for-each-ref parsers
      GitModels.swift             # RepoInfo, Commit, AuthorTally, ...
      CommitKind.swift            # Conventional-Commits + keyword inference
      GraphLayout.swift           # DAG-to-lanes layout used by DagCommand
    Adapters/
      DateValueAdapters.swift     # commit lists -> [DateValue]
      LineSeriesAdapters.swift    # commit deltas / LOC -> LineChartSeries
      BarEntryAdapters.swift      # file tallies, commit-kind counts -> [BarChartEntry]
      TimelineAdapters.swift      # tags + milestones -> [TimelineEntry]
      AuthorPaletteAdapter.swift  # stable BannerTone assignment per author
    Views/
      IndexView.swift             # the labeled subcommand listing
      ChartCard.swift             # title + subtitle + chart + footer wrapper
  Tests/GitVizTests/
    CommitKindTests.swift
    GitParsersTests.swift         # parses fixed log output strings (no Process)
    AdaptersTests.swift           # commit lists -> chart entry types
    GraphLayoutTests.swift        # DAG lane assignment
    RenderOnceSmokeTests.swift    # one tiny chart through RenderOnce -> golden string
    Fixtures/
      log-numstat.txt             # canned `git log --numstat` output
      shortlog.txt
      for-each-ref-tags.txt
      dag-glyphs.txt
```

Per-file size aim: ~150 lines. Commands are 30–80 lines each (they're
thin glue: parse opts → fetch data → run an adapter → build a chart →
`RenderOnce.print`). The actual logic concentrates in `Git/` (~600
lines) and `Adapters/` (~400 lines).

### Package.swift

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "gitviz",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "gitviz", targets: ["GitViz"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "GitViz",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
        .product(name: "SwiftTUIArguments", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "GitVizTests",
      dependencies: ["GitViz"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
```

## TTY and color policy

Centralized resolution in `RenderOnce` (in `SwiftTUICLI`). Precedence,
high to low:

1. Explicit `--no-color` flag on the command line.
2. `NO_COLOR` env var present and non-empty → disable color (per
   [no-color.org](https://no-color.org)).
3. `CLICOLOR_FORCE=1` env var → force color **even if stdout is not a
   TTY**.
4. `TERM=dumb` → disable color.
5. `isatty(STDOUT_FILENO) == 0` → disable color (piping to file,
   `grep`, `less` without `-R`).
6. Default → full ANSI 256-color.

The same gate drives:

- **Terminal width default**: `RenderOnce` reads `ioctl(TIOCGWINSZ)`
  for the live width and falls back to `$COLUMNS` then `80`. `--width`
  overrides.
- **Unicode-vs-ASCII glyph fallback (seam, not v1):** the chart
  primitives use box-drawing and shade ramp glyphs (`░▒▓█`, `─│╭╮╰╯`)
  that assume a Unicode-capable terminal. v1 leaves these as-is; if
  the future ASCII-only fallback is needed (e.g. `--ascii` opt-in or
  `LANG=C` auto-detection), it lands in `RenderOnce` as a final
  rewrite pass over emitted text, not in the chart code. The spec
  records the seam so a later tranche doesn't need to rewrite every
  chart.

## Tests

Three rings:

1. **Unit** — adapters, parsers, `CommitKind`, `GraphLayout`. Pure
   functions over fixed input. Fast. The bulk of the test surface
   lives here.
2. **Render smoke** — pick the smallest chart (e.g. `pulse` /
   `BulletChart`) and run it end-to-end through
   `RenderOnce.render(...)` against a synthetic `GitRepo` shim that
   returns a hand-rolled `RepoInfo` / `[Commit]` (not a real
   subprocess). Compares against a golden `.txt` to catch ANSI
   regressions and view-tree wiring bugs. One smoke test per chart
   type is enough — we are not snapshot-testing every subcommand.
3. **Live-repo guard (manual, not CI)** — a
   `Scripts/check_gitviz_smoke.sh` script (matching the repo's
   existing `Scripts/check_*.sh` convention) that runs `gitviz info`,
   `gitviz activity`, `gitviz dag` against the host project itself
   and prints the output. Failures are visual, not asserted; this is
   for "do the outputs look like the screenshots in the README"
   verification before commits.

`GitVizTests` deliberately does **not** spawn `git` subprocesses in
CI. All parser tests run against fixture strings checked into
`Fixtures/`. This keeps CI deterministic and avoids needing a known
git history per build agent.

## README

Single page: what the tool is, install (`swift run gitviz`), one-line
usage for every subcommand, two screenshots (the activity calendar and
the deltas line chart, matching the screenshots that drove the original
brief). Cross-links to
[CALENDAR_HEATMAP_AND_LINE_CHART.md](CALENDAR_HEATMAP_AND_LINE_CHART.md)
and to `SwiftTUICharts.docc` for reference.

## Implementation sequencing

The example depends on three pieces of infrastructure landing first:

1. `RenderOnce` in `SwiftTUICLI` — unblocks any non-interactive
   subcommand.
2. `CalendarHeatmap` in `SwiftTUICharts` — anchors the `activity`
   subcommand.
3. `LineChart` in `SwiftTUICharts` — anchors `deltas` and `loc`.

The implementation plan should order tranches accordingly: `RenderOnce`
first (smallest, narrowest, unblocks everything), then both chart
primitives (they're independent), then the example itself in two
passes — Git data layer + adapters + tests first, commands second.

## Out of scope

Named explicitly so they don't creep in during implementation:

- **Interactive mode.** Not even a TUI fallback for `dashboard`. Use
  `gitviz dashboard | less -R` to page output.
- **Remote/forge integrations.** No PR data, no review latency, no
  issue counts. Pure local-git.
- **Diff content analysis.** Insertions/deletions counts only — no
  per-line or per-hunk semantics.
- **Custom commit-kind taxonomies.** The `CommitKind` enum is fixed;
  no `--kind-map config.json` plugin point.
- **Output formats other than ANSI text.** No JSON, no SVG, no PNG
  export. A future `--output json` flag is plausible but not v1.
- **Authoritative line-of-code counting (`cloc`-style).** "LOC" in
  `gitviz loc` is `cumulative(insertions − deletions)`, a proxy that's
  right for trends and wrong as an absolute. Documented in the
  subcommand's help text.
- **DAG layout for huge histories.** `dag` caps at `--max 200` rows
  by default and bails (with a clear message) on histories that need
  >12 lanes; this isn't `tig`.
- **ANSI-injection sanitization beyond what `git` already does.**
  Author names that contain raw escape sequences are stripped by a
  small `sanitize(_:)` helper before display; everything else is
  passed through.
- **Unicode-to-ASCII glyph fallback** for non-UTF-8 terminals. The
  seam is reserved in `RenderOnce`; v1 emits Unicode glyphs only.
