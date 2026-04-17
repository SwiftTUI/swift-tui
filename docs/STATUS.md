# Status

Last updated: April 14, 2026

## Product Status

The core terminal UI stack is implemented and regression-tested across the full frame pipeline:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The package is already usable for real terminal interfaces. The main gaps are
not around the fundamental pipeline anymore; they are around breadth of surface
area, app-shell ergonomics, and a few still-conservative runtime paths.

The 2026 terminal-native reset is substantially landed: automatic chrome has
been reset, shell navigation primitives are canonical, multiline editing and
indeterminate loading are public, and toast/sheet presentation surfaces now
live in the main `View` module instead of only in earlier exploratory work.

## Shipped Surface

### Authoring surface

- SwiftUI-shaped `@MainActor`-isolated `View` authoring with body-only `View`, `@ViewBuilder`, `TupleView`, `ConditionalContent`, `AnyView`, and `Resolver`
- Layout and containers including `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, `GeometryReader`, and custom `Layout`, with `LazyVStack` and `LazyHStack` supporting viewport-lazy placement and single-`ForEach` full-lazy rows
- Controls and primitives including `Text`, proposal-aware `TextFigure` backed by embedded FIGlet fonts, rich `Text` interpolation, `Link`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, determinate and indeterminate `ProgressView`, `Label`, `LabeledContent`, `GroupBox`, `ControlGroup`, `Spacer`, `Divider`, and shapes
- PNG-backed `Image` with named-resource, local-file-URL, and embedded-byte sources plus `.resizable()`, `.scaledToFit()`, and `.scaledToFill()`
- Environment, observation, and focus including `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `PreferenceKey`, subtree preference readers, `OpenLinkAction`, actor-context-aware `.task(...)`, and default-focus modifiers
- Presentation and workflow surfaces including terminal-native `alert`, `confirmationDialog`, `sheet`, `toast`

### Runtime surface

- `DefaultRenderer` for one-shot rendering and pipeline inspection from the main actor
- `RunLoop` for interactive terminal sessions
- `TerminalHost`, terminal appearance detection, graphics-capability probing, capability-aware presentation, and OSC 8 hyperlink emission when supported
- host-owned `Theme` and paired `TerminalRenderStyle` updates so hosted
  sessions and browser/WASI runtimes can switch semantic themes at runtime
- Keyboard parsing, mouse input parsing, Unix signal handling, and runtime scheduling
- Identity-driven lifecycle diffs with post-present appear, disappear, task start, and task cancel staging
- Kitty and Sixel image presentation with ANSI or ASCII fallback compositing when graphics protocols are unavailable

### Scene and multi-scene surface

- `@MainActor` `App`, `Scene`, `SceneBuilder`, `WindowIdentifier`, and `WindowGroup` declarations in `TerminalUI`
- `TerminalUISceneDescriptor`, `TerminalUISceneManifest`, and `HostedSceneSession` in `TerminalUI` for host-package tooling and retained non-terminal hosting
- `TerminalCLIAppRunner` in `Runners/TerminalUICLI` for terminal-native executable launch, scene discovery, attach, and pty-backed secondary scenes
- `TerminalWASIAppRunner` in `Runners/TerminalUIWASI` for manifest generation and WASI-hosted scene launch
- The same authored `App` can feed three execution modes: terminal-native execution, WASI execution, or host-managed embedding through peer GUI host packages
- Pty-backed secondary scenes, Unix-domain-socket discovery, scene attachment, and lazy rendering of unattached secondary scenes
- `TabView` for terminal-native shell composition
- terminal-native `alert` and `confirmationDialog` presentation in the canonical `View` surface

### Charts

