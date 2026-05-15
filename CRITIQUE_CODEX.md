# SwiftTUI Critique

Assessment date: 2026-05-15.

This critique is based on a read-only repo survey, targeted source checks, and
independent review passes across API usability, infrastructure, architecture,
and onboarding. I am intentionally separating "this is serious engineering"
from "this is release-ready and easy to adopt." The first is strongly true. The
second is uneven.

## Overall Assessment

SwiftTUI is a serious codebase. The architecture has a coherent frame pipeline,
the product split is deliberate, the local test gate is broad, and the examples
go beyond toy snippets. The repo looks like it is being built by someone who
cares about long-term maintainability, public API governance, terminal safety,
accessibility, cross-host behavior, and regression evidence.

The main critique is not that the project is unserious. It is that the public
surface and release posture do not yet match the seriousness of the internal
engineering. A new evaluator sees too many equally weighted products, too much
internal/process language, incomplete open-source trust artifacts, manual-only
CI, and a few host-boundary implementation risks. Those issues are fixable, but
they matter because this package is trying to be a framework, not just a lab.

## Strengths Worth Preserving

- The architecture has a durable central model: `resolve -> measure -> place ->
  semantics -> draw -> raster -> commit`. It is described in
  `docs/ARCHITECTURE.md`, `docs/RUNTIME.md`, and `docs/STATUS.md`, and the
  code is organized around the same concept.
- The product split is directionally good. ADR-0017 explicitly reserves
  `SwiftTUI` as the terminal convenience product over `SwiftTUIRuntime`
  (`docs/decisions/0017-terminal-convenience-product-over-runtime.md:29`) and
  keeps WebHost, SwiftUI host, WASI, charts, animated images, terminal
  embedding, and workspaces opt-in.
- The local verification surface is unusually broad. `Scripts/test_all.sh`
  covers policy hooks, accessibility guardrails, public API baseline freshness,
  root suites, platform suites, examples, performance tooling, and browser
  integration (`Scripts/test_all.sh:154`).
- The pre-commit policy is meaningful, not decorative. `prek.toml` wires
  formatting, Foundation import constraints, public-surface policies,
  concurrency escape-hatch checks, accessibility guardrails, main-thread usage
  checks, and docs frontmatter validation (`prek.toml:8`).
- Public API drift is mechanically governed. The generated baseline records the
  public symbols by module and is checked by the repo gate
  (`docs/PUBLIC_API_BASELINE.md:16`, `Scripts/test_all.sh:536`).
- The example set is substantial. `gallery`, `gifeditor`, `terminal-workspace`,
  `WebExample`, `WebHostExample`, `file-previewer`, `gitviz`, and `gifcat`
  exercise real app surfaces, not only synthetic unit cases
  (`Examples/README.md:13`).
- The website is stronger product positioning than the README. It gives a
  crisp value proposition, import snippet, live demo, execution modes, and
  surface inventory (`Website/src/components/Hero.astro:13`,
  `Website/src/components/Quickstart.astro:16`).

## High-Priority Critique

### 1. The README starts too deep for the public landing page.

The README opens with the lowest-level `DefaultRenderer` path and immediately
explains subtle no-invalidator state behavior (`README.md:5`,
`README.md:40`). That is valuable, but it is not the first thing a new user
needs. The first page should say what the product is, show what it looks like,
show how to install it, then offer the low-level renderer as an advanced path.

Constructive direction: lead with the product promise from the website/status,
then a one-import `@main` app, then installation, then a visible output
artifact. Move the snapshot renderer and state caveat below "Advanced rendering"
or "Testing/previews."

### 2. External installation is under-documented in the README.

The README shows example commands and app code, but it does not show the
Package.swift dependency snippet that an external consumer needs. The website
does show one, but it pins `branch: "main"` (`Website/src/components/Hero.astro:53`).
The DocC module guide says "one dependency on the root `swift-tui` package" but
does not show the Package.swift wiring (`Sources/SwiftTUI/SwiftTUI.docc/Choosing-Modules-And-Platforms.md:7`).

Constructive direction: add a "Install" section to the README with a current
recommended dependency form. If `main` is the real expectation, call this alpha
and say so. If releases are intended, show a tag/range and a compatibility
table.

### 3. The repo lacks basic open-source trust artifacts.

There is no root `LICENSE`, `CONTRIBUTING`, `SECURITY`, or code-of-conduct file
in `git ls-files`; only vendored packages have licenses. Meanwhile the website
links to a root `LICENSE` URL and its JSON-LD advertises the same license URL
(`Website/src/components/SiteFooter.astro:45`,
`Website/src/pages/index.astro:35`). That mismatch damages public credibility.

