# SwiftTUI — A Critical Assessment

*Produced 2026-05-15 by Claude (Opus 4.7). Method: six parallel domain audits
(API/usability, architecture, infrastructure/CI, testing, governance/docs, Swift
code quality), each independently evidenced, followed by first-hand verification
of every Critical and High finding. This document is deliberately weighted toward
constructive criticism; a calibration section near the end records what the
project gets right, because a critique that ignores genuine strengths is easy to
dismiss.*

---

## Scope and method

This assessment covers infrastructure, architecture, public API, testing, and
project governance for the `swift-tui` repository as of commit `dec7bc60` on
`main`. It is based on reading — ~90k lines of Swift source, ~66k lines of test
code, 122 design documents, the build and CI configuration, and git history. It
did **not** run the build or the test suite, and it is **not** a security audit
(the five merged `fix-*-vulnerability` branches are taken at face value). The API
critique comes from reading the surface, not from writing a real application
against it. Line numbers are cited where verified directly; where a citation
comes from a sub-audit it is phrased so the finding does not collapse if a number
is slightly off.

Severity is assigned **relative to how the project presents itself** — a publicly
documented framework with a marketing site and published-looking packages — not
relative to "a personal weekend project," which would not warrant most of this.

---

## Executive summary

SwiftTUI is a substantial and, in places, genuinely sophisticated piece of
engineering: a real seven-phase layout/render pipeline, a SwiftUI-shaped authoring
surface, and working terminal / WASI / browser / SwiftUI-embedding hosts, built in
roughly seven weeks. The code *inside* the files is, for the most part, clean,
concurrency-disciplined, and well-tested.

The problem is not the engineering. It is that the project is wrapped in the
**presentation** of a mature, adoptable framework — a logo, a marketing site at
swifttui.io, 122 design documents, a "doctrine" — while lacking the **substance**
of one. It has no licence, so it is currently not legally usable by anyone. It has
no real release. Its continuous integration runs nothing automatically and, when
manually triggered, fails. Its declared primary platform (macOS) is never built or
tested by any automation. It has exactly one human contributor and no second
reviewer anywhere in the loop. The gap between how serious the project *looks* and
how serious it currently is to *depend on* is the throughline of everything below.

The single highest-value action is small and non-technical: decide whether this is
a personal project (in which case the marketing surface oversells it) or a
framework meant to be used (in which case the licence, release, and CI gaps are
disqualifying and must be closed before any further promotion).

## Severity counts

| Severity | Count | Meaning |
|----------|-------|---------|
| Critical | 4  | Blocks adoption or legal use; or removes all automated safety. |
| High     | 12 | Serious defect, correctness hazard, or major gap vs. stated goals. |
| Medium   | 25 | Real problem worth scheduled work; erodes quality or trust. |
| Low      | 16 | Minor; worth fixing opportunistically. |
| Nit      | 4  | Cosmetic. |
| **Total**| **61** | |

---

## Three framing observations

Most individual findings are instances of one of three patterns. They are worth
stating once, up front, because fixing the pattern is cheaper than fixing 61
symptoms.

**1. Presented maturity exceeds possessed maturity.** The repository has a `logo/`
directory (with a Pixelmator source file), an Astro marketing website, a published
DocC site, 122 markdown design documents including formal ADRs and a
"TERMINAL_NATIVE_DOCTRINE," and a README describing 14 products as accomplished
fact. Against that, the project is ~7 weeks old, has one contributor, no licence,
and one git tag pointing at a commit titled "TEMP." Every artifact that signals
maturity is present; most artifacts that *constitute* it are not. A reader cannot,
from the landing page, tell that this is pre-1.0, single-maintainer, and
API-unstable — and nothing on that page tells them.

**2. Inward-facing rigor, outward-facing neglect.** The project polices its own
internal consistency obsessively: seven pre-commit hooks, a public-API surface
policy with a committed machine-generated baseline, a structured-concurrency
escape-hatch ban, a terminology doctrine, accessibility guardrails. It enforces
import ordering. It does **not** enforce — or even provide — the external contract
with a user: a licence to compile the code, a release to depend on, a CI run to
prove a change works, a way to report a security bug. The discipline is real, but
it is pointed entirely inward.

**3. Process artifacts have outrun the ability to keep them true.** At ~25 commits
a day, single-author, the project generates governance scaffolding faster than it
can be kept accurate. The canonical work tracker (`docs/TODO.md`) is empty of
tasks. The ADR process documents "Reviewers" who do not exist. Six policy scripts
are wired into nothing. Documentation cites source paths under a directory that
was renamed. The scaffolding *looks* like rigor; in several concrete places it has
decoupled from reality, which is worse than not having it, because it misleads.

---

## G · Project seriousness & governance

*Domain assessment: the engineering is serious; the project, as a project, is not
yet — it is a serious prototype presented as a shipping framework.*

#### G1 · No `LICENSE` file — the project is not legally usable · **Critical**

**Evidence.** No `LICENSE` / `LICENSE.md` / `LICENSE.txt` / `COPYING` at the repo
root (`ls LICENSE*` → no matches; `git ls-files | grep -i licen` returns only
three *vendored* licences). No `license` field in the root `package.json`, in the
`@swifttui/web` / `@swifttui/build` manifests, or in `Package.swift`. The README
explicitly instructs readers to "depend on the `SwiftTUI` product," and a live API
reference is published at swifttui.io.

**Why it matters.** Under default copyright law, source published with no licence
grants **no** right to use, copy, modify, or distribute it. Every instruction in
the README to depend on SwiftTUI currently asks the reader to commit a copyright
violation. This is not an early-project formality gap — it is a hard blocker, made
conspicuous by the contrasting investment in a logo, a website, and 122 docs.

**Direction.** Add a top-level `LICENSE` before any further public promotion.
Apple's Swift open-source projects use Apache-2.0-with-runtime-exception; MIT is
the lighter common choice. Add a `license` field to every `package.json`.

#### G2 · The only release tag, `0.0.1`, points at a commit titled "TEMP" · **High**

**Evidence.** `git tag` → exactly one tag. `git show 0.0.1` → commit `c90c2b8f`,
message **"TEMP: Vendor file:// URL workaround for unidoc"**, authored by
`local <local@local>` on 2026-04-27. `git rev-list 0.0.1..HEAD --count` → **500**.
No GitHub releases, no semver progression, no release notes.

**Why it matters.** The one "version" of this software is anchored to an explicitly
temporary tooling-hack commit, by an anonymized/misconfigured git identity, now 500
commits stale. Anyone pinning a SwiftPM dependency to `0.0.1` gets that. There is
effectively no released version of SwiftTUI — which directly contradicts the
maturity implied by the live docs site.

**Direction.** Cut a genuine `0.1.0` from a clean commit with release notes; adopt
semver; delete or re-point the misleading `0.0.1` tag.

#### G3 · `docs/TODO.md` — the tracker four documents call canonical — has zero tasks · **Medium**

