# SwiftTUI Critique

Assessment date: 2026-05-16.

This is the merged, current critique list for the repository. It reconciles the
former Codex critique, Claude critique, and executive-summary critique against
the checked-out source tree as of this date. Keep this file as the ranked live
critique.

Scope note: this pass was source/configuration based. It did not run the build
or test suite, and it did not verify external GitHub state such as branch
protection or latest workflow run results.

## Current Bottom Line

The original critiques were right about the shape of the project: the framework
core is serious, but the public adoption contract needed work. Since those
critiques landed, the highest-leverage adoption basics have moved substantially:

- root `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, and release policy now exist
- package license metadata exists
- vendored license/provenance files have been restored
- `0.1.0` exists as the first release-policy-backed tag
- README install, stability, support matrix, and product-tier guidance exist
- CI configuration now has push/PR triggers, Swiftly-aligned Linux/macOS gates,
  policy checks, and an iOS package build job
- several concrete correctness issues have already been fixed:
  `Binding.init(get:set:)`, `Color.hex(_:)`, WebHost sink timeout, default
  launcher error reporting, SwiftUIHost stale-frame sequence handling,
  `@State`/`@GestureState` graph-registry cleanup, `@Environment`, and
  `View.id(_:)`

The live critique is therefore no longer "no license, no CI, no release." The
remaining highest-value work is now:

1. prove the restored CI externally and make it enforceable
2. clean up supply-chain/tooling drift
3. make the test gate complete and harder to rebaseline accidentally
4. close the remaining SwiftUI-shaped API honesty gaps
5. reduce maintenance load in the largest runtime files and stale historical docs

## Severity Legend

- **P0**: blocks adoption, release trust, or runtime safety
- **P1**: important correctness, test, or public API issue
- **P2**: scheduled quality work
- **P3**: opportunistic cleanup
- **Closed**: materially addressed in the current tree
- **Ambiguous**: needs a product or governance decision before implementation

## Ranked Live Critique

### 1. CI Is Configured, But Enforcement Still Needs External Proof

Status: **P0 / partially addressed / external verification needed**

The local workflow file has been materially repaired:
`.github/workflows/run-tests-linux.yml` now has `push`, `pull_request`, and
`workflow_dispatch` triggers; installs Swiftly; runs policy checks; runs Linux
and macOS repo gates; and includes a generic iOS package build.

Remaining critique:

- Verify the latest GitHub Actions runs are green.
- Verify branch protection requires the restored checks on `main`.
- Decide whether the macOS runner label `macos-26` is the intended public CI
  floor or a temporary runner choice.
- Decide whether policy checks should be a separate required status from the
  slower repo gate.

Ambiguity required to act: branch protection and required status checks are
GitHub repository settings, not source-tree state. Someone with repo admin
access must decide and apply them.

### 2. Personal Workflow Tooling Still Leaks Into Project Dependencies

Status: **P1 / open**

`package.json` still lists `@openai/codex` under `dependencies`. No repo script
or package import found in this pass requires it as project functionality.

Current evidence:

- `package.json` has `"@openai/codex": "^0.121.0"` under `dependencies`.
- The repo already discloses that the project is AI-assisted in README and
  `CONTRIBUTING.md`; keeping an AI CLI as an install dependency is a different
  issue.

Direction:

- Remove `@openai/codex` from `package.json` and `bun.lock`, or move it to a
  clearly local/dev-only path if there is a repo-owned command that truly needs
  it.

Ambiguity required to act: none, unless there is an unstated workflow script that
depends on this package.

### 3. Toolchain Pinning And `mise` Tasks Contradict The Swiftly Policy

Status: **P1 / open**

The repo's written policy says repo-local Swift work uses
`swiftly run swift ...`. `mise.toml` still pins `bun` and `prek` to `latest` and
contains release-looking tasks that call bare `swift build`.

Current evidence:

- `mise.toml` uses `bun = "latest"` and `prek = "latest"`.
- `mise.toml` tasks use `swift build -c release`.
- `docs/TOOLCHAINS.md` and README tell contributors to use
  `swiftly run swift ...`.

Direction:

- Either delete the stale `mise` release tasks or make them call
  `swiftly run swift`.
- Pin contributor tool versions used by CI/release paths.
- Leave `latest` only in explicitly local convenience paths.

Ambiguity required to act: decide whether `mise.toml` is an endorsed project
entrypoint or only a maintainer convenience file.

### 4. The Test Gate Still Appears To Miss A Declared Test Target

Status: **P1 / open**

`Package.swift` declares `SwiftTUITerminalWorkspaceTests`, but the explicit
filter list in `Scripts/test_all.sh` does not include it. `Scripts/test_gate.sh`
delegates to `Scripts/test_all.sh`, so this is still a live gate-completeness
concern.

Current evidence:

- `Package.swift` declares `SwiftTUITerminalWorkspaceTests`.
- `Scripts/test_all.sh` lists filters for many suites, including
  `SwiftTUITerminalTests`, but not `SwiftTUITerminalWorkspaceTests`.

Direction:

- Add the missing filter immediately.
- Prefer a meta-check that every `testTarget` in `Package.swift` is either in
  the runner or explicitly excluded with a documented reason.
- Consider replacing the hand-maintained root-package filter list with a plain
  root `swift test` where feasible.

Ambiguity required to act: none.

### 5. Coverage And Fixture Discipline Are Still Weak As Gates

Status: **P1 / open**

The suite is broad, but there is still no code-coverage signal, rendered-text
fixtures can still be re-recorded by environment variable, and the WASI branch
contains a real-platform assertion that asserts only `Bool(true)`.

Current evidence:

- No current script/workflow reference to `--enable-code-coverage` or `llvm-cov`.
- `RenderedTextFixtureMode` still uses `PARALLEL_RECORD_RENDERED_FIXTURES`.
- `Platforms/WASI/Tests/SwiftTUIWASITests/WASIRunnerTests.swift` still has
  `#expect(Bool(true))` under `canImport(WASILibc)`.