Constructive direction: add at least `LICENSE`, `CONTRIBUTING.md`, and
`SECURITY.md`. If contribution/security processes are intentionally private for
now, say that plainly instead of linking to nonexistent trust material.

### 4. The serious local gate is not matched by automatic CI.

The Linux test workflow is manual-only (`.github/workflows/run-tests-linux.yml:3`).
The only PR-triggered workflow in this repo survey is the Linux image build, and
it is path-scoped to Dockerfile/toolchain/workflow changes
(`.github/workflows/build-linux-image.yml:16`). That means the broad local gate
does not function as an automatic PR or push gate.

Constructive direction: add automatic `pull_request` and `push` triggers for a
curated gate. If the full gate is too expensive, make the expected protection
explicit: root Swift tests, policy checks, public API baseline, platform package
smokes, and the gallery example.

### 5. The Linux test workflow appears inconsistent with the repo's Swiftly policy.

The workflow installs Swift through `swift-actions/setup-swift@v3`
(`.github/workflows/run-tests-linux.yml:21`) and then runs `bun run test`
(`.github/workflows/run-tests-linux.yml:70`). The gate hard-requires `swiftly`
and runs Swift only through `swiftly run swift` (`Scripts/test_all.sh:485`,
`Scripts/test_all.sh:338`). The repo docs also say not to use bare Swift for
repo-local package work (`docs/TOOLCHAINS.md:10`, `docs/TOOLCHAINS.md:18`).

Constructive direction: make CI install Swiftly exactly like the macOS deploy
and perf workflows do, or change the gate to accept a verified CI toolchain
without `swiftly`. Right now the workflow and gate appear to disagree.

### 6. The work queue contract is currently contradictory.

`docs/TODO.md` says it is "the first place to check what is next" and that
planned or decision-bound status gaps must have TODO entries
(`docs/TODO.md:20`, `docs/TODO.md:21`). The file contains only rules. At the
same time, `docs/README.md` lists a current planned/active scroll-control plan
(`docs/README.md:87`), and `docs/STATUS.md` names open design questions
(`docs/STATUS.md:205`).

Constructive direction: either add the active/planned items to `TODO.md`, or
mark the docs index/status language as shipped/contextual/deferred. Empty TODO
is fine only if the rest of the repo consistently says there is no active queue.

### 7. Release posture is weaker than engineering posture.

The website shows `v0.0.1` (`Website/src/components/SiteHeader.astro:11`), the
install snippet points at `main`, the Cloudflare deploy workflow is manual-only
(`.github/workflows/cloudflare-pages.yml:25`), and there is no visible release
checklist or release workflow comparable to the local gate.

Constructive direction: add a release policy. Even for alpha, define what a tag
means, what gate must pass, what DocC/site artifact corresponds to it, and how
breaking public API changes are recorded.

### 8. The public product list is too crowded without support tiers.

`Package.swift` exposes daily-use modules, host runners, transport bridges,
argument parsing, PTY primitives, terminal workspace APIs, and host products at
the same level (`Package.swift:121`). The import matrix helps, but Xcode/SwiftPM
still presents `SwiftTUIPTYPrimitives`, `WASISurfaceBridge`, `SwiftTUIArguments`,
`SwiftTUICLI`, and `SwiftTUIRuntime` as peers of `SwiftTUI`.

Constructive direction: keep the products, but label tiers everywhere: primary
app surface, add-on content products, host/runner products, integration
primitives, and SPI/internal-adjacent products. The README and package docs
should make "start with `SwiftTUI`" visually dominant.

### 9. `WASISurfaceBridge` is advertised as importable but has no public API.

Docs describe `WASISurfaceBridge` as a transport-only consumer product
(`README.md:142`, `docs/HOST_PACKAGES.md:29`). The public API baseline reports
`WASISurfaceBridge` as `0 | 0` public symbols (`docs/PUBLIC_API_BASELINE.md:30`).
The useful types in `WebSurfaceTransport.swift` are `@_spi(WebHost) public` or
package-level, not ordinary public API (`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift:368`,
`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift:694`).

Constructive direction: either make it a real public transport API with a
documented stability tier, or stop advertising it as a public importable
product. A public product with no public surface looks accidental.

### 10. DocC coverage does not match the product graph.

The docs index says per-target API reference lives in `*.docc` catalogs under
`Sources/` and gives a `SwiftTUI` generation command (`docs/README.md:8`).
The README combined DocC command includes only `SwiftTUIViews`, `SwiftTUI`, and
`SwiftTUICharts`, omitting `SwiftTUIRuntime`, `SwiftTUIAnimatedImage`, and
platform products (`README.md:261`). There are no `Platforms/**/*.docc`
catalogs.

