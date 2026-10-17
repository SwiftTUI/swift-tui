# ``SwiftTUIWebHost``

Serve a native SwiftTUI app through a localhost browser host.

## Overview

`SwiftTUIWebHost` is the local-browser host product. It provides the embedded
HTTP/WebSocket server and browser resources. These components render a native
SwiftTUI process in a browser tab.

The packaged browser resources contain only the Canvas renderer and semantic
accessibility controls. The DOM renderer is experimental and requires an
app-owned browser bundle. Set `RuntimeConfiguration.browserAssetsPath` when
calling `WebHostRunner`, or use `RuntimeConfiguration.builder().browserAssets(at:)`.
The same configuration applies to the combined launcher's terminal companion;
see [Browser Companion](https://swifttui.sh/docs/documentation/swifttuiwebhostcli/browser-companion).

Most apps get this product through `SwiftTUI`. That product includes the
combined terminal and WebHost CLI runner by default. For a custom host-only
launcher, import `SwiftTUIWebHost` directly. For a narrower combined terminal
and WebHost graph, import `SwiftTUIWebHostCLI` directly.

## Request and resource boundaries

The HTTP reader parses ASCII delimiters as octets and rejects malformed
versions, field names, control bytes and duplicate singleton handshake
headers. WebSocket upgrades require HTTP/1.1, exact protocol tokens and a
canonical Base64 nonce containing sixteen bytes. Frame lengths use their
minimal encoding; close reasons preserve UTF-8 scalar boundaries and received
close bodies are validated before classification. These rules follow
[RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html) and
[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html).

Browser resources must appear in the bundle inventory with exact spelling,
including on case-insensitive volumes. Hidden paths and files outside the
bundle are excluded. Authenticated plain responses use `Cache-Control:
no-store`, including the token-bearing index page.

An origin's omitted port means its scheme's default port. A wildcard IPv4
listener permits interface-address origins at its listening port, with the
route checking the request authority against that address. Loopback listeners
keep their explicit host allow-list.

Each outbound boundary holds at most 32 records and 4 MiB plus one byte,
including in-flight writes. The byte budget admits one maximum host-wire
record together with its terminating LF; overflow disconnects instead of
dropping reliable records.

## Topics

### Browser Hosting

- ``WebHostRunner``
- ``WebHostRunnerError``
- ``WebHostConfig``