- `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, `BulletChart`, `Meter`, `Legend`, `HeatStrip`, and `StackedBarChart`

## Current Constraints

- The core `TerminalUI` runtime still renders one active scene into one active host per session, but it no longer decides that an authored app must declare exactly one scene.
- `TerminalUI` is now library-only. Platform integration splits between executable runner packages in `Runners/` and embedded host packages in `GUI/`.
- Embedded GUI host packages now use `TerminalUI` scene manifests plus `HostedSceneSession`, and the repository includes peer host packages at `GUI/SwiftUITUIGUI`, `GUI/SwiftTermTUIGUI`, `GUI/WebTUIGUI`, and `GUI/XtermWebTUIGUI`. Those packages still own their own platform shell integration, scene switching chrome, and style surfaces.
- Embedded GUI host packages own one active host style object at a time and
  can swap it at runtime; the root TUI app continues to render semantic tokens
  without knowing which host theme is active.
- The runtime is keyboard-first, but mouse input is supported where the terminal advertises reporting. Pointer interaction should be treated as additive rather than as the primary design center.
- Image decoding and terminal presentation are PNG-only in the current runtime. Broader media formats and animation remain deferred.
- WASI support now works with the `swiftly`-managed Swift 6.3.0 toolchain and `swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm ...` through the `Runners/TerminalUIWASI` / example-app build path. The shorter `swift ...` form is fine from a shell where `swift` already resolves through `swiftly`. `xcrun swift` may still resolve to an incompatible Xcode toolchain.
- Some focus surfaces are still missing:
  - namespace-scoped default-focus APIs such as `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus`
  - object-focused wrappers such as `@FocusedObject`
- Some geometry-bound preference surfaces are still deferred:
  - anchor-based preference APIs such as `anchorPreference(...)` and `transformAnchorPreference(...)` until local coordinate spaces and anchor resolution ship
- Some higher-level workflow surfaces are still unsettled:
  - richer multiline editing behaviors beyond the current `TextEditor`
  - toolbar, command, and keybinding surfaces (see hypothesis below)
- Some internal lowering seams remain package-only for runtime plumbing and tests:
  - `ViewNode`
  - `ResolvableView`

## Deferred By Design

See [VISION.md](VISION.md) for the rationale and the intended ordering.

- `NavigationStack`
- popover-style presentation beyond the current sheet support
- richer accessibility and assistive-technology modeling beyond the current semantic tree

The project now treats terminal-native reinterpretation as a first-class design
rule. The remaining gaps are therefore prioritized around terminal workspaces,
deeper scroll control, and navigation surfaces that still need a stronger
hypothesis before they graduate.

### Commands, Keybindings, and Scope Hypothesis

An earlier toolbar/command-palette/help-sheet implementation was reverted
because it preceded a clear design model. The current hypothesis operates at
a deeper level than toolbars or commands specifically.

**Commands belong to scopes. A scope is a tree-authored command set with an
activation predicate. The activation predicate is focus-chain membership.**

#### The abstraction: App Navigation ⊂ Modal App Behavior ⊂ Scopes

Users don't think "which view is rendering?" They think "what can I do right
now?" What they can do changes when they push a screen, open a modal, switch
tabs, enter a mode (vim-style), select something, or the app suppresses
interaction.

All of these are mode changes. Navigation is one disciplined kind of mode —
one that carries spatial visualization, stack-like nesting, and reversibility.
But navigation is not the primitive; modes are. And "mode" is a subset of a
more general abstraction: **scopes**.

#### The focus chain is the activation predicate

Every scope has an anchor node in the view tree. Tree presence is a
prerequisite — a scope whose anchor isn't resolved can't fire — but presence
alone isn't activation. A resolved-but-unreachable node (background tab,
severed focus path) is philosophically silent.

The actual activation predicate: **the anchor node is on the current focus
chain.** There is always a focus chain from the app root down to whichever
leaf currently owns focus. Every node on the chain is reachable by input;
every node off the chain is silent.

#### Candidate scope kinds

| Scope | Anchor predicate | UI correspondent |
|---|---|---|
| **App** | root is on chain (trivially always) | help overlay / `?` menu |
| **Screen** | current screen node is on chain | title/nav bar |
| **Presentation** | modal node is on chain (tail) | the modal itself |
| **Input** | named focus region is on chain | focus indicator |
| **Selection** | orthogonal state predicate | selection chrome |

All five differ only in *which node's chain-membership they predicate about*.
Modal shadowing falls out naturally: the modal node becomes the tail; the
parent is still on the chain above it, so parent scope is still active — the
modal's bindings just have priority on collisions (deeper wins).

Ship with a curated small set. The friction of adding a sixth kind is the
feature — it prevents ad-hoc scope proliferation.

#### Four requirements, reframed via the focus chain

- **Lifetime** — anchor node stays on the focus chain long enough to be useful
- **Locality** — author the command near the state it operates on; ensure that node is on the chain when the command should fire
- **Composability** — the focus chain is a stack; scopes compose by stacking
- **Discoverability** — the chain is knowable; the framework can enumerate active scopes

#### Discoverability invariant

Every active scope must have either a persistent chrome surface or a
discoverability path. Scopes without chrome still have to answer "how would
the user know?" This is what distinguishes a scope from a hidden mode — the
failure case we're escaping.

#### What `.onKeyPress()` becomes

A low-level escape hatch for "handle this key while this specific view is on
the focus chain." Not the primary keybinding API. The primary API is
scope-declaration at natural DSL boundaries (App, NavigationStack levels,
TabView, `.sheet()`, focus regions, selection state).

#### Current state and constraints

This hypothesis has not yet been implemented. The framework currently has:

- `.onKeyPress()` → global `HotkeyRegistry`, tree-lifetime-dependent, fragile
- `LocalKeyHandlerRegistry` → focus-identity-keyed, package-internal, used by built-in controls

Neither corresponds to the scope model. Both operate below the abstraction
we want.

#### Open design questions

- **Precedence on collisions.** If Selection-scope and Screen-scope both bind `d`, who wins? Depth on the chain is one ordering; scope-kind priority (Selection > Presentation > Screen > App) is another. Probably some combination.
- **State-predicated scopes still tree-author.** Selection state lives on some node; its anchor is that node. What's different is the activation predicate, not the authoring site.
- **Escape-hatch risk.** Someone will want a scope that doesn't fit the five. A generic condition-scope would become a dumping ground. Resist until a real case proves the curated set insufficient.
- **Modes aren't always navigation.** Vim-style modes (insert/normal/visual) are state-predicated scopes that don't correspond to tree transitions. The model handles this, but the DSL needs state-predicate scopes as first-class, not just structural ones.

#### Design sequence

When designing scope, command, and keybinding APIs:

1. Start from scope kinds — what are the activation predicates users care about?
2. For each scope kind, identify the anchor node type in the DSL
3. For each scope kind, identify the UI correspondent (or the discoverability path if not visibly chromed)
4. Define precedence for collisions across scopes
5. Only then: design the authoring API

Do not start from the authoring API. Starting there is what produced `.onKeyPress()`.

## Documentation Status

- Public module DocC catalogs now exist per target and should be treated as the public API guide
- The repository `README.md` is the public landing page
- The Markdown files in `docs/` remain the source of truth for architecture, runtime behavior, and API governance

## Reference Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): target boundaries and frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime behavior, lifecycle semantics, and incremental rendering
- [HOST_PACKAGES.md](HOST_PACKAGES.md): runner-package and embedded-host packaging model
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): current source ownership map
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): classified public surface inventory
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): future API governance rules
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture and regression policy
