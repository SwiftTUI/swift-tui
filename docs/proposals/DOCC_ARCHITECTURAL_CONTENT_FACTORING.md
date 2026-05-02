# DocC ↔ Contributor Doc Factoring

Audit of project-owned DocC catalogs (`Sources/*.docc/*.md`) for content that
serves contributors better than consumers, with a per-article recommendation
for what to factor out and where it should live.

## Background

The published DocC archive (`swiftly run swift package generate-documentation`)
is a consumer artifact: framework users read it to learn the public API. The
working hypothesis behind this audit is that several DocC articles in this
repo are doing a different job — explaining *why we built it this way*,
comparing roads not taken, naming internal seams and project-internal
hypotheses — and that audience is contributors, who already have a separate
home in `docs/`.

`Sources/View/View.docc/State-Keying.md` is the canonical example: it is a
~330-line side-by-side comparison of ordinal-keying and source-location-keying
strategies, framed as a design discussion. A consumer using `@State` does not
need that material to use the API correctly. A contributor reasoning about
the runtime needs all of it.

The repository already documents the right pattern in one place. The DocC
article `Sources/Core/Core.docc/CellPixelMetrics.md` is a tight symbol overview
that ends with a single `Related discussion` link out to
`docs/CELL_PIXEL_GEOMETRY_RESEARCH.md`. The contributor research doc holds the
trade-offs; the DocC article holds the API. This proposal generalizes that
pattern.

## Classification heuristic

An article belongs in DocC if a framework *user* would search for it from
inside Xcode-rendered docs or `swift package generate-documentation` output.

An article belongs in `docs/` if it answers any of:

- **"why did we choose this approach over alternative X?"**
- **"what did we try first that didn't work?"**
- **"what is the internal hypothesis behind this surface?"**
- **"what package-only seams support this and how should they evolve?"**
- **"what are the project's non-negotiable decisions?"**
- **"what regression suites pin this behavior?"**
- **"what is deliberately not in scope today?"**

Articles that mix the two should keep the consumer-facing material in DocC
and link out to the contributor doc for the rest.

## Existing duplication

Five DocC articles have a near-twin in `docs/` and one already shows drift:

| `docs/` (contributor) | `Sources/*.docc/` (DocC) | Lines (docs / DocC) | Drift? |
|---|---|---|---|
| `STATE_KEYING.md` | `View/View.docc/State-Keying.md` | 458 / 333 | **Yes** — DocC is materially shorter |
| `ARCHITECTURE.md` | `SwiftTUI/SwiftTUI.docc/Architecture.md` | 184 / 173 | Light |
| `RUNTIME.md` | `SwiftTUI/SwiftTUI.docc/Runtime.md` | 250 / 224 | Light |
| `VISION.md` | `SwiftTUI/SwiftTUI.docc/Vision.md` | 122 / 109 | Light |
| `FOCUS.md` | `View/View.docc/Focus.md` | 681 / 492 | **Yes** — DocC is ~190 lines shorter |
| `HOST_PACKAGES.md` | `SwiftTUI/SwiftTUI.docc/Host-Integration.md` | 143 / 108 | Light |

Maintaining two near-copies of the same material doubles edit cost and
guarantees they diverge. The State-Keying and Focus pairs already have.

## Per-article inventory

Each row below lists a project-owned DocC article, its primary audience, and
the recommended action.

### Module landing pages — keep as-is

| Article | Why keep |
|---|---|
| `Core/Core.docc/Core.md` | Tight module overview with `Topics`. The "Design Boundary" prose is API-shaping context a consumer needs ("this module does not talk to the terminal directly") and is short. |
| `View/View.docc/View.md` | Module overview + `Topics`. No internal-only content. |
| `SwiftTUI/SwiftTUI.docc/SwiftTUI.md` | Module overview + `Topics`. No internal-only content. |
| `SwiftTUICharts/SwiftTUICharts.docc/SwiftTUICharts.md` | Module overview + `Topics`. |

### Pure how-to / authoring guides — keep as-is

