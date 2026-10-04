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
setValue, editText and selectText. `control.value` is boolean, number, or text. Numeric controls publish
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
| TextField, TextEditor | setValue, editText, selectText | text |
| SecureField | setValue, editText, selectText | omitted |

Text edits carry a replacement string and directed UTF-16 anchor/head offsets.
Selection-only requests carry the expected current string and never write the
application binding. Both endpoints must be valid grapheme boundaries. The
runtime rejects stale expected text and out-of-range/split-grapheme selections.
Read-only editors permit selection review while rejecting value mutations.
Ordinary keyboard commands reuse the resulting caret. Secure fields do not
publish their value, selection or native text-query geometry.

### Wire compatibility

Full and delta records add optional node fields `actionTarget`, `actions`,
`isEnabled`, `value` (`{type: "boolean"|"number"|"text", value: ...}`),
`valueMin`, `valueMax`, `valueStep`, and nonsecure editor `textSelection`
(`[anchor, head]` in UTF-16 code units). Presentation-only nodes omit these
fields, except that any node under a disabled environment carries
`isEnabled: false`, control or not; hosts read an absent `isEnabled` as
enabled. A host must require an action token and advertised action before
sending a request; this also detects older runtimes without action support.
Unknown optional fields remain ignorable by older hosts.

Picker nodes can carry `selection`, with `presentation` (`menu`, `list`,
`radioGroup`, or `segmented`) and ordered `options` containing opaque `id`,
`label`, and `isEnabled`. Radio/segmented options with placed style routes also
carry optional `rect: [x, y, width, height]` in scene cell coordinates. These
bounds exclude the Picker's label, border and padding and remain available for
disabled options. Missing or clipped-out routes omit `rect`; older producers
also omit it. Hosts must not infer exact option geometry by dividing the whole
Picker rectangle. Selection commands still echo the opaque option ID through
text `setValue`; geometry is presentation metadata, never an action token.

The shared WASI/WebSocket input parser accepts newline-terminated records
introduced by RS (`0x1e`):

```text
accessibility:<percent-encoded-target>:focus
accessibility:<percent-encoded-target>:activate
accessibility:<percent-encoded-target>:increment
accessibility:<percent-encoded-target>:decrement
accessibility:<percent-encoded-target>:setValue:<boolean|number|text>:<percent-encoded-value>
accessibility:<percent-encoded-target>:editText:text:<percent-encoded-text>:<anchor>:<head>
accessibility:<percent-encoded-target>:selectText:text:<percent-encoded-expected-text>:<anchor>:<head>
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

## Optional widget properties

`AccessibilityProperties` is shared semantic metadata for control authors and
host integrations. Attach it with `View.accessibilityProperties(_:)` or set
`SemanticMetadata.accessibilityProperties`; extracted nodes expose `properties`.
The payload supplies selected, expanded, required, invalid, busy and read-only
states; descriptions and value descriptions; language and authored text kind;
heading/tree levels; table indexes/counts/spans and sort direction; set position
and size; and same-scene label, description, error, control, ownership, reading
flow and active-descendant relationships. Relations use semantic `Identity`
values. Authors can attach `.accessibilityProperties(.init(identifier: anchor))`
to a target and use that same `Identity` anchor in a relationship. The extractor
resolves unique visible anchors to current node IDs; missing, hidden, self and
ambiguous targets are removed. Anchors are scene-unique and do not alter graph
identity. Public `.id(...)` values are scoped graph IDs, not semantic anchors.

Composition merges specified fields individually. `nil` preserves an earlier
value; `false`, `""` and `[]` explicitly override it. Positions, levels and spans
must be positive. Counts admit zero and `-1` for unknown. Invalid or non-JavaScript
safe integers become unspecified. Supply properties appropriate to the role;
metadata does not implement a widget's interaction pattern or validation logic.

```swift
TextField("Email", text: $email)
  .accessibilityProperties(.init(
    required: true,
    invalid: emailIsInvalid,
    description: emailIsInvalid ? "Enter a complete email address." : ""
  ))

Text("Bonjour le monde.")
  .accessibilityProperties(.init(language: "fr", textKind: .paragraph))
```

The Canvas and DOM browser presenters use the same property adapter. Authored
paragraph, code and quotation text uses a text node; headings expose their
level. Relationship references resolve only to present, nonhidden elements in
the same scene and clear when a target disappears. A read-only control remains
focusable, but the runtime rejects assistive mutation with `unsupported`.
This is an assistive routing policy, not a general keyboard/pointer editing lock;
control authors must apply their own editing policy to those paths.

The shared WASI/WebSocket surface encoder emits an optional `properties` object
on each accessibility node in v2 keyframes and v3 deltas. Deltas replace the complete
semantic tree, so absence removes previous properties. The existing action
kinds and opaque committed target tokens are unchanged. Existing v2/v3 adapters
(including 0.15.1) ignore the unknown object and keep their earlier behavior;
updated adapters accept its absence and ignore unknown optional object keys.
Malformed known fields reject the frame. Both producer and adapter source must
include this extension for the richer behavior; it is not part of the 0.15.1
support claim. Raster-only v1 frames are unchanged. Secure-field control values
are omitted at the wire boundary even if an integration supplies one.

These are shared contracts and authoring primitives, not completion of default
semantics for every built-in widget, general custom action APIs, native host
support, terminal semantic reading or new screen-reader task qualification.
The browser mappings follow [WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria-1.2/).

### Public custom actions

An optional `opensLink: true` on a link control permits the presentation host to
open its textual destination instead of sending a second Swift activation. The
primitive sets it only for the default opener. Authored `OpenLinkAction` and
default `accessibilityAction` callbacks keep Swift authoritative. Browser hosts
honor their configured link callback, otherwise use a native safe-scheme anchor.
Disabled/read-only links cannot open. Older nodes omit this flag.

An optional `customActions` array lists nonempty operation names on an actionable
node. Its `actions` array includes `custom`. Hosts submit
`accessibility:<requestID>:<target>:custom:name:<percent-encoded-name>` using the
existing record framing. Names are exact per-control identifiers; the committed
list must contain the requested name. Unicode, delimiters and newlines use the
same UTF-8 percent encoding as text values. Unsupported names have no effect.
Older hosts can ignore the additive field; they cannot operate those actions.
The browser adapter presents named operations as associated native buttons.


### Browser prose and native editing

Independent ordinary `Text` carries `textKind: plain`; authored paragraphs use
`paragraph`, and heading roles retain their level. Supporting browser adapters
render semantic source strings as real text, preserving the text node on an
unchanged frame. Inline links and surrounding text remain in authored order
without repeating the parent string. Language inherits through structural
wrappers and explicit child language takes precedence. Primitive label chrome
and authored aggregate names retain their existing ownership rules.

Native editors retain composition while frames arrive and commit the final text
and directed caret once. An unchanged acknowledged value does not reset the
native editor or undo history. Late events from a removed/replaced editor cannot
mutate its replacement. These source contracts do not establish actual reader
text-unit navigation or universal browser undo support.
