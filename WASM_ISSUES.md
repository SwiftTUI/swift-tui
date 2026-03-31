# WASM Issues

## Resolved

The crashes observed when running wasm builds were mitigated by increasing stack size with `-Xlinker -z -Xlinker "stack-size=1048576"`

## Context

These notes capture what we learned while investigating the web example crash:

`Failed to start WebExampleApp: Out of bounds memory access (evaluating 'e.exports._start()')`

The work here was done against the `Examples/WebExample` wasm build, using the
`@bjorn3/browser_wasi_shim` harness to run `TerminalApp/dist/assets/app.wasm`
directly.

## High-level Summary

The original "button crash" is real, but it is not just an action-registration
problem or even purely a `Button` problem.

There appear to be at least two related wasm issues:

1. A standalone resolver/codegen problem around a generic `Content: View`
   wrapper that applies `foregroundStyle` from an `AnyShapeStyle` value and then
   participates in a `background { ... }` wrapper.
2. A broader control-body issue affecting manually resolved decorated children
   such as `Button` and `TextField`.

`Button` was simply the first obvious symptom in the web example.

## Confirmed Repro Matrix

### Safe

- `Button("Reset").buttonStyle(.plain)`
- A pseudo button built as plain `Text(...).padding(...).background { Rectangle().fill(.tint) }`
- `Link("Docs", destination: "https://example.com")`
- `Toggle("Enabled", isOn: .constant(false))` when it stays on the non-highlighted path
- `Text("Docs").foregroundStyle(AnyShapeStyle(.foreground)).background { Rectangle().fill(.tint) }`

### Crashes

- `Button("Default button")`
- `Button("Docs").buttonStyle(.link)`
- `TextField("Search", text: .constant("Docs"))`
- A generic wrapper shaped like this:

```swift
private struct StyledLabel<Content: View>: View {
  var content: Content

  var body: some View {
    let style = AnyShapeStyle(.foreground)
    content
      .foregroundStyle(style)
  }
}

private struct DecoratedLabel<Content: View>: View {
  var content: Content

  var body: some View {
    StyledLabel(content: content)
      .background {
        Rectangle().fill(.tint)
      }
  }
}
```

## What We Ruled Out

- It is not caused by button actions. The crash still happens with `Button`
  initializers that do not register an action.
- It is not caused by button semantics alone. A pseudo-button with explicit
  button-like semantic metadata was fine.
- It is not caused by the implicit `EmptyView` false branch in overlay/background
  builders. That was a separate resolver bug and fixing it did not eliminate the
  button crash.
- It is not just `chromeFill` / `chromeStrokeBorder`. Controls that never touch
  those helpers can still fail, and simpler pseudo-views can survive.
- It is not simply "any background modifier crashes in wasm". Simple
  `Text(...).background { ... }` compositions are fine.

## Strong Findings

### 1. Decorated button branches are the failing boundary

`Button` only survives on the `.plain` path. As soon as the button body takes a
decorated branch (`.link`, `.automatic`, `.bordered`, `.borderedProminent`),
wasm traps.

Instrumentation inside `Button.resolvedNode` showed:

- `buttonStyle == .link` reaches `"[button] resolving link body"` and then traps
  while resolving that child.
- `buttonStyle == .automatic` reaches `"[button] resolving chrome body"` and
  then traps while resolving that child.

So the failure is in child-body resolution, not action registration or parent
node creation.

### 2. The problem is broader than `Button`

`TextField("Search", text: .constant("Docs"))` also traps in wasm. That means
the crash is in shared control-body behavior, not something unique to button
role/action handling.

### 3. Generic `foregroundStyle(AnyShapeStyle)` plus `background` is one real repro

The smallest non-control repro we found was a generic `Content: View` wrapper
that:

- takes an `AnyShapeStyle` value
- applies `.foregroundStyle(style)` to generic content
- then becomes the base of `.background { ... }`

That combination traps in wasm.

By contrast, the same visual idea written directly on concrete `Text` is fine:

```swift
Text("Docs")
  .foregroundStyle(AnyShapeStyle(.foreground))
  .background {
    Rectangle().fill(.tint)
  }
```

This difference suggests the generic `View.foregroundStyle(...)` path matters.

### 4. Avoiding `AnyView` erasure in `View.foregroundStyle(...)` helped the standalone repro

A useful experiment was changing the generic `View.foregroundStyle` overload
from:

```swift
environment(\.foregroundStyle, AnyShapeStyle(style))
```

to returning `EnvironmentWritingModifier` directly.