| Article | Why keep |
|---|---|
| `View/View.docc/Authoring-Views.md` | "Use containers, modifiers, and previews like this." Brief actor-isolation note is load-bearing for callers, not contributor framing. |
| `View/View.docc/State-Environment-And-Focus.md` | Topical "use ``State`` for X, ``Binding`` for Y" overview. No internal-only content. |
| `SwiftTUICharts/SwiftTUICharts.docc/Building-Dashboards.md` | "Choose a chart, lay it out narrow." Pure how-to. |
| `SwiftTUI/SwiftTUI.docc/Running-Apps.md` | Lists the three runtime entry points and how to launch them. Pure how-to. |
| `Core/Core.docc/CellPixelMetrics.md` | **Already follows the recommended pattern**: short symbol overview, one `Related discussion` link out to the contributor research doc. Use as the template for everything below. |

### Articles to refactor — DocC keeps the consumer story, contributor doc owns the trade-offs

These articles each have a contributor-facing twin in `docs/`. Recommendation:
keep a *short, consumer-only* summary in DocC, link out to the `docs/` doc for
the architectural treatment, and stop maintaining the long form in two places.

#### `View/View.docc/State-Keying.md` ↔ `docs/STATE_KEYING.md`

**Audience today:** contributor. The whole article is a design comparison
("Strategy 1 vs Strategy 2", "Where They Diverge", "Interaction With The
Attribute Graph", "Summary Of Tradeoffs"). A consumer does not need to know
that ordinal keying is the natural fit for a persistent attribute graph in
order to use `@State`.

**What to keep in DocC** (≈ 30 lines):

- One paragraph: "SwiftTUI keys `@State` by view-identity-path plus
  source-location. Move a stateful view to a different identity path and you
  get a fresh state slot."
- The "Practical Owner Placement Guidance" section (lines 306–326 today) is
  *the* part a consumer benefits from — what to do when state must survive
  tab switches, presentation churn, and lazy seams. Keep this verbatim.
- Link to `docs/STATE_KEYING.md` for the strategy comparison.

**What moves to `docs/STATE_KEYING.md`** (already there): the full ordinal-vs-
source-location comparison, the "Where They Diverge" cases, the attribute-
graph discussion, the tradeoffs table.

**Side benefit:** the existing 125-line drift between the two copies stops
mattering — there is only one copy.

#### `View/View.docc/Focus.md` ↔ `docs/FOCUS.md`

**Audience today:** mostly consumer, with two contributor-only intrusions.

The bulk of the article (the focus model, `FocusState`, focused values, focus
sections, traversal semantics, common mistakes) is excellent consumer content.
Two passages are contributor-only:

1. **The "scope hypothesis" paragraph** (line 432 today, inside "Practical
   Implications For SwiftTUI"):

   > "**the focus chain is load-bearing for the scope hypothesis.** Commands
   > belong to scopes, and a scope's activation predicate is that its anchor
   > node is on the current focus chain. Tree presence is a prerequisite but
   > not sufficient — a resolved-but-unreachable node is philosophically
   > silent. This elevates focus from 'keyboard routing' to 'the primary
   > reachability primitive' — every command availability decision the
   > framework makes bottoms out in focus-chain membership."

   This names an internal hypothesis (the "scope hypothesis") and uses
   internal philosophical framing ("philosophically silent"). Belongs in
   `docs/FOCUS.md` and/or the existing
   `docs/proposals/ACTION_SCOPES_AND_COMMANDS.md`.

2. **The entire "A Nuanced Case: Focus Appearance In `List`" section**
   (lines 434–484 today, ≈ 50 lines).

   This section is a design diary: "What You Actually See In SwiftUI" → "Why
   The Analogy Is Imperfect" → **"The Decision The Project Has Made"** →
   "What This Decision Does Not Cover". It explains what an *earlier version
   of the runtime* did wrong ("two redundant signals at different layers,
   painted with the same color, cancel each other out") and why the current
   design is the way it is. None of this is necessary to use `List`. All of
   it is necessary to evolve the runtime responsibly.

   Belongs in `docs/FOCUS.md` (which is already 681 lines and the right home
   for this kind of justification).

**What to keep in DocC:** everything except those two passages. Replace the
"scope hypothesis" sentence with a one-line note that focus-chain membership
is the activation predicate for command availability, with a link to the
scope/command proposal. Replace the `List` design diary with a one-line
factual note ("focus highlight in `List` is row-shaped, not container-shaped")
and a link to `docs/FOCUS.md` for the rationale.

#### `SwiftTUI/SwiftTUI.docc/Architecture.md` ↔ `docs/ARCHITECTURE.md`

**Audience today:** mixed, leans contributor.

Consumer-useful parts:

- "Target Boundaries" section — concise, useful for understanding which
  module to import.
- "Frame Pipeline" section — explains the seven phases and where each phase's
  output lives. Useful for `FrameArtifacts` consumers.
- "Important Data Products" section — names the public types per phase.

Contributor-only parts:

- "Transitional Seams" section explicitly names package-only adapters
  (`ViewNode`, `ResolvableView`, internal resolver/lifecycle seams) and the
  rule that they should remain adapters. Consumers should not see this — it
  describes private surface area.
- The "Runtime Model" section's enumeration of every internal coordinator
  (`state container`, `dynamic state storage`, `lifecycle and task
  coordinators`, "package-private window host") is implementation detail.
- Detailed presentation-host re-resolution rules (sub-bullets under "Resolve")
  describe internal reconciliation behavior.

**What to keep in DocC:** target boundaries, frame pipeline phases at the
single-paragraph level per phase, public data products, a one-paragraph
runtime overview. Link out to `docs/ARCHITECTURE.md` for transitional seams,
internal coordinators, and presentation-host reconciliation rules.

#### `SwiftTUI/SwiftTUI.docc/Runtime.md` ↔ `docs/RUNTIME.md`

**Audience today:** mixed, leans contributor.

Consumer-useful parts:

- "Runtime Shape" — single paragraph stating what `RunLoop` does.
- "Root-Hoisted Presentations" behavior at the user-visible level (alerts,
  sheets, etc. are authored locally but displayed at the root).
- "Input, Focus, And Interaction" — overview of keyboard-first model.
- "Commit, Lifecycle, And Tasks" rules — these are observable to consumers
  via `.onAppear`/`.onDisappear`/`.task` and matter for correctness.
- "State Model", "Environment Model", "Observation Model" subsections —
  these describe consumer-observable invalidation rules.

Contributor-only parts:

- **"Current Incremental Cost Model"** section (≈ 60 lines today). The whole
  cost model — "Resolve / Measure And Place / Presentation / Cell Pixel
  Size Refresh" — describes internal performance behavior for someone
  reasoning about the implementation. The "Deterministic Scenario Checks"
  list and the "Known Full-Repaint Fallbacks" list are essentially regression
  rubrics. None of this is API.
- **"Crash Recovery"** section (≈ 25 lines). Describes a CLI-runner-internal
  signal handler, including signal-by-signal handling, an alternate stack,
  and POSIX caveats. Useful for someone touching `CrashSignalHandler`. A
  consumer just needs "the CLI runner restores your terminal on crash."

**What to keep in DocC:** the runtime shape, presentation behavior at the
authoring level, lifecycle/task rules, state/environment/observation models.
Replace the cost model section with a one-paragraph "is this incremental?"
summary and link to `docs/RUNTIME.md`. Replace the crash recovery section with
a one-line guarantee ("the CLI runner installs a crash guard that resets the
terminal before the process dies") and link to `docs/RUNTIME.md` for the
implementation detail.

#### `SwiftTUI/SwiftTUI.docc/Vision.md` ↔ `docs/VISION.md`

**Audience today:** contributor. Almost the entire document.

This article is project philosophy and roadmap policy:

- "Core Principles" — including "Deviations are permitted only when all of
  the following are true: (1) … (2) … (3) …" — that's a project rule, not
  consumer guidance.
- "SwiftUI Concepts That Need A Stronger Hypothesis First" — internal
  reasoning about deferred work.
- "What Is Not In Scope Today" — explicit roadmap negative space.
- "Aesthetic And Component Guidance" — points at Bubble Tea / Lip Gloss as
  evidence rather than templates. Consumer-irrelevant.

A consumer wanting to evaluate the framework for adoption *does* benefit from
a short "this is a SwiftUI-shaped subset, terminal-native, keyboard-first,
PNG images supported" overview, but does not need the multi-clause deviation
rule or the deferred-work taxonomy.

**Recommendation:** replace the DocC article with a ~20-line "About this
project" overview (what it is, what's in, what's deliberately deferred at the
one-line level), and link to `docs/VISION.md` for the full philosophy. The
DocC article today essentially *is* `docs/VISION.md`; remove the duplication.

Alternatively: delete the DocC article entirely and fold a one-paragraph
"About" into `SwiftTUI/SwiftTUI.docc/SwiftTUI.md`.

#### `SwiftTUI/SwiftTUI.docc/Host-Integration.md` ↔ `docs/HOST_PACKAGES.md`

**Audience today:** contributor.

This article is mostly project-internal contracts:

- "Shipped Architecture" — describes which package owns which file
  (`SwiftUIHostAppState`, `NativeSceneBridge`, etc.). Useful for the host-
  package authors. Not useful for someone choosing how to embed.
- "Responsibilities Split" — internal contract between the root package and
  peer host packages.
- **"Non-Negotiable Decisions"** — eight numbered project-policy decisions.
  This is governance, not API.
- **"Out Of Scope"** — what we will not build. Roadmap policy.

The genuinely consumer-facing question is short: "I'm building an app — how
do I run it on terminal vs WASI vs SwiftUI vs browser?" That answer already
exists in `Running-Apps.md` and `SwiftTUI.md`.

**Recommendation:** replace the DocC article with a short "Embedding modes"
overview (3 bullet points: terminal-native runner, WASI runner, embedded host
package) that links to `Running-Apps.md` for the API and to
`docs/HOST_PACKAGES.md` for the package contract. Delete the rest.

### Articles with smaller extractable contributor sections

These articles are consumer-facing overall but contain a paragraph or section
that should move to a `docs/` doc.

#### `Core/Core.docc/Rendering-Pipeline.md`

**What to extract:** the "Why The Split Matters" section's bullets that
mention testing-pin granularity ("tests can pin exact behavior at the right
abstraction boundary") and diagnostic granularity ("diagnostics can report
where work was computed versus reused"). Those are contributor framings of
*why we kept the phase split* — appropriate for `docs/ARCHITECTURE.md`,
not for the consumer rendering-pipeline article.

**What to keep:** the seven-phase order, the role of each phase, and the
"Related Symbols" `Topics`.

**Severity:** Low. This is a single bullet list inside an otherwise-fine
article.

#### `View/View.docc/AspectCorrectShapes.md`

**What to extract:** the "Behavior at `.estimated` metrics" and "Quantization
caveat" sections describe fixture-equivalence properties — "fixtures captured
against the old rasterizer at default metrics remain bit-identical against the
new code", and integer-division collisions where 6×14 cells produce the same
3×3 sub-pixel as 8×16. Those are contributor concerns about regression
stability and rasterizer math precision.

A consumer benefits from knowing that aspect correction is a no-op at the
default 8×16 fallback (so they understand why their existing screenshots
don't change). They do not need the integer-division collision reasoning.

**What to keep:** "The math in one paragraph" and "Worked example". A
one-line note that aspect correction collapses to identity at the conventional
8×16 cell.

**What moves to `docs/`:** the rasterizer-equivalence and quantization
discussion. Either folded into the existing
`docs/proposals/CELL_PIXEL_METRICS.md` or into the
`docs/CELL_PIXEL_GEOMETRY_RESEARCH.md` background doc.

**Severity:** Low. Two short sections.

## Summary table

| DocC article | Action | Severity |
|---|---|---|
| `Core/Core.md` | Keep | — |
| `Core/CellPixelMetrics.md` | Keep (use as template pattern) | — |
| `Core/Rendering-Pipeline.md` | Trim "why-we-split" justification | Low |
| `View/View.md` | Keep | — |
| `View/Authoring-Views.md` | Keep | — |
| `View/State-Environment-And-Focus.md` | Keep | — |
| `View/State-Keying.md` | Reduce to ~30 lines (consumer guidance + link out) | **High** |
| `View/Focus.md` | Remove "scope hypothesis" paragraph + remove `List` design-diary section | **High** |
| `View/AspectCorrectShapes.md` | Remove fixture/quantization discussion | Low |
| `SwiftTUI/SwiftTUI.md` | Keep | — |
| `SwiftTUI/Architecture.md` | Trim transitional seams + internal coordinators | **Medium** |
| `SwiftTUI/Runtime.md` | Replace cost-model + crash-recovery sections with summary + link | **Medium** |
| `SwiftTUI/Vision.md` | Reduce to ~20 lines (or delete and fold into module page) | **High** |
| `SwiftTUI/Host-Integration.md` | Reduce to "embedding modes" overview (or delete) | **High** |
| `SwiftTUI/Running-Apps.md` | Keep | — |
| `SwiftTUICharts/SwiftTUICharts.md` | Keep | — |
| `SwiftTUICharts/Building-Dashboards.md` | Keep | — |

## Recommended pattern for refactored articles

The repo already demonstrates this on `Core/CellPixelMetrics.md`:

```markdown
# ``Core/CellPixelMetrics``

<one-paragraph symbol overview>

## Overview

<consumer-relevant API facts>

## Topics

### Reading the metrics
- ``width``
- ``height``
…

### Related discussion

- [Cell Pixel Geometry Research](https://…/docs/CELL_PIXEL_GEOMETRY_RESEARCH.md)
```

For non-symbol articles (the article-only pages like `State-Keying.md`,
`Architecture.md`, `Vision.md`, `Host-Integration.md`), the same shape works:

```markdown
# Article Title

<one-paragraph orienting summary>

## Overview

<consumer-facing facts: ~20–60 lines, no design-diary content>

## Practical Guidance

<actionable rules a consumer can follow>

## Related Articles

- <doc:OtherUserFacingArticle>

## Further Reading

- [Architecture details](https://github.com/.../docs/ARCHITECTURE.md)
```

The `Further Reading` link is intentionally outside `Topics` so the DocC
renderer treats it as out-of-band rather than as a primary navigation entry.

## A note on absolute GitHub URLs

`Core/CellPixelMetrics.md` currently uses an absolute `github.com` URL for
its outbound link. That works in the published archive but breaks in offline
docs and depends on the repo's public URL not changing. For the refactored
articles above, two alternatives are worth considering:

1. **Relative file URL** (e.g. `../../../../docs/STATE_KEYING.md`) — works in
   the source repo but fails in the rendered archive.
2. **A short, stable redirect doc** that lives inside the DocC catalog and
   links to the contributor doc. This trades one indirection for portability.

The current absolute-URL approach is acceptable for now. Consider revisiting
if/when the project gets a stable docs site.

## Drift risk and decision

Six DocC articles exist as near-twins of `docs/` files. Two have already
drifted materially (State-Keying by ~125 lines, Focus by ~190 lines). Every
edit to a contributor-facing topic currently has to land in two places, and
the historical evidence is that it doesn't.

The choice is between:

- **Status quo** — keep two copies, accept ongoing drift, accept that the
  published DocC archive will continue to ship contributor framing.
- **Refactor as proposed** — DocC owns the consumer surface, `docs/` owns
  the architectural treatment, each topic lives in exactly one place.

This proposal recommends the second. The CellPixelMetrics article shows the
pattern works without losing discoverability for consumers.

## Out of scope for this proposal

- Vendored DocC catalogs (`Vendor/swift-png/Sources/*/docs.docc/`,
  `.build/checkouts/*/.docc/`) — not project-owned.
- Worktree copies under `.worktrees/` — they will inherit changes when their
  branches reconcile.
- Header doc-comments (`///`) inside `Sources/`. The audit was scoped to
  `.docc` catalogs as the user requested. A follow-up audit could examine
  whether any source files have multi-paragraph `///` blocks that explain
  internal trade-offs (these would surface in the same DocC archive, since
  symbol doc-comments are how DocC renders symbol pages).