Direction:

- Add coverage reporting before arguing about thresholds.
- Make fixture recording explicit-only, preferably through a dedicated script or
  non-gate mode, and fail the gate if recording is enabled.
- Replace the WASI tautology with a real WASI assertion or mark the branch as a
  known unsupported test path with an explicit reason.

Ambiguity required to act: decide whether coverage is informational first or a
failing threshold from day one.

### 6. Remaining SwiftUI-Shaped API Gaps Need Honest Product Decisions

Status: **P1 / partially addressed / ambiguous**

Some original API findings are now closed: `@Environment` exists,
`View.id(_:)` accepts arbitrary `Hashable`, and the `Binding` actor-isolation
hole is gone. The remaining high-signal API gaps are about compatibility
expectations.

Open items:

- No public `DismissAction` / `@Environment(\.dismiss)` equivalent was found,
  even though presentation internals have dismiss closures and an escape
  dismiss stack.
- `NavigationStack` and `.navigationDestination` remain intentionally
  binding-driven destination presentation, not SwiftUI's path/link model.
- `.sheet` still has only `isPresented:` forms; `popover(item:)` exists, but
  `sheet(item:)` and `onDismiss:` overloads do not.
- Public style protocols still require `snapshotLabel`, which exposes a
  diagnostics/testing concern to custom-style authors.

Direction:

- Add a public dismiss environment action, or explicitly document why presented
  content must receive dismissal through bindings/closures.
- Decide whether navigation keeps SwiftUI names with stronger warnings, adds
  path/link APIs, or renames the current concept to destination presentation.
- Add `.sheet(item:)` and `onDismiss:` if SwiftUI familiarity remains the goal.
- Move `snapshotLabel` behind an internal/package diagnostics protocol or derive
  it at the test/rendering boundary.