That change eliminated the standalone generic-wrapper repro above.

Important: it did **not** fully fix `Button` or `TextField`, so it exposed one
real wasm fragility but not the whole control crash.

### 5. Nested child contexts appear to participate in the button failure

Another experiment changed button child resolution from:

```swift
context.child(component: .named("ButtonBody"))
```

to resolving in the parent `context`.

That did not fix the button, but it changed the failure mode:

- with the normal child context, the trap happened during child resolution
- with the parent context, the child resolved and the crash moved later in the
  frame pipeline

That is a strong signal that nested child identity/context handling is part of
the wasm failure, even if it is not the whole story.

### 6. Flattening the button root removes one real failure mode

A later experiment stopped returning an extra intrinsic `ResolvedNode(kind:
.view("Button"))` wrapper and instead:

- resolved the decorated button body directly
- rewrote that resolved root's `identity`
- rewrote that resolved root's `kind` to `.view("Button")`
- merged button semantics onto that root

That change was enough to make a lone default button boot successfully in the
wasm harness.

So the extra wrapper node is not incidental. It is one real part of the crash.

### 7. The wrapper fix is not sufficient on its own

Even with that flattened-root experiment in place, the button could still fail
once the surrounding stack content was restored.

What we observed in the clean harness:

- `Button("Default button")` alone: safe
- one plain `Text` sibling before the button: safe
- two plain `Text` siblings before the button: safe
- one `.foregroundStyle(.separator)` `Text` sibling before the button: safe
- the fuller preview stack from the web example (two plain texts plus the
  separator-styled explanatory text): crash

This means the remaining failure is not just "button chrome by itself". There
is still an interaction with surrounding sibling content in a stack.

### 8. Clean runs point to allocator blow-up during resolve

After removing the extra resolved-tree and measurement dumps, the failing runs
produced a clearer wasm-side message:

- `Fatal error: failed to allocate 3073 bytes of memory with alignment 4`

That happened while the button was on the `"[button] resolving chrome body"`
path, before `"[button] child resolved"` in some configurations.

So at least one remaining failure mode is a resolve-time allocation explosion,
not just a later measurement trap.

## Current Working Hypothesis

The remaining crash is probably an interaction between:

- manually resolved control subtrees (`child.resolve(in: context.child(...))`)
- nested wrapper modifiers like `background` / `overlay`
- child identity/context derivation
- generic view wrappers or erased modifier paths
- stack sibling interactions involving environment-driven text styling

In short: decorated control bodies are surviving native builds but producing a
bad wasm path once they are resolved as nested child subtrees, and flattening
the outer button node only removes one layer of that problem.

## Suggested Next Steps

1. Re-run the control matrix after each change, not just `Button`.
   Include at least:
   - `Button(.plain)`
   - `Button(.link)`
   - default `Button`
   - `TextField`
   - focused `Toggle`
2. Compare manual child resolution sites across controls:
   - `Button`
   - `TextField`
   - `Toggle`
   - `Menu`
   - `Stepper`
3. Investigate whether a control can safely build its decorated body without
   calling `.resolve(in: context.child(...))` on that complex subtree.
4. Audit any generic modifier helpers that still erase through `AnyView` before
   participating in wrapper modifiers.
5. If this remains hard to isolate in the app, add a tiny wasm-specific harness
   that renders a single authored view instead of booting the whole web example.
6. Compare the full preview stack against the reduced safe cases by adding
   siblings back one at a time, especially styled `Text` rows, to determine
   what additional state tips the flattened-button experiment back into failure.

## Session 2: Heap Pressure Analysis and AnyView Audit (2026-03-31)

### 9. Multiple modifier methods wrapped in unnecessary `AnyView`

An audit of modifier methods found six that wrapped their return value in
`AnyView(resolving:)` despite their underlying modifier structs already
conforming to `View & ResolvableView`:

- `drawMetadata(_:)` — used in every `ButtonPlainBody`
- `semanticMetadata(_:)` — used by `.tag()`
- `layoutMetadata(_:)` — used in `ButtonChromeBody` for `needsMinimumHeight`
- `id(_:)` — used for explicit identity assignment
- `environment(_:_:)` — used by `.buttonStyle()`, `.pickerStyle()`, etc.
- `transformEnvironment(_:transform:)` — used by `.disabled()`

Each `AnyView(resolving:)` allocates a closure on the heap. For a single
default button, `drawMetadata` alone creates 2 closures (opacity in
`ButtonPlainBody`, underline in `ButtonLinkBody`). With `environment()`
closures from `.buttonStyle(.link)` etc., a single button easily creates 4+
`AnyView` closure allocations.

