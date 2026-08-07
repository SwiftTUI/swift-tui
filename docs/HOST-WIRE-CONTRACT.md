# Host Wire Contract

This document is the normative description of the converged host wire at
`HEAD`. It covers record shapes, cross-frame state, capability ingress,
transport ratchets, and current consumer obligations. The canonical field inventory
remains `HostWireSchema`. This document explains the stateful behavior that a
field manifest cannot express.

For host ownership and execution modes, see
[HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md). This contract covers the
web-surface stream shared by the WASI browser host, localhost WebHost, and the
host-managed Android path. It does not change the terminal-native protocol.
The external native `SwiftUIHost` receives committed frames directly and does
not consume this serialized stream.

## Record framing and shapes

Every typed record is UTF-8 and has the same outer framing:

```text
0x1E <record-type> ":" <payload> "\n"
```

The Swift encoder currently emits four record types:

| Record | Payload |
| --- | --- |
| `surface` | A JSON object containing a full or delta surface frame. |
| `clipboard` | A JSON object containing text requested for the system clipboard. |
| `runtimeIssue` | A JSON object containing a runtime warning or error. |
| `frameDiagnostic` | A JSON object containing the format plus its header and fields. |

The input parser accepts terminal bytes mixed with RS-prefixed `resize`,
`style`, `caps`, `resync`, `pointer`, `key`, `mouse`, and `paste` control
records. It buffers a partial control record until newline. Malformed or
unknown controls are dropped. They are not terminal input.

`pointer` is the only control record whose payload is `key=value` tokens
rather than positional fields:

```text
0x1E "pointer:" <key> "=" <value> [":" <key> "=" <value> …] "\n"
```

`panning` is the only key today. `panning=1` declares that the client's
native interaction paradigm scrolls by dragging content directly, which is
true of touch devices and coarse-pointer browsers and false of desktop
pointers. Absence of the record means the desktop paradigm, so a page bundle
that predates it behaves exactly as before. Unrecognized keys are skipped and
a record carrying only unrecognized keys is dropped, so a later key can be
added without changing this record's arity.

Unlike `caps`, this record is live on every ingress including the in-process
WASI transport: it describes the browsing device rather than the decoder, and
a device can change paradigm mid-session without reconnecting.

`surface` has three record shapes:

- Version 1 is a full frame with `styles` and `rows`.
- Version 2 is the same full-frame shape selected when the frame carries a
  sequence, accessibility tree, accessibility announcements, or scroll
  regions.
- Version 3 has `encoding: "delta"` and replaces `rows` with `deltaRows`.

The v1/v2 choice is not a capability revision. Additive fields such as
`epoch`, `gen`, links, focus presentation, preferred grid size, and Android's
terminal style can appear without changing that choice. The encoder emits a
v3 record only after a consumer declares `acceptsDeltaFrames` and establishes
a compatible baseline. The record also carries `baselineGen`.

## Evolution rules

The following rules are load-bearing:

1. Unknown JSON object keys are additive and must be ignored. New optional
   data ships as a new key. Absence means that feature is not present.
2. Cell, rectangle, point, size, hyperlink, and damage tuples are frozen. The
   browser decoder requires their exact arity. Android currently reads known
   slots leniently. Extend the enclosing object with a parallel key instead of
   adding a tuple element, because deployed browser decoders reject an added
   slot.
3. The version literals describe record shapes, not contract revisions.
   Additive fields do not bump the version.
4. An incompatible new record shape requires a named capability in
   `HostWireCapabilities`, with an ingress and an absence-means-current-bytes
   default for every transport.
5. String token vocabularies are manifest-frozen for emission but open-world
   at decoding. Extending an emitted vocabulary requires both a
   `HostWireSchema` manifest edit and review of every decoder's degradation
   default. An unknown string must not reject an otherwise-structural frame.

Browser and Android decoders reject a `surface` version newer than the newest
shape they understand. This skew guard is separate from capability
negotiation. There is no encoder-side version ceiling.

## String token vocabularies

`HostWireSchema` owns the frozen emitted sets for focus semantics,
announcement politeness, accessibility live regions, image formats, and image
scaling modes. Consumers normalize unknown strings at the point where a token
affects behavior:

| Unknown token | Browser degradation |
| --- | --- |
| Focus semantics | `automatic` |
| Announcement politeness | `polite` |
| Accessibility-node live region | Ignored |
| Image scaling mode | `fit` |
| Image format | Skip that image only |

Unknown image formats do not reject the frame or suppress sibling images.
Structural type errors remain frame-invalidating. Open-world treatment applies
only when the field is otherwise a string.

## Cross-frame encoder state

`HostWireEncodingState` has four stateful axes. It carries record identity and
repairable baseline/image state, but still has no delivery acknowledgement.

### Encoding epoch and record generation

Each newly negotiated encoding state receives a process-local `UInt32`
`epochID`. Records emitted from that state carry the additive-optional keys
`epoch` and `gen`. `gen` begins at 1 and increases once for every full or delta
record the encoding state commits. A delta also carries `baselineGen`, the
generation immediately preceding it in that epoch. On the Android copy ABI, the
commit is the delivery leg. The encoder discards a generation for a handshake
that never copied. Thus, a consumer never receives a `baselineGen` that names an
unsent record.

The tuple `(epoch, gen)` is encoder-owned. It is not the runtime frame
`sequence`. A keyframe repair can re-encode the same Android frame sequence at a
new generation. The host can skip several runtime frames before it consumes one
Android record. Reconstructing the complete encoding state, such
as an accepted WebSocket capability declaration, allocates a new epoch.
Repairing an existing state does not.

These fields are optional in the schema for legacy compatibility but are
always emitted by the current Swift encoder. Their addition does not change
the full-frame version literals, the delta version literal, or the capability
set.

### Transmit-once images

`knownImageIDs` records which payloads were transmitted within one encoding
state. The first appearance of an image ID includes `dataBase64`. Later
appearances retain the image's geometry and metadata but omit the payload.
Reconstructing the encoding state empties the set and causes payloads to be
sent again.

A `resync:{"scope":"images","ids":[...]}` uplink removes those IDs from the
set so their next appearance includes payload bytes again. Omitting `ids`, or
sending an empty list, clears the whole set. The encoder still has no
downlink acknowledging which images a consumer retained.

Consumers can keep decoded images in bounded caches. A payload-less record with
an uncached ID is a recoverable miss. The consumer admits eligible missing IDs
to an `images` resync request, subject to its documented resource bounds. The
accepted surface frame still advances. An unresolved
image is absent, or an existing cached image remains visible, until a
payload-carrying appearance repairs that ID. Requests are deduplicated per ID
while outstanding. A consumer retries a delivery failure only when its
transport defines that failure as retryable.

Android resolves the resync JNI entry point lazily for version-skew
compatibility. A return value of zero means the old native host does not expose
the entry point. Android treats that request as unavailable and keeps the ID
outstanding and deduplicated until its payload arrives or the encoding epoch is
reset or restarted. It does not retry-poll the unavailable symbol, and an
incidental keyframe does not count as image repair.

The browser canvas painter retains a first-seen payload through at most three
decode attempts. It drops the retained base64 after decode succeeds. It requests
the ID after the retry budget ends or after a payload-less record misses its
cache. It tracks at most 256 unresolved entries and 64 MiB of retained
payload. The consumer defers overflow and can retry it on a later presented
frame instead of admitting it immediately. The DOM painter also offers an
unknown payload-less ID for resync instead of silently omitting it. Browser
resync admission is capped at 1,024 outstanding IDs. A successfully delivered
request stays deduplicated while its ID remains present and unresolved. Payload
arrival, removal from a presented frame, or an encoding epoch reset clears the
encoding epoch resets. Disappearance therefore lets a later reappearance
request the ID again.

Android keeps its decoded bitmap cache bounded at 8 MiB. An ordinary eviction
is repaired through the same per-ID request and payload re-application path
rather than by pinning every transmitted image in memory. Oversized Android
images continue to bypass the cache.

### Delta baseline

`hasBaseline` and `baselineSize` are the entire baseline currency. A full
frame establishes a baseline. A later frame can be a delta when all of these
conditions are true:

- delta emission is enabled.
- damage is non-`nil`.
- the baseline grid size equals the current grid size.
- damage does not request a full text repaint or graphics replay.