Ambiguity required to act: navigation is the major decision. Renaming, adding
SwiftUI-style navigation, and documenting divergence have different source
compatibility costs.

### 7. Public Documentation Coverage Is Still Not Enforced

Status: **P1 / open**

The original "public doc-comment coverage is thin" critique remains directionally
true. The formatter configuration still disables the rules that would force this
work.

Current evidence:

- `.swift-format.json` sets `AllPublicDeclarationsHaveDocumentation` to `false`.
- `.swift-format.json` also keeps `NeverForceUnwrap` and `NeverUseForceTry`
  disabled, even though the most obvious public `try!` hazard has been fixed.
- Many public declarations still appear without immediate doc comments.

Direction:

- Start with documentation on the consumer-selected surface: style protocols,
  built-in styles, presentation modifiers, text inputs, navigation, host runners,
  and product entrypoints.
- Re-enable documentation linting as a ratchet, not necessarily an immediate
  zero-baseline hard gate.
- Re-enable `NeverUseForceTry` separately now that `Color.hex(_:)` is throwing.

Ambiguity required to act: choose a ratchet shape before flipping strict doc
linting, otherwise this becomes an enormous unrelated cleanup.

### 8. `WASISurfaceBridge` Is Still A Public Product With No Ordinary Public API

Status: **P2 / open**

The README and host docs now describe `WASISurfaceBridge` as package-only
plumbing rather than a consumer product. That fixes the most misleading prose,
but the product still exists in `Package.swift`.

Current evidence:

- `Package.swift` still declares `.library(name: "WASISurfaceBridge", ...)`.
- Docs now call it package-only plumbing used by `SwiftTUIWASI` and
  `SwiftTUIWebHost`.

Direction:

- Either remove the public library product and keep it as an internal target, or
  give it a real public transport API and stability tier.

Ambiguity required to act: decide whether any external package is supposed to
depend on `WASISurfaceBridge` directly.

### 9. Platform Product DocC Coverage Is Still Uneven

Status: **P2 / open**

DocC catalogs exist for the `Sources/` products, but no platform products under
`Platforms/` have DocC catalogs.

Current evidence:

- Existing first-party DocC catalogs are:
  `SwiftTUICore`, `SwiftTUIViews`, `SwiftTUI`, `SwiftTUICharts`,
  `SwiftTUIRuntime`, and `SwiftTUIAnimatedImage`.
- Platform products such as `SwiftTUICLI`, `SwiftTUITerminal`,
  `SwiftTUITerminalWorkspace`, `SwiftTUIWASI`, `SwiftTUIWebHost`,
  `SwiftTUIWebHostCLI`, and `SwiftUIHost` have prose docs, but no product
  catalogs.

Direction:

- Add DocC catalogs for the public platform products, or state clearly that
  platform products are documented by prose guides only.
- Keep the public site generation command aligned with whichever decision is
  made.

Ambiguity required to act: decide whether DocC is required for every public
product or only for authoring/runtime products.

### 10. Large Runtime Files Remain A Maintainability Risk

Status: **P2 / open**

The largest files are still very large and sit on high-risk behavior. This is
not a style complaint; it affects reviewability of frame scheduling, animation,
terminal presentation, and graph state.

Current evidence:

