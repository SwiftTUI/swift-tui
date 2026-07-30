# Host Wire Contract

This document is the normative description of the converged host wire at
`HEAD`: its record shapes, cross-frame state, capability ingress, transport
ratchets, and current consumer obligations. The canonical field inventory
remains `HostWireSchema`; this document explains the stateful behavior that a
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
`style`, `caps`, `resync`, `key`, `mouse`, and `paste` control records. It
buffers a partial control record until newline. Malformed or unknown controls
are dropped; they are not terminal input.

`surface` has three record shapes:

- Version 1 is a full frame with `styles` and `rows`.
- Version 2 is the same full-frame shape selected when the frame carries a
  sequence, accessibility tree, accessibility announcements, or scroll
  regions.
- Version 3 has `encoding: "delta"` and replaces `rows` with `deltaRows`.

The v1/v2 choice is not a capability revision. Additive fields such as
`epoch`, `gen`, links, focus presentation, preferred grid size, and Android's
terminal style can appear without changing that choice. A v3 record is
emitted only after `acceptsDeltaFrames` has been declared and a compatible
baseline exists; it additionally carries `baselineGen`.

## Evolution rules

The following rules are load-bearing:

1. Unknown JSON object keys are additive and must be ignored. New optional
   data ships as a new key; absence means that feature is not present.
2. Cell, rectangle, point, size, hyperlink, and damage tuples are frozen. The
   browser decoder checks their exact arity; Android currently reads known
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
negotiation; there is no encoder-side version ceiling.

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
Structural type errors remain frame-invalidating; open-world treatment applies
only when the field is otherwise a string.

## Cross-frame encoder state

`HostWireEncodingState` has four stateful axes. It carries record identity and
repairable baseline/image state, but still has no delivery acknowledgement.

### Encoding epoch and record generation

Each newly negotiated encoding state receives a process-local `UInt32`
`epochID`. Records emitted from that state carry the additive-optional keys
`epoch` and `gen`; `gen` begins at 1 and increases once for every full or delta
record the encoding state commits. A delta also carries `baselineGen`, the
generation immediately preceding it in that epoch. On the Android copy ABI the
commit is the delivery leg, so a generation encoded for a handshake that never
copied is discarded rather than consumed — a consumer therefore never receives
a `baselineGen` naming a record it was never sent.

The tuple `(epoch, gen)` is encoder-owned. It is not the runtime frame
`sequence`: a keyframe repair can re-encode the same Android frame sequence
at a new generation, and several runtime frames can be skipped before one
Android record is consumed. Reconstructing the complete encoding state, such
as an accepted WebSocket capability declaration, allocates a new epoch.
Repairing an existing state does not.

These fields are optional in the schema for legacy compatibility but are
always emitted by the current Swift encoder. Their addition does not change
the full-frame version literals, the delta version literal, or the capability
set.

### Transmit-once images

`knownImageIDs` records which payloads were transmitted within one encoding
state. The first appearance of an image ID includes `dataBase64`; later
appearances retain the image's geometry and metadata but omit the payload.
Reconstructing the encoding state empties the set and causes payloads to be
sent again.

A `resync:{"scope":"images","ids":[...]}` uplink removes those IDs from the
set so their next appearance includes payload bytes again. Omitting `ids`, or
sending an empty list, clears the whole set. The encoder still has no
downlink acknowledging which images a consumer retained.

Consumers may keep decoded images in bounded caches. A payload-less record
whose ID is no longer cached is a recoverable miss: the consumer admits
eligible missing IDs to an `images` resync request, subject to its documented
resource bounds. The accepted surface frame still advances; an unresolved
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
decode attempts, drops the retained base64 after decode succeeds, and requests
that ID after the retry budget is exhausted or a payload-less record misses
its cache. It tracks at most 256 unresolved entries and 64 MiB of retained
payload; overflow is deferred and may be retried on a later presented frame
rather than being admitted immediately. The DOM painter likewise offers an
unknown payload-less ID for resync instead of silently omitting it. Browser
resync admission is capped at 1,024 outstanding IDs. A successfully delivered
request stays deduplicated while its ID remains present and unresolved, but is
cleared when payload arrives, the ID disappears from a presented frame, or the
encoding epoch resets. Disappearance therefore lets a later reappearance
request the ID again.

Android keeps its decoded bitmap cache bounded at 8 MiB; an ordinary eviction
is repaired through the same per-ID request and payload re-application path
rather than by pinning every transmitted image in memory. Oversized Android
images continue to bypass the cache.

### Delta baseline

`hasBaseline` and `baselineSize` are the entire baseline currency. A full
frame establishes a baseline. A later frame may be a delta when:

