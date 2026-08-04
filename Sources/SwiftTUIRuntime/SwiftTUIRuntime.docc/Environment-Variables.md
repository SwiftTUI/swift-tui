# Environment Variables

Every `SWIFTTUI_*` environment variable the framework reads, grouped by
subsystem.

## Overview

SwiftTUI reads its process environment in a small number of well-defined
places: the runtime configuration resolver, the run loop's render-mode
selector, the resolve-engine profile, a central feature-gate registry, the
diagnostic trace sinks, and the platform runners. This page lists every
variable each of those owners reads, what values it accepts, and what it
changes.

### Reading rules

Unless a row says otherwise, boolean variables share one grammar: **unset**
keeps the default, **empty or `0`** means off, and **any other value** means
on. Integer and path variables state their shape in their row.

Most gates read the environment **once** and latch the result — set variables
before the process launches. Command-line flags parsed by `SwiftTUICommand`
(`SwiftTUIArguments`) layer on top of the environment result, so an explicit
flag wins over an inherited variable.

SwiftTUI also honors the standard terminal conventions — `NO_COLOR`,
`FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`, `TERM`, `COLORTERM`, and
`LANG`/`LC_*` — through ``TerminalCapabilityProfile`` and the runtime
configuration resolver. `NO_COLOR` always wins over `FORCE_COLOR`.

### Output and presentation

Read by `RuntimeConfiguration.detect(environment:isStdoutTTY:)` at session
start.

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_ACCESSIBLE` | boolean | Selects accessible output. Implies ASCII glyphs, reduced motion, no progress animations, and linear output. |
| `SWIFTTUI_LINEAR` | boolean | Selects linear (append-only) output. Implies accessible output. |
| `SWIFTTUI_JSON` | boolean | Selects JSON output. Wins over `SWIFTTUI_ACCESSIBLE`. |
| `SWIFTTUI_PLAIN` | boolean | Shorthand for `--no-color --ascii --reduce-motion`. |
| `SWIFTTUI_ASCII` | boolean | Forces ASCII glyphs in place of Unicode box drawing and symbols. |
| `SWIFTTUI_REDUCE_MOTION` | `0` / truthy | Truthy forces reduced motion. An explicit `0` restores normal motion even where CI or a non-TTY stdout implied reduction. |
| `SWIFTTUI_NO_PROGRESS` | `0` / truthy | Truthy hides progress animations. An explicit `0` restores them where `CI` implied hiding. |
| `SWIFTTUI_QUIET` | boolean | Quiet verbosity. Wins over `SWIFTTUI_VERBOSE`. |
| `SWIFTTUI_VERBOSE` | integer > 0 | Verbose logging at the given level. |
| `SWIFTTUI_DEBUG` | boolean | Debug mode. On the terminal CLI runner this also enables the diagnostics TSV at its default path (see `SWIFTTUI_DIAGNOSTICS`). |
| `SWIFTTUI_CURSOR_FOLLOWS_FOCUS` | boolean | Moves the hardware terminal cursor to the focused control so screen readers can track focus. |

Precedence within the family: `SWIFTTUI_JSON` > `SWIFTTUI_ACCESSIBLE` >
`SWIFTTUI_PLAIN`; accessible/linear output then forces ASCII, reduced motion,
and no progress regardless of the individual toggles.

### Web host session

Also read by `RuntimeConfiguration.detect`. The group is consulted only when
`SWIFTTUI_WEB` is truthy; it makes the batteries-included runner serve the app
to a browser instead of (or alongside) the terminal.

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_WEB` | boolean | Enables the web host session. |
| `SWIFTTUI_PORT` | integer, default `0` | Listen port. `0` picks an ephemeral port. |
| `SWIFTTUI_BIND` | address, default `127.0.0.1` | Listen address. |
| `SWIFTTUI_OPEN` | boolean | Requests opening the served URL in a browser. |
| `SWIFTTUI_NO_OPEN` | boolean | Vetoes `SWIFTTUI_OPEN`. |
| `SWIFTTUI_WEB_SCENE` | ``WindowIdentifier`` string | Selects which scene the web session hosts. |

