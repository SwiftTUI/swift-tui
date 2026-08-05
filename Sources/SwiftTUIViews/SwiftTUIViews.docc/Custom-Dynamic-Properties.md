# Custom Dynamic Properties

Build your own property wrappers on the `DynamicProperty` extension point,
composing the built-in wrappers for storage.

## Overview

`DynamicProperty` is the protocol behind every stored property the framework
manages for a view: conform a custom property wrapper to it and the wrapper
becomes a first-class participant in view evaluation. Before each body
evaluation the framework discovers the view's conforming stored properties,
gives wrappers composed *inside* them their own per-instance state storage,
and calls the property's `update()` under the enclosing view's authoring
scope.

```swift
@propertyWrapper
struct Debounced: DynamicProperty {
  @State private var accepted = ""
  @State private var pendingSince: ContinuousClock.Instant? = nil
  private let delay: Duration

  init(delay: Duration = .milliseconds(300)) {
    self.delay = delay
  }

  var wrappedValue: String {
    accepted
  }

  mutating func update() {
    // Runs before every body evaluation of the enclosing view, after
    // this wrapper's own composed dynamic properties have updated.
  }
}
```

The conformance is what buys composition safety. Two instances of a
conforming wrapper in one view hold distinct composed `@State` storage — the
framework qualifies each inner slot with the property's discovered position.
A plain helper struct that composes `@State` *without* conforming keeps the
legacy behavior: every instance's inner slot collapses onto the wrapper's
own declaration site, so instances silently share storage (the runtime
reports a `state.duplicateSlotClaim` runtime issue when this happens).

## The update pass

For each body evaluation of a view that stores dynamic properties, the
framework:

1. Discovers the view's stored properties conforming to `DynamicProperty`
   (reflection, cached per type — wrapper-free views pay one dictionary
   lookup). Only *stored* properties participate; computed properties are
   invisible to discovery, matching SwiftUI.
2. Recursively updates each property's own discovered dynamic properties
   first, then calls the property's `update()` — so your `update()` always
   observes live composed state.
3. Evaluates the body.

The pass runs on every body-evaluation surface — composed `body`
implementations, framework primitives, and `ViewModifier` bodies — under the
same ambient authoring scope the body observes. When a subtree is served
from reuse, neither the body nor the update pass runs; see the contract
below.

## The copy-semantics contract

`update()` receives a *copy* of the property. Effects that go through
reference-backed storage — every built-in wrapper: `@State`'s box,
`@Environment`'s ambient lookup, `Binding`'s closures — persist. Mutations
to plain stored fields of your wrapper are discarded when `update()`
returns.

This is a recorded divergence from SwiftUI, where an `update()` mutation to
a plain stored property is visible to that one body evaluation (and only
that one — SwiftUI also starts each cycle from a pristine copy). The rule of
thumb is the same in both frameworks: state that must survive between
evaluations belongs in composed reference-backed storage, never in plain
stored fields.

## Keep update() inside the dependency vocabulary

A reused subtree skips body evaluation *and* the update pass. Every
dependency a wrapper can express through the framework — state slots,
environment values, focus state, focused values, observable reads — already
denies reuse when it changes, so a wrapper built from those is always
consistent: if none of its inputs changed, skipping its `update()` is
unobservable.

The contract consequence: `update()` must not carry effects *outside* that
vocabulary. A wrapper that manages its own timer, subscription, or external
side channel from `update()` gets no guarantee the framework will call it —
no reuse gate can deny reuse for a dependency the graph cannot see. Route
external inputs through composed `@State` writes (which invalidate the
owner) instead.

## Degraded paths

Outside a live graph — constructing views before mounting, one-shot
snapshot rendering without an invalidating runtime — a composed `@State`
follows the same seed-storage path as a directly-declared one: reads serve
the wrapper's initial value, writes update the detached seed. See
<doc:State-Keying> for where graph-backed storage begins and ends, and for
owner-placement guidance that applies unchanged to composed wrappers.

Reads through your wrapper inside a body are reader-attributed exactly like
direct wrapper reads: the dependency lands on the node that actually
evaluates the read, so a wrapper that merely projects a binding does not
re-resolve the owner's whole subtree.

## Topics

### Related articles

- <doc:State-Keying>
- <doc:State-Environment-And-Focus>
- <doc:Divergences-And-Gaps>