- `Sources/SwiftTUIRuntime/SwiftTUI.swift`: 2,724 lines
- `Sources/SwiftTUIRuntime/Lifecycle/AnimationController.swift`: 2,509 lines
- `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`: 2,325 lines
- `Sources/SwiftTUICore/Resolve/ViewGraph.swift`: 1,672 lines
- `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`: 1,521 lines
- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`: 1,272
  lines

Direction:

- Split by stable concepts, not arbitrary size:
  `DefaultRenderer`, frame-tail worker, retained renderer state, presentation
  surface protocols, concrete POSIX terminal host, animation property tracking,
  transition tracking, matched geometry tracking, and web-surface codec/transport
  seams.
- Do this only when touching a seam for functional work or when a focused
  extraction has low risk and clear tests.

Ambiguity required to act: choose the first extraction target. The best
near-term candidate is probably presentation-surface protocols out of
`TerminalHost.swift` or `DefaultRenderer`/frame-tail support out of
`SwiftTUIRuntime/SwiftTUI.swift`.

### 11. The Seven-Phase Pipeline Is Still Looser Than The Doctrine Implies

Status: **P2 / open**

The architecture doctrine is sound, but phase products still share and copy
metadata across `ResolvedNode` and `PlacedNode`. There has been some cleanup in
adjacent areas, but the main concern remains.

Current evidence:

- `PlacedNode` still stores layout, draw, semantic, and draw-payload data
  propagated from `ResolvedNode`.
- `PlacedNode` still has "Mirror of `ResolvedNode/...`" comments for some fields.
- `LayoutEngine+Placement.swift` still copies metadata from resolved nodes into
  placed nodes.

Direction:

- Do not attempt a wholesale pipeline rewrite.
- Start by removing or centralizing mirrored metadata where a single immutable
  shared structure can replace duplicated fields.
- Add tests around any retained-layout or late-preference path before changing
  this structure.

Ambiguity required to act: decide whether the goal is a type-pure phase boundary
or a smaller "no unsynchronized mirrors" policy.

### 12. Stale Behavioral Comments And Historical Source Paths Still Create Noise

Status: **P2 / partially addressed**

The repo now has a stable-doc source-path checker and durable docs are in better
shape. However, stale behavioral/source-path material still exists in historical
plans and at least one active package comment.

Current evidence:

- `FrameArtifacts.drawnIdentities` still says the runtime gates animation tick
  scheduling on viewport visibility.
- `RunLoop+Rendering.swift` says that viewport gate is gone.
- Many `docs/plans` and historical proposal files still refer to old
  `Sources/SwiftTUI/...` paths.

Direction:

- Fix active source comments immediately.
- Treat historical plans differently from durable docs: either archive them
  clearly, or allow stale paths there and keep the stable-doc checker focused on
  current source-of-truth docs.

Ambiguity required to act: decide whether historical plans are allowed to remain
as historical records with stale paths, or whether all docs must be path-fresh.

### 13. Example Support Tiers Are Improved But Still Not Explicit

Status: **P2 / partially addressed**

README and `Examples/README.md` now provide product-oriented example guidance and
clearly state that `bun run test` gates only `Examples/gallery` while
`bun run test:all` gives exhaustive example coverage. The examples table still
does not explicitly distinguish flagship examples, regression examples,
integration references, and experimental examples.

Direction:

- Add a support-tier column only if public readers still misinterpret every
  example as equally supported.
- Keep the current gate-vs-exhaustive testing caveat; it is useful and current.

Ambiguity required to act: decide whether the current "Surface" and test-scope
language is enough, or whether formal tiers are needed.

### 14. Name Collision Remains A Strategic Adoption Risk

Status: **P2 / ambiguous**

The project name still collides with other SwiftUI-inspired terminal UI projects.
This is not a code defect, but it affects search, package discovery, and
community attribution.

Direction:

- Decide before further promotion whether the name remains `SwiftTUI`.
- If the name stays, add a concise README note that distinguishes this project
  from other similarly named Swift TUI frameworks.

Ambiguity required to act: this is a branding decision, not an engineering
cleanup.

### 15. Historical Release Tag `0.0.1` Still Exists

Status: **P3 / partially addressed**

The release policy now states that `0.0.1` predates the release policy and should
not be used. `0.1.0` exists as the first real release-policy-backed tag. The old
tag still exists.

Direction:

- If feasible, delete or move the stale local/remote `0.0.1` tag.
- If preserving history is preferred, the current `docs/RELEASES.md` warning is
  adequate.

Ambiguity required to act: changing published tags is a maintainer policy
decision.

## Closed Or Mostly Addressed Since The Original Critiques

These items should not remain in the live priority list except as regression
checks.

- **Legal usability:** root `LICENSE` exists and `package.json` has MIT license
  metadata.
- **Security/contribution basics:** `SECURITY.md` and `CONTRIBUTING.md` exist.
- **Vendored license/provenance:** `Vendor/UnixSignals` now has
  `LICENSE.txt`, `NOTICE.txt`, and `CONTRIBUTORS.txt`; `Vendor/swift-figlet`
  has a `LICENSE`.
- **Release posture:** README points at `0.1.0`, and `docs/RELEASES.md`
  describes alpha versioning and release gates.
- **README maturity calibration:** README now states pre-1.0,
  single-maintainer, AI-assisted status near the top.
- **README installation:** README now includes a SwiftPM dependency snippet.
- **Support matrix/product tiers:** README now has a support matrix and product
  tiers; `WASISurfaceBridge` is described as package-only plumbing.
- **TODO contradiction:** `docs/TODO.md` is no longer empty; it contains current
  unresolved decisions and planned work.
- **CI source configuration:** CI triggers, Swiftly install, policy checks,
  macOS gate, and iOS build are present in the workflow file.
- **Public binding correctness:** `Binding.init(get:set:)` now takes
  `@MainActor` closures directly.
- **Color parsing crash:** `Color.hex(_:)` now throws instead of trapping on
  invalid caller input.
- **WebHost infinite sync wait:** WebHost sending now has a timeout and explicit
  send errors. A deeper async presentation seam may still be desirable, but the
  unbounded wait finding is closed.
- **Default launcher traps:** terminal and WebHost default `App.main()` paths now
  report launch errors through `exitLaunch(withError:)`.
- **SwiftUIHost stale frames:** `SwiftUIHostSceneHost` tracks latest frame
  sequence and drops older frames; tests cover stale-frame dropping.
- **Graph registry cleanup:** `StateBox` and `GestureStateBox` now call
  registry `forget` on deinit.
- **`@Environment`:** a public `Environment` property wrapper now exists.
- **`View.id(_:)`:** public `View.id` now accepts arbitrary `Hashable`.

## Ambiguities To Resolve Before Acting

These are the decisions most likely to block implementation or cause churn if
skipped.

1. Is `mise.toml` an endorsed contributor/release entrypoint or a private
   convenience file?
2. Should CI branch protection be mandatory for `main`, and which statuses are
   required?
3. Should coverage reporting be informational first, or should it enforce a
   threshold immediately?
4. Should rendered fixture updates remain environment-variable driven, or move
   to a dedicated explicit recording command?
5. Should SwiftTUI navigation keep SwiftUI names while documenting divergence,
   rename the current API, or add path/link compatibility?
6. Should presented content get a public SwiftUI-like `DismissAction`, or should
   dismissal remain binding/closure driven?
7. Should `WASISurfaceBridge` remain an external SwiftPM product with real
   public API, or become internal package plumbing only?
8. Does every public product need a DocC catalog, or are platform products
   intentionally prose-documented?
9. Are historical plans allowed to retain stale paths as historical records, or
   must all tracked docs remain path-current?
10. Is the project name final despite the ecosystem collision?

## Suggested Next Tranche

The highest-signal next work is a small remediation tranche, not a broad
architecture rewrite:

1. Remove `@openai/codex` from project dependencies.
2. Fix or delete `mise.toml` release tasks and pin endorsed tool versions.
3. Add `SwiftTUITerminalWorkspaceTests` to the gate and add a target-coverage
   meta-check.
4. Make rendered fixture recording explicit-only.
5. Replace the WASI `#expect(Bool(true))` branch.
6. Add coverage reporting without failing thresholds.
7. Fix the stale `drawnIdentities` comment.
8. Decide the navigation/dismiss/WASISurfaceBridge ambiguities before starting
   public API churn.