The state does not retain baseline rows. A delta identifies its immediately
preceding record through `baselineGen`. Together with `epoch`, a consumer can
reject a stale, reordered, or non-contiguous delta. A
`resync:{"scope":"keyframe"}` request clears `hasBaseline`, so the next record
is full in the same epoch and consumes the next generation.

### Persistent style epoch

A full frame builds a first-appearance-ordered style table and, on a
delta-capable stream, starts a new persistent style epoch. Each delta interns
new styles into that table.

How a delta *transmits* that table depends on one negotiated bit:

| `styleAppend` | Delta `styles` | `stylesBase` |
| --- | --- | --- |
| Undeclared (deployed default) | The entire accumulated table | Absent |
| Declared | Only the styles this record added | The retained table's length |

The append shape is negotiated rather than additive because its *presence*
changes how `styles` must be read. A decoder that replaces its table wholesale
mis-indexes every style in the record. A consumer that declared
`styleAppend` splices `styles` onto its retained table at `stylesBase`. If
`stylesBase` does not equal that table's length, the consumer refuses the record
and requests a keyframe. Splicing at the wrong offset silently repaints cells in
the wrong style, which is strictly worse than refusing and recovering.

The full retransmit it replaces was measured at Stage SV as 69.7% of
late-record bytes in a style-churning epoch. The append shape cuts a
300-frame 80×24 opacity-fade run by 62.9% overall and 75.8% across its last
50 frames.

The table budget is `max(1,024, grid area + 1)`, including the explicit
`null` style in slot zero. If a delta exceeds the budget, encoding falls
back to a full frame and starts a new style epoch.

## Where state ratchets

Encoding mutates the state before any transport has proof that a consumer
retained the bytes.

