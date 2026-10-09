# Terminal Reader

Read and operate a running terminal application through sequential semantic text.

## Starting and leaving

Ordinary terminal `App` entry points include the reader without author opt-in.
Run the executable with `--reader`, or export `SWIFTTUI_READER=1` in your shell
profile. `--no-reader` overrides the environment for one launch. F12 switches
between the grid and reader while preserving application state. The browser
companion may remain attached; `--companion off` leaves the reader available.

Type commands followed by Enter. `help` lists them; `quit`, Ctrl-C, or Ctrl-D at
an empty prompt returns to the shell. Escape discards the current command and
editing draft. Ctrl-U clears the command line. Reader mode uses normal terminal
scrollback, with no alternate screen or screen-clearing repaint. Raw input is
restored on exit. It does not start a speech engine; the terminal and the user's
screen reader provide speech and review of the emitted text.

## Reading and updates

`read`, `next`, and `previous` read named semantic elements. `up` and `down` move
through their hierarchy. `find TEXT` searches current semantic content;
`categories` and `category NAME` visit headings, controls, links, or authored
navigation groups. `text OFFSET` reads long content in 2,048-character pages.
`scenes` lists the application's scenes; `scene ID` reviews and operates another
scene through its existing state owner.

Review position is independent of keyboard focus. Repaints do not reread content
or rewrite history. Modal dialogs constrain review and restore its previous
position when dismissed. Removing a reviewed element moves to a remaining one
and reports that change. Application assistive-focus requests move review.

Element chunks and quiet updates are the initial settings. `chunks section`
also reads immediate children; `chunks element` restores element reading.
`updates` reads queued changes. `policy announce` emits changes between commands,
while `policy quiet` keeps them queued. Intermediate progress is coalesced and
read on demand; completions, errors, and explicit announcements remain ordered.
`pause` suppresses update notices, and `resume` enables them again.

`history` replays immutable review entries. History retains at most 128 entries
and 128 KiB; pending updates and progress also have bounded storage. Eviction
is reported. Long summaries are truncated with an explicit notice; text paging
can reach the complete current source. Control and bidi formatting scalars are
removed before semantic text reaches the terminal.

## Operating controls

Use `actions` on the current element. `activate`, `increment`, `decrement`, and
`set VALUE` invoke its advertised operations. `options` lists selection choices
in pages; `options START` continues and `choose NUMBER` selects the corresponding
opaque option. `do NUMBER` or `do EXACT NAME` invokes an advertised custom action.
Collection review controls reach offscreen records without changing selection.
Their named operations can read, select, or return to a remembered item.

All mutations use committed semantic dispatch. Disabled, unsupported, removed,
and stale targets are rejected; the reader reports the acknowledgement. Browser
and terminal inputs operate the same application state.

## Editing

`edit` starts a draft for the current text control, preserving its selection.
Positions count Unicode grapheme clusters from zero. `select START END` sets the
selection, `insert TEXT` replaces it, `delete` removes it, `replace TEXT` replaces
the draft, and `append-line TEXT` adds a new line. `read` reviews the draft;
`save` submits text and selection together, and `cancel` discards it. A changed
or removed live control invalidates the draft. Read-only text permits selection.

Secure fields begin with an empty replacement draft. Their values and draft
commands are not echoed or retained in reader history, pending notices, or
request-correlation metadata. Paste is one command's data, never a sequence of
automatically executed commands. Embedded terminal child output remains owned
by that child; the reader cannot redact a password that a child itself prints.

This documents implementation behavior. Actual screen-reader, SSH, multiplexer,
and alternative-input qualification is recorded separately for each release.