Constructive direction: either add DocC catalogs for public platform products
or document that those products are covered by prose guides only. For a
multi-product framework, "DocC means only some products" is a discoverability
gap.

## API And Usability Critique

### 11. The generated baseline can mislead readers about `import SwiftTUI`.

The recommended import is `SwiftTUI`, but the baseline lists `SwiftTUI` as
`0 | 0` public symbols (`docs/PUBLIC_API_BASELINE.md:20`) because it is a
re-export shell (`Sources/SwiftTUI/SwiftTUI.swift:1`). That is technically
correct as an ownership count, but it is confusing as a consumer-facing surface
summary.

Constructive direction: rename the table framing to "owned public symbols" and
add a note that re-export products expose symbols owned by other modules.

### 12. The public API baseline is useful for governance but noisy for adoption.

The baseline reports `SwiftTUIViews` at 255 top-level and 9,637 public symbols
(`docs/PUBLIC_API_BASELINE.md:22`). Many ordinary values show large inherited
member counts because every `View` gets the modifier surface. This is great for
detecting churn, but poor as a "what should I use?" map.

Constructive direction: keep the generated baseline for maintainers, but add a
short stable "daily API" page that lists the common authoring controls,
modifiers, and runtime entry points without symbol-graph noise.

### 13. The main example weakens the one-import story unless readers know why.

The gallery is positioned as the primary public workbench
(`Examples/README.md:17`), but its reusable views target depends on
`SwiftTUIRuntime` and imports it directly (`Examples/gallery/Package.swift:33`,
`Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift:1`). That is valid
for a shared view library, while the executable target imports `SwiftTUI` and
`SwiftTUIWebHostCLI`. A new user may copy the wrong import pattern.

Constructive direction: add a short note in the gallery README and examples
index: executable apps import `SwiftTUI`; reusable view packages can import
`SwiftTUIRuntime` when they intentionally avoid terminal runner behavior.

### 14. Platform support signals are scattered.

`Package.swift` declares macOS 15 and iOS 18 unless
`DISABLE_EXPLICIT_PLATFORMS=1` is set (`Package.swift:16`). A separate
`nativeRuntimePlatforms` list includes macOS, Linux, Android, and iOS
(`Package.swift:7`). README development requirements mention macOS and Swiftly
(`README.md:183`), while status and toolchain docs separately discuss Linux,
WASI, Android, and product-specific exclusions (`docs/STATUS.md:165`,
`docs/TOOLCHAINS.md:124`).

Constructive direction: add a single consumer-facing support matrix: product,
platforms, build path, runtime status, CI coverage, and known exclusions.

### 15. Consumer and maintainer toolchain guidance is not cleanly separated.

Repo docs correctly require `swiftly run swift ...` for local framework work
(`docs/TOOLCHAINS.md:10`). The website quickstart says consumers can use
standard SwiftPM and any Swift 6.3 toolchain on PATH
(`Website/src/components/Quickstart.astro:32`, `Website/src/components/Quickstart.astro:56`).
Both can be true, but the distinction is easy to miss when moving between
README, DocC, examples, and website.

Constructive direction: explicitly label "Using SwiftTUI in your app" versus
"Contributing to SwiftTUI itself" in README, DocC, website, and examples.

### 16. Default launcher failure modes are not product-polished.

The default terminal `App.main()` uses `try!` for `TerminalRunner.run`
(`Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift:496`). The WebHost CLI
default `App.main()` catches and calls `fatalError`
(`Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift:65`).
For a framework default entry point, this is blunt: errors such as no scenes,
unsupported launch mode, or host setup failures become crashes rather than
clear diagnostics unless users opt into custom launch code.

Constructive direction: route default-entry errors through stderr plus a
nonzero process exit where possible. Reserve traps for impossible invariants.

### 17. Examples need support tiers.

The examples index calls all examples "maintained" and maps them by product
(`Examples/README.md:3`, `Examples/README.md:29`). The public surface policy
allows examples to be demos, tests, and design exploration rather than public
products (`docs/PUBLIC_SURFACE_POLICY.md:58`). Those statements are compatible,
but users need clearer labels: flagship maintained apps, focused regression
examples, platform integration references, and experimental/historical samples.

Constructive direction: add a "Support tier" column to `Examples/README.md`.

### 18. The root README lacks visual proof.