| Transport | Current ratchet |
| --- | --- |
| WASI browser | Capabilities and state are created with the transport. `present` encodes and mutates state, then synchronously writes the complete record to stdout. A write error can occur after the mutation. There is no acknowledgement. Reloading constructs a fresh transport. A parsed `resync` record mutates the existing state under its mutex. |
| Localhost WebHost | `present` encodes and mutates state before enqueuing bytes on the asynchronous FIFO sink pump. Send completion and failure are observed later through `drain` or a subsequent enqueue. An accepted `caps` declaration replaces all encoding state and begins a new connection epoch. `resync` instead repairs the current epoch under the same state mutex. Whether a record is *delivered* is a separate decision the channel makes from its connection phase — see [WebHost connection lifecycle](#webhost-connection-lifecycle). |
| Host-managed Android | **Delivery-coupled.** Encoding is deferred to `copyLatestFrameBytes` and runs against a *candidate* copy of the encoding state. A size query for a newer sequence encodes and stores that candidate beside committed state. A copy serves the scratch that its preceding size query measured. It never serves a newer re-encode. It promotes candidate → committed only after it writes bytes into the caller's buffer. An accepted resync drops the whole scratch, including any uncommitted candidate, so the next handshake re-encodes from repaired committed state. |

The WASI and WebHost rows are encode-time epochs. A failed write, a failed
asynchronous send, or a consumer eviction does not roll the encoder state back.
Android is the only transport where encode and delivery are separate calls.
Its ratchet is therefore coupled to delivery. See
[Android delivery-coupled commit](#android-delivery-coupled-commit).

## Capability ingress

`HostWireSchema.capabilityMappings` is the canonical mapping. There are
currently two named bits:

| Capability | Default | Effect |
| --- | --- | --- |
| `acceptsDeltaFrames` | `false` | Permits v3 delta records after a full baseline. |
| `styleAppend` | `false` | A delta carries `stylesBase` plus only the styles it added, instead of the whole accumulated table. |

Absence begins with full-frame output. A rejected declaration leaves the
existing state unchanged. Each accepted declaration constructs the whole
encoding state rather than patching one field.

The ingress lifecycle differs by transport:

- **WASI browser — construction only.** `SWIFTTUI_SURFACE_DELTA` is resolved
  once when the transport is built. Runtime `caps` input is deliberately
  ignored because reload creates a new in-process transport.
- **Localhost WebHost — once per connection, before any surface record.** The
  browser client sends one `caps:{"acceptsDeltaFrames":true}` record after
  opening a socket. That is now the only accepted shape. The channel accepts a
  declaration from the current connection only while the connection is in the
  pre-capabilities phase. A second declaration on the same connection does not
  start a new epoch. An accepted declaration clears the delta baseline and transmitted-image
  set, marks the session surface-active, and requests a refresh.
- **Host-managed Android — before scene start only.** `declareCapabilities`
  rejects malformed declarations and declarations after start. The JNI bridge
  resolves the declaration symbol lazily, so a newer AAR against an older
  native host degrades to defaults.

`SWIFTTUI_SURFACE_MAX_VERSION` is retired and inert. Versions are decoder
shape guards, not negotiated ceilings.

## Delivery repair uplink

`HostWireSchema.DeliveryUplink` manifests the two records that change or
repair cross-frame wire state: `caps` and `resync`. Resync is always safe and
therefore is not a capability bit. The Foundation-free request parser accepts:

- `{"scope":"keyframe"}` to force the next surface record full.
- `{"scope":"images","ids":[...]}` to request selected image payloads, with
  omitted or empty `ids` meaning all images.

Malformed requests and unknown scope tokens are rejected without mutation.
Unknown object keys are skipped for additive compatibility.

The scopes are independent and can be requested together. Keyframe resync
clears only the delta baseline. It does not clear `knownImageIDs` or force all
image payloads to repeat. Image resync removes only the selected IDs. It does
not clear the delta baseline. If both repairs are outstanding, the next record
is a full keyframe whose image list re-carries only the requested payloads
(or every payload when the image request omitted `ids`).

Ingress follows each host's existing control channel:

- **WASI browser:** the shared input parser produces the request and
  `WASIRunner` routes it to `WebSurfaceTransport`. Runtime `caps` remains
  deliberately ignored because WASI capability negotiation is
  environment-owned.
- **Localhost WebHost:** `WebSocketInputReader` routes it to
  `WebSocketSurfaceTransport`.
- **Host-managed Android:** `AndroidHostSceneHost.requestResync(json:)` and
  the `swift_tui_android_request_resync` C ABI route it to mutex-guarded host
  state.

## Current consumer contract

Every delta-capable consumer is required to:

1. Apply accepted surface records in order.
2. Reject a delta unless its retained `(epoch, gen)` matches the delta's
   `(epoch, baselineGen)`, preserving the last internally consistent frame.
3. Request one keyframe repair for a rejected stamped delta. Deduplicate that
   request until a full frame is applied. Retry only delivery failures that the
   transport defines as retryable.
4. Request selected image payloads after bounded decode retries or cache
   misses while bounding admission and retained unresolved data. Browser can
   defer overflow and deduplicates an admitted ID until payload, disappearance,
   or epoch reset, while Android deduplicates until payload or epoch reset. An
   unavailable Android JNI request remains outstanding instead of being
   retried or cleared by an incidental keyframe.
5. Accept the complete accumulated style table on every delta.

The sibling browser and Android decoders both consume the producer's additive
generation fields. They retain the last applied `(epoch, gen)`, refuse a
stamped delta whose baseline does not match, and request a keyframe instead of
corrupting the retained grid. Their delivery paths deduplicate an outstanding
keyframe request until a full frame is applied. Browser transports requeue
retryable send or queue failures. Android's lazy-JNI old-host return of zero
means unavailable. It remains deduplicated instead of repeatedly invoking a
missing entry point.

Both consumers also implement resend-on-miss without making image retention
unbounded. Browser decode failures use the bounded retry path above. The limits
are 256 unresolved canvas entries, 64 MiB of retained payload, and 1,024
admitted outstanding request IDs. Capacity overflow can be deferred for
a later frame. A browser request is cleared by payload repair, disappearance
from a presented frame, or epoch reset. Android keeps its 8 MiB `LruCache` and
drains missing payload IDs into image-resync requests. It suppresses another
successful request for an ID until a payload-carrying record clears it. When
the Android resync entry point is unavailable, the ID remains outstanding
until payload repair or an encoding epoch reset or restart. An incidental
keyframe does not clear it. Browser and Android accept unknown string tokens
structurally. Browser consumption applies the defaults above. Android retains
focus, accessibility, and scaling strings, omits image format from its model,
and applies host-side defaults.

## WebHost connection lifecycle

One scene input stream lives for the whole session. A client connection comes
and goes beneath it. The channel is in one of four phases.

| Phase | Surface records | Non-surface records | Scene input |
| --- | --- | --- | --- |
| `detached` | Dropped | Retained, bounded FIFO of 32 (oldest dropped at the cap) | Alive |
| `pre-capabilities` | Dropped, observed as suppressed | Delivered, after the detached backlog is flushed in order | Alive |
| `active` | Delivered | Delivered | Alive |
| `terminal` | Dropped | Dropped | Finished |

**Blank beats stale.** A surface record buffered while no client is attached
cannot serve the next client. A delta names a baseline that the fresh decoder
does not have. Even a full frame belongs to the encoding epoch that ended with
the previous client. Neither record can become a fallback delivery. The
reconnecting client's first surface record is the keyframe produced by its own
declaration.

**A client close is connection-local.** It transitions the channel to
`detached` and must not finish the scene input continuation. Finishing it
terminates `WebSocketInputReader` permanently, so a reattaching client's
declaration cannot be read and the session cannot leave
`pre-capabilities`. Only `shutdown()` finishes scene input, and
`WebHostServerSession.stop()` calls it before the server stop handler on every
path so no stop can omit it. `shutdown()` is idempotent: the second call is a
no-op, and later attach, send, input, and close callbacks cannot reactivate or
deliver.

**Connection tokens.** Each `attach` takes the next monotonically increasing
token. The channel accepts a `close` message, capability declaration, or parsed
input record only while its token names the current connection. This rule stops
a late callback from a replaced client from detaching, activating, or injecting
input into its successor. Ordinary teardown of a connection the channel already
retired is not counted as an ignored stale callback. An explicit stale `close`
message is.

**Inbound bytes are tagged, and refused in three places.** Scene input is a
stream of `connectionOpened` / `bytes(token:)` / `connectionClosed` / `shutdown`
events rather than raw chunks, and the reader owns parser state for exactly one
connection:

| Refusal point | Reason recorded | What it prevents |
| --- | --- | --- |
| Before parsing | `stale-at-ingress` (already superseded when it arrived) or `stale-at-consumption` (current on arrival, still queued when superseded) | A chunk in flight during a reconnect combining with the new client's bytes |
| At `connectionOpened` | `connection-boundary` | The successor's first chunk completing a partial record the previous client left in the parser |
| Before applying a parsed record | Not recorded as a chunk. The record has no effect. | A connection retires while the code holds a parsed declaration or input event. |

A retired connection's receive loop deliberately outlives detachment so bytes
already in flight are refused *with a reason* rather than vanishing.
`shutdown()` cancels whatever is left.

## Android delivery-coupled commit

The two-phase copy ABI is a size query (`outBuffer == nil`) followed by a copy.
Because those are two calls, a frame commit can land between them, and the
first call can be abandoned entirely. The ABI is sound under both:

- **The size query is not a delivery acknowledgement.** It encodes against a
  candidate copy of the encoding state. This copy contains the transmitted-image
  set, the accumulated style epoch, and the delta baseline. The query leaves
  committed state untouched. A handshake that is never copied consumes no generation, transmits
  no image, and advances no baseline. The next size query re-encodes from
  committed state. Therefore, the record after an abandoned candidate uses the
  generation and baseline generation that the consumer holds.
- **A copy delivers what its size query measured.** A commit that lands
  mid-handshake does not make the copy re-encode: reporting one frame's size
  and delivering another is exactly the straddle this coupling closes. The
  newer frame is picked up by the next poll.
- **Accumulated damage follows the same candidate rule.** Damage unions across
  committed-but-unpolled frames, because a consumed frame's own damage
  under-covers the diff against the previous *consumed* frame. The candidate
  encode consumes that union. Frames that arrive during the handshake
  accumulate from empty. Thus, a commit drops exactly the damage that the
  delivered record covered. An abandoned candidate folds its damage back into the live
  accumulator instead of dropping it.
- **An undersized copy is not a delivery.** When the caller's capacity cannot
  hold the record, the reported size is returned, no bytes leave the process,
  and nothing ratchets. The client retries with the reported size and receives
  the same record.

A host can therefore commit frames from a thread other than the one performing
the handshake without corrupting the wire. The shipped Kotlin poll loop still
calls `tick()` and then the handshake sequentially on the Android main looper.
That ordering is a scheduling property of the client, not a soundness
requirement of the ABI.

## Contract stage status

The coordination root tracks this program in
`docs/plans/2026-07-28-006-delivery-coupled-wire-epochs-plan.md`. That plan is
forward-looking. The rows below describe only the state at this package's
`HEAD`.

| Coordination stage | State at `HEAD` |
| --- | --- |
| S1 | Complete: every surface record carries an epoch and generation. Deltas name their baseline generation. All three Swift host ingresses accept keyframe/image resync. The sibling browser and Android decoders compare stamped baselines and emit deduplicated keyframe repairs. |
| S2 | Resend-on-miss is complete. Browser decode/cache misses enter bounded unresolved/request tracking, with overflow deferred and admitted IDs deduplicated until payload repair, disappearance, or epoch reset. Android bitmap-cache eviction requests selected IDs deduplicated until payload repair or epoch reset. Android treats a lazy-JNI old-host return of zero as unavailable rather than retrying it or treating an incidental keyframe as image repair. The wire still has no retained-image acknowledgement. |
| S3a | Complete: the Android copy ABI encodes against a candidate and commits only when bytes are copied out. An abandoned size query, an undersized copy, or a commit landing mid-handshake leaves committed encoder state and accumulated damage intact. See [Android delivery-coupled commit](#android-delivery-coupled-commit). |
| S3b | Complete: the detached backlog drops surface records and bounds the rest at 32. A client close is connection-local and leaves scene input alive. Every connection carries a token that gates input, close, and capability callbacks. Session stop is the sole idempotent terminal transition. See [WebHost connection lifecycle](#webhost-connection-lifecycle). |
| S3d | Complete: with `styleAppend` negotiated, a delta carries `stylesBase` and only its appended styles. All three decoders splice onto their retained table and refuse a base that does not match it. Undeclared streams keep the full retransmit byte for byte. See [Style epoch](#persistent-style-epoch). |
| S3e | Complete. The browser/WASI shared input queue writes a control record larger than its remaining 64 KiB capacity as ordered chunks. It does not reject the record, so a large paste arrives intact. A write that fits with nothing queued ahead of it still lands **synchronously**. Only a write that cannot fit suspends and waits for capacity. Writes are **serialized**. A small write issued while a chunked one is suspended queues behind it. It does not take the fast path or land inside the first record. Capacity waits are bounded by a caller-owned deadline, and a deadline failure surfaces as a runtime issue in the mount, not console-only. |

The Stage SV investigation also tested the claimed unbounded Android damage
union. That claim is **refuted**, not a current gap:
`PresentationDamage` normalizes duplicate rows and overlapping ranges during
construction. After 10,000 unpolled one-cell commits, the public copy seam
still emitted one row and one range. There is no required S3c stage unless
different evidence establishes a separate bound problem.
The measurement is recorded in the coordination root's
`docs/reports/2026-07-28-006-delivery-coupled-wire-epochs-sv-evidence.md`.

## Source anchors

The principal Swift sources for this contract are:

- `Sources/SwiftTUIRuntime/Terminal/HostWireSchema.swift`
- `Sources/SwiftTUIRuntime/Terminal/HostWireCapabilities.swift`
- `Sources/SwiftTUIRuntime/Terminal/HostWireFrameModel.swift`
- `Sources/SwiftTUIRuntime/Terminal/HostWireStyleTable.swift`
- `Sources/SwiftTUIRuntime/Terminal/WebSurfaceFrameEncoder.swift`
- `Sources/SwiftTUIRuntime/Terminal/WebSurfaceImageEncoder.swift`
- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceInputParser.swift`
- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`
- `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostServer.swift`
- `Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidHostSceneHost.swift`
- `Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidHostABI.swift`
- `Sources/SwiftTUICore/Commit/PresentationDamage.swift`

Consumer behavior is implemented in the sibling repositories by
`swift-tui-web/packages/web/src/WebHostSurfaceTransport.ts`, its DOM and canvas
painters, and
`swift-tui-android/swift-tui-host/src/main/kotlin/sh/swifttui/android/host/`.
Those repositories remain the source of truth for their own decoder and
renderer behavior.
