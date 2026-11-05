# Loopback companion profile 1

Identifier: `swifttui.companion/1`. The native process owns the scene graph and
serves its bundled browser assets. The browser owns presentation and input.
The selected bundle provenance records the exact web revision and asset hashes.
This profile uses the host wire without changing the in-process Swift values.

The launch URL contains a per-server token. Authenticated GET `/` serves the
entry page; `/scene-manifest.json` serves the canonical ordered scene catalog;
declared asset paths serve the bundle. An accepted query token sets the
HttpOnly, SameSite=Strict `SwiftTUIWebHostToken` cookie. A present query token
takes precedence over the cookie, including an incorrect query token. Plain
authenticated responses are `Cache-Control: no-store`. Unknown paths/methods
return 404; missing or invalid authorization returns 403. Tokens must not be
published in persistent conformance reports.

GET `/ws/scene/<id>` upgrades a known scene. HTTP/1.1, a nonempty Host,
nonduplicated singleton headers, Connection/Upgrade tokens, WebSocket version
13 and a canonical base64 16-byte key are required. Invalid upgrade syntax
returns 400. Authorization and origin checks precede upgrade. A browser origin
must use http/https, the server port, and the configured bind host, localhost
or 127.0.0.1, without userinfo/query/fragment or a non-root path. A wildcard
IPv4 bind additionally admits a canonical IPv4 origin matching Host. Native
clients may omit Origin; a foreign browser origin is rejected with 403.

| Phase | Admission and output |
| --- | --- |
| Detached | Surface records are dropped. Up to 32 bounded non-surface records are retained FIFO. Overflow explicitly fails the send. The scene remains alive. |
| Pre-capabilities | A new connection receives controls but no surface. Input has that connection's token. Partial input from its predecessor is discarded. |
| Active | The first accepted capability declaration atomically reanchors the encoding epoch, activates output and requests a keyframe. Repeated declarations on the same connection are ignored. |
| Terminal | Server shutdown finishes scene input, releases pending sends and closes connections. It is idempotent. |

Replacement invalidates the old connection's input, callbacks and queued
output. A late close cannot close its successor. Input queues and complete
WebSocket messages have bounded ingress; overflow closes the offending
connection. Surface encoding is committed only after the socket writer
acknowledges the entire record. A failed/partial write fails the pending send,
disconnects that connection and requires a fresh keyframe after reconnect.
No stale delta is replayed as the first frame of a replacement connection.

The browser resets its decoder, image state, pending action correlations and
editing focus when the session changes. Application state can survive browser
detachment; wire delivery state cannot. Clipboard draining, selective image
repair and keyframe repair remain separate operations from `wire.md`.