For a terminal UI framework, visual evidence is part of usability. The website
has a live demo, but the root README has no screenshot, asciinema, or static
terminal-output preview near the top. The first code block prints output, but
the output itself is not shown (`README.md:5`).

Constructive direction: add one stable screenshot or text fixture render in the
first screen, then link to the live browser/WASI demo.

## Infrastructure And Process Critique

### 19. The normal gate intentionally excludes most examples.

The full script covers many examples (`Scripts/test_all.sh:167`), but the
curated repo gate includes only `Examples/gallery` from the examples set
(`Examples/README.md:62`). That is a reasonable cost tradeoff, but it means
flagship examples like `gifeditor`, `terminal-workspace`, `file-previewer`, and
`WebExample` are not continuously covered by the default gate.

Constructive direction: publish the tradeoff explicitly and consider rotating
or tiered example gates. For example: every PR gets gallery plus package
smokes; nightly/manual gets all examples and browser integration.

### 20. Performance work has tooling but no enforced threshold.

The perf smoke workflow is manual-only (`.github/workflows/perf-smoke.yml:3`),
archives artifacts, and runs one iteration (`Scripts/run_perf_smoke.sh:9`). It
does not appear to enforce a regression budget. That is useful for investigation
but not yet a performance guard.

Constructive direction: keep artifact capture, then add a small non-flaky
threshold or trend check for the few scenarios that are stable enough to gate.

### 21. Some repo-owned task definitions violate the toolchain policy.

`docs/TOOLCHAINS.md` says repo-local builds/tests should use
`swiftly run swift` (`docs/TOOLCHAINS.md:10`). `mise.toml` uses bare
`swift build` in release tasks and also pins `bun` / `prek` to `latest`
(`mise.toml:1`, `mise.toml:5`). That gives contributors a footgun in a file
that looks like an endorsed workflow.

Constructive direction: either delete stale `mise` tasks or make them conform
to the same `swiftly` and version-pin story as the rest of the repo.

### 22. Dependency determinism is mixed.

Swift package dependencies are resolved and the Bun lockfile exists, but the
root `package.json` uses caret ranges for `@openai/codex` and `yaml`
(`package.json:22`), workflows use `bun-version: latest`
(`.github/workflows/run-tests-linux.yml:25`,
`.github/workflows/cloudflare-pages.yml:78`), and `mise.toml` uses latest for
tooling (`mise.toml:1`). Lockfiles mitigate package installs, but runtime
tooling can still drift.

Constructive direction: pin Bun and contributor tools for CI/release paths.
Leave "latest" only in clearly local convenience paths.

### 23. The docs archive is too hard to navigate.

`docs/README.md` is rigorous but overwhelming. It mixes source-of-truth
references, active proposals, shipped implementation records, postmortems, and
historical plans in one long index (`docs/README.md:64`). That is useful for
maintainers who already know the repo, but it is a high-friction onboarding
surface.

Constructive direction: add a short path-based index at the top: "I want to
build an app", "I want to contribute to runtime", "I want to integrate a host",
"I want to understand public API policy." Keep the archive below that.

### 24. Some docs still point at stale source paths.

`docs/ASYNC_RENDERING.md` points readers to `Sources/SwiftTUI/SwiftTUI.swift`,
`Sources/SwiftTUI/RunLoop+Rendering.swift`, and
`Sources/SwiftTUI/FrameDiagnosticsLogger.swift` (`docs/ASYNC_RENDERING.md:268`).
Current code lives under `Sources/SwiftTUIRuntime/...`. `docs/RUNTIME.md` also
mentions `Sources/SwiftTUI/TerminalHost.swift` (`docs/RUNTIME.md:290`).

Constructive direction: add a simple docs link/path check for known source
anchors, or at least refresh path references after product moves.

## Architecture And Implementation Critique

### 25. `SwiftUIHost` ignores the semantic host-frame sequence contract.

`SemanticHostFrame.sequence` is documented as monotonically increasing so hosts
can detect stale async work without inferring freshness from callback ordering
(`Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift:409`). `HostedRasterSurface`
hands frames to hosts through an unstructured `Task { @MainActor ... }`
(`Sources/SwiftTUIRuntime/Scenes/HostedRasterSurface.swift:47`). The SwiftUI
host receiver overwrites latest raster, semantics, focus, and damage without
checking `frame.sequence`
(`Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift:137`).

Constructive direction: store the latest consumed sequence in SwiftUIHost and
drop older frames. If callback ordering is actually guaranteed, document the
guarantee and explain why sequence is not needed there.

### 26. WebHost adapts async output to sync presentation with an unbounded wait.