### Terminal capabilities

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_KITTY_KEYBOARD` | `0` opts out | The host probes for the kitty keyboard protocol and enables its disambiguation flag when supported. Only the exact value `0` disables the probe. The probe is also skipped inside tmux/screen and on non-TTY descriptors. |

### Render pipeline

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_RENDER_MODE` | `sync`, `async` (default), `async-no-cancel`, `async-no-drop` | Initial value of ``RunLoop/renderMode``, which selects the interactive pipeline documented in <doc:Runtime-Render-Pipeline>. Unrecognized values fall back to `async`. |

- `sync` — the one-shot synchronous pipeline. The entire fused frame tail
  (layout, semantics, draw, raster) runs on the main actor with no worker
  offload and no cancellation machinery.
- `async` — the cancellable pipeline. The frame tail may run on the layout
  worker; a queued tail can be cancelled before start when newer input
  intent arrives, and a completed frame can be dropped when superseded
  (bounded by the drop-eligibility blockers).
- `async-no-cancel` — never cancels a queued tail and commits completed
  frames in order. Browser-hosted sessions use this mode for presentation
  cadence.
- `async-no-drop` — keeps pre-start cancellation but never drops a
  completed frame.

Even in the async modes, per-frame offload eligibility is automatic: a tree
containing main-actor-only custom layouts, main-actor-only indexed child
sources, or layout-realized content runs its tail on the main actor for that
frame. There is no variable for that fallback — `sync` is the switch that
guarantees fully main-actor execution.

### Resolve-engine profile

The stack-lean profile trades resolve-pass conveniences for shallow call
stacks. It exists for WASI browser hosts, where worker threads get a small
fraction of the main thread's native stack.

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_STACK_LEAN_PROFILE` | exactly `0` or `1` | The stack-lean resolve profile: lean ambient slots instead of task-locals, reuse/memo/selective evaluation off, chunked descent. Defaults on for WASI builds, off natively. Other values are ignored. |
| `SWIFTTUI_LEAN_RETAINED_REUSE` | exactly `1` | Re-enables retained reuse under the lean profile (a reuse hit shortens the descent, so it can only shallow the stack). Ignored when the lean profile is off. |
| `SWIFTTUI_RESOLVE_DEPTH_LIMIT` | positive integer | Overrides the chunked-descent depth cap (default 6 under the lean profile) and force-enables the chunked resolve driver on native builds for debugging. `0` or negative disables the driver. |

### Soundness and verification gates

These gates are enrolled in the framework's central `FeatureGate` registry and
share the standard boolean grammar.

| Variable | Default | Effect |
| --- | --- | --- |
| `SWIFTTUI_SOUNDNESS_PROBE` | on | The reconciliation soundness probe: read-only oracles (stamp coherence, checkpoint equality, teardown coherence, …) run on sampled frames in release and every frame in debug. `0` opts out. |
| `SWIFTTUI_SOUNDNESS_PROBE_SAMPLE` | `256` release, `1` debug | Runs the oracles on 1-in-*N* frames. Driven by the frame counter, so sampling is deterministic. |
| `SWIFTTUI_SOUNDNESS_PROBE_TRACE` | off | Emits one `[SOUNDNESS]` line per recorded violation. |
| `SWIFTTUI_SOUNDNESS_PROBE_TRACE_FILE` | stderr | Path that receives the soundness trace lines instead of stderr. |
| `SWIFTTUI_RASTER_VERIFY_INCREMENTAL` | debug on, release off | Forces the incremental-raster verification policy: re-rasters fresh and compares byte-for-byte, recording any mismatch. |
| `SWIFTTUI_RASTER_TRUST_SOUND_DAMAGE` | release on, debug off | Forces the trusting policy: incremental damage is applied without the fresh-raster comparison. When both raster variables are set, verify wins. |
| `SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE` | off | Opt-in prototype: bounded damage for additive presentation overlays instead of a full-surface re-raster on topology change. Validate runs with `SWIFTTUI_RASTER_VERIFY_INCREMENTAL=1`. |
| `SWIFTTUI_PRESENTED_PROGRESS_GUARD` | off | Opt-in insurance: a completed frame whose presentation diff is non-empty is never drop-eligible, so undelivered pixels cannot be coalesced away. |
| `SWIFTTUI_COLLECTION_PROBES` | debug on, release off | Arms the collection magnitude counters (realized rows, list layout derivations) so release timings can be correlated with realization counts. |

### Diagnostics and tracing

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_PROFILE` | grammar | Activates the opt-in `SwiftTUIProfiling` product on scenes that add `.profiling()`: `signal-list[;sink-list]` with signals `frames`, `memory[@duration]`, `cpu[@duration]` and sinks `tsv=path`, `jsonl=path`, `summary`. See the `SwiftTUIProfiling` DocC catalog for the full grammar. |
| `SWIFTTUI_FRAME_TRACE` | file path | Installs the per-frame TSV trace sink (`COMMIT`, `ZEROART`, and `ELIDE` rows with causes, tail state, animation counts, and drop decisions). Unavailable on WASI. |
| `SWIFTTUI_MEMO_TRACE` | boolean, default on | The memoization soundness oracle, sampled 1-in-256 in release and every frame in debug. `0` disables the oracle; a truthy value additionally emits one `[MEMO-TRACE]` line per frame. |
| `SWIFTTUI_MEMO_TRACE_FILE` | file path | Appends `[MEMO-TRACE]` lines to a file (and enables emission) instead of stderr. |
| `SWIFTTUI_MEMO_TRACE_SAMPLE` | integer | Overrides the memo oracle's 1-in-*N* frame sampling. |
| `SWIFTTUI_REUSE_TRACE` | boolean, default off | Per-frame `[REUSE-TRACE]` histogram of why retained reuse was denied per node (dirty, env-mismatch, suppressed, …). |
| `SWIFTTUI_REUSE_TRACE_FILE` | file path | Appends reuse-trace lines to a file instead of stderr. |
| `SWIFTTUI_INVAL_TRACE` | boolean, default off | Per-frame `[INVAL-TRACE]` line decomposing how the invalidation set was assembled (raw scheduler set, portal translation, force-root reasons). |
| `SWIFTTUI_INVAL_TRACE_FILE` | file path | Appends invalidation-trace lines to a file instead of stderr. |
| `SWIFTTUI_PUBLICATION_DIAGNOSTICS` | `1`/`true`/`yes`/`on` | Enables runtime registration-publication diagnostics (checkpoint and portal bookkeeping counters). |
| `SWIFTTUI_DIAGNOSTICS` | boolean or file path | Terminal CLI runner: `1`/`true` writes the diagnostics TSV to `/tmp/termui-diagnostics.tsv`; any other truthy value is used as the file path. `SWIFTTUI_DEBUG=1` (or `--debug`) implies the default path. |