**Fix applied:** all six methods now return their modifier struct directly as
`some View`, matching the pattern already used by `foregroundStyle`.

### 10. `settingEnvironment` redundantly recomputes `isFocused`

Both `settingEnvironment` and `transformingEnvironment` called
`contextualEnvironmentValues()` on every invocation. This method recomputes
`isFocused` by checking the identity against the focused identity. But these
methods don't change the identity or the focused identity — they only change
style/layout values like `foregroundStyle`, `tintStyle`, `isEnabled`, etc.

The recomputation was producing the same result every time. It also triggered an
extra copy of `EnvironmentValues` (a struct with a `[ObjectIdentifier: any
EnvironmentValueBox]` dictionary).

**Fix applied:** removed the `contextualEnvironmentValues` call from both
methods. The `isFocused` value is established in the `ResolveContext.init`
(which uses `applyEnvironmentValues: true`) and flows unchanged through
`child()` and `settingEnvironment` calls.

### 11. `applying(to:)` created two `EnvironmentSnapshotStorage` objects

`EnvironmentValues.applying(to:)` used property setters on `EnvironmentSnapshot`
that each allocated a new `EnvironmentSnapshotStorage` class instance:

```swift
var merged = snapshot
merged.values.merge(snapshotValues) { _, new in new }  // new storage #1
merged.style = StyleEnvironmentSnapshot(...)             // new storage #2
```

**Fix applied:** refactored to compute both fields first, then construct a
single `EnvironmentSnapshot` via init. Also added an early check for empty
`snapshotValues` to skip the merge entirely in the common case.

### 12. Per-button allocation map

With all three fixes applied, the allocation profile for a single default
button resolve (ButtonChromeBody path) is:

| Before | After | Source |
|--------|-------|--------|
| ~4 AnyView closures | 0 | drawMetadata, layoutMetadata, environment |
| 2 EnvironmentValues copies | 0 | contextualEnvironmentValues in settingEnvironment |
| 2 EnvironmentSnapshotStorage | 1 | applying(to:) double-setter |
| 7 Identity arrays | 7 | context.child() — unchanged |

Estimated reduction per button: ~6 heap allocations eliminated, 1 halved.

### 13. Areas investigated but not changed

**PaddingView / FrameView / FlexibleFrameView child contexts:** These single-
child layout wrappers create child contexts (`context.child(.named("content"))`)
for identity disambiguation. Removing the child context would save 1 Identity
array allocation per wrapper, but risks cache collisions in the resolve reuse
session during incremental updates. Left unchanged pending wasm-specific testing.

**BackgroundView / OverlayView dual child contexts:** Both create two child
contexts (base + decoration). These are needed for identity disambiguation when
both sides contain stateful or handler-registering views. Cannot be safely
removed.

**Identity representation:** Each `Identity.child()` allocates a new `[String]`
array via `components + [component.rawValue]`. A single-string path
representation would reduce allocations but is a larger refactor.

### Pre-existing test failure

The test "link Button lowers to link-colored underlined text without border
chrome" was already failing before this session. The expected background color
is `.white` but the actual is the tint color (blue) from `.background {
Rectangle().fill(.tint) }` in `ButtonLinkBody`. This appears to be a test
expectation that hasn't been updated to match the current rendering behavior.

## Practical Takeaway

If the immediate goal is "keep the web example booting", the safest short-term
approach is still to avoid default decorated controls in the default wasm scene.

If the goal is "fix button chrome in wasm", the most promising direction is to
treat this as a shared decorated-control resolution bug, not as a button-only
feature bug. The fixes in session 2 reduce per-button heap pressure
significantly but may not fully eliminate the allocator blow-up on their own —
they need to be tested against the actual wasm build.

## Remaining Next Steps

1. **Test the session 2 fixes in the actual wasm build.** The AnyView removal
   and allocation reductions should meaningfully reduce heap pressure but need
   validation against the real allocator failure.
2. Re-run the control matrix from the original suggested steps.
3. If the crash persists, investigate:
   - Increasing the wasm default memory (linker flags or wasm-ld options)
   - Further reducing `Identity.child()` array allocations (compact path representation)
   - Adding `@inline(never)` to more resolve methods to reduce code size
   - Flattening the button root (Finding #6) combined with session 2 fixes
4. Consider whether the `EnvironmentValues.storage` dictionary (existential
   `any EnvironmentValueBox` values) contributes significant per-value heap
   pressure and whether a flat struct could replace it for common keys.

