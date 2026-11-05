# SwiftTUI host wire profile 1

Profile ID: `swifttui.host-wire/1`. JSON Schema dialect: 2020-12.
The schema defines structure. This document defines semantics and admission;
passing the schema alone does not establish conformance. Package versions,
contract kit revisions, wire capabilities and native ABI revisions are separate.
Full record versions 1 and 2 and delta record version 3 retain their meanings.

## Admission and evolution

Apply transport ingress limits first, then the 4 MiB record limit (RS through
payload, excluding LF), UTF-8 and nesting depth (at most 32), JSON structure,
field semantics, and session applicability. Grid axes are at most 1,024 and area
at most 65,536. Limits, canonical vocabularies and tuple arities are indexed in
`../schemas/host.schema.json`. Cells are exactly `[x,text,spanWidth,styleIndex]`.
A cell lies in the current grid, has positive span, follows its predecessor
without overlap, and references the effective style table. Omitted trailing
full-frame rows are empty; an empty delta row clears the retained row.

Writers never extend tuples. Unknown optional object keys are ignored. Display
vocabularies are open: unknown focus semantics is nonediting automatic focus,
unknown announcement politeness is polite, unknown live-region tokens are
unset, unknown image formats are skipped and unknown scaling modes fit. Unknown action names are never dispatched.
Optional is distinct from nullable: only styles and legacy scene titles/defaults
admit JSON null. A malformed optional action response is discarded locally;
its surrounding otherwise valid frame remains usable. Secure-field values are
never presented to accessibility clients.

Canonical writers emit ASCII decimal UInt64 IDs, bounded by
18,446,744,073,709,551,615. IDs are strings, never JSON numbers. Legacy action
ID ingress may normalize up to twenty decimal digits of zero padding. Signs,
separators, non-ASCII digits, empty IDs and overflow are invalid. Target tokens
are opaque, nonempty and distinct from presentation IDs. Text selection units
are UTF-16. Percent escapes decode once to valid UTF-8; LF, RS, percent and
colon in a value are escaped before framing.

The strict admission profile rejects duplicate JSON keys and nonfinite numbers,
including finite JSON exponent spellings that overflow the receiver's binary64.
A delta may jump generation numbers when its declared baseline exactly matches
the retained generation. Generation is not an acknowledgement watermark. Legacy
reader differences are retained as explicit expectations in the conformance
corpus; they are not permission for new writers to emit ambiguous records.

## Receiver transitions

| Event | Preconditions and commit | Failure and recovery |
| --- | --- | --- |
| Full frame | Validate all state-bearing fields, then replace grid, style table and metadata atomically. New epoch clears session image knowledge and pending requests. | Preserve the last valid presentation and request a keyframe. |
| Delta | Same epoch, dimensions and `baselineGen` as retained frame; apply validated whole rows atomically. `stylesBase`, when present, equals retained style count. | Preserve grid/styles and coalesce a keyframe request until repair. |
| Style append | Consumer declared `styleAppend`; concatenate at `stylesBase` and validate indices against the resulting table. | No partial splice; keyframe repair. |
| Image payload | Retain payload by opaque image ID; placement may omit bytes for a known ID. | A missing/evicted/failed image requests its ID; image repair does not invalidate grid state. |
| Image repair request | `scope=images`, with requested IDs; missing/empty IDs means all. | Retransmit requested payloads while preserving the raster baseline. |
| Keyframe repair request | `scope=keyframe`. | Invalidate raster baseline, preserve delivered image knowledge. |
| Action reply | Request ID and target exactly match an outstanding request in the current session. Settle it once. | Unissued, repeated, other-target or old-session replies have no effect. |
| Reset | Clear parser fragments, raster/image state and pending requests; retain no previous-session action target. | Late responses cannot settle new requests. |

Each action has four separate phases: validate encoding, enqueue, authorize at
dispatch, publish a correlated outcome. Queue acceptance does not imply runtime
acceptance. Runtime authorization checks target lifetime, modal scope, enabled
and read-only state, supported operation, and secure-text policy. Rejected input
emits no terminal keys. Unknown/malformed control records are discarded through
their LF. Partial records are buffered; an RS inside an admitted input command
abandons the fragment and starts a new control. Overflow discard continues
through LF even if it encounters RS. Connection replacement discards fragments.

Pending action retention is bounded (256 requests, 30 seconds) and targets
removed from a frame retire their requests. Request identifiers are not reused
within the lifetime of a host owner, including resets. App focus generation is
independent and is reset with the connection. Image recovery IDs are capped at
1,024, each at most 1,024 UTF-8 bytes; disappeared images retire pending repairs.

## Delivery profiles

WASI (`swifttui.wasi-command/1`) selects capabilities at startup from the documented
surface environment and advances encoding state when a record is encoded.
Input command boundaries are not read boundaries. Buffered input and terminal
escape handling retain event ordering. WASI's finite input queue can impose a
tighter per-command ingress budget; callers must observe delivery failure.

WebSocket (`swifttui.companion/1`) accepts one capability declaration per
connection. Acceptance starts a new epoch, baseline and image knowledge.
Encoding advances before asynchronous FIFO enqueue; failed sends do not rewind
that encoding state. The pump drops dependent queued batches and disconnects
the failed connection. Teardown retires its token and fragments/backlog. A replacement connection starts a
new session even if it selects the same scene. `sharedViewport` requires
`geometryRevisions`; pointer events echo the presented geometry/viewport.

Android (`swifttui.android-delivery/1`) declares wire capabilities before start.
A size query prepares a candidate but consumes no frame, generation, damage or
clipboard. Undersized and abandoned copies do not commit. A successful copy
commits exactly the prepared candidate even when a newer frame arrives between
query and copy. Resync invalidates a prepared candidate. Clipboard copying has
its own drain state; successful clipboard copy drains once, independently of
frame copy. Destroy invalidates the handle and all prepared state.

## Ordered scene catalogs

Canonical JSON uses `defaultSceneId`. Readers accept the historical
`defaultSceneID` and descriptor arrays. A valid explicit ID wins over flags;
without one, select the sole true flag, otherwise the first scene. Conflicting
explicit keys, unknown explicit IDs, duplicate IDs, nonboolean flags and
multiple true flags without an explicit ID are errors. Legacy missing/null
titles are allowed. Native empty discovery has no default; browser mount
requires a scene. Writers derive all compatibility flags from the selected ID.
The native manifest CLI retains its historical key spelling for deployed tools.