- delta emission is enabled;
- damage is non-`nil`;
- the baseline grid size equals the current grid size; and
- damage does not request a full text repaint or graphics replay.

The state does not retain baseline rows. A delta identifies its immediately
preceding record through `baselineGen`; together with `epoch`, a consumer can
reject a stale, reordered, or non-contiguous delta. A
`resync:{"scope":"keyframe"}` request clears `hasBaseline`, so the next record
is full in the same epoch and consumes the next generation.

### Persistent style epoch

A full frame builds a first-appearance-ordered style table and, on a
delta-capable stream, starts a new persistent style epoch. Each delta interns
new styles into that table. The `styles` field of every delta contains the
entire accumulated table, not only the new suffix.

The table budget is `max(1,024, grid area + 1)`, including the explicit
`null` style in slot zero. If a delta would exceed the budget, encoding falls
back to a full frame and starts a new style epoch.

## Where state ratchets

Encoding mutates the state before any transport has proof that a consumer
retained the bytes.

| Transport | Current ratchet |
| --- | --- |
| WASI browser | Capabilities and state are created with the transport. `present` encodes and mutates state, then synchronously writes the complete record to stdout. A write error can occur after the mutation; there is no acknowledgement. Reloading constructs a fresh transport. A parsed `resync` record mutates the existing state under its mutex. |
| Localhost WebHost | `present` encodes and mutates state before enqueuing bytes on the asynchronous FIFO sink pump. Send completion and failure are observed later through `drain` or a subsequent enqueue. Every accepted `caps` declaration replaces all encoding state and begins a new connection epoch; `resync` instead repairs the current epoch under the same state mutex. |
| Host-managed Android | **Delivery-coupled.** Encoding is deferred to `copyLatestFrameBytes` and runs against a *candidate* copy of the encoding state. A size query for a newer sequence encodes and stores that candidate beside committed state; a copy serves the scratch its preceding size query measured — never a newer re-encode — and promotes candidate → committed only once bytes are written into the caller's buffer. An accepted resync drops the whole scratch, including any uncommitted candidate, so the next handshake re-encodes from repaired committed state. |

