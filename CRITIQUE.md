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
2. enforce public documentation coverage with a ratchet
3. decide whether coverage reporting remains informational or becomes a threshold
4. settle the platform-product DocC strategy
5. reduce maintenance load in the largest runtime files and stale historical docs

## Severity Legend

- **P0**: blocks adoption, release trust, or runtime safety
- **P1**: important correctness, test, or public API issue
- **P2**: scheduled quality work
- **P3**: opportunistic cleanup
- **Closed**: materially addressed in the current tree
- **Ambiguous**: needs a product or governance decision before implementation

## Ranked Current Critique

### 1. CI Is Configured, But Enforcement Still Needs External Proof

Status: **P0 / partially addressed / external verification needed**

The local workflow file has been materially repaired:
`.github/workflows/run-tests-linux.yml` now has `push`, `pull_request`, and
`workflow_dispatch` triggers; installs Swiftly; runs policy checks; runs Linux
and macOS repo gates; and includes a generic iOS package build. Follow-up CI
log review also repaired runner bootstrap drift: Linux jobs now install
Swiftly's required `libcurl4-openssl-dev` dependency before selecting Swift
6.3.1, and the generic iOS package build selects an Xcode installation with
Swift 6.3 support instead of the runner's older default Xcode.

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

### 2. Personal Workflow Tooling No Longer Leaks Into Project Dependencies

Status: **Closed**

The root Bun workspace no longer installs `@openai/codex` as project
functionality.

Current evidence:

- `package.json` has no `dependencies` section.
- `bun.lock` no longer contains `@openai/codex` or its platform packages.

Regression guard: keep personal AI tools out of checked-in project dependency
graphs unless a repo-owned script truly needs them.

### 3. Local Tool-Manager Configuration Is No Longer An Endorsed Entrypoint

Status: **Closed**

The repo's written policy says repo-local Swift work uses
`swiftly run swift ...`. The stale tracked `mise.toml` release tasks have been
removed, and `mise.toml` is now ignored as private local tooling.

Current evidence:

- `mise.toml` is not tracked.
- `.gitignore` ignores local `mise.toml`.
- `docs/TOOLCHAINS.md` and README continue to make `swiftly run swift ...` the
  repo path.

Regression guard: if a tool-manager file becomes an endorsed project entrypoint
later, it should be pinned and call `swiftly run swift ...`.

### 4. The Test Gate Now Covers Declared Root Test Targets

Status: **Closed**

`Scripts/test_all.sh` now runs `SwiftTUITerminalWorkspaceTests`, and a
meta-check keeps the hand-maintained filter list aligned with root
`Package.swift` test targets.

Current evidence:

- `Scripts/test_all.sh` includes `SwiftTUITerminalWorkspaceTests`.
- `Scripts/check_root_test_target_coverage.sh` fails when a root test target is
  declared but not covered by `Scripts/test_all.sh`.
- `Scripts/test_gate.sh` delegates to `Scripts/test_all.sh`, so the curated gate
  inherits the same guardrail.

Regression guard: keep the meta-check in the gate before adding new root test
targets.

### 5. Coverage And Fixture Discipline Have Baseline Guardrails

Status: **P1 / mostly addressed / threshold decision remains**

The suite now has an informational coverage command, fixture recording is routed
through an explicit script instead of the old direct environment variable, the
gate fails if recording mode is enabled, and the WASI tautology assertion has
been replaced.

Current evidence:

- `bun run test:coverage` runs `Scripts/report_test_coverage.sh`, which invokes
  `swiftly run swift test --enable-code-coverage` and prints coverage output.
- `Scripts/record_rendered_text_fixtures.sh` is the fixture update entrypoint.
- `Scripts/test_all.sh` fails if rendered fixture recording variables are set.
- `Scripts/check_rendered_text_fixture_matrix.sh` is part of the gate.
- The WASI runner test now asserts default transport-mode behavior under
  `canImport(WASILibc)`.

Direction:

- Decide later whether coverage should stay informational or become a failing
  threshold.
- Consider publishing the coverage JSON as a CI artifact once external workflow
  status is verified.

Ambiguity required to act: coverage thresholds are still a governance decision.

### 6. SwiftUI-Shaped Navigation And Dismissal Policy Is Recorded

Status: **Closed**

The major API ambiguity in this tranche is closed without renaming the shipped
navigation surface.

Current decision:

- Keep the SwiftUI names `NavigationStack` and `.navigationDestination(...)`.
- Document that SwiftTUI's terminal contract is intentionally binding-driven:
  Boolean and item bindings own destination presentation.
- Keep public `NavigationLink`, public `NavigationPath`, and environment
  navigation controllers outside the shipped v1 surface.
- Explicitly exclude `@Environment(\.dismiss)` by policy. Presented content
  should dismiss through owner-controlled bindings, explicit callbacks, or the
  runtime dismiss stack such as Escape handling.

Current evidence:

- `docs/decisions/0001-swiftui-shaped-not-bubbletea-shaped.md` codifies the
  keep-the-SwiftUI-name policy for `NavigationStack` and the exclusion of
  `@Environment(\.dismiss)`.
- `docs/proposals/NAVIGATION_DESTINATION_PRESENTATION.md` records the shipped
  name and dismissal policy next to the v1 navigation proposal.
- `docs/STATUS.md` and `docs/PUBLIC_API_INVENTORY.md` describe the same public
  surface.

Residual additive API polish, such as `.sheet(item:)`, `onDismiss:` overloads,
or moving `snapshotLabel` behind a diagnostics-only seam, can be triaged as
ordinary public-surface cleanup. It no longer blocks the navigation/dismissal
policy decision.

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

### 8. `WASISurfaceBridge` Product Boundary Is Settled

Status: **Closed**

`WASISurfaceBridge` is package-only plumbing, not an ordinary external SwiftPM
product.

Current evidence:

- `Package.swift` declares `WASISurfaceBridge` as a target consumed by
  `SwiftTUIWASI` and `SwiftTUIWebHost`, not as a public `.library` product.
- The README describes the `WASISurfaceBridge` transport target as package-only
  plumbing used by `SwiftTUIWASI` and `SwiftTUIWebHost`.

Regression guard: do not add a standalone public `WASISurfaceBridge` product
unless the bridge gets a documented public transport API and stability tier.

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
shape. The active `drawnIdentities` behavioral comment has been corrected, but
stale source-path material still exists in historical plans.

Current evidence:

- Many `docs/plans` and historical proposal files still refer to old
  `Sources/SwiftTUI/...` paths.

Direction:

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

1. Should CI branch protection be mandatory for `main`, and which statuses are
   required?
2. Should coverage reporting be informational first, or should it enforce a
   threshold immediately?
3. Does every public product need a DocC catalog, or are platform products
   intentionally prose-documented?
4. Are historical plans allowed to retain stale paths as historical records, or
   must all tracked docs remain path-current?
5. Is the project name final despite the ecosystem collision?

## Suggested Next Tranche

The highest-signal next work is now external enforcement and documentation
ratchets, not navigation/dismissal/product-boundary churn:

1. Verify GitHub Actions are green and branch protection requires the intended
   statuses.
2. Add public documentation coverage with a ratchet rather than an immediate
   zero-baseline strict gate.
3. Decide whether coverage reporting stays informational or becomes a threshold.
4. Decide the platform-product DocC strategy.
5. Start the large-runtime-file decomposition only after the gate stays green.