### Browser (WASI) host

Read by the WASI runner. The browser bridge sets most of these; they are
listed for completeness and for driving the wasm binary directly.

| Variable | Values | Effect |
| --- | --- | --- |
| `SWIFTTUI_TRANSPORT` | `ansi`, `terminal`, `xterm`, `ghostty-web`; default surface | Selects the ANSI terminal transport instead of the structured surface transport. |
| `SWIFTTUI_SURFACE_DELTA` | `1`/`true`/`yes`/`on` | Declares that the host accepts delta frames on the surface transport (the browser bridge's capability opt-in). |
| `SWIFTTUI_FRAME_DIAGNOSTICS` | boolean | Enables wire frame diagnostics. Falls back to `SWIFTTUI_DIAGNOSTICS`; `off`/`false`/`none`/`0`/empty disable. |
| `SWIFTTUI_MODE` | `manifest` | Prints the app's scene manifest as JSON and exits without launching a scene. |
| `SWIFTTUI_SCENE` | scene selector | Selects the scene to launch. Falls back to the first command-line argument. |
| `SWIFTTUI_RENDER_STYLE` | base64 | A base64-encoded terminal render style forwarded by the host. |
| `SWIFTTUI_COLUMNS` / `SWIFTTUI_ROWS` | integers | Surface size fallbacks, consulted after the standard `COLUMNS`/`LINES`. Clamped to at least 40×20; defaults 120×36. |

The retired `SWIFTTUI_SURFACE_MAX_VERSION` key is inert: capabilities are
named feature bits now, so there is no version ceiling to override.

### Repository tooling

Variables with the `SWIFTTUI_` prefix that only the test and gate tooling
reads — timeout scaling, fixture regeneration, serialized test execution, and
similar — are contributor-facing and documented in the repository's
`docs/DEVELOPMENT.md` and `docs/KNOWN-TEST-FLAKES.md`, not here.

## See Also

- <doc:Running-Apps>
- <doc:Runtime-Render-Pipeline>
- ``RuntimeRenderMode``
- ``RunLoop/renderMode``