The WASI and WebHost rows are encode-time epochs: a failed write, a failed
asynchronous send, or a consumer eviction does not roll the encoder state back.
Android is the one transport where encode and delivery are separate calls, and
it is therefore the one transport whose ratchet is coupled to delivery — see
[Android delivery-coupled commit](#android-delivery-coupled-commit).

## Capability ingress

`HostWireSchema.capabilityMappings` is the canonical mapping. There is
currently one named bit:

| Capability | Default | Effect |
| --- | --- | --- |
| `acceptsDeltaFrames` | `false` | Permits v3 delta records after a full baseline. |

Absence begins with full-frame output. A rejected declaration leaves the
existing state unchanged. Each accepted declaration constructs the whole
encoding state rather than patching one field.

The ingress lifecycle differs by transport:

- **WASI browser — construction only.** `SWIFTTUI_SURFACE_DELTA` is resolved
  once when the transport is built. Runtime `caps` input is deliberately
  ignored because reload creates a new in-process transport.
- **Localhost WebHost — any time, every arrival is an epoch.** The browser
  client intends to send one `caps:{"acceptsDeltaFrames":true}` record after
  opening a socket, but the server accepts declarations at any time. Each
  arrival clears the delta baseline and transmitted-image set.
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

- `{"scope":"keyframe"}` to force the next surface record full; and
- `{"scope":"images","ids":[...]}` to request selected image payloads, with
  omitted or empty `ids` meaning all images.

Malformed requests and unknown scope tokens are rejected without mutation.
Unknown object keys are skipped for additive compatibility.

The scopes are independent and may be requested together. Keyframe resync
clears only the delta baseline; it does not clear `knownImageIDs` or force all
image payloads to repeat. Image resync removes only the selected IDs; it does
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

1. apply accepted surface records in order;
2. reject a delta unless its retained `(epoch, gen)` matches the delta's
   `(epoch, baselineGen)`, preserving the last internally consistent frame;
3. request one keyframe repair for a rejected stamped delta, deduplicate that
   request until a full frame is applied, and retry only delivery failures its
   transport defines as retryable;
4. request selected image payloads after bounded decode retries or cache
   misses while bounding admission and retained unresolved data; browser may
   defer overflow and deduplicates an admitted ID until payload, disappearance,
   or epoch reset, while Android deduplicates until payload or epoch reset; an
   unavailable Android JNI request remains outstanding instead of being
   retried or cleared by an incidental keyframe; and
5. accept the complete accumulated style table on every delta.

The sibling browser and Android decoders both consume the producer's additive
generation fields. They retain the last applied `(epoch, gen)`, refuse a
stamped delta whose baseline does not match, and request a keyframe instead of
corrupting the retained grid. Their delivery paths deduplicate an outstanding
keyframe request until a full frame is applied. Browser transports requeue
retryable send or queue failures. Android's lazy-JNI old-host return of zero
means unavailable; it remains deduplicated instead of repeatedly invoking a
missing entry point.

Both consumers also implement resend-on-miss without making image retention
unbounded. Browser decode failures use the bounded retry path above, with at
most 256 unresolved canvas entries or 64 MiB of retained payload and at most
1,024 admitted outstanding request IDs. Capacity overflow can be deferred for
a later frame. A browser request is cleared by payload repair, disappearance
from a presented frame, or epoch reset. Android keeps its 8 MiB `LruCache`,
drains missing payload IDs into image-resync requests, and suppresses another
successful request for an ID until a payload-carrying record clears it. When
the Android resync entry point is unavailable, the ID remains outstanding
until payload repair or an encoding epoch reset or restart; an incidental
keyframe does not clear it. Browser and Android accept unknown string tokens
structurally. Browser consumption applies the defaults above; Android retains
focus, accessibility, and scaling strings, omits image format from its model,
and applies host-side defaults.

## Android delivery-coupled commit

The two-phase copy ABI is a size query (`outBuffer == nil`) followed by a copy.
Because those are two calls, a frame commit can land between them, and the
first call can be abandoned entirely. The ABI is sound under both:

- **The size query is not a delivery acknowledgement.** It encodes against a
  candidate copy of the encoding state — the transmitted-image set, the
  accumulated style epoch, and the delta baseline — and leaves committed state
  untouched. A handshake that is never copied consumes no generation, transmits
  no image, and advances no baseline; the next size query re-encodes from
  committed state, which is why an abandoned candidate's frame is followed by a
  record whose generation and baseline generation are the ones the consumer
  actually holds.
- **A copy delivers what its size query measured.** A commit that lands
  mid-handshake does not make the copy re-encode: reporting one frame's size
  and delivering another is exactly the straddle this coupling closes. The
  newer frame is picked up by the next poll.
- **Accumulated damage follows the same candidate rule.** Damage unions across
  committed-but-unpolled frames, because a consumed frame's own damage
  under-covers the diff against the previous *consumed* frame. The candidate
  encode consumes that union and frames arriving during the handshake
  accumulate from empty, so a commit drops exactly the damage the delivered
  record covered. An abandoned candidate folds its damage back into the live
  accumulator instead of dropping it.
- **An undersized copy is not a delivery.** When the caller's capacity cannot
  hold the record, the reported size is returned, no bytes leave the process,
  and nothing ratchets. The client retries with the reported size and receives
  the same record.

A host may therefore commit frames from a thread other than the one performing
the handshake without corrupting the wire. The shipped Kotlin poll loop still
calls `tick()` and then the handshake sequentially on the Android main looper,
but that ordering is now a scheduling property of the client, not a soundness
requirement of the ABI.

## Contract stage status

The coordination root tracks this program in
`docs/plans/2026-07-28-006-delivery-coupled-wire-epochs-plan.md`. That plan is
forward-looking; the rows below describe only the state at this package's
`HEAD`.

| Coordination stage | State at `HEAD` |
| --- | --- |
| S1 | Complete: every surface record carries an epoch and generation, deltas name their baseline generation, all three Swift host ingresses accept keyframe/image resync, and the sibling browser and Android decoders validate stamped baselines and emit deduplicated keyframe repairs. |
| S2 | Resend-on-miss is complete: browser decode/cache misses enter bounded unresolved/request tracking, with overflow deferred and admitted IDs deduplicated until payload repair, disappearance, or epoch reset; Android bitmap-cache eviction requests selected IDs deduplicated until payload repair or epoch reset. Android treats a lazy-JNI old-host return of zero as unavailable rather than retrying it or treating an incidental keyframe as image repair. The wire still has no retained-image acknowledgement. |
| S3a | Complete: the Android copy ABI encodes against a candidate and commits only when bytes are copied out. An abandoned size query, an undersized copy, or a commit landing mid-handshake leaves committed encoder state and accumulated damage intact. See [Android delivery-coupled commit](#android-delivery-coupled-commit). |
| S3b | `WebHostSceneChannel` retains an unbounded detached output backlog and flushes it when a client attaches, before processing that client's capability declaration. Detached surface records can therefore precede the epoch reset intended for the new client. |
| S3d | Every delta retransmits the complete accumulated style table. Measured style churn makes late-record cost grow with the epoch rather than with current damage. |
| S3e | The browser/WASI shared input queue rejects a control record larger than its remaining 64 KiB capacity as one chunk. The paste route catches and reports the error but drops the whole logical paste. |

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
