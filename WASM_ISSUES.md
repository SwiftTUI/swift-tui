# WASM Issues

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

## Current Working Hypothesis

The remaining crash is probably an interaction between:

- manually resolved control subtrees (`child.resolve(in: context.child(...))`)
- nested wrapper modifiers like `background` / `overlay`
- child identity/context derivation
- generic view wrappers or erased modifier paths

In short: decorated control bodies are surviving native builds but producing a
bad wasm path once they are resolved as nested child subtrees.

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

## Practical Takeaway

If the immediate goal is "keep the web example booting", the safest short-term
approach is still to avoid default decorated controls in the default wasm scene.

If the goal is "fix button chrome in wasm", the most promising direction is to
treat this as a shared decorated-control resolution bug, not as a button-only
feature bug.
