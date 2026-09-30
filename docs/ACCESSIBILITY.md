# Accessibility (internal notes)

The consumer-facing accessibility documentation (the semantic modifiers,
`AccessibilityRole`/`AccessibilityPoliteness`, `AccessibilityAnnouncer`,
reduced motion, and output-mode detection) is the published DocC article
[Accessibility](../Sources/SwiftTUIViews/SwiftTUIViews.docc/Accessibility.md)
(`SwiftTUIViews` catalog). This file holds the maintainer-facing pipeline
wiring: how one snapshot feeds every consumer path.

## The extraction pipeline

Authored `.accessibility*` modifiers write `SemanticMetadata`. During the
semantics phase of the pipeline, `SemanticExtractor` walks the placed tree and
produces a `SemanticSnapshot` whose `accessibilityNodes` is a flat array of
`AccessibilityNode` values. Parent links are stored, so the array
reconstructs a tree. The snapshot deliberately does **not** bake in focus
state. Consumers cross-reference live focus from `FocusTracker` during
presentation. Thus, one snapshot stays valid when focus moves.

## Snapshot consumers and their limits

| Consumer | Current behavior | Evidence boundary |
| --- | --- | --- |
| Terminal cursor mode | Uses focus and cursor anchors to position the hardware cursor. Off by default; text input retains its caret. | Emits terminal bytes, not a semantic tree or spoken announcement. Reader compatibility requires testing. |
| Canvas and DOM browsers | A shared ARIA sidecar receives semantic nodes; supported controls route typed actions back to Swift. | Names, roles and unit assertions do not prove complete assistive task access. |
| Public SwiftUI host | Presents native semantic elements and runtime-origin focus. | Presentation does not establish assistive action support; macOS and iOS require independent qualification. |
| Android host | Serializes semantic nodes and exposes native accessibility-provider actions. | Provider tests do not establish TalkBack discovery or operation. |
| Test support | `renderLinearAccessibilityOutput(_:)` produces a reading-order string using `LinearAccessibilityRenderer`. | A snapshot assertion utility, not a shipped interactive terminal reader or screen-reader output capture. |

The [consumer article](../Sources/SwiftTUIViews/SwiftTUIViews.docc/Accessibility.md)
records the current control, release and authoring boundaries. Native host
packages own their adapter implementations; no browser acceptance transfers to them.

## Assistive action contract

`AccessibilityNode.actionTarget` identifies one live control in one scene. It
is opaque: adapters must echo the published token, never derive it from the
public authored identity, and discard tokens when the scene ends. A recreated
control gets a new token even if its authored identity is reused. Requests
resolve against the latest committed semantic tree and active focus regions.
They do not synthesize keyboard events or invoke ancestor key handlers.
WebSocket ingress attaches its connection token to requests in process. The run
loop drops queued requests from a retired host session before state mutation or
acknowledgement, including when a new page reuses the same request ID. This
provenance is package-only and does not change the wire format. Untagged requests
from other host adapters retain their existing behavior.

`control.actions` advertises focus, activate, increment, decrement, and/or
setValue. `control.value` is boolean, number, or text. Numeric controls publish
optional minimum, maximum and step. SecureField omits its value entirely.
The runtime rejects stale, disabled, hidden/out-of-scope and unsupported targets,
wrong value types, nonfinite numbers and numbers outside published bounds.
The owning control compares against its live binding so value echoes are inert,
including multiple requests before the next render. Focus echoes are also inert.

Supported primitive routes:

| Control | Actions besides focus | Published value |
| --- | --- | --- |
| Button and activating controls | activate | none |
| Toggle, DisclosureGroup | activate, setValue | boolean |
| Slider, Stepper | increment, decrement, setValue | number |
| TextField, TextEditor | setValue | text |
| SecureField | setValue | omitted |

### Wire compatibility

Full and delta records add optional node fields `actionTarget`, `actions`,
`isEnabled`, `value` (`{type: "boolean"|"number"|"text", value: ...}`),
`valueMin`, `valueMax`, and `valueStep`. Presentation-only nodes omit these
fields, except that any node under a disabled environment carries
`isEnabled: false`, control or not; hosts read an absent `isEnabled` as
enabled. A host must require an action token and advertised action before
sending a request; this also detects older runtimes without action support.
Unknown optional fields remain ignorable by older hosts.

The shared WASI/WebSocket input parser accepts newline-terminated records
introduced by RS (`0x1e`):

```text
accessibility:<percent-encoded-target>:focus
accessibility:<percent-encoded-target>:activate
accessibility:<percent-encoded-target>:increment
accessibility:<percent-encoded-target>:decrement
accessibility:<percent-encoded-target>:setValue:<boolean|number|text>:<percent-encoded-value>
```

Encode UTF-8 bytes using URI-component escaping, including colons, newlines,
percent signs, and RS. Invalid or oversized records are discarded under the
existing input budget. A host can insert a decimal request ID immediately after `accessibility:`.
The next presented frame includes `accessibilityActionResponse` with that ID
(as a decimal string), target token, and result. The response is a persistent
watermark for the last processed request, including rejections and no-ops;
coalesced or polled frames therefore acknowledge every earlier request on the
same ordered scene channel. It never repeats submitted values. Hosts use it
to keep an unacknowledged edit from being overwritten by an older frame and to
restore authoritative state after rejection. IDs belong to one scene session
and, on WebHost, to one connection: a reconnected page numbers its requests
afresh, so no frame it receives, including the keyframe replayed on reconnect,
carries the previous connection's watermark.
Values and focus in subsequent frames remain runtime-authoritative; adapters
must suppress callbacks while reflecting them.
The Swift entry point is `HostedSceneSession.send(.accessibility(request))`.
The request has no authority outside its owning scene and must use that scene's
input channel. Host-specific adapters and actual assistive acceptance are
separate from this shared dispatch implementation.

## Known gaps

SwiftUI and Android overlays need assistive callbacks connected to the
shared contract. A WCAG conformance suite and screen-reader listening evidence
are not established by semantic snapshots or runtime tests. Current gaps are
tracked in the [divergence and gap register](../Sources/SwiftTUIViews/SwiftTUIViews.docc/Divergences-And-Gaps.md).

The manual screen-reader listening review protocol lives in
`Tests/SwiftTUITests/Accessibility/README.md`.