**Evidence.** `docs/TODO.md` is 26 lines: a `## Rules` section describing how the
file should be used, and **no task entries**. The README ("use `docs/TODO.md` as
the live tracker"), `AGENTS.md`, `STATUS.md` ("Any gap … must have a corresponding
item here"), and `docs/README.md` all route the reader to it as the work queue.
Meanwhile `STATUS.md`'s "Current Constraints" lists ~10 deferred items and
`VISION.md` lists deferrals (`NavigationLink`, IME, process reattachment).

**Why it matters.** This is a concrete internal contradiction: four documents point
at a tracker that tracks nothing, while the actual deferred work lives only in
prose elsewhere. It is the clearest single instance of framing observation #3 —
process scaffolding that has decoupled from reality.

**Direction.** Either populate `TODO.md` from the deferral lists already written in
`STATUS.md`/`VISION.md`, or delete it and the four cross-references and state
plainly that deferred work is tracked narratively in `STATUS.md`.

#### G4 · No `CONTRIBUTING`, `SECURITY`, `CODE_OF_CONDUCT`, or issue/PR templates · **Medium**

**Evidence.** None of these files exist; `.github/` contains only `workflows/`.
Notably, git history shows real security work — merged branches
`fix-png-decoder-memory-vulnerability`,
`fix-text-rendering-terminal-injection-vulnerability`,
`fix-unsanitized-osc-8-link-destinations`, `fix-unbounded-textfigure-metrics-cache`,
`propose-fix-for-@state-session-vulnerability`.

**Why it matters.** For a pre-1.0 solo project these files are individually
optional; their *total* absence alongside a public site signals the project has
not crossed from "personal repo" to "thing others are invited into." The missing
`SECURITY.md` is the most defensible concern: the project has a demonstrated
security surface (memory bugs in image decoding, terminal escape-sequence
injection), and a downstream user who finds a sandbox-escape has no private
disclosure channel.

**Direction.** Add a minimal `SECURITY.md` (a contact address and a "pre-1.0, no
SLA" disclaimer suffices) and a short `CONTRIBUTING.md` pointing at `AGENTS.md` and
`docs/README.md`. CoC and templates can wait until there are contributors.

#### G5 · The README presents a shipping framework with no maturity calibration · **Medium**

**Evidence.** The 12.6 KB README describes 14 products, multiple runners/hosts,
WASI/web/browser deployment, "first-class terminal workspaces," and a live API
site. It contains no version badge, no "alpha / experimental / pre-1.0" notice, no
project-age or API-stability statement. It states capability as fact
("`SwiftTUITerminalWorkspace` provides first-class terminal workspaces"). The
honest caveats exist — `STATUS.md` and `VISION.md` are candid — but one click away.

**Why it matters.** The README is accurate about *what exists*; no false feature
claims were found. The defect is calibration-by-omission: a reader landing on the
README has no signal that this is single-author, ~7 weeks old, with zero real
releases and (G1) no licence. The confident tone materially overstates how safe it
is to depend on this today.

**Direction.** Add a three-sentence stability banner near the top of the README:
pre-1.0, single-maintainer, API unstable, licence pending. This converts the
project's *actual* honesty (which lives in `STATUS.md`) into honesty a casual
reader will see.

#### G6 · 122 documents / ~372k words is a maintenance liability for one person · **Medium**

**Evidence.** 122 tracked markdown files under `docs/` (`docs/plans/` 37 files,
`docs/proposals/` 36, `docs/decisions/` 18), with single plan documents exceeding
3,000 lines and proposals exceeding 90 KB. That is roughly 2.4 doc-words per line
of Swift.

**Why it matters.** This cuts both ways and the strength is acknowledged in §"What
the project gets right." But 372k words is a corpus one maintainer cannot keep
accurate indefinitely as ~25 commits/day reshape the code — and drift has already
begun (see A5). The `plans/` directory is the weak form: ~30k lines of dated,
mostly already-shipped implementation plans whose only ongoing cost is being kept
from contradicting current reality. A reader cannot tell which of 122 files is
authoritative versus historical.

**Direction.** Move shipped plans into a clearly-labelled `docs/plans/archive/` (or
a git tag). Maintain only the durable source-of-truth set (`ARCHITECTURE`,
`RUNTIME`, `STATUS`, `VISION`, ADRs, policies). Resist writing new long-form
`proposals/` for features that have already shipped.

#### G7 · The ADR process documents a review step that cannot exist · **Low**

**Evidence.** `docs/decisions/README.md`, "How an ADR comes into being," step 3:
"Reviewers verify the ADR matches the change." `git shortlog -sne` → 1,248 commits
`adamz`, 2 `Claude`, 1 `local`. There are no reviewers.

**Why it matters.** The ADR system itself is genuinely good (see strengths). But
describing a peer-review gate on a single-author repository overstates how
decisions are actually vetted — a careful reader notices the workflow is fictional,
and that undermines trust in the rest of the doc set.

**Direction.** Reword to reflect reality: "the author self-reviews the ADR against
the change." Honesty about being solo is more credible than implying a team.

#### G8 · Name collision with the established incumbent in the same niche · **Medium**

**Evidence.** `gh search repos SwiftTUI` returns `rensbreur/SwiftTUI` at **1,504
stars** — *the* well-known SwiftUI-inspired terminal-UI framework, years old — plus
`bannzai/SwiftTUI`, `finnvoor/SwiftTUI`, `rxtech-lab/SwiftTUI`. This project took
the identical project name, identical umbrella module name, and identical
`import SwiftTUI` statement, in the identical problem domain.

**Why it matters.** A project intended to be adopted must be findable and
unambiguous. "Should I use SwiftTUI?" is now a question with at least five
answers; search, attribution, and any future package-registry publication all
collide with a 1,500-star incumbent. This is a positioning problem, not a
nitpick — it directly affects whether anyone can discover or correctly refer to
this project.

**Direction.** Consider a distinct name before promotion (the marketing domain
swifttui.io is already a partial commitment, which makes this costly — another
reason to decide early). At minimum, the README should acknowledge the other
project to reduce confusion.

#### G9 · Inconsistent, low-information commit messages · **Low**

**Evidence.** Of the last 300 commit subjects, roughly 140 have no
conventional-commit prefix; recent examples include bare `layout`, `web`,
`logo updates`, `keyboard movement for layout`. The other ~160 do use prefixes
(`feat:`, `fix:`, `docs:`), interleaved with no era boundary.

**Why it matters.** Minor and common in solo repos — but the project imposes strict
conventions on itself everywhere else (pre-commit hooks, surface policy, a
changelog hash-prefix rule). The commit log is the one place that discipline
lapsed, and one-word subjects degrade `git bisect`/`git log` archaeology — which
matters precisely because history is the only "why" record on a bus-factor-one
codebase.

**Direction.** Commit to conventional prefixes (the project already half-does it)
or at minimum require informative subjects; a `commit-msg` hook would enforce it.

#### G10 · Bus-factor of one, with an AI co-author and no second human · **Medium**

**Evidence.** ~1,250 commits in ~7 weeks (~25/day) — a rate only sustainable with
heavy automation. `AGENTS.md` is addressed to "Claude Code and other agentic
assistants." `@openai/codex` is a committed dependency. Two commits are authored by
`Claude`; a `claude/review-runners-hosts-*` branch exists.

**Why it matters.** AI assistance is not itself a defect, and the evidence is
genuinely mixed: the code is clean, the durable docs are internally consistent and
actively maintained — this is *not* "AI slop." But ~25 commits/day single-author
means no other human has reviewed any of this; the "Reviewers" step is fictional
(G7); the project is exactly one person's mental model deep. For something
presented as an adoptable framework, that bus factor is the core seriousness risk,
and it is currently undisclosed.

**Direction.** This is not a thing to "fix" — it is a thing to *state*. An honest
README/`CONTRIBUTING` note that the project is AI-assisted, single-maintainer, and
not yet reviewed by anyone else lets adopters price the risk correctly.

#### G11 · Merged branches and worktrees left uncleaned · **Nit**

**Evidence.** Six local feature branches (`popovers`, `scroll`, `webhost`,
`workspace`, `graphs`, `feature/terminal-scene-sizing`) plus a `claude/review-*`
branch; seven worktrees including a `prunable` one under `/private/tmp`. All seven
branches are already ancestors of `main`.

**Why it matters.** This is not parallel half-finished work — it is unpruned cruft.
The only cost is that a newcomer cloning the repo sees six "feature" branches and
reasonably infers in-flight work that does not exist.

**Direction.** `git branch -d` the merged branches; `git worktree prune`.

---

## I · Infrastructure, CI/CD & tooling

*Domain assessment: the infrastructure looks mature — SBOMs, injection-hardened
workflows, a devcontainer, a 737-line gate script — but the load-bearing piece is
missing: nothing runs automatically, and the one workflow that exists cannot pass.*

#### I1 · Continuous integration runs nothing automatically — auto-testing was deliberately disabled · **Critical**

**Evidence.** Commit `0dffff25` (adamz, 2026-05-02), message **"disable ci
auto-test"**, removes the `push:` and `pull_request:` triggers from
`run-tests-linux.yml`. All four workflows are now `workflow_dispatch`-only, except
`build-linux-image.yml`, which triggers only on Dockerfile changes and runs **no
tests**. There is no branch protection on `main` (`gh api …/branches/main/protection`
→ 404).

**Why it matters.** A ~90k-line framework with 14+ products has zero automated
checks gating any change. Nothing builds, tests, or lints a push or a PR. For a
project that ships an `AGENTS.md` and invites contribution, a contributor's PR
receives no feedback at all.

**Direction.** Restore `push`/`pull_request` triggers on a working test workflow
(see I2); enable branch protection on `main` with that workflow as a required
status check.

#### I2 · The one test workflow cannot pass — its last six runs all failed · **Critical**

**Evidence.** `run-tests-linux.yml` installs Swift via `swift-actions/setup-swift`,
which puts a toolchain on `PATH` but does **not** install `swiftly`. The gate it
runs (`test_all.sh`) hard-requires `swiftly` (`require_command swiftly`) and shells
every build through `swiftly run swift …`. Result: `Missing required command:
swiftly`. `gh run list --workflow=run-tests-linux.yml` shows the last **six** runs
all `failure` — and the two oldest were `push`-triggered (2026-05-02), i.e. CI was
already red *before* I1 disabled the triggers.

**Why it matters.** Even a manually dispatched test run cannot pass. The workflow
and the gate disagree on the toolchain manager, and because the workflow never runs
automatically, the rot went unnoticed. The narrative this evidence supports —
CI broke, then auto-triggering was removed rather than the break fixed — is the
most concerning version of I1.

**Direction.** Install `swiftly` in the workflow; the project's own
`perf-smoke.yml` and `cloudflare-pages.yml` already contain a correct,
copy-pasteable `swiftly` install block.

#### I3 · No macOS or iOS CI, although macOS is the declared primary platform · **Critical**

**Evidence.** README: "Currently fully supported: macOS 15+." `Package.swift`
declares `.macOS(.v15)` and `.iOS(.v18)`. The only test workflow runs on
`ubuntu-latest`. No workflow invokes `xcodebuild` or a macOS/iOS destination. The
two `macos-26` jobs that exist (`perf-smoke`, `cloudflare-pages`) run perf and the
website deploy — neither runs the test suite. The Apple-only surface — `SwiftUIHost`,
`Examples/SwiftUIExample`'s Xcode project, `Examples/LayoutsSwiftUI` — is built by
no automation.

**Why it matters.** The framework's flagship supported platform and its
Apple-specific code are never exercised by CI. The only platform CI ever attempts
is Linux — explicitly the *non*-primary platform, the one needing the
`DISABLE_EXPLICIT_PLATFORMS` hack (I7). A macOS- or iOS-breaking change sails
through.

**Direction.** Add a `macos-26` job running the full gate (it already branches
correctly for Apple hosts); add at minimum an `xcodebuild -destination
'generic/platform=iOS'` build.

#### I4 · The entire quality gate lives in skippable local pre-commit hooks · **High**

**Evidence.** The seven `prek` hooks (swift-format, no-Foundation-in-library,
public-surface-policy, structured-concurrency-escape-hatch ban, accessibility
guardrails, main-thread usage, doc-frontmatter) are git pre-commit hooks — local,
bypassed by `git commit --no-verify`, and not run by anyone who clones without
running `prek install`. No workflow invokes `prek` or any `check_*.sh`. The four
policy scripts that *are* wired into `test_all.sh` only run via the broken/dispatch
workflow (I1/I2), i.e. effectively never.

**Why it matters.** Every guardrail the project built — surface freezes,
Foundation-free enforcement, the concurrency escape-hatch ban — enforces nothing
against a PR. Substantial engineering invested in `check_*.sh` is wasted without a
CI enforcement point.

**Direction.** Run `prek run --all-files` (or the `check_*.sh` set) as a fast,
required CI job on every PR, independent of the slower Swift build/test job.

#### I5 · `@openai/codex` is a production `dependency` of the workspace · **High**

**Evidence.** Root `package.json` lists `"@openai/codex": "^0.121.0"` under
`dependencies` (not `devDependencies`). `bun.lock` pulls it plus seven
platform-specific binary sub-packages; it is installed in CI on every
`bun install --frozen-lockfile`. No build script, test, or workspace package
imports or invokes `codex` — it is an AI coding CLI, not a build tool.

**Why it matters.** An AI CLI as a runtime dependency is wrong on every axis: it
implies the products need it (they do not); it bloats every install for every
contributor and CI run; it adds a frequently-updated, caret-ranged binary to the
supply-chain surface for zero functional gain; and it leaks the maintainer's
personal workflow into the project's published manifest.

**Direction.** Remove `@openai/codex` from `package.json` entirely. Install it
globally or in personal dotfiles if wanted.

#### I6 · A vendored Apache-2.0 package has had its licence file stripped · **Medium**

**Evidence.** `Vendor/UnixSignals/Sources/UnixSignals/UnixSignal.swift` header:
"This source file is part of the SwiftServiceLifecycle open source project /
Copyright (c) 2023 Apple Inc. … / Licensed under Apache License v2.0 / See
LICENSE.txt … / See CONTRIBUTORS.txt … / SPDX-License-Identifier: Apache-2.0" — with
a `// © GoodHatsLLC` line prepended. `find Vendor/UnixSignals` for any
licence/notice/contributors file returns **nothing**. `Vendor/swift-figlet` also
has no `LICENSE`.

**Why it matters.** Apache-2.0 §4 requires the licence text and attribution travel
with redistributed copies. `UnixSignals` is a redistributed derivative of Apple
code, and the vendored copy strips the very `LICENSE.txt`/`CONTRIBUTORS.txt` its own
header points readers to, while adding a copyright line on top. That is a licence
compliance defect, and it compounds G1.

**Direction.** Restore `LICENSE.txt` + `CONTRIBUTORS.txt`/`NOTICE` to
`Vendor/UnixSignals/`; add a `LICENSE` to `Vendor/swift-figlet/`.

#### I7 · `Package.swift` reads an environment variable to decide its declared platforms · **Medium**

**Evidence.** `Package.swift:14` — `let explicitPlatforms = ProcessInfo…
environment["DISABLE_EXPLICIT_PLATFORMS"] != "1"`; when set, the manifest drops
`.macOS(.v15)`/`.iOS(.v18)`. The identical pattern is copy-pasted into the
`Package.swift` of four vendored packages. It is set by `test_all.sh`,
`Scripts/linux.sh`, and `.devcontainer`.

**Why it matters.** A package manifest should be deterministic. Making the package
*graph* depend on an ambient env var means `swift build` produces a different
package depending on the environment — an undocumented, load-bearing config smell
threaded through five manifests.

**Direction.** Investigate whether the explicit `platforms:` block is needed at all
(Linux builds ignore Apple platform pins). If a Linux-specific manifest is genuinely
required, use one documented mechanism, not an env var read by five manifests.

#### I8 · Vendored packages are flat, un-pristine snapshots with no provenance · **Medium**

**Evidence.** `Vendor/` is 346 tracked files across five `path:`-dependency
packages. None are git submodules; none retain a `.git`; none record an upstream
URL or source commit. At least three are known-modified (the I7 hack), so they are
not pristine.

**Why it matters.** Vendoring by flat copy with no recorded upstream commit means
there is no update story — nobody can 3-way-merge against upstream, audit
divergence, or pick up a security fix without manually re-diffing, and a naive
re-vendor silently drops local patches.

**Direction.** Use git submodules pinned to a commit, or add a `Vendor/README.md`
per package recording upstream URL, source commit, and the list of intentional
local patches.

#### I9 · The toolchain stack is ~7 layers, several pinned to `latest` · **Medium**

**Evidence.** A contributor must install and understand `mise`, `swiftly`, `bun`,
`prek`, `swift-format`, `cspell` (and `codex` arrives via I5). `mise.toml` pins
`bun` and `prek` to `latest`; `swiftly` is unpinned in most install paths. Only
`.swift-version` (6.3.1) and the wasm SDK checksum are genuinely pinned.

**Why it matters.** Three layers resolve to `latest`, so two contributors
onboarding a week apart get different toolchains — undermining the reproducibility
that adopting `mise`/`swiftly` is meant to provide. Onboarding cost is high; the
README spends two paragraphs just on *not* using bare `swift`.

**Direction.** Pin exact versions for `bun`, `prek`, and `swiftly`; document the
`mise` bootstrap step in the README's "Development Requirements."

#### I10 · `.swift-format.json` disables the rules that would catch this critique's own findings · **Medium**

**Evidence.** `.swift-format.json` `rules`: `AllPublicDeclarationsHaveDocumentation:
false`, `NeverForceUnwrap: false`, `NeverUseForceTry: false`,
`NeverUseImplicitlyUnwrappedOptionals: false`, `ValidateDocumentationComments:
false`, `BeginDocumentationCommentWithOneLineSummary: false`.

**Why it matters.** `swift-format` is wired into the pre-commit hook, so it runs on
every commit — but it is configured *not* to flag missing public-API documentation
(see U10, ~25% coverage), force-`try` (see C1, the `Color.hex` crash), or
force-unwraps. The checks exist in the tool and are switched off. The project has a
lint pass that is configured to not see real problems.

**Direction.** Re-enable `NeverUseForceTry` and `AllPublicDeclarationsHaveDocumentation`
(at least as warnings) and let them drive the cleanup in C1 and U10.

#### I11 · `perf-smoke` is a perf *archive*, not a perf *gate* · **Low**

**Evidence.** Job name: "Archive non-failing perf smoke artifacts."
`run_perf_smoke.sh` has no threshold and never exits non-zero on regression. The
workflow is `workflow_dispatch`-only.

**Why it matters.** It can never catch a latency regression — nothing compares
against a baseline or fails the build. The README's performance-evaluation tooling
has no automated regression guard.

**Direction.** If perf matters, store a baseline and fail the job past a threshold;
otherwise document it as a manual-only diagnostic.

#### I12 · Six `check_*.sh` scripts are wired into no runner and no hook · **Low**

**Evidence.** `check_demo_builds.sh`, `check_gitviz_smoke.sh`,
`check_rendered_text_fixture_matrix.sh`, `check_view_protocol_shape.sh` are
referenced by no runner; two more run only via `prek`. `check_demo_builds.sh` in
particular builds every demo/host (including the macOS-only surface missing from
I3) and runs an input fuzzer.

**Why it matters.** Dead automation gives a false sense of coverage and bit-rots
silently. `check_demo_builds.sh` is real verification value left on the floor.

**Direction.** Wire the orphans into `test_all.sh`/CI or delete them.

#### I13 · GitHub Actions pinned to the deprecated Node-20 runtime · **Low**

**Evidence.** Workflow runs emit a deprecation warning for `actions/checkout@v4`,
`actions/cache@v4`, and `swift-actions/setup-swift@v3`; Node 20 is removed from
runners in September 2026.

**Direction.** Bump to Node-24-compatible action versions before September 2026.

#### I14 · Repository-root clutter · **Nit**

**Evidence.** `nyan.gif` (a demo asset for `Examples/gifcat`) and `logo/logo.pxd`
(a Pixelmator design source) sit at or near the repo root; `.DS_Store` is present
on disk (correctly untracked, but `.gitignore` lacks an explicit `.DS_Store` line).

**Direction.** Move `nyan.gif` under `Examples/gifcat/`; add `.DS_Store` to
`.gitignore` explicitly.

---

## A · Architecture & module design

*Domain assessment: macro-structure is sound — a principled phased pipeline, clean
acyclic module layering — but several modules contain god-objects, and the phase
boundaries are looser in the type system than the doctrine claims.*

#### A1 · Oversized files and functions · **High**

**Evidence.** 22 files exceed 800 lines. The largest:
`SwiftTUIRuntime/SwiftTUI.swift` 2,724; `AnimationController.swift` 2,509;
`TerminalHost.swift` 2,325; `ViewGraph.swift` 1,672. The largest functions:
`renderPendingFramesAsync` ~480 lines at ~9 levels of indentation;
`childPlacements` ~468; `renderPendingFrames` ~355; `processResolvedTree` ~291.
`AnimationController` is a single class whose `Checkpoint` struct has 22 stored
fields and which implements three sink protocols at once. The project's own
argument-parsing plan states new files "target 200–400 lines per the project's
coding style" (`docs/plans/2026-05-04-002-argument-parsing-plan.md:112`) — so
`SwiftTUI.swift` is roughly 7× the project's own referenced norm.

**Why it matters.** Most of these files are internally cohesive — a 22-field
checkpoint is not random — but cohesion does not make a 480-line, 9-deep function
reviewable, unit-testable, or safe to edit. The worst offender,
`renderPendingFramesAsync`, is in the highest-churn, highest-risk code in the
project. A 22-field god-object also makes ownership unclear: a change to transition
removal logic forces re-reasoning about matched-geometry capture because they share
one `self`.

**Direction.** Split `AnimationController` along its three sink protocols
(`PropertyAnimationController` / `TransitionController` / `MatchedGeometryTracker`).
Decompose the render-loop functions into named phase functions and hoist the nested
local `@MainActor func`s to private methods. Extract per-`switch`-case bodies in
`childPlacements`.

#### A2 · A 2,724-line `SwiftTUI.swift` lives inside `SwiftTUIRuntime` — and a second file shares the name · **Medium**

**Evidence.** `find Sources -name SwiftTUI.swift` →
`Sources/SwiftTUI/SwiftTUI.swift` (a 3-line `@_exported` shim) and
`Sources/SwiftTUIRuntime/SwiftTUI.swift` (2,724 lines). The large one declares one
public type (`DefaultRenderer`) preceded by ~1,100 lines of async-frame-pipeline
infrastructure and a pthread worker pool, followed by a wall of `*ForTesting`
methods. `SOURCE_LAYOUT.md` describes it only as "`@_exported` re-export … plus
`DefaultRenderer`."

**Why it matters.** A file named after the project, inside a module named after the
project, is an ownership smell — and it has become the module grab-bag the name
invites. Two files named `SwiftTUI.swift` in different modules also harms
navigability.

**Direction.** Keep `SwiftTUIRuntime/SwiftTUI.swift` as the thin umbrella only; move
`DefaultRenderer`, the frame-tail infrastructure, the worker pool, and the
test-only surface into named files under `Pipeline/`.

#### A3 · The seven-phase pipeline is sound as doctrine but under-enforced by the types · **Medium**

**Evidence.** `ARCHITECTURE.md` lists seven distinct data products
(`ResolvedNode` → `MeasuredNode` → `PlacedNode` → …), and `Pipeline/Pipeline.swift`
proves the phases *can* compose as cleanly-typed independent closures. But
`ResolvedNode` already stores `layoutMetadata`, `drawMetadata`, `semanticMetadata`,
`drawPayload`; and `PlacedNode` re-declares and **mirrors** them — with comments
literally reading "Mirror of `ResolvedNode/…`." `ResolvedNode` equality includes
`drawMetadata`.

**Why it matters.** The phases do not hand each other minimal typed results; they
pass one fat node whose fields are populated progressively and copied across node
types by hand. The separation of *concerns* holds (raster is where bytes happen),
but the separation of *boundaries* does not — a draw-payload change can ripple into
resolve-phase equality. The "Mirror of…" comments are an admission that the same
data is maintained in two places.

**Direction.** Hard to undo wholesale; the narrow, defensible ask is to stop
*mirroring* — have `PlacedNode` reference its `ResolvedNode` (or a shared immutable
metadata struct) rather than copy fields the layout engine must remember to
propagate.

#### A4 · `TerminalHost.swift` co-locates the surface-protocol family with one concrete implementation · **Medium**

**Evidence.** The 2,325-line `Terminal/TerminalHost.swift` defines the abstract
`PresentationSurface` protocol family (the contract every web/raster transport
implements) alongside the concrete POSIX `TerminalHost` class that dominates the
file.

**Why it matters.** Every host product conceptually depends on the *protocol*, not
on `TerminalHost`; a reader looking for "what must my web transport implement" must
open a 2,300-line terminal-specific file.

**Direction.** Extract `Terminal/PresentationSurface.swift` (the protocols +
`SemanticHostFrame` + capabilities); leave `TerminalHost.swift` as the concrete
implementation only.

#### A5 · Documentation has drifted from a renamed source directory · **Medium**

**Evidence.** `SOURCE_LAYOUT.md` claims it "should stay aligned with future file
moves," yet omits `SwiftTUIRuntime/Configuration/` (three files). `RUNTIME.md` and
~6 proposal docs cite paths under `Sources/SwiftTUI/` (e.g.
`Sources/SwiftTUI/TerminalHost.swift`, `Sources/SwiftTUI/AnimationController.swift`)
that now live under `Sources/SwiftTUIRuntime/`; `Sources/SwiftTUI/` today contains
one 3-line file.

**Why it matters.** A "stable reference" document pointing at a renamed directory
misleads contributors and erodes confidence in the rest of the (otherwise good)
doc set. This is framing observation #3 in miniature.

**Direction.** Add a one-line CI grep rejecting stale `Sources/SwiftTUI/<subpath>`
references; refresh the `SwiftTUIRuntime` block of `SOURCE_LAYOUT.md`.

#### A6 · The `Platforms/` vs `Sources/` target split is coherent but unstated in the manifest · **Low**

**Evidence.** Targets live at both `Sources/X` and `Platforms/Y/Sources/X` via
explicit `path:`. The convention (framework vs platform-integration) is documented
in `SOURCE_LAYOUT.md` but a `Package.swift` reader sees only deep paths with no
comment.

**Direction.** Add a top-of-`Package.swift` comment block stating the rule.

#### A7 · Latent `ViewNode` name collision across re-exported modules · **Low**

**Evidence.** `SwiftTUICore.ViewNode` (a `package final class`) and
`SwiftTUIViews.ViewNode` (a `package protocol`) coexist in the runtime namespace;
code already disambiguates with `SwiftTUICore.ViewNode`. Separately, `SwiftTUIRuntime`
`@_exported import`s the vendored `EmbeddedFonts` into every consumer's namespace.

**Why it matters.** Benign while both `ViewNode`s are `package`; a real problem if
either is promoted public. `@_exported` of a vendored font package leaks an
implementation dependency's symbols to consumers.

**Direction.** Rename one `ViewNode` (e.g. the core class to `ViewGraphNode`).
Reconsider whether `EmbeddedFonts` needs to be `@_exported`.

#### A8 · A bare `swift build` compiles all 15 products; `resolve` checks out every dependency · **Low**

**Evidence.** SwiftPM builds every product by default, so `swift build` with no
target compiles WebHost/FlyingFox/WASI. `swift package resolve` checks out the
whole manifest graph (FlyingFox, SwiftTerm, five `Vendor/` packages) regardless of
which product a downstream app consumes. Compile *isolation* is correct — a
terminal-only app links no FlyingFox — but checkout cost is unconditional.

**Why it matters.** A downstream consumer of only `SwiftTUI` still pays resolution
and checkout for FlyingFox and SwiftTerm. This is the genuine residual cost of the
single-package design (which is otherwise the right call for a fast-moving solo
project).

**Direction.** Keep one package now. If checkout cost becomes a complaint, extract
`swift-tui-webhost` and `swift-tui-terminal` as separate packages — they are the
two integrations whose external dependencies a core consumer never wants.

---

## U · Public API & usability

*Domain assessment: the core authoring surface is a faithful SwiftUI port, but the
analogy leaks the moment an app grows past one view — three load-bearing SwiftUI
idioms are silently absent, and one looks like SwiftUI while behaving differently.*

#### U1 · No `@Environment` property wrapper — SwiftUI's most common idiom is absent · **High**

**Evidence.** The only environment-reading API is the closure-based
`EnvironmentReader`; there is no `@propertyWrapper` anywhere in
`Sources/SwiftTUIViews/Environment/` (verified). A view reading three environment
values nests three `EnvironmentReader` closures rather than declaring three
properties.

**Why it matters.** `@Environment(\.colorScheme) var x` appears in essentially
every SwiftUI app. Its absence changes the shape of `body` and breaks the muscle
memory the framework explicitly courts, and it is not listed among the deliberate
SwiftUI divergences.

**Direction.** Add an `@Environment` property wrapper backed by the same context
plumbing `@State` uses; keep `EnvironmentReader` as the escape hatch.

#### U2 · No `@Environment(\.dismiss)` / `DismissAction` — presented content cannot dismiss itself · **High**

**Evidence.** `.sheet(isPresented:)` has the exact SwiftUI signature, but there is
no `dismiss` environment action. The project's own gallery (`CommandPalette.swift`)
documents the gap in a code comment and hand-threads a `dismiss` closure from the
parent.

**Why it matters.** `.sheet(isPresented:)` invites the SwiftUI mental model where
presented content calls `@Environment(\.dismiss)`. The framework provides the
presentation half but not the dismissal half, so every sheet/popover must hoist a
`Binding<Bool>` or thread a closure. The project's own showcase calls this a known
gap.

**Direction.** Ship a `dismiss` environment action the presentation stack injects
into presented content.

#### U3 · `NavigationStack` / `.navigationDestination` look like SwiftUI but model something else; `NavigationLink` is absent · **High**

**Evidence.** `NavigationStack` has only `init(id:root:)` / `init(root:)` — no
`path:`, no `NavigationPath`, no `NavigationLink`, no `navigationTitle`.
`.navigationDestination` exists only as `isPresented:` / `item:` overloads — which
is SwiftUI's *sheet* signature. `STATUS.md` confirms `NavigationLink` and
`NavigationPath` are "intentionally out of the shipped surface."

**Why it matters.** The gap is *declared*, which is honest — but the surviving API
is named identically to SwiftUI's navigation while behaving as a binding-driven
modal-replacement stack. "Looks like SwiftUI, behaves differently" is the sharpest
usability leak in the framework, because identical names defeat the very knowledge
transfer the project is built to exploit.

**Direction.** Either add real `NavigationLink`/`path:` support, or rename to signal
the different model (it is closer to a "router" or "destination host"). At minimum
the docs must warn that SwiftTUI navigation is not SwiftUI navigation.

#### U4 · `Binding.init(get:set:)` uses `unsafeBitCast` to forge closure actor-isolation · **High**

**Evidence.** `Sources/SwiftTUIViews/Foundation/ViewBaseTypes.swift:29-39` — the
public initializer accepts `@isolated(any) @Sendable` closures and does
`unsafe unsafeBitCast(get, to: (@MainActor @Sendable () -> Value).self)`.
`wrappedValue` is `@MainActor` and calls the closure synchronously. A sound
`@MainActor` initializer exists directly above it (`package init(mainActorGet:)`)
but is not public; the public one casts. (Found independently by two sub-audits.)

**Why it matters.** `unsafeBitCast` between closures of different isolation tells
the compiler a lie. If a `Binding` is ever built from a non-`@MainActor` context,
`wrappedValue` executes that closure on the wrong executor — a data race the
compiler can no longer catch. `Binding` is one of the most-used public types in the
framework. This also routes around exactly the `@unchecked Sendable` /
`nonisolated(unsafe)` ban a `prek` hook enforces — the unsoundness is achieved
through a hole the hook does not cover.

**Direction.** Make the public initializer's parameters `@MainActor @Sendable`
directly (matching the storage and the existing `package` initializer), or store
the closures as `@isolated(any)` and make `wrappedValue` hop. Do not paper over the
mismatch with a bitcast.

#### U5 · The README's "import only `SwiftTUI`" guidance is contradicted by the project's own examples · **Medium**

**Evidence.** The README and `PUBLIC_SURFACE_POLICY.md` present `import SwiftTUI` as
canonical for terminal apps. Across `Examples/`, `import SwiftTUIRuntime` appears
~77× versus `import SwiftTUI` ~45×; in the flagship `gallery` example, **0 of 17**
view files import `SwiftTUI`.

**Why it matters.** A new user is told one thing and shown another by the
maintainer's own showcase code. The intended one-import simplification is not
actually realized.

**Direction.** Make the examples consistently `import SwiftTUI`, or, if
`SwiftTUIRuntime` is the intended import for view-only packages, say so and stop
calling `SwiftTUI` "the one import."

#### U6 · `@main` behavior depends invisibly on which module is imported · **Medium**

**Evidence.** Three `App.main()` extensions exist across `SwiftTUICLI`,
`SwiftTUIWebHostCLI`, and a `SwiftTUICommand` variant. The README shows the *same*
`@main struct: App` for terminal and web; the runner is chosen purely by import
set. Importing both `SwiftTUI` and `SwiftTUIWebHostCLI` yields two
`public static func main()` candidates on the same protocol.

**Why it matters.** "The import decides the runner" is invisible magic, and a
plausible import combination produces an ambiguity build error or a silent pick.

**Direction.** Prefer an explicit launcher (`try await TerminalRunner.run(...)`) as
the documented default, or make the runner a type the app names explicitly.

#### U7 · A diagnostics concern (`snapshotLabel`) leaks into five public style protocols · **Medium**

**Evidence.** `ButtonStyle`, `PickerStyle`, `TextFieldStyle`, `TabViewStyle`, and
`ToastStyle` all require a `snapshotLabel: String` — a snapshot-testing member that
SwiftUI's equivalents do not have.

**Why it matters.** A consumer implementing a custom style sees an internal
testing concern in the protocol contract and in DocC/autocomplete — exactly the
kind of seam the project's own `PUBLIC_SURFACE_POLICY` says should stay confined to
lower-level types.

**Direction.** Move `snapshotLabel` to an internal protocol, or derive it via
reflection at the diagnostics call site.

#### U8 · `View.id(_:)` accepts only the internal `Identity` type, not arbitrary `Hashable` · **Medium**

**Evidence.** The sole `id` modifier is `func id(_ identity: Identity)`; SwiftUI's
is `func id<ID: Hashable>(_ id: ID)`. Consumers hand-build `Identity(components:)`.
Worse, `ScrollViewProxy.scrollTo` *does* take a `Hashable & Sendable` ID — so
`proxy.scrollTo(myInt)` compiles but can never match a view (views carry
`Identity`, not `Int`) and silently no-ops.

**Why it matters.** `.id(item.id)` is everyday SwiftUI; here `.id(someInt)` fails to
compile. The asymmetry with `scrollTo` is an active footgun — a compiling call that
silently does nothing.

**Direction.** Add `func id<ID: Hashable>(_ id: ID)` routing through the existing
`Identity.explicitID(_:)`; this also realigns `.id()` with `scrollTo`.

#### U9 · `.sheet`/`.alert` lack `onDismiss:`/`item:` overloads — and are inconsistent with `.popover` · **Medium**

**Evidence.** `.sheet` has only `isPresented:` forms — no `onDismiss:`, no
`sheet(item:)`. `.alert` has only `isPresented:` forms. But `.popover` *does* have
an `item:` overload.

**Why it matters.** SwiftUI's `.sheet(item:)` and `onDismiss:` are common; their
absence forces `Binding<Bool>` + `onChange` workarounds. The internal inconsistency
(`popover` has `item:`, `sheet` does not) means the modal-presentation family does
not compose uniformly.

**Direction.** Add `item:`/`onDismiss:` to `.sheet`, matching `.popover`.

#### U10 · Public-API doc-comment coverage is roughly a quarter · **Medium**

**Evidence.** Around 22–26% of public declarations carry a `///` doc comment.
Entirely undocumented: every built-in style (`BorderedProminentButtonStyle`, etc.),
the style protocols themselves, `TextField`, `Spinner`. `.swift-format.json` has
`AllPublicDeclarationsHaveDocumentation: false` (see I10), so the check is disabled.

**Why it matters.** A framework re-implementing a familiar API needs docs *most*,
because the behavioral deltas from SwiftUI (U2, U3, U8) must be stated. The
undocumented set is precisely the discoverable, consumer-chosen surface.

**Direction.** Re-enable the lint rule; prioritize doc comments on the style
protocols, built-in styles, and core controls.

#### U11 · ~50 internal modifier structs are `public` only to satisfy opaque-return rules · **Low**

**Evidence.** `PaddingModifier`, `FrameModifier`, `OverlayModifier`, etc. are
`public` purely so `public func`s returning them compile; they are never written by
a consumer.

**Direction.** Mark them `package` where the opaque return fully hides them;
otherwise group under a DocC exclusion so they do not read as authoring API.

#### U12 · `PUBLIC_API_INVENTORY.md` mis-states a shipping modifier as removed · **Low**

**Evidence.** The inventory lists `.onKeyPress(...)` under "Removed From The Public
Surface," but `onKeyPress` is fully public today.

**Why it matters.** A document whose stated job is answering "should I use X?"
flatly mis-states a shipping API.

**Direction.** Correct the entry to distinguish the removed global-hotkey seam from
the shipping focused-key `onKeyPress`.

#### U13 · `SwiftTUICommand` requires a stored `@OptionGroup` property the protocol cannot enforce · **Low**

**Evidence.** The protocol requires only `var swiftTUIOptions: SwiftTUIOptions
{ get }`; the doc comment says it "MUST" be an `@OptionGroup`-wrapped stored
property. A computed `var swiftTUIOptions { SwiftTUIOptions() }` satisfies the
protocol, compiles, and silently parses none of the framework flags.

**Direction.** Have the runner assert at startup that parsing actually populated
the option group.

#### U14 · The README's first code sample leads with `await MainActor.run` and the low-level renderer · **Low**

**Evidence.** The opening snippet wraps `DefaultRenderer().render(...)` +
`TerminalSurfaceRenderer` in `await MainActor.run { ... }` at file scope; its
capability profile (`.previewUnicode`) differs from the actual `minimal` example
(`.ansi256`).

**Why it matters.** A SwiftUI-shaped framework opening its README with
`await MainActor.run` and manual two-stage rasterization sets the wrong first
impression and foregrounds the snapshot-testing layer over the `App`/`Scene` story.

**Direction.** Lead with the `@main struct: App` example; move the `DefaultRenderer`
snippet to a "snapshot testing / internals" section; align the capability profile
with the `minimal` example.

#### U15 · `DefaultRenderer`'s reused-view state-leak caveat is a leaky abstraction · **Low**

**Evidence.** The README and the `@State` doc comment warn that, with
`DefaultRenderer` and no runtime graph, reusing the same stateful view *instance*
lets `@State` writes bleed into a later `render()` of that instance.

**Why it matters.** `@State` semantics depend on whether a runtime graph exists —
a smell, though honestly documented and scoped to the snapshot path. It is flagged
for completeness rather than as a defect.

**Direction.** Consider having `DefaultRenderer.render` take a `() -> some View`
factory so the API shape discourages instance reuse rather than relying on prose.

#### U16 · Naming nits · **Nit**

**Evidence.** `Standard.Error` (a `TextOutputStream` named `Error`, conceptually
colliding with Swift's `Error`) lives in a file named `Stand.swift`;
`View.erasedToAnyView` is a non-SwiftUI spelling of `AnyView(_:)`; two modifiers
return concrete `ModifiedContent` while ~35 siblings return `some View`.

**Direction.** Rename `Standard.Error` and the `Stand.swift` file; align the two
outlier modifiers to `some View`.

---

## T · Testing

*Domain assessment: a genuinely strong suite for the project's age — 100% migrated
to Swift Testing, ~1,900 tests, real edge-case coverage in the core — undermined by
the fact that none of it runs automatically, one whole target is never executed,
and coverage is unmeasured.*

#### T1 · The test suite gates nothing — see I1 / I2 · **Critical (cross-reference)**

The ~1,900-test suite has no working CI path. With auto-testing disabled (I1) and
the one workflow broken (I2), regressions are caught only when the maintainer
remembers to run the gate locally. `AGENTS.md` instructs "always run `bun run test`
… and confirm it passes," but that is unenforceable. This is recorded under
Infrastructure; it is repeated here because it determines whether the tests
themselves protect anything. They currently do not.

#### T2 · `SwiftTUITerminalWorkspaceTests` is a real target that no script runs · **High**

**Evidence.** `Package.swift` declares `SwiftTUITerminalWorkspaceTests` (8 tests
across 3 files). Both `test_gate.sh` and `test_all.sh` invoke suites by explicit
`swift test --filter <Name>`; the verified filter list contains 12 suites and
**`SwiftTUITerminalWorkspaceTests` is not among them**. `--filter SwiftTUITerminalTests`
does not regex-match `SwiftTUITerminalWorkspaceTests`. No script runs a bare
unfiltered `swift test`.

**Why it matters.** A subsystem shipped as "first-class terminal workspaces"
(`STATUS.md`) has unit tests that pass in isolation but never execute in the gate
`AGENTS.md` calls the completion gate. The session-store and layout logic they
cover is exactly the kind of stateful code that rots silently.

**Direction.** Add `--filter SwiftTUITerminalWorkspaceTests`; better, replace the
hand-maintained filter list with a single root-package `swift test`, or add a
meta-test asserting every `testTarget` in `Package.swift` is in the runner.

#### T3 · No code-coverage measurement anywhere · **High**

**Evidence.** No `--enable-code-coverage`, no `llvm-cov`, no codecov, in any script,
workflow, or doc. The 66k:90k test:source LOC ratio is cited as if it implied
coverage; it is unverified, and large monolithic test files (one is 6,430 LOC)
inflate test LOC without proving line coverage.

**Why it matters.** Without coverage data the thin spots (T4) are invisible — which
is *why* T2 went unnoticed: there was no signal distinguishing tested-and-passing
from never-executed.

**Direction.** Run `swift test --enable-code-coverage` in the gate; export an
`llvm-cov` summary; track per-module percentage.

#### T4 · Stateful platform launchers are thinly tested; one test asserts nothing · **High**

**Evidence.** `SwiftTUIWASITests` is 2 tests for an entire platform target; under
`canImport(WASILibc)` — the branch that actually runs on WASI — its only assertion
is `#expect(Bool(true))`. `SwiftTUIPTYPrimitivesTests` is 3 tests. By contrast the
pure core pipeline has hundreds of tests.

**Why it matters.** The runtime, input, and terminal-IO paths — the most stateful,
OS-coupled, hardest-to-get-right parts of a TUI framework — are the *least*
covered. A WASI-launcher regression has effectively no test that would catch it.

**Direction.** Replace `#expect(Bool(true))` with a real WASI-path assertion or a
`withKnownIssue`/skip; add launcher/manifest-mode behavior tests for `SwiftTUIWASI`.

#### T5 · Rendered-text fixtures can be silently re-baselined by an environment variable · **Medium**

**Evidence.** The fixture suite runs `assertRenderedTextFixtures` in `.automatic`
mode, which *records* (overwrites the `.txt` baselines, deletes orphans) whenever
`PARALLEL_RECORD_RENDERED_FIXTURES=1`. The expected output is produced by the same
renderer under test. No checksum, no review gate — only a prose policy.

**Why it matters.** A regression run with that variable set rewrites the "expected"
files to match the regression. Snapshot suites are only as trustworthy as their
regeneration discipline; here the discipline is a human convention. (The fixture
*content* is well-designed — the risk is purely the regeneration trapdoor.)

**Direction.** Make recording explicit-only (a dedicated `Scripts/record_fixtures.sh`
or `mode: .record` in code); have the gate fail if the env var is set.

#### T6 · The repo gate was committed in a known-red state · **Medium**

**Evidence.** The gate/exhaustive split commit (`89dd2d03`) documents in its own
message that `bun run test` "still hit existing failures in `Examples/gallery`
signal 10, `Tools/TermUIPerf` signal 10, and one transient toast auto-dismiss
test." A follow-up, `75dcc503` "restore full repo verification," fixed the crashes.

**Why it matters.** A completion gate is only meaningful if green is its normal
state. The "split, then restore" two-commit churn shows the split was used partly
to route around a red full suite rather than purely to speed it up; shipping the
gate red trains a contributor to treat failures as expected noise.

**Direction.** Keep the split (the design is sound — the framework suites run in
both modes; only example-app builds are deferred). Never commit the gate red.

#### T7 · A few fixed sleeps and an unquarantined flaky test remain · **Low**

**Evidence.** Against the project's own anti-fixed-sleep policy: a 200 ms
`Task.sleep` in `SocketDiscoveryTests`; `usleep`-based write-staggering with a
comment admitting runner sensitivity; a 15-second poll deadline in
`InputBatchingResponsivenessTests`; and the admitted-flaky toast test from `89dd2d03`
left unmarked. (Most async waits in the suite *are* done correctly, with bounded
condition polling — these are the exceptions.)

**Direction.** Convert the socket sleep to a condition wait; quarantine the toast
test with `withKnownIssue` rather than relying on "passed on rerun."

---

## C · Swift code quality & correctness

*Domain assessment: the internal code is disciplined and unusually clean for
single-author, AI-assisted work — but it contains a small number of genuine crash
and concurrency hazards, the most serious of which is U4.*

#### C1 · `Color.hex(_:)` traps the process on invalid input · **High**

**Evidence.** `Sources/SwiftTUICore/Styling/Styling.swift:72-77` — the public,
non-throwing `static func hex(_ hex: String, profile:)` is implemented as
`try! .init(hex: hex, profile: profile)`, and `Color.init(hex:)` genuinely throws
`ColorError.invalidHexString`. `Color.hex("#GGG")` crashes the process. (The ~24
*constant-literal* `try!`s elsewhere — `try! Self(hex: "#E05757FF")` — are
defensible; this one is not, because its argument is unbounded runtime input.)

**Why it matters.** A crash reachable from ordinary caller-supplied data is a
footgun. A framework should not trap on bad input to a public convenience API.
Note that `.swift-format.json` disables `NeverUseForceTry` (I10), so the linter
will never flag this.

**Direction.** Make `Color.hex(_:)` either `throws` or `-> Color?`, mirroring
`URL(string:)`.

#### C2 · Off-main layout safety rests on an unchecked exhaustiveness invariant + `assumeIsolated` · **Medium**

**Evidence.** Background-thread layout runs through `nonisolated` proxy methods that
wrap their bodies in `MainActor.assumeIsolated { ... }` (14 such calls). Off-main
dispatch is gated by three recursive `containsMainActorOnly…` predicates that walk
the node tree.

**Why it matters.** This is correct *only if* those predicates are exhaustive
against every future node shape. If a new node kind adds a child-bearing field, the
gate silently leaks and `MainActor.assumeIsolated` becomes a hard crash on a
background thread. The safety is real but load-bearing on a hand-maintained
allowlist with no compile-time enforcement.

**Direction.** Document on `canOffloadLayout` why the predicate is exhaustive; add a
debug-only assertion at the worker boundary that the resolved tree contains no
MainActor-only layout before dispatch.

#### C3 · Empty `catch` blocks silently discard terminal/clipboard I/O errors · **Medium**

**Evidence.** ~5 sites (`ClipboardWriting.swift`, `TerminalAppearanceDetection.swift`,
`TerminalHost.swift`, `HostedSceneSession.swift`) catch an error and discard it with
no logging — `catch { return false }`, `catch { return heuristic }`.

**Why it matters.** The recovery behavior is often fine (a clipboard write failing
because the terminal lacks OSC 52 *should* return `false`), but the error carrying
the actual reason is thrown away with no diagnostic. When a user reports "copy
doesn't work," there is no trace — against the project's "never silently swallow
errors" norm.

**Direction.** Route discarded errors through the existing diagnostics channel
(`RuntimeIssue`/`FrameDiagnostics`), even when recovery is unchanged.

#### C4 · `childPlacements` silently truncates on a child/measurement count mismatch · **Low**

**Evidence.** The `.intrinsic` case computes
`min(resolved.children.count, measured.childMeasurements.count)`; extra children
are dropped with no diagnostic.

**Why it matters.** A count mismatch is an internal pipeline-invariant violation
(resolve and measure disagreeing). Silently clamping produces a quietly-wrong frame
instead of surfacing the bug — inconsistent with the codebase's willingness to
`fatalError` on other invariant violations.

**Direction.** `assert` the counts match (or emit a `RuntimeIssue`) before clamping.

#### C5 · Doc comments stranded after attributes · **Low**

**Evidence.** ~12 sites place a `///` doc comment *between* an attribute
(`@propertyWrapper`, `@MainActor`) and the declaration. Swift associates a doc
comment only when it immediately precedes the declaration, so DocC may drop these.

**Why it matters.** These are the *documented* public types — the text exists but
may not render — likely an artifact of `swift-format`'s attribute reordering.

**Direction.** Move the `///` block above all attributes; verify with a `docc` build.

#### C6 · Minor code smells · **Nit**

**Evidence.** `OSAllocatedUnfairLock.withLockUnchecked` is a distinct-signature
alias whose body is identical to `withLock` — the "Unchecked" name promises a
fast path that does not exist. `processResolvedTree` contains an empty `if` block
used purely as a comment anchor.

**Direction.** Delete the alias or document it as an intentional shim; replace the
empty `if` with a plain comment.

---

## What the project gets right

A critique with no calibration is easy to dismiss, and several of these are
genuinely better than typical. They are also the reason the recommendations below
are mostly small: the hard parts are done.

- **The seven-phase pipeline is a real, principled decomposition.** `Pipeline.swift`
  proves the phases can compose as cleanly-typed independent closures; isolating
  raster/terminal-byte concerns from layout is exactly right for a TUI framework.
- **Module dependency direction is clean and acyclic.** `SwiftTUICore` imports no
  first-party module upward; heavy external dependencies (FlyingFox, SwiftTerm) are
  correctly quarantined to their integration products — a terminal-only app links
  neither.
- **Strict-concurrency discipline is genuinely respected.** Zero `@unchecked
  Sendable`, zero `nonisolated(unsafe)` across 90k lines; shared mutable state sits
  behind `Synchronization.Mutex` or `@MainActor`. `strictMemorySafety()` and five
  upcoming features are enabled. (U4's `unsafeBitCast` is the one real hole.)
- **Marker discipline is exemplary.** Zero `TODO`/`FIXME`/`HACK`/`XXX` across the
  whole of `Sources/`; effectively zero commented-out code; zero tabs.
- **Testing has substance.** 100% migrated to Swift Testing (0 XCTest), ~1,900
  tests; the core suite probes real failure modes — LRU cache eviction with
  hit/miss assertions, 1,024-deep stack-safety, `MemoryLayout` size budgets.
- **The public-API baseline machinery** — a committed, machine-generated
  `.public-api-baseline.txt` regenerated on every public-symbol change — is a
  discipline most frameworks lack.
- **The durable documentation is rich and, today, maintained.** `ARCHITECTURE.md`,
  `RUNTIME.md`, `TERMINOLOGY.md` form a coherent reference; `LAYOUT-RESOLVE-SPLIT.md`
  is a model architecture-decision record. The ADR practice (numbered, front-matter,
  correct use of `superseded`/`reverted`) is more decision discipline than most
  multi-year projects have.
- **The core authoring surface is a faithful SwiftUI port.** `View`/`body`,
  `ForEach`'s three canonical initializers, parameter-pack `ViewBuilder` (no
  10-child cap), protocol-based extensible styles — a SwiftUI developer can write a
  first screen with little friction.
- **The `AnyView` / `scopedAnyView` policy is unusually rigorous** and well
  contained — it does not leak into consumer code.
- **Real infrastructure-security care exists** where it was applied: workflows route
  user-controlled inputs through quoted `env:` blocks with explanatory comments; the
  Linux Docker image emits SBOM and provenance. The instincts are right — they just
  need to extend to the test pipeline.

The throughline: this project is strong at *building things* and strong at
*internal discipline*. It is weak at *being a project other people can rely on*.

---

## Prioritized recommendations

Ordered by leverage. The first group is small, non-technical, and unblocks
everything else.

1. **Decide what this is.** Personal project, or framework meant to be used? If
   the former, dial back the marketing surface (G5). If the latter, items 2–4 are
   not optional.
2. **Make the code legally usable.** Add a top-level `LICENSE` (G1); add `license`
   to every `package.json`; restore `LICENSE.txt`/`NOTICE` to `Vendor/UnixSignals`
   (I6). This is an afternoon of work and it is currently a hard blocker.
3. **Make CI real.** Fix the `swiftly` install in `run-tests-linux.yml` (I2);
   restore `push`/`pull_request` triggers (I1); add a `macos-26` test job and an
   iOS build (I3); run `prek`/`check_*.sh` as a required PR job (I4); enable branch
   protection on `main`.
4. **Fix the genuine correctness hazards.** `Color.hex(_:)` → throwing or optional
   (C1); replace the `Binding.init` `unsafeBitCast` with an honest signature (U4).
5. **Calibrate the self-presentation.** Add a pre-1.0 / single-maintainer /
   AI-assisted stability banner to the README (G5, G10); cut a real `0.1.0` and
   retire the `TEMP` `0.0.1` tag (G2); populate or delete `TODO.md` (G3); reword the
   ADR "Reviewers" step (G7).
6. **Re-enable the lint rules you turned off.** `NeverUseForceTry` and
   `AllPublicDeclarationsHaveDocumentation` in `.swift-format.json` (I10) — let them
   drive the C1 and U10 cleanup.
7. **Replace the hand-maintained test `--filter` list with a plain `swift test`**
   so a target can never again be silently dropped (T2); add coverage measurement
   (T3); make fixture recording explicit-only (T5).
8. **Reduce the surface you must keep true.** Archive shipped `plans/` (G6); fix the
   doc path drift and add a CI grep to prevent its recurrence (A5); remove
   `@openai/codex` (I5); prune merged branches (G11).
9. **Decompose the god-files** along the seams identified in A1–A4 — highest
   priority on `renderPendingFramesAsync` and `AnimationController`, the
   highest-risk code.
10. **Close the API gaps that most break the SwiftUI promise:** an `@Environment`
    property wrapper (U1), a `dismiss` action (U2), and `.id(_: some Hashable)` (U8).

---

## Appendix — verification log

Critical and High findings were verified first-hand. Key results:

| Claim | Verification |
|-------|--------------|
| No `LICENSE` (G1) | `ls LICENSE*` → no matches; `git ls-files \| grep -i licen` → only 3 vendored. |
| CI auto-test disabled (I1) | `git show 0dffff25` → "disable ci auto-test", removes 4 lines (`push`/`pull_request`) from `run-tests-linux.yml`. |
| CI broken & red (I2) | `gh run list --workflow=run-tests-linux.yml` → last 6 runs all `failure`; 2 oldest were `push`-triggered. |
| `0.0.1` → "TEMP" (G2) | `git show 0.0.1` → `c90c2b8f` "TEMP: Vendor file:// URL workaround for unidoc", `local <local@local>`; 500 commits since. |
| `UnixSignals` licence stripped (I6) | source header cites `LICENSE.txt`/`CONTRIBUTORS.txt`; `find Vendor/UnixSignals` finds neither. |
| `Binding.init` `unsafeBitCast` (U4) | read `ViewBaseTypes.swift:29-39` directly. |
| `Color.hex` `try!` (C1) | read `Styling.swift:72-77` directly. |
| `SwiftTUITerminalWorkspaceTests` unrun (T2) | `grep -nE 'filter' Scripts/test_all.sh` → 12 suites, target absent. |
| No `@Environment` wrapper (U1) | `git grep propertyWrapper Sources/SwiftTUIViews/Environment/` → none. |
| Lint rules disabled (I10) | read `.swift-format.json` `rules` block directly. |
| Name collision (G8) | `gh search repos SwiftTUI` → `rensbreur/SwiftTUI` 1,504★, plus 4 others. |

**Limitations of this assessment.** The build and test suite were not run; CI
failure is inferred from `gh` run history and the `swiftly`/`setup-swift` mismatch.
This is not a security audit. The API critique is from reading the surface, not
from building an application against it. Architecture and code-quality findings
sampled the largest and most central files plus a breadth sample; they are not an
exhaustive line-by-line review of all 351 source files.
