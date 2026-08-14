# Dormant Tab State

`TabView` resolves only the selected tab body. When selection changes, the
departing body is torn down and its persistent value state is archived until
that tag becomes active again. Inactive bodies do not evaluate, draw, publish
semantics, register handlers, or remain in the live view graph.

## Identity and lifetime

An archive belongs to one live `TabView` owner and one selection identity. The
key includes the tag value, its optional-matching policy, and its duplicate-tag
occurrence. Stable tags therefore preserve state across declaration reorder,
including state nested below an explicit `id`. Removing a tag evicts its
archive, reinserting it starts from authored seeds, and replacing the owning
`TabView` creates a new lifetime with no inherited archive.

Unique, stable tags are the supported shape. Duplicate tags receive isolated
occurrence keys so storage cannot alias, and SwiftTUI reports a
`tab.duplicateTag` runtime warning because selection between equal tags is
ambiguous.

The registry is stored on the `TabView` owner and retains at most one archive
per declared inactive tab. Repeated switching does not retain historical view
nodes or create an unbounded cache.

Payload entity routes are scoped by the nearest enclosing entity plus the
`TabView`'s authored identity, never by a graph-node allocation. A `TabView`
nested inside another tab can therefore rejoin both its active payload and its
own inactive-tab archives when the outer tab returns. The persistent registry
contains only tag keys, lifetime generations, numeric refresh tokens, and
value-only archives. Live graph locator recipes are stored in a separate
transient slot and are not nested into an enclosing archive.

The live active payload has two structural levels. The outer payload node owns
the stable tab entity. Its unowned child identity contains the owner-scoped
typed tag, optional-matching bit, duplicate occurrence, and lifetime
generation. Authored content is centrally resolved at that qualified child and
its resolved root is returned unchanged. A public `id` can therefore own the
child without displacing the tab entity, while lifecycle, semantics, behavior,
layout, and reuse metadata remain attached to the authored root.

## What is preserved

The archive is deliberately narrower than a view-node snapshot. It stores
state-slot values only when their producer declares them persistent and the
payload is recursively value-only. It also stores closure-free entity-routing
anchors for state owners; these are identity values, not retained view nodes,
and exist only so activation can preseed parent routes before descendant state:

- `State`, including `State` nested inside a custom `DynamicProperty`
- `FocusState` value storage
- collection scroll anchors used by list and table windows
- navigation-destination activation currency

`State` remains generic, so persistent provenance is followed by a second
safety audit. Values containing a class instance, task/native-object handle,
metatype, `ObjectIdentifier`, binding or other closure, unmanaged reference,
or unsafe pointer are not archived. Archive records store only the audited
value and its type metadata; they reconstruct a fresh slot on activation
rather than retaining the live slot's comparator closure. A nested archive may
carry that framework-owned type metadata only when it exactly matches the
audited enclosed value; user-authored metatype state remains ineligible.

Excluding persistent state is never silent. SwiftTUI emits the deduplicated
`tab.dormantStateUnsupportedValue` runtime issue with the stored type and asks
the author to use recursively value-only state or hoist that ownership above
the `TabView`. Task, native-handle, closure/binding, unmanaged-reference, and
pointer payloads are not retained as a fallback.

Restoration creates the selected tab's state owners and installs these values
before dynamic-property updates and body evaluation. Entity-bearing records
are prepared at their authored immutable identities and bound to their real
entity routes. Multiple entity owners can therefore coexist at one structural
position without displacing each other from the graph; authored resolution
adopts each routed owner in the same frame. A prepared owner that the authored
payload does not claim is reclaimed at the frame barrier, so restoration does
not leave placeholder nodes behind.
Synchronous and asynchronous rendering use the same graph operation. The
archive registry and newly prepared state owners participate in the frame
checkpoint, so an aborted frame does not partially consume or publish dormant
state.

If an asynchronous frame tail is suspended while the departing tab receives a
state write, the completed-frame candidate captures a value-only refresh before
materializing the prepared graph. Commit applies that refresh after
materialization and immediately before finalization, guarded by the exact state
owner lifetime and a numeric refresh token. Dropped candidates and stale tokens
cannot mutate the committed registry.

## What is torn down

Everything with a live runtime edge remains transient. Dormancy does not retain
`GestureState`, view nodes, resolved or drawn output, action and input handlers,
focus candidates, lifecycle registrations, tasks, observation dependencies,
presentation portals, animation runtime state, or evaluator closures.

Consequently, returning to a tab re-establishes its runtime registrations and
lifecycle normally. `onAppear` runs again, tasks start again, focus candidacy is
derived from the new active tree, and gesture state begins at its authored
seed. Only the persistent value families listed above cross the dormant seam.