`WebSocketSurfaceTransport.present` is synchronous through `PresentationSurface`,
but `sendBytes` creates a `Task`, waits on a `DispatchSemaphore`, and has no
timeout/cancellation path
(`Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift:184`).
The underlying sink is explicitly async
(`Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostServer.swift:103`). This is
a real host-boundary risk: browser/WebSocket backpressure or a stuck sink can
park runtime presentation.

Constructive direction: make host presentation async at the seam, or introduce
a bounded backpressure policy with cancellation and an explicit failure path.

### 27. Graph-scoped state has a global registry with no visible cleanup path.

`StateGraphBindingRegistry.shared` stores `ObjectIdentifier(StateBox) ->
ViewGraphScopeID -> Identity` and exposes only `remember` and `currentIdentity`
(`Sources/SwiftTUIViews/State/State.swift:374`). There is no corresponding
prune/remove API visible near the registry. The graph-scoped state model is
well motivated, but long-lived hosted sessions with many short-lived state boxes
could accumulate stale metadata.

Constructive direction: tie registry cleanup to view graph teardown or state
box lifecycle, and add a test that mounts/unmounts many stateful identities
without growing retained registry state.

### 28. Some core architectural comments disagree with current behavior.

`FrameArtifacts.drawnIdentities` still says the runtime uses this set to gate
animation tick scheduling on viewport visibility
(`Sources/SwiftTUICore/Commit/FrameArtifacts.swift:179`). Current runtime code
explicitly says that viewport gate is gone and schedules follow-up animation
work whenever `hasPendingWork` is true
(`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:985`). This is not a
minor typo; it is stale guidance on a core frame product.

Constructive direction: update the `drawnIdentities` comment to describe its
current role, and add a small docs/source drift check for known terminology if
this kind of drift recurs.

### 29. Several implementation files have too much locality concentrated in one file.

`Sources/SwiftTUIRuntime/SwiftTUI.swift` is 2,724 lines and starts with
re-exports followed immediately by frame-tail retained state and async render
machinery (`Sources/SwiftTUIRuntime/SwiftTUI.swift:1`). Other large files
include `RunLoop+Rendering.swift` (1,521 lines), `TerminalHost.swift` (2,325
lines), `ViewGraph.swift` (1,672 lines), and `WebSurfaceTransport.swift` (1,272
lines). Big files are not automatically bad, but here some filenames are too
generic for the amount of machinery they contain.

Constructive direction: split by stable concepts, not by arbitrary size:
`DefaultRenderer`, frame-head draft, frame-tail worker, retained layout state,
semantic host-frame presentation, terminal fd host, and presentation writer
could each be easier to navigate as named modules/files.

### 30. Runtime traps are used in public execution paths.

There are legitimate internal invariants in this kind of renderer, but public
framework execution paths still contain traps and preconditions. The default
CLI entry point uses `try!` (`Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift:496`),
the WebHost CLI default uses `fatalError` for caught errors
(`Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift:65`),
and render/focus code contains preconditions for missing artifacts
(`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:220`,
`Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift:839`).

Constructive direction: define which failures are user/configuration errors
and which are impossible invariants. User/configuration errors should be
reported; impossible invariants can remain traps with tests.

### 31. Host/product terminology is good, but some public names still blur layers.

The docs define runner versus host terminology, and ADR-0017 is clear. But
public products still include names like `SwiftTUIWebHostCLI` and
`SwiftTUIWebHost` where runner, host, browser bundle, and CLI behavior are
compound. The docs explain this, but the product names alone do not.

Constructive direction: do not necessarily rename products now, but add
consistent subtitles wherever products are listed: "combined terminal/WebHost
runner", "localhost browser host", "WASI runner", "transport bridge", etc.

## Product Seriousness Summary

This repo is serious in architecture, tests, API governance, and platform
ambition. Its weaknesses are the things that make a serious framework feel
safe to adopt: clear installation and versioning, automatic CI, open-source
trust files, stable product tiers, complete docs coverage for the exported
product graph, and host-boundary failure handling.

The most valuable next tranche would be:

1. Add root trust/release artifacts: `LICENSE`, `CONTRIBUTING.md`,
   `SECURITY.md`, release policy, and README install/version guidance.
2. Make CI automatic and aligned with `swiftly`.
3. Reconcile `TODO.md`, `docs/README.md`, and `STATUS.md`.
4. Fix or reframe `WASISurfaceBridge`.
5. Add a consumer support matrix and product-tier table.
6. Address the SwiftUIHost sequence check and WebHost blocking transport seam.

Those changes would make the public story match the quality of the underlying
engineering.
