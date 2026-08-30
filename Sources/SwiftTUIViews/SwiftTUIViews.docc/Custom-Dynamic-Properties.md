# Custom Dynamic Properties

Build your own property wrappers on the `DynamicProperty` extension point,
composing the built-in wrappers for storage.

## Overview

`DynamicProperty` is the protocol behind every stored property the framework
manages for a view: conform a custom property wrapper to it and the wrapper
becomes a first-class participant in view evaluation. Before each body
evaluation the framework discovers the view's conforming stored properties,
gives wrappers composed *inside* them their own per-instance state storage,
and calls the property's `update(in:)` under the enclosing view's authoring
scope, before the graph decides whether it can reuse prior output.

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

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    // Runs before every body evaluation of the enclosing view, after
    // this wrapper's own composed dynamic properties have updated.
    // Nonmutating here because this wrapper's state lives in its composed
    // `@State`; declare it `mutating` to write a stored property instead.
    return .unchanged
  }
}
```

The conformance is what buys composition safety. Two instances of a
conforming wrapper in one view hold distinct composed `@State` storage; the
framework qualifies each inner slot with the property's discovered position.
A plain helper struct that composes `@State` *without* conforming keeps the
legacy behavior: every instance's inner slot collapses onto the wrapper's
own declaration site, so instances silently share storage (the runtime
reports a `state.duplicateSlotClaim` runtime issue when this happens).

## The update pass

For each body evaluation of a view that stores dynamic properties, the
framework:

1. Discovers the view's stored properties conforming to `DynamicProperty`
   (reflection, cached per type; wrapper-free views pay one dictionary
   lookup). Only *stored* properties participate; computed properties are
   invisible to discovery, as in SwiftUI.
2. Recursively updates each property's own discovered dynamic properties
   first, then calls the property's `update(in:)` in place, so your update
   always observes live composed state and its own writes reach the body.
3. Uses the returned certification at the graph's reuse door, then evaluates
   the body only when reuse is declined.

The pass covers every body-evaluation surface (composed `body`
implementations, framework primitives, and `ViewModifier` bodies) under the
same ambient authoring scope the body observes. A certified enclosing subtree
may be served without descending into its already-certified children.

## Evaluation-visible state in a plain stored property

`update(in:)` is `mutating`, and the framework runs it through the container
copy that the *next body evaluation consumes*. A plain stored mutation is
therefore visible to that body and to every closure the body creates:

```swift
@propertyWrapper
struct Ticking: DynamicProperty {
  private var now: ContinuousClock.Instant = .now

  var wrappedValue: ContinuousClock.Instant { now }

  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    let sampled = ContinuousClock.now
    guard sampled != now else { return .unchanged }
    now = sampled
    return .changed
  }
}
```

The copy is private to one mount and one evaluation. Two mounts of the same
view *value* each prepare their own, so one mount's mutation is never visible
to another, and the value you wrote in the initializer is what the graph keeps
for reuse comparison.

A non-mutating implementation still satisfies the requirement, so reference
storage and composed built-in wrappers (`@State`'s box, `@Environment`'s
ambient lookup, a `Binding`'s closures) keep working unchanged — and remain
the right choice for anything that must outlive one evaluation, or that an
asynchronous callback writes.

### Where the in-place guarantee stops

The write lands when the property is a **strongly stored, statically typed
field of a struct container** — the shape a property-wrapper declaration always
produces. Two authored shapes have no addressable field slot to write back
through, and there the framework updates a copy:

- an **enum container** (a `View` or `DynamicProperty` that is an enum), whose
  payload `Mirror` can read but not address; and
- a field whose **static type is existential** (`Any`, `any SomeProtocol`) even
  though the value inside it conforms.

A stored mutation in either shape is dropped. Debug builds report the drop as
the `dynamic-property-mutation-discarded` soundness violation naming the
property and its container, so it is loud rather than silent — but the fix is
to declare the wrapper as a normal stored property, or to keep its
evaluation-visible state in reference storage.

A conforming type is itself a value type — a struct or an enum. A class
conformance does not compile; see <doc:Divergences-And-Gaps>. Class-typed
*fields* are unaffected: a view can store an `@Observable` model, a closure,
or a resource handle and still get the in-place update for its wrappers.

## Certify reuse explicitly

Return `.unchanged` only after registering every dependency that can affect
the wrapper's visible result. Return `.changed` when the result changed during
this update. The default is `.uncertified`; it conservatively denies both
retained and memoized reuse, including reuse of an enclosing subtree.

For a timer, subscription, or other external side channel, retain
`context.invalidationLease` in reference-backed storage. The lease can fire
from any executor and invalidates only the exact live graph node and
registration generation that issued it; a callback for departed content is
inert.

```swift
@propertyWrapper
struct AsyncReading<Value>: DynamicProperty {
  @MainActor
  final class Storage {
    var value: Value
    var lease: DynamicPropertyInvalidationLease?

    init(_ value: Value) {
      self.value = value
    }

    nonisolated func receive(_ value: Value) {
      Task { @MainActor in
        self.value = value
        self.lease?.invalidate()
      }
    }
  }

  private let storage: Storage

  init(wrappedValue: Value) {
    storage = Storage(wrappedValue)
  }

  var wrappedValue: Value {
    storage.value
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    storage.lease = context.invalidationLease
    return .unchanged
  }
}
```

Replace the stored lease on every update. A later registration supersedes the
old generation, and the framework revokes the route when the wrapper or graph
departs. The storage is still responsible for stopping its external work when
its own lifetime ends.

## Degraded paths

Outside a live graph (constructing views before mounting, or one-shot
snapshot rendering without an invalidating runtime), a composed `@State`
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
