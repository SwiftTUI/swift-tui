# Terminal and CLI profile 1

Identifier: `swifttui.terminal-cli/1`. CLI JSON is LF-delimited UTF-8 JSON with
`type: "frame"`, a cell `size`, and `rows` containing plain strings. It is not
an RS-framed `surface` record and its rows are not styled-cell tuples.
The structural authority is `../schemas/cli-frame.schema.json`; row count
matches size.height after structural validation.
Accessibility nodes and warnings accompany the same committed frame. Secure
field contents are redacted before JSON rendering. Optional fields may grow;
consumers must ignore unknown fields and diagnostic codes. Human diagnostics,
debug bundles, graph dumps and implementation counters have no stable grammar.

Bare app launch accepts `run [--instance NAME]`, `instances`,
`scenes [--pid N | --instance NAME]` and
`attach SCENE [--pid N | --instance NAME]`. The selectors are alternatives;
conflicting selectors, missing arguments and non-Int32 PIDs fail before an app
starts. An omitted selector selects the most recent running instance.
Scene identifiers and titles resolve through the live catalog's normalized
selector lookup. Ambiguous selectors fail. These runner verbs select terminal
operation even when the environment enables web launch. A custom
`SwiftTUICommand` consumer owns its parser and passes explicit configuration.

`--json`/`SWIFTTUI_JSON=1` selects machine-readable frames. `--accessible`
selects linear accessibility output; `--reader` selects terminal reading.
`--no-color`, `--force-color`, `--ascii`, `--reduce-motion`, `--stable-output`
and `--cursor-follows-focus` set their named presentation preferences. Explicit
options override environment-derived values. `--web`, `--port`, `--bind`,
`--scene`, `--open`/`--no-open` select browser launch. The companion options
select shared native/browser presentation. Port values are validated before
binding. A missing linked web runner fails clearly, without silently starting
a different host. The authoritative option names and environment spellings
are the public `SwiftTUIOptions` and `SwiftTUIEnvironmentVariable` declarations.

On POSIX systems, local discovery uses `/tmp/swifttui/<app>/<pid>.sock` and
the grammar in `../grammar/attach.abnf`. Request limit: 4,096 bytes; response
limit: 4 MiB; client timeout: five seconds. The live LIST array contains `id`,
`title`, `ptyPath` and `isAttached`. These attachment fields do not belong to
the browser scene schema. COMPANION returns the current companion URL when available. ATTACH returns a slave PTY path, or an ERR reason
for a scene without a PTY, an unknown selector or malformed request. CRLF is
not the LF terminator. The parser also accepts a bare command internally;
network clients send LF. A connection is not a multiplexed command session.

The proxy forwards bytes over a raw PTY, relays resize and restores the
calling terminal's attributes when it finishes. A closed peer ends the proxy.
The owning process removes its socket and instance registration at shutdown.
Primary scenes use inherited stdio and have no attachable secondary PTY.
Windows supports the native console and companion, but not POSIX local attach;
WASI has its own execution profile. Unsupported attachment fails explicitly.

Terminal capability selection accounts for TTY status, TERM/COLORTERM,
locale, NO_COLOR and emulator markers. Public profiles distinguish ASCII vs
Unicode, no/16/256/true color, style escapes, hyperlinks, mouse reporting and
synchronized output. An explicit profile is authoritative. Redirected/dumb
output does not assume interactive terminal facilities. Probes suspend the
input reader while awaiting replies. Resize invalidates presentation geometry;
partial writes invalidate the retained terminal baseline. Shutdown restores
raw mode, cursor/screen ownership and terminal modes acquired by the session.
