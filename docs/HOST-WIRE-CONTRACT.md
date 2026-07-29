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
`style`, `caps`, `key`, `mouse`, and `paste` control records. It buffers a
partial control record until newline. Malformed or unknown controls are
dropped; they are not terminal input.

`surface` has three record shapes:

- Version 1 is a full frame with `styles` and `rows`.
- Version 2 is the same full-frame shape selected when the frame carries a
  sequence, accessibility tree, accessibility announcements, or scroll
  regions.
- Version 3 has `encoding: "delta"` and replaces `rows` with `deltaRows`.

The v1/v2 choice is not a capability revision. Additive fields such as links,
focus presentation, preferred grid size, and Android's terminal style can
appear without changing that choice. A v3 record is emitted only after
`acceptsDeltaFrames` has been declared and a compatible baseline exists.

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

`HostWireEncodingState` has three stateful axes. None currently carries an
epoch identifier, record generation, baseline generation, or delivery
acknowledgement.

### Transmit-once images

`knownImageIDs` is an insert-only set within one encoding state. The first
appearance of an image ID includes `dataBase64`; later appearances retain the
image's geometry and metadata but omit the payload. Reconstructing the
encoding state empties the set and causes payloads to be sent again.

The encoder has no current downlink acknowledging image retention and no
uplink through which a consumer can request a missing payload.

### Delta baseline

`hasBaseline` and `baselineSize` are the entire baseline currency. A full
frame establishes a baseline. A later frame may be a delta when:

- delta emission is enabled;
- damage is non-`nil`;
- the baseline grid size equals the current grid size; and
- damage does not request a full text repaint or graphics replay.

The state does not retain baseline rows. A delta record does not identify the
full or delta record to which it applies. The emitted record therefore lets a
consumer check only that it has a retained baseline with the same dimensions;
it cannot prove which record established that baseline.

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
| WASI browser | Capabilities and state are created with the transport. `present` encodes and mutates state, then synchronously writes the complete record to stdout. A write error can occur after the mutation; there is no acknowledgement. Reloading constructs a fresh transport. |
| Localhost WebHost | `present` encodes and mutates state before enqueuing bytes on the asynchronous FIFO sink pump. Send completion and failure are observed later through `drain` or a subsequent enqueue. Every accepted `caps` declaration replaces all encoding state and begins a new connection epoch. |
| Host-managed Android | Encoding is deferred to `copyLatestFrameBytes`. The first size query for a new sequence encodes into committed state, increments the encoded-frame count, and clears accumulated damage before checking whether a destination buffer can receive the bytes. The following copy call reuses those scratch bytes if the sequence is unchanged. |

These are encode-time epochs, not delivery-coupled epochs. A failed write,
failed asynchronous send, abandoned Android size query, failed decode, or
consumer eviction does not roll the encoder state back.

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

## Current consumer contract

Until the known gaps below close, a delta-capable consumer is implicitly
required to provide:

1. lossless, in-order application of every accepted surface record;
2. a baseline that survives for the entire encoding epoch;
3. perfect memory for every image ID whose payload appeared in that epoch;
4. a style table that accepts the complete accumulated table on every delta.

No deployed consumer has explicitly acknowledged that contract, and current
implementations violate parts of it:

- The browser decoder applies a delta to the last same-sized frame; it has no
  generation with which to detect a skipped or reordered record. A delta
  received without a retained baseline is dropped and leaves the current
  surface unchanged.
- The Android decoder also accepts a same-sized retained baseline without an
  epoch or baseline generation.
- The canvas painter removes a failed decode from its cache. A later
  payload-less repeat cannot retry the decode.
- The Android renderer stores decoded images in an 8 MiB `LruCache`. Eviction
  can discard a bitmap that the insert-only encoder will not resend.
  Oversized images bypass the cache and recycled entries are defensively
  skipped, but there is no recovery request after an ordinary eviction.
- Browser and Android accept unknown string tokens structurally. Browser
  consumption applies the defaults above; Android retains focus,
  accessibility, and scaling strings, omits image format from its model, and
  applies host-side defaults.

## Android single-looper convention

The supported Android host runs frame polling on the Android main looper. Each
iteration calls `tick()` and then performs the size/copy handshake
sequentially. `tick()` drains ready Swift main-actor work, including frame
commits. The exported lifecycle and frame-control entry points use checked
main-actor access, but the mutex-guarded copy entry point does not. The shipped
Kotlin poll loop's main-looper call order, rather than the copy ABI itself,
maintains the single-looper convention.

This convention currently prevents a Swift frame commit from interleaving
between the size query and copy in the supported host. Until delivery-coupled
candidate commit exists, a host that permits a frame commit between those two
calls must not use this handshake. The convention does not make the size query
a delivery acknowledgement: abandoning the second call still leaves encoder
state advanced.

## Known contract gaps

The coordination root tracks these gaps in
`docs/plans/2026-07-28-006-delivery-coupled-wire-epochs-plan.md`. That plan is
forward-looking; the rows below describe only what is missing at this
package's `HEAD`.

| Coordination stage | Gap at `HEAD` |
| --- | --- |
| S1 | Surface records have no epoch, generation, or baseline generation. Consumers cannot distinguish a contiguous delta from a stale or reordered one, and no transport accepts a keyframe or image resync request. |
| S2 | Image payloads are transmit-once, but a canvas decode failure or Android cache eviction can still lose one. There is no resend-on-miss path or retained-image acknowledgement. |
| S3a | Android's size query commits cross-frame encoder state before the bytes are copied and decoded. An abandoned handshake, a grown second query, or decode failure can strand that state. |
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
