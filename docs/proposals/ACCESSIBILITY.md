# Accessibility

**Status:** Living proposal and implementation record. The original research
from the `accessibility-investigation` branch remains here for context, but
the shared substrate and first target consumers have now shipped: CLI
accessible output, Web/WASI ARIA, SwiftUI host bridging, and text-input caret
anchors for cursor-following. Long by intent — the goal is to keep the
context here rather than scattered across session notes.

**Owner:** unassigned. Tracking branch: `accessibility-investigation`.

---

## Table of contents

1. [Context](#context)
2. [Strategic shape](#strategic-shape)
3. [Principles](#principles)
4. [The landscape](#the-landscape)
   1. [Screen reader support per platform](#screen-reader-support-per-platform)
   2. [What blind developers actually use](#what-blind-developers-actually-use)
   3. [Why TUIs are hard for screen readers](#why-tuis-are-hard-for-screen-readers)
   4. [Accessibility APIs at the terminal layer](#accessibility-apis-at-the-terminal-layer)
   5. [Real-world reports — what works and what fails](#real-world-reports--what-works-and-what-fails)
5. [Peer frameworks](#peer-frameworks)
6. [The universal lessons](#the-universal-lessons)
7. [What we already have in swift-tui](#what-we-already-have-in-swift-tui)
8. [Best-practices checklist](#best-practices-checklist)
   1. [Color and contrast](#1-color-and-contrast--the-env-var-contract)
   2. [Don't rely on color alone](#2-dont-rely-on-color-alone)
   3. [Keyboard navigation and focus](#3-keyboard-navigation-and-focus)
   4. [Motion and animation](#4-motion-and-animation--reduced-motion)
   5. [Unicode, box-drawing, emoji](#5-unicode-box-drawing-emoji)
   6. [Reading order and redraws](#6-reading-order-and-redraws)
   7. [Status messages and live regions](#7-status-messages-and-live-regions)
   8. [Density and zoom](#8-density-and-zoom-low-vision)
   9. [Standards and legal](#9-standards-and-legal-references)
   10. [Testing](#10-testing-tuis-for-accessibility)
9. [Proposed API surface](#proposed-api-surface)
10. [Anti-patterns this proposal commits us to avoiding](#anti-patterns-this-proposal-commits-us-to-avoiding)
11. [What the non-CLI targets unlock](#what-the-non-cli-targets-unlock)
    1. [Embedded web host](#embedded-web-host-platformswebhost-proposed)
    2. [WASM web target](#wasm-web-target-platformsweb)
    3. [SwiftUI host](#swiftui-host-platformsswiftui)
12. [Relationship to other proposals](#relationship-to-other-proposals)
13. [Open questions](#open-questions)
14. [Out of scope](#out-of-scope-this-version)
15. [Suggested phasing](#suggested-phasing)
16. [Sources](#sources)
17. [Changelog](#changelog)

---

## Context

Accessibility has been a deferred objective in this framework. The goal of
this branch is to move it from "we'll think about that later" to a concrete,
reviewable proposal: what would we ship, what would we not, and why.

This is harder than iOS or web accessibility because terminals expose almost
nothing semantic to assistive technology (AT). A screen reader sees a
character grid and a cursor — there is no accessibility tree, no ARIA, no
`isAccessibilityElement`, no `aria-live`. Most TUI frameworks (ncurses,
Bubble Tea, Ratatui, Textual, Brick) ship with no first-party accessibility
features, and the few that do (Charm `huh`, Ink, Terminal.Gui, GitHub CLI,
Microsoft Terminal) converge on a small set of patterns we can adopt and
adapt.

swift-tui is unusually well-positioned to do better than peers, for three
reasons:

1. The pipeline already has a `semantics` phase between `place` and `draw`
   ([`Sources/SwiftTUICore/Semantics/Semantics.swift`](../../Sources/SwiftTUICore/Semantics/Semantics.swift),
   [`SemanticRoleTypes.swift`](../../Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift)).
2. The focus engine already tracks logical focus (`FocusTracker`,
   `FocusPolicy`, `FocusInteractionTypes`, `FocusPresentation`,
   `View/Focus/`).
3. The renderer is diff-based (`CommitPlanner`, `Rasterizer`), so we don't
   pay the "full repaint per frame" cost that breaks every other TUI for
   screen readers.

Beyond the CLI, two additional rendering targets exist —
`Platforms/Web/` (HTML over `WASISurfaceBridge`) and `Platforms/SwiftUI/`
(SwiftUI host) — which means the same view tree can be rendered with
different accessibility strategies on different surfaces.

Quote from a blind Claude Code user, on the importance of getting this
right ([anthropics/claude-code#247](https://github.com/anthropics/claude-code/issues/247)):

> "Please add an env var or some config which allows users like myself who
> are blind programmers to have a cleaner, ascii cli where I can anchor a
> hotspot on my screen reader to catch the important parts of the cli
> rather than having to scroll using up or down screen reader keys to
> read the output."

The existence of this issue, and dozens like it across other CLIs, is the
direct motivation for this proposal.

## Strategic shape

The accessibility story is **four rendering targets, four strategies**,
all driven from the same `semantics` phase output:

| Target | Delivery shape | Strategy | A11y ceiling |
|---|---|---|---|
| **CLI** | Local binary, terminal output | Cursor-as-focus, env-var contract, ASCII fallback, reduce-motion, append-only status, optional linear "drop the TUI" mode | Bound by what the user's terminal + screen reader can do |
| **Embedded web host** | Local binary, browser at `localhost` | Same binary opens an HTTP/WebSocket server; the browser renders DOM with real ARIA from the semantic stream. `myapp --web` and you're in the browser. | Full WCAG 2.2 AA achievable. **The strongest accessibility delivery vehicle for any compiled SwiftTUI binary.** |
| **WASM web** | Compile to WASM, deploy to web | View tree runs entirely in the browser; same ARIA mapping. The "deploy your TUI as a website" story. | Full WCAG 2.2 AA achievable |
| **SwiftUI host** | Local binary, native macOS / iOS window | Bridge semantic data to SwiftUI's `.accessibilityLabel` / `.accessibilityRole` / `.accessibilityHidden` modifiers. | Full UIKit/AppKit accessibility |

The CLI target is the hardest and the most novel. The **embedded web
host** is the most important addition since the first draft of this
proposal: it gives every compiled SwiftTUI binary a "view this in the
browser" capability without needing a separate WASM build, which makes
it our credible accessibility answer for users on platforms where
terminal screen reader support is weak (notably blind macOS users —
VoiceOver-on-Terminal.app is structurally poor; see
[the landscape](#screen-reader-support-per-platform)).

The embedded web host architecture is investigated in detail in the
sister proposal [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md). The
flag surface that gates accessibility modes (`--accessible`, `--ascii`,
`--reduce-motion`, `--no-color`, `--web`, etc.) is investigated in
[`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md). This proposal is the
**design authority** for the semantic data; the other two are design
authorities for the **delivery vehicle** and the **flag surface**
respectively.

This proposal focuses on the CLI target, the shared semantic API
surface, and the per-target render strategies. The wire-format and
server details belong in `EMBEDDED_WEB_HOST.md`; the flag-parsing and
env-var-precedence implementation details belong in `ARGUMENT_PARSING.md`.

## Principles

1. **The `semantics` phase is the single source of truth.** Every target
   reads from the same per-node role/label/state record. There is no
   parallel "accessibility tree" maintained alongside the view tree.
2. **Cursor position can expose focus.** When cursor-following is enabled,
   the hardware terminal cursor must sit at the focused widget's
   interaction point in CLI TUI output, even when visually hidden. This is
   a high-ROI accessibility move, but it is visually disruptive enough that
   it defaults off for ordinary TUI output.
3. **Diff-only commits.** The rasterizer never emits a full-screen
   repaint when nothing changed. (Already true; this proposal preserves
   it.) Decorative animations are gated by reduce-motion.
4. **Honor environment contracts.** `NO_COLOR`, `FORCE_COLOR`,
   `CLICOLOR`, `CLICOLOR_FORCE`, `COLORTERM`, `TERM=dumb`, `LANG=C`,
   `CI`, isatty — all read with the standard precedence. CLI flags
   override env. `NO_COLOR` wins over `FORCE_COLOR`.
5. **Color is decoration, never the only signal.** Every state encoded
   with color must also be encoded with a glyph, prefix, position, or
   text label.
6. **Terminal AT is unknowable from inside the framework.** We don't
   detect "is a screen reader attached" — we expose toggles that users
   set intentionally. This matches every peer framework's approach.
7. **Accessible mode is a render-time choice, not an authoring choice.**
   View authors don't write two view bodies. The same view tree renders
   one way under defaults and another way under accessible mode.
8. **Decorative redraws are bugs.** Spinners made of unicode characters,
   periodic full-screen repaints, animations that don't change state —
   all of these actively hurt screen reader users and contribute nothing
   to sighted users either. Reduce-motion is the default in CI / non-TTY
   contexts.

---

## The landscape

This section captures the research findings in full so readers don't have
to chase URLs to understand the design rationale. Sources are linked
inline; the consolidated bibliography is at the bottom.

### Screen reader support per platform

**Windows is the strongest platform**, and **NVDA is the consensus winner
for terminal use**. Parham Doustdar, a totally blind developer, says
flatly ([parhamdoustdar.com](https://www.parhamdoustdar.com/2016/04/03/tools-of-blind-programmer/)):

> "I use NVDA because it's really high-quality, it's written by blind
> people, and I don't have to keep looking for pirated copies because
> it's free."

NVDA's documentation notes that its review cursor is "mostly useful in
Windows command consoles where there is no system caret" — a hint at the
underlying architecture problem: terminals don't expose a caret/selection
model the way a textbox does, so screen readers fall back on geometric
"review cursor" navigation of the screen rectangle.

Microsoft Windows Terminal / ConPTY accessibility relies on a custom
UI Automation peer (`TermControlAutomationPeer`) that Microsoft wrote
from scratch — they had to build UIA support themselves rather than
reusing XAML accessibility, which "cost more dev hours than expected."
The class-name change broke NVDA at one point and required a coordinated
patch ([NVDA PR #13261](https://github.com/nvaccess/nvda/pull/13261)).
Users on the NVDA mailing list still report regressions:

> "the new environment with Windows Terminal is less comfortable than
> the old cmd, at least when using NVDA without add-ons"

The recommended workaround is the **NVDA Console Toolkit add-on** with
"Override shift+numPad7 behavior to take review cursor to the first
visible line" enabled. NVDA + Windows Terminal is currently the most
viable terminal screen-reader story on any platform.

**macOS is significantly worse.** VoiceOver in Terminal.app and iTerm2
reads input echo and basic command output, but [AppleVis user
reports](https://www.applevis.com/blog/announcing-tdsr-command-line-screen-reader-macintosh-gnulinux)
describe "major bugs with vim" daily. Warp's own
[a11y discussion #1704](https://github.com/warpdotdev/Warp/discussions/1704)
confirms the structural problem: Warp uses a custom Rust GPU UI that
"doesn't expose standard macOS accessibility element trees to the
system" — they bolted on `NSAccessibility` notifications as a partial fix
but it doesn't give VoiceOver a real navigable tree.

This is why **TDSR (Two Day Screen Reader)** exists — a Python wrapper
terminal that *contains* its own screen reader, used by blind macOS
users because OS-level support is poor.

**Linux is the most fragmented.** The fireborn blog post
["I Want to Love Linux. It Doesn't Love Me Back"](https://fireborn.mataroa.blog/blog/i-want-to-love-linux-it-doesnt-love-me-back-post-3-speakup-brltty-and-the-forgotten-infrastructure-of-console-access/)
is the most concrete recent (2024–2025) account:

> "Speakup [the in-kernel TTY screen reader] works at boot, but the
> moment you hit a login prompt, you enter a session with user-locked
> audio due to PulseAudio and PipeWire, and you've got a working screen
> reader screaming silently into the void."

> "BRLTTY often says 'screen not in text mode' — which is accurate, but
> not helpful."

Orca works on top of GNOME Terminal because VTE exposes content via
AT-SPI, but Orca itself depends on AT-SPI and pulls it down with the
desktop session. GPU-rendered terminals (Alacritty, Kitty, WezTerm, foot)
generally have no AT-SPI integration whatsoever.

Summary:

| Platform | Best terminal | Best screen reader | Status |
|---|---|---|---|
| Windows | Windows Terminal | NVDA (free, written by blind devs) | Best of the three |
| macOS | iTerm2 / Terminal.app | VoiceOver (poor) or TDSR (custom) | Structurally weak |
| Linux | GNOME Terminal (VTE) | Orca (desktop) / Speakup (console) | Fragmented; works in narrow lanes |

### What blind developers actually use

The CHI 2021 paper ["Accessibility of Command Line Interfaces"](https://dl.acm.org/doi/fullHtml/10.1145/3411764.3445544),
[HN: Resources for blind developers](https://news.ycombinator.com/item?id=18522497),
and [HN: How a Blind Person Programs](https://news.ycombinator.com/item?id=8965048)
converge on a small toolkit:

- **Windows + WSL is dominant.** From `jareds` on HN:
  > "I use Windows 10 every day with Jaws and Windows subsystem for
  > Linux. WSL has noticeably increased my productivity compared to
  > Cygwin."
- **Edit locally, run remotely.** From `sbahram` on HN:
  > "edit on Windows PC, then transfer files [because] editing on
  > Windows tends to be far more accessible than relying on the
  > interplay of nano or vi within an ssh window."
- **Emacs + Emacspeak** (T.V. Raman, 1994) is the "audible interface"
  approach: it speaks *the underlying buffer*, not the rendered screen.
  Doustdar at EmacsConf 2019:
  > "when I press C-n, instead of asking an application's APIs to
  > provide the selected line… it runs after `next-line' and uses
  > `buffer-substring' to get the current line and speaks it."

  This semantic-vs-visual distinction is the core insight: Emacspeak
  works because it has access to the *intent* of the action, not just
  the rendered consequence. TUI frameworks generally don't.
- **TDSR** ([AppleVis announcement](https://www.applevis.com/blog/announcing-tdsr-command-line-screen-reader-macintosh-gnulinux))
  — a Python wrapper terminal that *contains* its own screen reader
  rather than relying on VoiceOver/Orca to read the terminal. This
  exists precisely because OS-level support is poor.
- **Speakup + BRLTTY** for kernel-console use; **edbrowse / w3m / lynx**
  for the web from a console.
- **tmux** appears widely but causes screen-reader friction because it
  uses the alternate screen buffer plus full repaints on pane changes
  — there are no widely-cited "screen-reader-friendly" tmux configs.
- **Modal editors (vim/neovim)** require `:set noruler` and
  screen-reader-aware plugins like
  [vim-accessibility](https://github.com/luffah/vim-accessibility),
  which adds `:SpeakLine`/`:SpeakWORD` and a `<C-s>` toggle for screen
  reader mode in GVim.

A consistent thread across these accounts: blind developers
**piecemeal together** working setups, often involving wrappers,
custom plugins, and avoidance of TUIs that don't behave. They are not
served well by the current state of the art.

### Why TUIs are hard for screen readers

The technical patterns that break screen readers, drawn from
[GitHub's "Building a more accessible GitHub CLI"](https://github.blog/engineering/user-experience/building-a-more-accessible-github-cli/),
[Bubble Tea issue #780](https://github.com/charmbracelet/bubbletea/issues/780),
and [Pinokio issue #1049](https://github.com/pinokiocomputer/pinokio/issues/1049):

1. **No semantic structure.** GitHub:
   > "Even if a TUI's displayed text is structured, to a screen reader
   > there is no apparent structure to the text being displayed like
   > there is in HTML."

   The screen reader sees a 80×24 character grid; it cannot tell a
   heading from a list item from a button.

2. **Constant redraws.** GitHub:
   > "Non-alphanumeric visual cues and uses of constant screen redraws
   > for visual or other effects can be tricky to correctly interpret
   > as speech."

   Their old spinner — "a 'spinner' made by redrawing the screen to
   display different braille characters" — was unusable; they replaced
   it with static "Working…" text.

3. **Alternate screen buffer (`smcup`/`rmcup`).** TUIs that switch to
   the alt buffer (vim, less, htop, tmux, every Bubble Tea / Textual /
   Ratatui app by default) leave no scrollback for review. The screen
   reader's review cursor has nothing to walk over after exit.
   Combined with full-screen redraws on every keystroke, the ATs see
   "the entire screen changed" and either announce nothing or announce
   everything.

4. **Cursor tracking lies.** From `sbahram`:
   > "Jaws and even NVDA had far worse cursor tracking in the Windows
   > CMD window, so you couldn't be sure that when your screen reader
   > said it was beside a certain character, that it actually was."

   Modal editors compound this — typing `j` is *navigation*, not
   insertion, so the reader announces the wrong thing.

5. **PTY output isn't exposed.** Pinokio user:
   > "the terminal is implemented as a graphical / pseudo-terminal
   > (canvas or custom rendering) and does not expose its content via
   > Windows UI Automation… The text DOES appear visually on screen.
   > The problem is that the terminal… does not expose its content."

   Many "modern" terminals (Warp, xterm.js-based web terminals, custom
   renderers) hit this wall.

6. **No "live region" equivalent.** There is no terminal-layer way to
   say "this part of the screen just changed and is important" — TUIs
   paint with ANSI cursor-positioning and the AT can't distinguish a
   status update from a full repaint.

7. **NVDA crashes on aggressive repaints.** Documented in the
   ["text mode lie" piece](https://xogium.me/the-text-mode-lie-why-modern-tuis-are-a-nightmare-for-accessibility):
   > "frequent redraws trigger immediate crash of the screen reader"

### Accessibility APIs at the terminal layer

There is **no cross-platform standard** for terminals exposing semantic
content to AT. The state of the art:

- **Windows.** Microsoft Terminal's `TermControlAutomationPeer` exposes
  the screen buffer via UIA, including selection and notification
  events. This is the only major terminal that does this natively.
  JAWS/NVDA depend on the automation peer being named `TermControl` for
  compatibility heuristics.

  Carlos Zamora's PRs ([#1691](https://github.com/microsoft/terminal/pull/1691),
  [#4018](https://github.com/microsoft/terminal/pull/4018),
  [#14097](https://github.com/microsoft/terminal/pull/14097)) wire up
  selection-changed / text-changed (new output) / scroll / cursor-changed
  UIA events. [Issue #2447](https://github.com/microsoft/terminal/issues/2447)
  documents the signaling chain:
  `ConHost event → WindowUiaProvider → ScreenInfoUiaProvider → UiaAutomationEvent`.
  This is the closest thing the TUI world has to ARIA live regions.

- **Linux.** GNOME Terminal inherits AT-SPI exposure from VTE (the
  widget library shared with Tilda, Terminator, etc.).
  [Digital Darragh](https://www.digitaldarragh.com/2011/08/22/using-the-tilda-terminal-in-linux-with-full-accessibility-for-orca-users/)
  confirms VTE-based terminals are the accessible Linux path. Alacritty,
  Kitty, WezTerm, foot — GPU-rendered or custom-renderer terminals —
  generally have no AT-SPI integration.

- **macOS.** Terminal.app and iTerm2 expose text via NSAccessibility's
  text protocols. Warp's `NSAccessibility` notifications are partial.
  No standard for TUI semantic exposure.

- **Proposed work.** The CHI 2021 paper proposes exposing CLI output
  structure through accessibility APIs but no protocol has been
  ratified. Bubble Tea's [issue #780](https://github.com/charmbracelet/bubbletea/issues/780)
  suggests the most promising lead is "using a second buffer so that
  screen reader users can get structured text that includes information
  about the selected element" — i.e., the TUI maintains a parallel
  semantic stream that the AT consumes instead of the visual one. This
  is essentially the Emacspeak model generalized.

- **AccessKit.** [AccessKit](https://accesskit.dev/how-it-works/) is a
  Rust crate exposing one tree-shaped data schema (id + role + attrs +
  actions) and platform adapters for Windows UIA, macOS NSAccessibility,
  and Linux AT-SPI. It was built for GUI toolkits (egui, Slint), not
  terminals — but it's the only mature cross-platform a11y abstraction
  not tied to a specific render path. If swift-tui ever wanted to expose
  a real platform a11y tree, AccessKit is the prior art. **No TUI
  framework has tried this**, so it's a deferred but not impossible
  future direction.

### Real-world reports — what works and what fails

- **GitHub CLI (`gh`):** Rebuilt prompts using `charmbracelet/huh`,
  replaced animated spinners with static "Working…" text, rebuilt color
  palette around terminal background — explicitly because "speech
  synthesis screen readers do not handle this well" with redraw-based
  spinners. Shipped `gh a11y` in v2.72+ as an explicit accessible mode.
  The single most-cited successful CLI accessibility retrofit.

- **VSCode integrated terminal:** [Issue #59794](https://github.com/microsoft/vscode/issues/59794):
  > "I just tried to use the terminal in VS Code with both JAWS and
  > NVDA, and it doesn't seem to be working for me."

  Eventually fixed via an explicit screen-reader mode (Alt+F1) and
  tighter accessibility-aware buffering.

- **Vim/Neovim:** Modal interaction confuses readers — the reader "may
  read what changed on screen, which may be nothing but cursor position,
  making it unclear whether you typed 'j' as insertion or navigation."
  Workarounds: `:set noruler`, vim-accessibility plugin, GVim's `Ctrl+s`
  screen-reader mode.

- **Warp:** GPU-rendered UI bypasses platform AT entirely; partial
  NSAccessibility shim. Praised by some users for command-block
  keyboard navigation but not blind-accessible.

- **htop / btop / tmux / Bubble Tea apps / Textual apps / Ratatui apps:**
  No native AT integration. Relying entirely on the OS screen reader
  walking the terminal grid via review cursor — works for static layouts,
  fails on any dynamic redraw.

- **Pinokio (Electron-with-xterm.js):** Output completely invisible to
  NVDA/UIA despite being visually rendered.

- **Fly.io web terminal:** Made "screen reader accessible" with
  xterm.js but admitted "we're limited by what our terminal emulation
  library can do" — no public detail on how.

- **Claude Code:** [Issue #247](https://github.com/anthropics/claude-code/issues/247)
  (the quote at the top of this doc) is a concrete blind-developer
  request for ASCII / clean-output mode. [Issue #8276](https://github.com/anthropics/claude-code/issues/8276)
  is a low-vision-relevant reflow bug. Both are good worked examples
  of what users actually file.

- **DeepSeek-TUI:** [Issue #450](https://github.com/Hmbown/DeepSeek-TUI/issues/450)
  proposes `NO_ANIMATIONS=1` env var as the smallest possible
  accessibility win; this is the pattern we adopt with
  `SWIFTTUI_REDUCE_MOTION=1`.

- **Mutt and WeeChat:** The canonical "works with screen readers"
  examples. They work because they keep the cursor on the selected
  element (Mutt: selected message, WeeChat: input line). This is the
  pattern Brick later retrofitted for itself.

- **`menuconfig` (Linux kernel):** Cited in the ["text mode lie"
  piece](https://xogium.me/the-text-mode-lie-why-modern-tuis-are-a-nightmare-for-accessibility)
  as accessible because "it enforces a strict, single-column focus."
  Linear focus order beats spatial layout for screen readers, every
  time.

- **Irssi:** "the gold standard for accessible chat" because it uses
  VT100 scrolling regions instead of full redraws. Append-only, not
  rewrite-the-screen.

---

## Peer frameworks

What every TUI / CLI framework we surveyed does (or doesn't do) for
accessibility, with concrete API where it exists.

### Comparison table

| Framework | A11y story | Concrete mechanism |
|---|---|---|
| **Textual (Python)** | Minimal first-party. Web deploy via `textual serve` is the accessibility escape hatch. Has `TEXTUAL_ANIMATIONS` / `App.animation_level` for reduce-motion. | No screen-reader API. Web-deploy is the workaround. |
| **Bubble Tea (Go)** | Core has none — issue #780 still open. Sibling lib **Huh** ships `WithAccessible(true)` / `ACCESSIBLE` env var. | Drops the TUI entirely, falls back to linear stdin prompts. |
| **Ratatui (Rust)** | None shipped. Roadmap mentions a11y aspirationally. | — |
| **ncurses / notcurses** | No first-party support. The "API" is *cursor placement*. notcurses' braille support (`NCBLIT_BRAILLE`) is rendering-only, not a11y. | Hardware cursor = focal point screen readers read from. |
| **Ink (React for CLIs)** | Most fleshed-out a11y API of any modern TUI lib found. ARIA subset on `<Box>`/`<Text>`. | `INK_SCREEN_READER=true`, `useIsScreenReaderEnabled()`, `aria-role`/`aria-state`/`aria-label`/`aria-hidden`. |
| **Terminal.Gui (.NET)** | Reputation > reality. v2 is a big architectural rewrite but no shipped accessibility tree / UIA bridge surfaced in public docs/issues. | — |
| **Brick (Haskell)** | Bug fixed in vty 5.33: stock widgets place cursor at logical focus. | New `putCursor` (same sig as `showCursor`) that writes the hardware cursor without rendering it. |
| **Windows Terminal** | The deepest TUI a11y work that exists. Full UIA tree (`UiaTextRange`), event signaling for selection / new-text / scroll / cursor. | UIA notifications for new output → Narrator/NVDA can report deltas. |
| **GitHub CLI (`gh`)** | Real shipped feature: `gh a11y` (v2.72+). Adopted Charm's Huh for prompts, dropped braille spinners. | Linear prompts, "Working…" static indicator, ANSI 4-bit palette. |
| **lazygit / k9s / slack-term** | Not specifically targeted; rely on cursor placement and luck. Mutt + WeeChat are the canonical "works with screen readers" examples. | — |
| **AccessKit** | (Not a TUI lib, but worth flagging.) Rust crate exposing one tree-shaped a11y schema with adapters for UIA / NSAccessibility / AT-SPI. Built for GUI toolkits (egui, Slint). No TUI has used it. | Cross-platform a11y abstraction. Closest prior art for "expose a real a11y tree from a non-native UI." |

### Per-framework details

**Textual.** Their position is that the accessibility story is the
web target. `textual serve` deploys a Textual app over the network with
a web frontend, which is genuinely accessible (real DOM, real ARIA
where Textual emits it). For the terminal target, they ship
`TEXTUAL_ANIMATIONS=basic|none` and `App.animation_level` for
reduce-motion but no semantic API. This is essentially the "the web is
the answer" stance, and for a Python framework with no native rendering
target, it's coherent.

**Bubble Tea / Huh / GitHub CLI.** Bubble Tea itself has no a11y. Issue
#780 has been open for years. The Charm team's actual answer is **Huh**,
their forms library:

```go
accessibleMode := os.Getenv("ACCESSIBLE") != ""
form.WithAccessible(accessibleMode)
```

In accessible mode, Huh drops the TUI entirely and renders the form as
sequential stdin prompts. No alternate screen, no redraws, no ANSI
positioning — just `printf`/`scanf`. GitHub CLI adopted Huh and added
`gh a11y` as a flag, then went further: replaced their braille spinner
with `Working…`, switched to ANSI 4-bit colors so users' palettes apply.

This pattern — "in accessible mode, render as a linear stream of
printed lines and prompts" — is the most pragmatic single feature you
can ship. It sidesteps every terminal-AT integration problem at once.

**Ink.** The most fleshed-out semantic API in any modern TUI lib:

```jsx
<Box aria-role="checkbox" aria-state={{checked: true}}>
  <Text>Accept terms and conditions</Text>
</Box>
```

Supported roles: `button, checkbox, combobox, list, listbox, listitem,
menu, menuitem, option, progressbar, radio, radiogroup, tab, tablist,
table, textbox, timer, toolbar`.

Supported states: `busy, checked, disabled, expanded, multiline,
multiselectable, readonly, required, selected`.

Plus `aria-label`, `aria-hidden`, and a `useIsScreenReaderEnabled()`
hook. Toggled via `INK_SCREEN_READER=true` or
`render(<App/>, {isScreenReaderEnabled: true})`.

**Important caveat:** Ink has no platform a11y bridge. These props
change the *rendered text* (e.g., expanding visual cues into words).
The "screen reader" is the user's terminal-mode screen reader (Speakup,
NVDA over UIA, etc.), reading whatever Ink prints. So in practice
ARIA-mode = a richer-text linear render mode. swift-tui's web target
can do *better* than this — emit real ARIA, not "ARIA-flavored text."

**Brick (Haskell) + vty 5.33.** Mario Lang (blind developer) describes
the fix on [blind.guru](https://blind.guru/blog/2021-06-25-brick.html):

> "The most important bit of metadata for a terminal screen reader is
> actually the cursor location."

The bug: Brick's stock widgets weren't placing the hardware cursor at
the focused element. Mutt and WeeChat work for screen readers because
they always put the cursor on the focused thing. Brick added `putCursor`
(positions without rendering) as a sibling to `showCursor`, retrofitted
all stock widgets, and shipped it in vty 5.33.

For swift-tui this means: **every focusable view should be able to
"claim the cursor" at its logical anchor even when not visually
rendering one.** The focus engine already knows where focus is; the
rasterizer needs to write the hardware cursor there at commit time.

**Windows Terminal — UIA event signaling.** The most ambitious approach.
The terminal itself bridges to the platform a11y API. UIA notifications
are how Narrator and NVDA know **what new text to announce** without
re-scanning the screen. swift-tui can't fix the terminal side, but it
can be a "good citizen" — keep the cursor right and avoid spurious
repaints — so platform UIA tools work on terminals that have them.

**ncurses / notcurses.** The lore answer. The "API" is the hardware
cursor. notcurses' braille support is for rendering pretty pictures,
not accessibility — and is in fact the *exact pattern* (braille
characters as visual elements) that breaks screen readers.

**Ratatui / Terminal.Gui / Brick (current).** No a11y story shipped.
Ratatui's docs aspirationally mention accessibility; Terminal.Gui has
the *reputation* of being the most accessibility-conscious .NET TUI
but in practice no shipped UIA bridge exists.

**AccessKit.** Not a TUI lib, but worth flagging because it's the
closest prior art for "expose a real a11y tree from a non-native UI."
[How it works](https://accesskit.dev/how-it-works/) explains the
schema (id + role + attrs + actions) and the platform adapters. If
swift-tui ever decided the CLI ceiling wasn't enough — e.g., wanted to
publish a real a11y tree to the host OS even from inside a terminal,
the way Microsoft Terminal does — AccessKit is what we'd build on.
Deferred.

---

## The universal lessons

Five rules show up in every primary source we read (GitHub CLI engineering
blog, blind.guru / Brick, Bubble Tea issue #780, the CHI 2021 paper, Ink
docs, Charm `huh` README, seirdy's CLI best-practices guide, the
"text-mode lie" post, Microsoft Terminal UIA design docs):

1. **Cursor-as-focus is foundational.** Mario Lang: "The most important
   bit of metadata for a terminal screen reader is actually the cursor
   location." Brick / vty 5.33 retrofitted `putCursor` for exactly this.
   Mutt and WeeChat are blind-dev-favorites because they keep the cursor
   on the focused element.

2. **Decorative redraws are the #1 a11y bug.** Spinners made of braille
   characters read aloud literally as "dot dot dot dot." Every full-screen
   repaint resets screen-reader cursor tracking. NVDA has been documented
   to crash on aggressive repaints. GitHub CLI replaced their braille
   spinner with `Working…` text and called it out as the single biggest
   improvement.

3. **A "drop the TUI" fallback is the most pragmatic single feature.**
   Charm `huh` ships `WithAccessible(true)` / `ACCESSIBLE` env var that
   replaces the entire interactive form with sequential stdin prompts.
   `gh a11y` does the same. Ink has `INK_SCREEN_READER=true`. This
   sidesteps every terminal-AT integration problem at once.

4. **The env-var contract is real and not negotiable.** `NO_COLOR`,
   `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `COLORTERM`, `TERM=dumb`,
   `LANG=C`, `CI`, isatty — users *will* set these and judge tools by
   whether they're honored. Specs are at [no-color.org](https://no-color.org/)
   and [bixense.com/clicolors](http://bixense.com/clicolors/).

5. **No automated TUI a11y testing exists.** Snapshot tests on
   accessible-mode output and piping renders through `espeak-ng` are
   the closest thing. Manual NVDA / Speakup / VoiceOver sessions are the
   gold standard. The CHI 2021 paper authors recommend listening tests
   explicitly.

---

## What we already have in swift-tui

> **Audit correction (2026-05-04):** the section below has been
> rewritten with concrete file/line references after auditing the
> codebase. See [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) for the
> full audit; this section is the digest. The earlier draft
> overstated semantic-tree completeness and understated env-var
> coverage.

The substrate is **richer than the first draft assumed in two places
and thinner in one place**. Specifically:

### Already populated and flowing (better than expected)

- **Accessibility roles are authored on built-in widgets and flow through
  the shared snapshot.**
  [`Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`](../../Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift)
  now defines `AccessibilityRole`, the ADR-0011 successor to the old
  `PresentationRole`, with built-in cases plus the added accessibility
  cases (`secureField`, `checkbox`, `image`, `progressBar`, `timer`,
  `heading(level:)`, `status`, `region`, `separator`, `columnHeader`,
  `rowHeader`, `cell`, `menuItem`, `tab`, `tabPanel`, `group`, and
  `custom(String)`). Built-in widgets populate
  `SemanticMetadata.accessibilityRole`: `Toggle` → `.toggle`
  ([`ValueControls.swift:88`](../../Sources/SwiftTUIViews/Controls/ValueControls.swift)),
  `TextField` → `.textField`
  ([`ValueControls.swift:261`](../../Sources/SwiftTUIViews/Controls/ValueControls.swift)),
  `TextEditor` → `.textEditor`
  ([`TextEditor.swift:70`](../../Sources/SwiftTUIViews/Input/TextEditor.swift)),
  `SecureField` → `.secureField`
  ([`SecureField.swift:91`](../../Sources/SwiftTUIViews/Input/SecureField.swift)),
  `Picker` → `.picker`
  ([`Picker.swift:154`](../../Sources/SwiftTUIViews/Controls/Picker.swift)),
  `Link` → `.link`
  ([`Link.swift:49`](../../Sources/SwiftTUIViews/Controls/Link.swift)),
  `DisclosureGroup` → `.disclosureGroup`
  ([`ValueControls.swift:356`](../../Sources/SwiftTUIViews/Controls/ValueControls.swift)),
  `TabView` → `.tabView`
  ([`TabView.swift:227`](../../Sources/SwiftTUIViews/NavigationViews/TabView.swift)),
  `ScrollView` → `.scrollView` / `.scrollViewWithIndicators`
  ([`ScrollView.swift:240`](../../Sources/SwiftTUIViews/ScrollView/ScrollView.swift)).
  `SemanticExtractor` now emits sparse
  `SemanticSnapshot.accessibilityNodes` records for roles, authored
  labels/hints/live regions, focus-chain nodes, and structural
  ancestors.

- **Tab item labels are already structured.**
  `SemanticMetadata.tabItemLabel` is a `TabItemLabel(title, detail?,
  badge?)` — see
  [`RenderTreeAndSemanticsTypes.swift:1-31`](../../Sources/SwiftTUICore/Resolve/ResolvedNode.swift).
  Good prior art for what a structured accessibility label looks like
  in this codebase. The `accessibilityLabel(_:)` modifier should
  follow the same pattern.

- **Env-var and flag parsing is partly landed.**
  [`TerminalPresentation.swift:84-135`](../../Sources/SwiftTUI/Terminal/TerminalPresentation.swift)'s
  `TerminalCapabilityProfile.detect(environment:isTTY:)` already
  reads `NO_COLOR`, `TERM` (incl. `dumb`/`*256color`), `COLORTERM`
  (incl. `truecolor`/`24bit`), `LC_ALL`/`LC_CTYPE`/`LANG` (drives
  ASCII glyph fallback automatically), and `isTTY` (drops to no
  color when stdout is not a TTY). Since the audit,
  `RuntimeConfiguration.detect(environment:isStdoutTTY:)` and the
  `SwiftTUIArguments` peer package have landed. They add parsing and
  precedence for `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`,
  and the `SWIFTTUI_*` family, plus framework flags such as
  `--accessible`, `--ascii`, `--reduce-motion`, `--plain`,
  `--linear`, `--cursor-follows-focus`, `--no-progress`, `--json`, and
  `--web`. Current behavior wiring is narrower than the parse surface:
  `--no-color`, `--force-color`, `--ascii`, `--plain`,
  `--cursor-follows-focus`, `--accessible`, `--reduce-motion`, and
  `--no-progress` now reach runtime behavior. Accessible output uses the
  linear renderer. Standalone `--linear`, `--json`, and `--web` behavior
  remain follow-ups.

- **Cursor positioning mechanism exists.**
  [`TerminalHost.swift`](../../Sources/SwiftTUI/Terminal/TerminalHost.swift)
  exposes `moveCursor(to:)` (lines 991, 1923), plus
  `hideCursorSequence()` / `showCursorSequence()` (1699/1703,
  1961/1965). The runtime hides the cursor at startup
  ([line 1894](../../Sources/SwiftTUI/Terminal/TerminalHost.swift)) and shows
  it at teardown ([line 1908](../../Sources/SwiftTUI/Terminal/TerminalHost.swift)).
  The runtime policy is now opt-in through
  `RuntimeConfiguration.cursorFollowsFocus`,
  `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1`, or `--cursor-follows-focus`; when
  disabled, normal TUI output leaves cursor placement alone after commits.

- **Focus engine exposes the data we need.**
  [`FocusTracker`](../../Sources/SwiftTUICore/Semantics/FocusTracker.swift) has
  `currentFocusIdentity: Identity?`. Each `FocusRegion` carries a
  `rect: CellRect`. Cursor placement = lookup + `moveCursor`.

- **Diff-based commit pipeline confirmed.** `CommitPlanner.swift` and
  `Rasterizer.swift` deliver on the pipeline's promise — terminal
  output is incremental, not full-repaint per frame. The
  WASI-surface encoder, however, currently emits a full surface per
  commit; see Finding 6 in the audit.

### Current follow-up state

- **Target-specific accessibility consumption is now partly wired.** The
  shared substrate carries `accessibilityLabel`, `accessibilityHint`,
  `accessibilityHidden`, `accessibilityLiveRegion`,
  `accessibilityRole`, and `SemanticSnapshot.accessibilityNodes`. The
  terminal runtime now consumes those records for opt-in cursor-as-focus,
  accessible linear output, reduce-motion/no-progress behavior, and
  accessible-mode live-region announcements. The Web/WASI surface now
  consumes those records through the `web-surface` v2
  `accessibilityTree` field and browser-side ARIA mounting. The SwiftUI
  host now consumes those records through a native accessibility overlay
  and platform live-region announcements.

  **Runtime policy note (2026-05-05):**
  [`ADR-0013`](../decisions/0013-accessibility-runtime-policy.md)
  now resolves the CLI policy before implementation: JSON beats
  accessible within the same precedence layer, accessible mode implies
  ASCII/reduced-motion/no-progress/linear output, cursor-as-focus defaults
  off and can be enabled with `--cursor-follows-focus` or
  `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1`, and CLI live regions announce only in
  accessible linear output in v1.

- **The `WebSurfaceFrameEncoder` now carries accessibility data.**
  The Web/WASI surface uses the `web-surface` v2 frame shape with an
  `accessibilityTree` alongside the raster grid. Browser-side mounting turns
  those `AccessibilityNode` records into ARIA nodes and live-region
  announcements without changing the raster canvas.

- **Cursor-anchor policy is shipped behind the opt-in runtime gate.**
  `AccessibilityNode.cursorAnchor` exists as the shared output field, and nil
  means consumers should fall back to the node origin. CLI cursor-following is
  default-off and opt-in through `cursorFollowsFocus`. Built-in `TextField`,
  `SecureField`, and `TextEditor` now publish real caret anchors and suppress
  their synthetic caret when hardware cursor-following is active. Custom focus
  targets can publish a local cursor anchor with
  `accessibilityCursorAnchor(_:)`.

### Implication

The proposal split is sharper than the first draft implied:

- **What is now landed:** accessibility-specific fields on
  `SemanticMetadata` (`accessibilityLabel`, `accessibilityHint`,
  `accessibilityHidden`, `accessibilityLiveRegion`,
  `accessibilityCursorAnchor`), the
  `AccessibilityRole` rename and expanded role set from ADR-0011,
  SwiftUI-shaped authoring modifiers for those fields,
  `SemanticExtractor` emission of sparse `AccessibilityNode` records
  on `SemanticSnapshot`, and built-in text-input caret anchors. CLI target
  behavior from ADR-0013 has also landed: normalized accessible runtime
  configuration, terminal cursor-as-focus, accessible linear output,
  motion/progress policy, and accessible-mode live-region announcements.

- **What remains:** the first-class target consumers are now wired for
  CLI, Web/WASI, and SwiftUI host paths. Public cursor anchors,
  imperative announcements, listening/lint guardrails, and visual-only
  content policy are also wired. Remaining proposal-level follow-up is now
  limited to broader behavior policy such as reduce-motion animation semantics
  and modal focus handling.

- **What this proposal does *not* do:** invent the role substrate
  (it exists), invent cursor-placement primitives (they exist), or
  invent env-var detection (the shared resolver and standard flag
  package now exist; remaining work is behavior wiring).

- **What this proposal *required from sibling proposals*:** the
  Web/WASI surface format has been extended with an `accessibilityTree`
  field to carry `AccessibilityNode` records to the browser. See
  [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md) Audit correction and
  [`ADR-0014`](../decisions/0014-accessibility-web-aria-wire-policy.md).

### Relevant prior decisions

- [`0009-theme-host-owned-views-write-semantic-tokens`](../decisions/0009-theme-host-owned-views-write-semantic-tokens.md)
  establishes a notion of semantic tokens. Accessibility roles are a
  parallel channel (theme = visual intent; a11y = AT intent — keep
  them separate).
- [`0003-action-scopes-not-global-hotkeys`](../decisions/0003-action-scopes-not-global-hotkeys.md)
  defines focus-chain command dispatch. Live-region announcements
  need to compose with this — modal scopes should be able to claim
  announcement regions.

---

## Best-practices checklist

Concrete patterns drawn from peer frameworks, primary sources, and
direct quotes from blind developers. This is the set of rules-of-thumb
the implementation should be measured against.

### 1. Color and contrast — the env var contract

**You don't know the user's palette.** Terminal emulators set background
colors, not your app. The GitHub CLI team's takeaway:

> "structural information must be conveyed in a way that's
> programmatically determinable — even if no explicit markup is
> present"

and apps must "take into account this variable" of user-controlled
background.

**Rules of thumb:**

- **Default to the 16 ANSI colors** (8 normal + 8 bright). They
  re-theme with the user's terminal, so your "red" honors their "red."
- Don't ship 24-bit truecolor by default; offer it behind
  `COLORTERM=truecolor` detection ([Bixense](http://bixense.com/clicolors/)).
- WCAG-style ratios are unverifiable in a TUI because you don't know
  the user's bg. Best you can do: pick foregrounds that maintain
  contrast against *both* common dark and light themes (avoid
  yellow-on-white, blue-on-black, bright-cyan-on-white).

**The env-var contract** (implement all of these):

| Variable | Behavior |
|---|---|
| `NO_COLOR` set & non-empty | Disable all color. Spec is "regardless of value" — `NO_COLOR=0` still disables. ([no-color.org](https://no-color.org/)) |
| `FORCE_COLOR` non-empty, non-`0` | Force color even when stdout isn't a TTY. |
| `CLICOLOR=0` | Disable color (legacy BSD convention). |
| `CLICOLOR_FORCE` non-empty, non-`0` | Force color. |
| `COLORTERM=truecolor`/`24bit` | OK to emit 24-bit sequences. |
| `TERM=dumb` | No ANSI sequences at all. |
| stdout is not a TTY | Disable color (auto). |
| `--color=always|never|auto` | CLI flag overrides env. |

**Precedence:** `NO_COLOR` wins over `FORCE_COLOR`. CLI flags win over
env. Auto-detect TTY when neither is set
([Python.org discussion](https://discuss.python.org/t/no-color-and-force-color-precedence/107166),
[Bixense CLICOLOR](http://bixense.com/clicolors/)).

### 2. Don't rely on color alone

Color-blind affects ~8% of men. Red/green pairs are the worst offender.
Concrete patterns from successful CLIs:

- **Prefix glyphs/words for state:** `git status` uses `M `, `A `, `??`.
  `cargo` uses `error:`, `warning:`, `note:`. `npm` uses `npm ERR!`.
  The text label, not the color, conveys meaning.
- **Position/layout:** error column always leftmost; success at end of
  line. `pytest` uses `.`/`F`/`E`/`s` characters before any color is
  applied.
- **Symbol + label, never symbol alone:** `[OK] passed` not just green
  dot. Reserve color as redundant emphasis.
- **For diffs:** prefix `+`/`-` (the way diff has done it for 50 years).
  Color is decoration on top.
- **Avoid red/green as the only differentiator.** Reach for blue/orange
  or cyan/magenta if you must encode two states by color, or add icons
  and text ([CLI palettes article](https://cli.r-lib.org/articles/palettes.html)).

### 3. Keyboard navigation and focus

- **Tab order = reading order.** Top-to-bottom, left-to-right. If your
  DSL allows out-of-order focus, you're building an accessibility bug.
- **Visible focus indicator is mandatory** and must be conveyed by
  *more than color* — use a `>` caret, reverse-video, brackets
  `[ Item ]`, or underline. **Reverse-video is the most universally
  rendered.**
- **Cursor position can expose focus for screen readers.** This is the single
  most important TUI rule. From Mario Lang:
  > "The most important bit of metadata for a terminal screen reader
  > is actually the cursor location."

  When the accessibility cursor-following policy is enabled, position the
  hardware cursor where logical focus lives, even if visually hidden.
  Distinguish "hidden cursor" (still positioned, screen-reader-tracked)
  from "absent cursor" (broken). Brick's lesson: implement both `putCursor`
  (invisible, positioned) and `showCursor` (visible). SwiftTUI defaults
  this policy off for normal TUI output because always-on cursor motion is
  distracting during ordinary keyboard navigation.

- **Escape always cancels.** Modal dialogs MUST close on `Esc` and
  return focus to the prior location ([Sarah Higley, "Escaping 101"](https://sarahmhigley.com/writing/escaping-101/)).
  Provide a visible "Cancel" too.
- **Document keys in-app** (`?` for help is the convention from
  less/vim/htop) and emit a keymap to `--help` so screen-reader users
  with man-page scripts can find them ([seirdy.one](https://seirdy.one/posts/2022/06/10/cli-best-practices/)).
- **Keymap conflicts with vim/emacs:** If you trap `Ctrl-A`, `Ctrl-E`,
  `Ctrl-W`, `Ctrl-U`, you collide with readline/emacs muscle memory. If
  you trap `j/k/h/l`, `:`, `/`, you collide with vim. Make bindings
  reconfigurable; treat single-letter alphabetic bindings only as
  opt-in modes.
- **Don't intercept terminal escape codes** the user/wrapper relies on
  (`Ctrl-Z` suspend, `Ctrl-C` interrupt, `Ctrl-S`/`Ctrl-Q` flow
  control).

### 4. Motion and animation — reduced-motion

There's no `prefers-reduced-motion` env var in terminals — but a
convention is forming:

- **Spinners are actively harmful to screen readers.** From seirdy:
  > "Nearly all animated spinners are extremely problematic for
  > screenreaders"

  ([seirdy.one](https://seirdy.one/posts/2022/06/10/cli-best-practices/)).
  Each frame redraws the same line, which screen readers re-announce.
  From the Inclusive Lens piece on Ink/gemini-cli:
  > "the application doesn't just fail; it actively spams you"

  ([xogium.me](https://xogium.me/the-text-mode-lie-why-modern-tuis-are-a-nightmare-for-accessibility)).

- **GitHub CLI's solution:** "replaced animated spinners with static
  text progress indicator messages instead of redrawing braille
  characters." In `gh a11y` mode: print `Loading...`, then later
  `Done.` — no redraws.

- **Honor these triggers to disable animation:** `NO_COLOR` (commonly
  used as a proxy), `CI=true`, `TERM=dumb`, non-TTY stdout, and a
  dedicated `--no-progress`/`--plain` flag plus our own env var
  (`SWIFTTUI_REDUCE_MOTION=1`).

- **Progress bars** are better than spinners (bounded, can be
  re-rendered as discrete percentage steps `10%... 20%... 30%`). Update
  at coarse intervals (every 5–10%, not every frame) when accessible
  mode is on ([evilmartians CLI UX](https://evilmartians.com/chronicles/cli-ux-best-practices-3-patterns-for-improving-progress-displays)).

- **Never blink.** Blink attribute is a WCAG 2.3.1 seizure-trigger and
  a CLI-accessibility no-no. Hard rule.

### 5. Unicode, box-drawing, emoji

- **Box-drawing chars are read aloud verbosely.** VoiceOver announces
  `┏` as "box drawings heavy down and right" and `━` as "box drawings
  heavy horizontal" ([CSS-Tricks](https://css-tricks.com/comparing-jaws-nvda-and-voiceover/)).
  NVDA's defaults skip many symbols entirely so structure becomes
  invisible ([Deque punctuation guide](https://www.deque.com/blog/dont-screen-readers-read-whats-screen-part-1-punctuation-typographic-symbols/)).

- **Quoted from a blind Claude Code user**
  ([anthropics/claude-code#247](https://github.com/anthropics/claude-code/issues/247)):
  > "Please add an env var or some config which allows users like
  > myself who are blind programmers to have a cleaner, ascii cli where
  > I can anchor a hotspot on my screen reader to catch the important
  > parts of the cli rather than having to scroll using up or down
  > screen reader keys to read the output."

- **Implement an ASCII-only mode.** R's `cli` package uses the
  `cli.unicode` option for this; Rust's `cli` crate has dual symbol
  tables. swift-tui should:
  - Honor `LC_ALL=C` / `LANG=C` (auto ASCII fallback).
  - Honor a `SWIFTTUI_ASCII=1` env var or `--ascii` flag.
  - Pair every Unicode glyph with an ASCII fallback: `─` → `-`,
    `│` → `|`, `└` → `+`, `✓` → `[OK]`, `✗` → `[X]`, `⏵` → `>`.

- **Skip emoji for state.** They're read inconsistently across screen
  readers and don't render in many terminals.

- **Don't draw decorative borders by default.** Borders break on resize
  and add noise. If used, single-line `─│└` rather than heavy/double;
  keep them togglable.

### 6. Reading order and redraws

- **Linear is the gold standard.** From the Inclusive Lens piece:
  > "a dumb, linear CLI stream is infinitely superior to a 'smart' TUI
  > that lags, spams, and scatters the cursor across the screen"

  ([xogium.me](https://xogium.me/the-text-mode-lie-why-modern-tuis-are-a-nightmare-for-accessibility)).

  The same author cites Linux `menuconfig` as accessible because "it
  enforces a strict, single-column focus." Irssi is "the gold standard
  for accessible chat" because it uses VT100 scrolling regions instead
  of full redraws.

- **Diff your screen, don't repaint it.** Track which cells changed and
  emit only those. Full-screen repaints push gigabytes of redundant
  text at screen readers and can crash NVDA. (swift-tui already does
  this via `CommitPlanner`.)

- **Layout columns top-down in DOM order** when serialized for an
  accessible/dump mode. If your DSL renders side-by-side `HStack`,
  provide a `--linear` flag that emits left-column then right-column.
  Don't expect screen readers to navigate spatially.

- **Don't move things mid-render.** Toasts that appear in random screen
  positions, footers that get rewritten — bury those behind a flag.

### 7. Status messages and live regions

There's no native ARIA-live in terminals, but the equivalent patterns:

- **Dedicated, append-only "status line" channel.** Append messages to
  a known region; screen readers can be parked there. *Don't*
  clear+redraw — append.

- **Echo critical announcements as plain new lines** in accessible
  mode. A "saved" toast becomes a printed line `[12:04:13] Saved.` —
  that's how screen readers actually catch it.

- **Severity prefixes:** `error:` / `warn:` / `info:` lets screen-reader
  users grep their scrollback. The CHI 2021 study found participants
  > "frequently used workarounds like grepping logs, redirecting output
  > to files, or using –json flags"
  ([CHI 2021](https://dl.acm.org/doi/abs/10.1145/3411764.3445544)).

- **Make errors readable when spoken.** From the same paper:
  > "error messages should be ensured to be understandable when read
  > aloud"

  Avoid bare regexes, jargon-only output, ASCII art borders around
  errors.

- **Provide `--json` / `--plain` / `--quiet`** modes. Screen-reader
  users routinely pipe to files or another tool; structured output is
  an accessibility feature, not just a scripting feature.

### 8. Density and zoom (low vision)

- **Terminals zoom by font size**, which means fewer columns. WCAG
  1.4.10 reflow expectation: content should be usable at very narrow
  widths (single column at the equivalent of 320 CSS px). Implication
  for swift-tui:
  - **Reflow gracefully at narrow widths.** Test at 40 columns. No
    fixed-width tables — collapse to label/value pairs vertically.
  - **No required horizontal scrolling.** Hard rule.
  - **Re-render on `SIGWINCH`.** And do it correctly on widen *and*
    narrow (the Claude Code bug filed at
    [claude-code#8276](https://github.com/anthropics/claude-code/issues/8276)
    was a narrow→wide reflow miss).

- **Don't depend on subtle 1-cell highlights.** A focus indicator
  that's only a single dim character is invisible at 200%–400% zoom
  because the next character is half the screen away. Use full-line
  reverse video.

- **Avoid ASCII art and decorative banners** — they look like garbage
  at large font sizes and are noise to screen readers.

### 9. Standards and legal references

- **Section 508 (US):** As updated in 2017 it incorporates WCAG 2.0
  A/AA. CLIs are *not exempted*; they fall under "ICT" and software
  requirements ([Section508.gov](https://www.section508.gov/)). The
  often-repeated "CLIs are inherently accessible" claim is a myth the
  CHI 2021 paper specifically refutes.

- **EN 301 549 (EU)** and the **European Accessibility Act (2025)** —
  same WCAG 2.1 AA baseline, applies to "non-web software."

- **UK GDS:** Government services must meet WCAG 2.2 AA
  ([gds-way.digital.cabinet-office.gov.uk](https://gds-way.digital.cabinet-office.gov.uk/manuals/accessibility.html)).
  GDS doesn't publish CLI-specific guidance but ships CLI accessibility
  *testing* tools.

- **BBC** ships [bbc-a11y](https://github.com/bbc/bbc-a11y) but their
  public standards are web-focused; no CLI-specific manifesto exists.

- **Microsoft Inclusive Design** principles (recognize exclusion, learn
  from diversity, solve for one extend to many) apply but no
  CLI-specific doc.

- **Apple HIG:** No TUI section, but VoiceOver-on-Terminal.app behavior
  is implicitly governed by AppKit accessibility. Worth testing under
  macOS VoiceOver since SwiftTUI users will often run on macOS.

- **Closest things to a TUI standard:** the
  [seirdy.one inclusive CLI guide](https://seirdy.one/posts/2022/06/10/cli-best-practices/)
  and the
  [CHI 2021 paper](https://dl.acm.org/doi/abs/10.1145/3411764.3445544)
  by Pradhan, Mehta & Bigham.

### 10. Testing TUIs for accessibility

- **No mature automated tool exists for TUIs** specifically. Web-style
  scanners (axe, pa11y, bbc-a11y) don't apply.

- **Manual screen-reader testing is the gold standard** and the CHI
  authors' explicit recommendation:
  - **macOS:** VoiceOver on Terminal.app and iTerm2.
  - **Windows:** NVDA (free, what most blind devs use) on Windows
    Terminal.
  - **Linux:** Speakup at the console; Orca on the desktop.

- **Audio sanity check:**
  > "Send your tool's output through a program like `espeak-ng` and
  > listen to it"

  ([seirdy.one](https://seirdy.one/posts/2022/06/10/cli-best-practices/)).
  It catches the punctuation/symbol noise problem fast.

- **Snapshot tests for accessible-mode output.** Capture stdout of a
  render in `SWIFTTUI_ASCII=1 NO_COLOR=1 SWIFTTUI_REDUCE_MOTION=1` and
  diff. This is the TUI analog to iOS's AccessibilitySnapshot.

- **Programmatic screen-reader drivers:** [Guidepup](https://assistivlabs.com/articles/automating-screen-readers-for-accessibility-testing)
  drives VoiceOver/NVDA in CI; useful for spot-checks on a handful of
  flows.

- **Lint your render:** detect raw box-drawing characters with no
  ASCII fallback registered, color-only state encodings, spinner usage
  without reduce-motion guard, missing focus indicator on focusable
  widgets.

- **Resize fuzz:** drive `SIGWINCH` at random widths from 20 to 200
  columns and assert no horizontal overflow / no crashes.

---

## Proposed API surface

### Authoring modifiers (View)

```swift
extension View {
  /// Spoken label for assistive tech; overrides any inferred label.
  func accessibilityLabel(_ label: String) -> some View

  /// Optional longer description; omitted by default.
  func accessibilityHint(_ hint: String) -> some View

  /// Semantic role. Defaults are inferred from the view kind
  /// (Button -> .button, Toggle -> .switch, etc.).
  func accessibilityRole(_ role: AccessibilityRole) -> some View

  /// Hides this subtree from AT. Use for purely decorative content.
  func accessibilityHidden(_ hidden: Bool = true) -> some View

  /// Marks this region as a live area. Updates announce when the
  /// inner text changes. Politeness governs interruption behavior.
  func accessibilityLiveRegion(_ politeness: AccessibilityPoliteness)
    -> some View

  /// Override where the hardware terminal cursor is parked when this
  /// view is focused. Defaults to the view's natural interaction
  /// point (caret for text fields, row start for list rows, label
  /// start for buttons).
  func accessibilityCursorAnchor(_ anchor: CellPoint)
    -> some View
}
```

`AccessibilityRole` is the renamed-and-extended successor to the
existing `PresentationRole` per
[ADR-0011](../decisions/0011-accessibility-role-replaces-presentation-role.md).
Built-ins already populate 20 of the cases; ADR-0011 adds the
remaining ~15. Single field on `SemanticMetadata`, single modifier
surface, single source of truth.

Cases inherited from `PresentationRole` (kept verbatim):

```
alert, button, confirmationDialog, disclosureGroup, link, list, menu,
picker, scrollView, scrollViewWithIndicators, section, sheet, slider,
stepper, table, tableRow, tabView, textEditor, textField, toggle
```

Cases promoted out of aliasing:

```
secureField              // SecureField now reports .secureField (was aliased to .textField)
```

Cases added by ADR-0011:

```swift
case checkbox            // alternative to .toggle for checkbox-style controls
case image
case progressBar
case timer
case heading(level: Int)
case status
case region
case separator
case columnHeader
case rowHeader
case cell
case menuItem
case tab                 // a single tab item; .tabView is the container
case tabPanel            // body of a tab
case group               // generic container with no more specific role
case custom(String)      // explicit escape hatch for app-specific roles
```

Plus the politeness enum, which is new:

```swift
public enum AccessibilityPoliteness: Sendable {
  case off, polite, assertive
}
```

The structural representation that `SemanticExtractor` produces from
these — the `AccessibilityNode` struct that flows through to the
embedded-host wire format, the SwiftUI bridge, and the CLI runtime
— is locked in by
[ADR-0012](../decisions/0012-accessibility-node-shape.md). Headlines:
flat array on `SemanticSnapshot`; parent encoded via
`parentIdentity: Identity?`; focus state computed by the consumer
(not baked into the node); pruned to a11y-relevant nodes plus
structural ancestors; document order = layout reading order; cursor
anchor field on the node, in absolute surface coordinates.

### Imperative announcement primitive

```swift
@MainActor
public enum AccessibilityAnnouncer {
  public static func announce(
    _ message: String,
    politeness: AccessibilityPoliteness = .polite
  )
}
```

Per-target behavior:

- **CLI:** appends sanitized lines to accessible linear output. Normal TUI
  mode does not write an announcement side-channel.
- **Web:** writes to a hidden `aria-live` element with matching
  politeness.
- **SwiftUI:** posts `UIAccessibility.post(.announcement, …)` /
  `NSAccessibility.post(.announcementRequested)`.

### Environment contract

Read at runtime startup and on `SIGWINCH` / config reload. CLI flags
override env. No-op when stdout is non-TTY (auto-disables animations
and color regardless).

The **parsing** of these flags and env vars and the precedence
implementation live in [`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md);
this section defines the **semantic meaning** of each variable. The
two proposals must stay in sync. If you're changing the precedence
rules, edit `ARGUMENT_PARSING.md`. If you're changing what a flag
*means* in terms of accessibility behavior, edit here.

| Variable | Effect |
|---|---|
| `NO_COLOR` (set, any value) | Disable color. Wins over `FORCE_COLOR`. |
| `FORCE_COLOR` (non-empty, non-`0`) | Force color even when stdout is non-TTY. |
| `CLICOLOR=0` | Disable color (legacy BSD convention). |
| `CLICOLOR_FORCE` (non-empty, non-`0`) | Force color. |
| `COLORTERM=truecolor` / `24bit` | Allow 24-bit color output. |
| `TERM=dumb` | No ANSI sequences; print plain text only. |
| `LANG=C` / `LC_ALL=C` | Auto-enable ASCII glyph mode. |
| `CI=true` | Treat as non-interactive: disable animations and reduce-motion-sensitive content. |
| `SWIFTTUI_ACCESSIBLE=1` | Enable accessible mode (linear render, no alt-screen, no spinners, append-only status). |
| `SWIFTTUI_ASCII=1` | Force ASCII glyph fallback. |
| `SWIFTTUI_REDUCE_MOTION=1` | Suppress animations and spinners. |
| `SWIFTTUI_CURSOR_FOLLOWS_FOCUS=1` | Opt in to moving the terminal cursor to the focused accessibility node in TUI output. |

CLI flags: `--accessible`, `--ascii`, `--no-color`, `--no-progress`,
`--plain`, `--linear`, `--cursor-follows-focus`, `--json`.

### Glyph fallback table

Every Unicode glyph used in built-in views is paired with an ASCII
fallback that ships in a single table (likely
`Sources/SwiftTUICore/Support/GlyphFallbackTable.swift`). Examples:

| Unicode | ASCII fallback | Notes |
|---|---|---|
| `─` `│` `┌┐└┘` `├┤┬┴┼` | `-` `|` `+` everywhere | Box drawing |
| `▀▄▌▐▛▜▙▟` | `*` for filled cells, `+` corners | Half-block borders (current default) |
| `✓` `✗` | `[OK]` `[X]` | State glyphs |
| `▶` `▼` `▲` `◀` | `>` `v` `^` `<` | Disclosure indicators |
| `⏵` `⏸` `⏹` | `>` `\|\|` `[]` | Media controls |
| `…` | `...` | Ellipsis |
| `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` (braille spinners) | `Working…` static line | Never animated in accessible mode |
| Emoji (any) | text label or omit | Read inconsistently across SRs |

The fallback is selected when ASCII mode is active. The mode is active
when any of: `LANG=C`, `LC_ALL=C`, `SWIFTTUI_ASCII=1`, `--ascii`, or
accessible mode.

### Cursor placement

Implemented in the commit phase behind an explicit runtime policy: when
`RuntimeConfiguration.cursorFollowsFocus` is true, at the end of every TUI
commit, position the hardware terminal cursor at the focused interaction
point. This policy defaults off for normal TUI output.

- **Text fields:** built-in `TextField`, `SecureField`, and `TextEditor`
  publish real caret anchors. Custom `TextFieldStyle` implementations should
  render `fieldContent` to preserve precise caret anchoring; styles that only
  render `displayText` fall back to the owning node's origin.
- **List rows:** at the start of the selected row's text.
- **Buttons:** at the first character of the label.
- **Custom focus targets:** configurable via `accessibilityCursorAnchor`,
  defaulting to the view's origin if unspecified.

When no widget is focused and the policy is enabled, the runtime hides the
cursor rather than leaving it wherever the renderer last drew. Longer term,
the best screen-reader behavior is a stable parked cursor location (e.g.,
bottom-left or end of last appended status line). This is the Brick lesson.

**Text-input caret tracking status:** `TextField`, `SecureField`, and
`TextEditor` now use the shared text input model to compute a caret anchor from
layout. When `cursorFollowsFocus` is enabled, they suppress the synthetic `_`
caret and publish the real caret anchor through accessibility semantics. Secure
fields publish only location metadata; their secret value remains redacted.

### Reduce-motion behavior

When reduce-motion is active:

- Spinners (any animated indicator) replaced with a single static line
  (`Working…`) updated only when state genuinely changes
  (`Working…\nDone.`).
- Progress bars update at coarse intervals (every 5–10%, not every
  frame).
- Transitions / animations are skipped; final state renders directly.
- Blink attribute never emitted (this is also a WCAG 2.3.1 hard rule).
- Non-essential auto-refresh halted.

### Accessible mode (the "drop the TUI" fallback)

When `SWIFTTUI_ACCESSIBLE=1` or `--accessible` is set:

- No alternate screen buffer (`smcup`/`rmcup`) — render flows in
  scrollback.
- No clear-and-redraw of regions; output is append-only.
- HStacks / side-by-side layouts linearize to top-down (left column
  then right column).
- Decorative borders dropped (or rendered with the ASCII table).
- Focused widget's prompt is printed and waits on stdin, then echoes
  result and continues — this is the `huh` / `gh a11y` pattern.
- Status updates printed inline with `[time] severity: message` format.
- All severity-prefixed: `error:`, `warn:`, `info:`, `note:`.

This mode is a render-strategy switch, not an authoring switch. View
authors write the same SwiftUI-shaped tree; the runtime chooses how to
realize it.

---

## Anti-patterns this proposal commits us to avoiding

- **Spinner braille / unicode-dot animations** — read aloud literally
  ("dot dot dot dot"). GitHub CLI's #1 fix.
- **Full-screen repaints on every keystroke** — NVDA crash trigger.
  swift-tui's diff-based commit pipeline already prevents this; we
  preserve the invariant.
- **Hidden cursor parked anywhere not at the focused element** —
  Brick's bug. Silently mistells screen readers what's selected.
- **Color as the only state signal** (red error, green success). ~8%
  of men can't tell. Add prefix glyphs/words.
- **Default box-drawing borders without an ASCII fallback** — huge
  speech-noise generator. Toggle off with `LANG=C` / `SWIFTTUI_ASCII`.
- **Trapping `Ctrl-C` / `Ctrl-Z` / `Ctrl-S` / `Ctrl-Q`** — breaks
  user/wrapper expectations.
- **Single-cell or color-only focus indicators** — invisible at 200%+
  zoom and to color-blind users. Reverse-video full-line is the safe
  default.
- **Required horizontal scroll at any width** — WCAG reflow violation.
- **Pop-in toasts / floating notifications in random screen regions**
  — screen readers can't track them. Compose with
  `accessibilityLiveRegion` / `AccessibilityAnnouncer`.
- **"ARIA-flavored text" as a substitute for real ARIA in the web
  target** — Ink does this because they have to (no platform a11y
  bridge). Our web target should emit real ARIA, not text-rendered
  pseudo-ARIA.
- **Detecting "is a screen reader attached"** — neither possible from
  inside a CLI nor desirable. Expose toggles users set explicitly.

---

## What the non-CLI targets unlock

### Embedded web host (`Platforms/WebHost/`, proposed)

This is the strongest accessibility delivery vehicle in the framework
and the single most consequential update to this proposal since v1.

The user has a compiled SwiftTUI binary. They run `myapp --web`. The
binary opens an HTTP/WebSocket server bound to `127.0.0.1`, prints a
URL with a per-launch auth token, and waits. The user opens the URL in
their browser. The browser renders the same view tree using real DOM
elements with real ARIA roles, labels, and live regions, driven by the
semantic stream the binary is sending over the WebSocket.

For accessibility this is transformational because:

1. **Zero recompile.** The same binary that runs as a TUI runs as a
   web server. No WASM toolchain, no separate build, no deploy step.
   The accessibility mode is a flag away.
2. **The browser is a known-accessible target.** macOS VoiceOver works
   well in browsers; NVDA works well in browsers; Orca works well in
   Firefox/Chromium. We do not need to fight terminal-AT integration —
   we sidestep it.
3. **Real ARIA, not "ARIA-flavored text."** Ink fakes ARIA by
   expanding visual cues into text the terminal screen reader reads.
   We can emit honest `<button role="button" aria-label="…">` markup
   that browsers and ATs already speak natively.
4. **Same semantic data feeds it.** The `semantics` phase already
   captures role/label/state. The web host's only job is to serialize
   that record over the wire and the browser's only job is to mount
   it as DOM. The accessibility API authoring surface
   (`accessibilityLabel(_:)`, `accessibilityRole(_:)`, etc.) lights up
   on this target with no extra authoring work.

The architecture, wire format, server choice, security model, and CLI
shape are designed in [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md).
For accessibility's purposes the contract is:

| Authoring | Wire | Browser DOM |
|---|---|---|
| `accessibilityRole(.button)` | `{role: "button", …}` | `<button role="button">` |
| `accessibilityRole(.heading(level: 2))` | `{role: "heading", level: 2, …}` | `<h2>` |
| `accessibilityLabel("Save")` | `{label: "Save", …}` | `aria-label="Save"` |
| `accessibilityHint("Saves the file")` | `{hint: "…", …}` | `aria-describedby` |
| `accessibilityHidden(true)` | `{hidden: true, …}` | `aria-hidden="true"` and skipped from focus |
| `accessibilityLiveRegion(.polite)` | `{liveRegion: "polite", …}` | `aria-live="polite"` |
| `AccessibilityAnnouncer.announce(_:)` | `{type: "announce", message: "…", politeness: …}` | text injected into hidden offscreen `aria-live` region |

This is the same Textual takes with [`textual serve`](https://github.com/Textualize/textual-serve)
and considers their primary accessibility story — but Textual ships
raw ANSI bytes and lets xterm.js render visually, which gives screen
readers nothing semantic. We can do meaningfully better because our
semantic record is already richer than ANSI.

For users whose terminal screen reader story is poor — blind macOS
users especially — the recommended workflow is:

```
$ myapp --web
SwiftTUI is running at http://127.0.0.1:9123/?token=...
$ # Open the URL in your browser; use it there with VoiceOver/NVDA/Orca.
```

### WASM web target (`Platforms/Web/`)

The existing WASM-based web target is a peer to the embedded host. It
is the right answer for "deploy your TUI as a public website." The
ARIA mapping is identical; the difference is *where* the SwiftTUI
runtime executes (in-browser via WASM vs in-process on the user's
machine).

For accessibility purposes, both web targets unlock the same set of
ARIA bindings driven from the same `semantics` phase. The framework
should provide a single ARIA-emission code path that both targets
consume, parameterized over the transport.

### SwiftUI host (`Platforms/SwiftUI/`)

The SwiftUI host bridges swift-tui's semantic record to native Apple
accessibility by mounting a nonvisual SwiftUI overlay above the raster
terminal surface. The policy is recorded in
[`ADR-0015`](../decisions/0015-accessibility-swiftui-host-policy.md):
v1 uses semantic focus metadata rather than imperative VoiceOver focus
movement, converts `CellRect` through the host's native cell metrics for
accessibility frames, diffs live regions by identity before posting
platform announcements, and never invents labels for visual-only
content. This implementation is tracked by
[`2026-05-05-005-accessibility-swiftui-host-plan.md`](../plans/2026-05-05-005-accessibility-swiftui-host-plan.md),
now marked completed.

| swift-tui | SwiftUI |
|---|---|
| `accessibilityLabel(_:)` | `.accessibilityLabel(_:)` |
| `accessibilityHint(_:)` | `.accessibilityHint(_:)` |
| `accessibilityRole(_:)` | `.accessibilityAddTraits(_:)` (mapped) |
| `accessibilityHidden(_:)` | `.accessibilityHidden(_:)` |
| `accessibilityLiveRegion(_:)` | combination of `.accessibilityElement` + announcement post |
| `AccessibilityAnnouncer.announce` | `UIAccessibility.post(.announcement, …)` |

---

## Relationship to other proposals

This proposal is one of four closely related drafts on the
`accessibility-investigation` branch. Each owns a different design
authority and they cross-reference rather than duplicate:

| Proposal | Owns |
|---|---|
| [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) (this doc) | The semantic API surface (`accessibilityLabel`, `accessibilityRole`, `accessibilityHidden`, `accessibilityLiveRegion`, `AccessibilityAnnouncer`), per-target render strategies (cursor-as-focus, ASCII fallback, reduce-motion, ARIA mapping), and the env-var contract for accessibility-related toggles. |
| [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md) | The architecture, wire format, server choice, browser bundle, security model, and CLI shape for "run your binary, view it in a browser at localhost." Recommends a `Platforms/WebHost/` runner peer using FlyingFox + the existing WASISurfaceBridge encoder *extended* with an `accessibilityTree` field (per the audit). |
| [`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md) | The framework-reserved flag namespace, the `SwiftTUIOptions` `OptionGroup` and `SwiftTUIApp` protocol, and the precedence rules between CLI flags, env vars, and TTY auto-detection. Recommends layering on `swift-argument-parser` and shipping as a peer to the existing `SwiftTUICLI` runner. |
| [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) | The factual record of what's already in the codebase. Read this *first* if any of the other proposals' "what we already have" claims feel surprising — the audit corrected a few of them. |

**Reading order for a new contributor:** start here (`ACCESSIBILITY.md`)
for the *why*, then `ARGUMENT_PARSING.md` for the *flag surface*, then
`EMBEDDED_WEB_HOST.md` for the *delivery vehicle*. The three together
form the accessibility plan; this proposal alone is incomplete.

**What this means concretely:**

- The `--accessible`, `--ascii`, `--reduce-motion`, `--no-color`, and
  `--linear` flags listed in this proposal's [environment contract](#environment-contract)
  are *defined* here (semantic meaning) but *implemented* in
  `ARGUMENT_PARSING.md`'s `SwiftTUIOptions` (parsing, precedence, env
  var alignment). Don't duplicate the parsing rules here.
- The `--web` flag and its sub-flags (`--port`, `--bind`, `--no-open`,
  `--web-token`) are implemented in `EMBEDDED_WEB_HOST.md` and surfaced
  in `ARGUMENT_PARSING.md`'s standard flags table. This proposal
  references them only to note their accessibility role.
- The "ARIA mapping" half of Phase 6 in this proposal's phasing
  depends on the embedded web host runner shipping (or the WASM web
  target maturing). Both feed off the same semantic record.

---

## Open questions

(Things we should decide before implementation starts. List is meant
to be argued with, not accepted.)

1. **Should `SWIFTTUI_ACCESSIBLE=1` imply `SWIFTTUI_ASCII=1` and
   `SWIFTTUI_REDUCE_MOTION=1`, or are they orthogonal?** Argument for
   coupling: simpler mental model; users who want one usually want all.
   Argument against: a sighted user with a small terminal may want
   ASCII without losing color. Lean: imply, but allow individual
   overrides.

2. **Does `accessibilityRole` default infer from the view kind, or is
   it required for non-builtins?** **Resolved by
   [ADR-0012](../decisions/0012-accessibility-node-shape.md)
   §"Role inference"** — built-ins set the role in
   `SemanticMetadata.accessibilityRole` (post ADR-0011 rename);
   consumer-authored views without an explicit role default to
   `.group` if they have a11y-relevant descendants and are skipped
   otherwise.

3. **Linear-mode HStack ordering: top-down left-right by source order,
   or by laid-out reading order?** SwiftUI picks layout reading order;
   web ARIA picks source order. The two can diverge under RTL. Lean:
   layout reading order, mirrored under RTL.

4. **Where does `accessibilityLiveRegion`'s output go in CLI mode when
   the app is *not* in accessible mode?** Options: discard, write to a
   reserved status line, write to stderr behind a flag. Lean: reserved
   status line; an app-author can opt out per-region.

5. **Do we need an `accessibilityCursorAnchor()` modifier, or can the
   focus engine always derive the anchor from the focused view's
   geometry?** **Resolved by
   [ADR-0012](../decisions/0012-accessibility-node-shape.md)** —
   the field exists on `AccessibilityNode` (in absolute surface
   coordinates); nil means "use the node's origin." The public
   `accessibilityCursorAnchor(_:)` modifier accepts a local `CellPoint` for
   custom focus targets. Built-in caret-anchor population for `TextField`,
   `SecureField`, and `TextEditor` has landed through the text input V1 plan;
   see [`TEXT_INPUT_MODEL.md`](./TEXT_INPUT_MODEL.md).

6. **How do animations interact with reduce-motion?** Specifically: a
   transition that *also* changes text content (e.g., a list reorder).
   Skipping the animation should still announce the new state. The
   `Animation` subsystem (`Sources/SwiftTUIViews/Animation/`,
   `Sources/SwiftTUI/Lifecycle/AnimationController.swift`) needs an audit.

7. **Theme / appearance interaction.** Decision 0009 has views write
   semantic tokens. Do accessibility roles ride on the same channel,
   or a parallel one? Lean: parallel (semantic tokens are *theme*
   intent; accessibility roles are *AT* intent; conflating risks both).

8. **Embedded web host: do we ship the ARIA mapping in v1, or is it a
   follow-up?** Now that
   [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md) exists, the
   question is whether the accessibility ARIA mapping rides on its v1
   or waits for v2. Argument for v1: it's the strongest a11y story we
   have, and the required semantic source data will exist once
   Phase 3b lands. Argument against: embedded host has its own scope,
   and the audited `web-surface` format still needs a v2
   `accessibilityTree` extension plus browser-side DOM mounting.
   Lean: ship ARIA mapping in embedded-host v1, but keep the
   per-target render strategy gated behind a feature flag so we can
   ship the CLI side independently.

   The original v1-vs-v2 question for the **WASM** web target stands
   separately: it's the deploy-as-website story and is less urgent
   for accessibility than the embedded host. Lean: WASM ARIA mapping
   in v2 of the WASM target, after the embedded host validates the
   semantic-record-to-DOM translation.

9. **How do we handle `Canvas` / `BrailleCanvas` / image rendering?**
   **Resolved in source (2026-05-06).** Visual-only view surfaces require an
   accessibility label or an explicit `accessibilityHidden(true)` choice.
   `Canvas` and `Image` mark themselves as image-like visual content.
   `AnimatedImage` inherits the `Image(data:)` policy. Common
   `SwiftTUICharts` views publish built-in textual summaries as image labels
   when using their default summary initializers; custom builder-based charts
   warn unless authors add `accessibilityLabel(...)` or hide the chart.
   Unlabeled visual content is omitted from accessible linear output and emits
   a semantic warning in accessible output instead of guessing a label.

10. **Modal presentations** (`.sheet`, `.alert`, `.confirmationDialog`).
    They need focus trapping and `Esc` to dismiss; what happens to
    focus on dismiss is a separate subproblem. Lean: defer to the
    action-scopes proposal (decision 0003) and add a follow-up note.

11. **Detection vs declaration.** We've said we don't detect screen
    readers. But should we honor `SSH_TTY` / `TERM_PROGRAM` /
    `WT_SESSION` (Windows Terminal session marker) as hints — e.g.,
    enable UIA-event-friendly behavior on Windows Terminal? Lean: no
    detection; users opt in with env vars or flags. Keep it simple.

12. **Spinner replacement granularity.** When reduce-motion replaces
    a spinner with `Working…`, does it also include progress
    information ("Working… 32%")? Argument for: useful. Argument
    against: now we're doing periodic updates again, which is what we
    were trying to avoid. Lean: yes but only when the surrounding
    progress changes by ≥10%, never on a timer.

13. **Should reading `LANG=C` auto-enable accessible mode, or only
    ASCII?** Some users set `LANG=C` for performance/locale reasons,
    not a11y reasons. Lean: ASCII only; accessible mode requires
    explicit opt-in.

14. **Charts / `SwiftTUICharts`.** Charts are inherently visual.
    What's the accessible representation? Tabular data? Text
    summary? Lean: every chart must be authored with a textual data
    summary that takes over in accessible mode, similar to
    `<figcaption>` + `aria-describedby` in HTML.

15. **Output-mode precedence between JSON and accessible output.**
    CLI flags currently resolve `--accessible` before `--json`, while
    environment detection lets `SWIFTTUI_JSON=1` override
    `SWIFTTUI_ACCESSIBLE=1`. Before wiring either output mode to
    behavior, pick one precedence rule and align code, tests, and
    `ARGUMENT_PARSING.md`.

---

## Out of scope (this version)

- Programmatic screen-reader driving in CI (Guidepup integration).
- `espeak-ng` listening tests.
- AccessKit-style cross-platform AT bridge (UIA / NSAccessibility /
  AT-SPI from one schema). Worth revisiting if the CLI target ceiling
  becomes the binding constraint, but no TUI framework has successfully
  shipped this and the web target gives us a credible workaround.
- Terminal capability negotiation beyond what
  `TerminalGraphicsCapabilities` already detects.
- BIDI / RTL text shaping. Cross-cuts with layout, deferred.
- Non-English screen-reader pronunciation tuning. We emit text; the SR
  pronounces it. Out of scope for the framework.
- Braille display optimization (BRLTTY-specific output formatting).
- Voice-input / dictation integration.

---

## Suggested phasing

> **Audit correction (2026-05-04):** Phase 1 is smaller than first
> drafted (env detection partly exists; we extend rather than build).
> Phase 3 splits cleanly into 3a (authoring fields/modifiers) and 3b
> (extractor changes). Phase 6 was bigger than first drafted because
> the embedded-host wire format had to be extended with an
> `accessibilityTree` field; that Web/WASI v2 encoding has now landed.
> See [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) for the cost-delta
> reasoning per phase.

(Sketch only — order is argued for, not committed to. Phases marked
with † depend on `ARGUMENT_PARSING.md` reaching at least Phase 1
(SwiftTUIOptions OptionGroup landed). Phases marked with ‡ depend on
`EMBEDDED_WEB_HOST.md` reaching at least Phase 1 (basic runner +
WebSocket transport landed).)

1. **Phase 1 — Env contract + ASCII mode.** † **(Partly landed.)**
   `RuntimeConfiguration`, `RuntimeConfiguration.detect(...)`,
   `SwiftTUIOptions`, and `SwiftTUIOptions.runtimeConfiguration(...)`
   now cover the env/flag surface from `ARGUMENT_PARSING.md`.
   `--no-color`, `--force-color`, `--ascii`, and `--plain` reach
   `TerminalHost` rendering. Remaining Phase 1 work is behavior-side:
   grow the glyph fallback coverage where built-ins still use Unicode
   directly. ADR-0013 decides that `--accessible` and
   `SWIFTTUI_ACCESSIBLE=1` imply ASCII, reduced motion, no progress,
   and linear output.

2. **Phase 2 — Cursor-as-focus.** **(Same effort as drafted.)** The
   mechanism (`moveCursor`, `hideCursor`, `showCursor`) and the data
   (`FocusTracker.currentFocusIdentity` → `FocusRegion.rect`)
   already exist; the new work is the policy: after each commit,
   look up the focused widget and call `moveCursor` to its anchor.
   ADR-0012 puts `cursorAnchor` on `AccessibilityNode`; the remaining
   behavior gate is now resolved by ADR-0013: terminal TUI output shows and
   moves the cursor only when `RuntimeConfiguration.cursorFollowsFocus` is
   enabled and a focused accessibility node exists. Built-in text input
   controls publish caret anchors, custom focus targets can use
   `accessibilityCursorAnchor(_:)`, and nodes without an anchor fall back to
   their origin.

3. **Phase 3a — Accessibility authoring modifiers.** **(Landed.)** Added
   `accessibilityLabel`, `accessibilityHint`, `accessibilityHidden`,
   `accessibilityLiveRegion`, `accessibilityRole(_:)`, and
   `accessibilityCursorAnchor(_:)` modifiers plus the corresponding fields on
   `SemanticMetadata`. ADR-0011 is implemented: `PresentationRole` is now
   `AccessibilityRole`, with the missing accessibility cases added.

4. **Phase 3b — `SemanticExtractor` accessibility records.**
   **(Landed.)** Extends
   `SemanticSnapshot` with `accessibilityNodes:
   [AccessibilityNode]`. It populates during the existing walk in
   [`Semantics.swift`](../../Sources/SwiftTUICore/Semantics/Semantics.swift). Skip
   transient and `accessibilityHidden(true)` subtrees. Output is a
   flat list with parent-identity references (matches existing
   `interactionRegions` / `focusRegions` shape); tree reconstruction
   happens at the consumer.

5. **Phase 4 — Reduce-motion + accessible mode.** † **(CLI runtime
   landed.)** Spinner/progress controls honor reduced-motion and
   no-progress policy, `SWIFTTUI_ACCESSIBLE=1` and `--accessible`
   imply ASCII/reduced-motion/no-progress/linear output, and the
   accessible linear renderer consumes `SemanticSnapshot.accessibilityNodes`.
   ADR-0013 pins the output precedence, reduced-motion behavior,
   no-progress behavior, and the accessible linear renderer format.

6. **Phase 5 — Live regions + announcer.** **(Landed.)**
   `accessibilityLiveRegion`
   is wired into the semantic substrate and the terminal runtime
   announces changed live-region labels in accessible linear output.
   ADR-0013 scopes CLI v1 announcements to accessible linear output
   only; normal TUI mode does not write live-region text to stderr or
   another side channel. The public `AccessibilityAnnouncer.announce(_:)`
   API queues app-triggered `SemanticSnapshot.accessibilityAnnouncements`
   for the committed frame. CLI accessible output renders them as sanitized
   announcement lines; Web/WASI frames encode them for the hidden ARIA live
   region; SwiftUI host sessions post them through the platform announcement
   API.

7. **Phase 6 — Embedded-host / Web/WASI ARIA mapping.** ‡ **(Landed
   for the shared WASI/web-surface path.)** Three sub-steps:

   1. **Wire-format extension.** Bump `WebSurfaceFrameEncoder`'s
      version field from `1` to `2`. Add an `accessibilityTree`
      field alongside `rows` carrying the `AccessibilityNode` list
      from Phase 3b. Backward-additive: a v1-aware browser bundle
      ignores it; a v2-aware bundle uses it.
   2. **Browser-side mounter.** Extend the existing browser bundle
      in `Platforms/Web/` to mount `accessibilityTree` as a hidden
      DOM tree (offscreen positioned, `aria-hidden="false"` while
      the visual grid stays as the painted layer). Role-correct
      elements with `aria-label`, `aria-describedby`,
      `aria-live`. Browser AT traverses the DOM; sighted users see
      the grid. Focus on the AccessibilityNode marked `isFocused`
      gets `.focus()`'d.
   3. **Diff-based encoder.** Today the encoder emits a full
      surface per commit. For the embedded-host's WebSocket transport
      this becomes wasteful at higher refresh rates. Add a
      diff-based encoder variant that mirrors the terminal-side
      `CommitPlanner` strategy. Optional for v1 of the embedded
      host; required before scaling.

   **This is the strongest single accessibility ship the framework
   can make** because it gives every binary a first-class accessible
   viewer in the browser. The shared WASI/web-surface encoder and
   browser bundle now implement the v2 tree and ARIA mounter; a
   separate embedded host runner can reuse that path when it conforms
   its transport.

8. **Phase 7 — WASM web ARIA mapping.** **(Landed.)** Same code path
   as Phase 6, different transport. The WASI package emits
   `accessibilityTree` data and the browser runtime mounts it as
   offscreen ARIA beside the painted canvas.

9. **Phase 8 — SwiftUI host bridge.** **(Landed.)** Maps
   `AccessibilityNode` records (Phase 3b) to a native SwiftUI
   accessibility overlay in the SwiftUI host. Lights up VoiceOver/AT on
   Apple platforms. The flat-list-with-parent-IDs shape from Phase 3b is
   consumed through host-owned role, focus, hit-testing, and announcement
   policy from ADR-0015.

10. **Phase 9 — Tests + lint.** **(Landed for guardrails, listening docs,
    and visual-only policy.)** Snapshot tests cover accessible-mode output,
    Web/WASI ARIA transport, SwiftUI host mapping, imperative announcements,
    cursor anchors, and visual-only warning behavior.
    `Scripts/check_accessibility_guardrails.sh` now pins reviewed raw-glyph,
    color-state, and visual-content source manifests so new risk surfaces
    require explicit review. Listening tests under VoiceOver/NVDA/Orca are
    documented in
    `Tests/SwiftTUITests/Accessibility/README.md`. The browser-target
    listening tests are the easiest wins because the browser AT story is
    mature.

Each phase is independently shippable; each makes the framework
materially more accessible than the previous one. Phases 1–5 are
**CLI accessibility** and can land without any web-host work. Phase 6
is the headline a11y ship and benefits the most users; it requires
the embedded host runner to exist.

---

## Sources

The full research archive (with quotes and per-framework deep-dives) is
in this document. The primary sources, grouped by theme:

### Successful CLI accessibility retrofits

- GitHub Engineering — [Building a more accessible GitHub CLI](https://github.blog/engineering/user-experience/building-a-more-accessible-github-cli/)
- GitHub Community — [GitHub CLI a11y Public Preview discussion](https://github.com/orgs/community/discussions/158037)
- Charm — [`huh` README — `WithAccessible`](https://github.com/charmbracelet/huh)
- Microsoft — [VSCode issue #59794: integrated terminal not accessible with JAWS/NVDA](https://github.com/microsoft/vscode/issues/59794)
- Anthropic — [claude-code issue #247: Screen Reader Accessibility for Unicode Symbols](https://github.com/anthropics/claude-code/issues/247) (concrete blind-dev request)
- Anthropic — [claude-code issue #8276: text doesn't reflow when terminal is resized](https://github.com/anthropics/claude-code/issues/8276)
- DeepSeek-TUI — [issue #450: NO_ANIMATIONS env var](https://github.com/Hmbown/DeepSeek-TUI/issues/450)
- Fly.io — [Web terminal screen-reader accessible](https://community.fly.io/t/our-web-terminal-is-now-screen-reader-accessible/14395)

### Peer TUI framework accessibility

- charmbracelet — [Bubble Tea issue #780: screen reader accessibility roadmap](https://github.com/charmbracelet/bubbletea/issues/780)
- vadimdemedes — [Ink readme (ARIA subset, INK_SCREEN_READER, useIsScreenReaderEnabled)](https://github.com/vadimdemedes/ink)
- Mario Lang — [Why the text terminal cursor is important for Accessibility (Brick + vty 5.33)](https://blind.guru/blog/2021-06-25-brick.html)
- ratatui — [Ratatui homepage](https://ratatui.rs/)
- dankamongmen — [notcurses repo](https://github.com/dankamongmen/notcurses)
- gui-cs — [Terminal.Gui v2 docs](https://gui-cs.github.io/Terminal.Gui/)
- microsoft — [Windows Terminal — UIA Signaling Model #2447](https://github.com/microsoft/terminal/issues/2447), [PR #1691 (UIA tree)](https://github.com/microsoft/terminal/pull/1691), [PR #4018 (UiaTextRange refactor)](https://github.com/microsoft/terminal/pull/4018), [PR #14097 (WPF UIA events)](https://github.com/microsoft/terminal/pull/14097)
- AccessKit — [How it works](https://accesskit.dev/how-it-works/)
- HN — [ncurses accessibility discussion](https://news.ycombinator.com/item?id=28354733)
- opencode — [issue #8565: accessibility mode for screen reader users](https://github.com/anomalyco/opencode/issues/8565)

### Screen reader and platform AT

- NV Access — [NVDA 2025 user guide — review cursor / console](https://download.nvaccess.org/documentation/userGuide.html)
- nvaccess — [NVDA discussion #18616: command-line terminal navigation](https://github.com/nvaccess/nvda/discussions/18616)
- nvaccess — [PR #13261: Windows Terminal UIA class-name break](https://github.com/nvaccess/nvda/pull/13261)
- NVDA mailing list — [How to read Command Prompt](https://nvda.groups.io/g/nvda/topic/how_to_read_command_prompt/830352)
- microsoft — [TermControlAutomationPeer source](https://github.com/microsoft/terminal/blob/main/src/cascadia/TerminalControl/TermControlAutomationPeer.cpp)
- microsoft — [Building Windows Terminal with WinUI](https://devblogs.microsoft.com/commandline/building-windows-terminal-with-winui/)
- pinokiocomputer — [Pinokio issue #1049: terminal output not exposed to NVDA/UIA](https://github.com/pinokiocomputer/pinokio/issues/1049)
- warpdotdev — [Warp Discussion #1704: Building the most accessible terminal](https://github.com/warpdotdev/Warp/discussions/1704)
- Speakup — [Project home](http://www.linux-speakup.org/)
- Linux Journal — [Making Linux Accessible with Speakup](https://www.linuxjournal.com/article/8501)
- BRLTTY — [Official site](https://brltty.app/)
- Emacspeak — [The Complete Audio Desktop](https://emacspeak.sourceforge.net/)
- Digital Darragh — [Tilda terminal with Orca / VTE accessibility](https://www.digitaldarragh.com/2011/08/22/using-the-tilda-terminal-in-linux-with-full-accessibility-for-orca-users/)

### Voices of blind developers

- Parham Doustdar — [Tools of a Blind Programmer](https://www.parhamdoustdar.com/2016/04/03/tools-of-blind-programmer/)
- Parham Doustdar — [How a Completely Blind Manager/Dev Uses Emacs Every Day (EmacsConf 2019)](https://emacsconf.org/2019/talks/08/)
- HN — [Ask HN: Resources for blind developers and sysadmins?](https://news.ycombinator.com/item?id=18522497)
- HN — [How a Blind Person Programs](https://news.ycombinator.com/item?id=8965048)
- HN — [How do blind people code and work with terminals?](https://news.ycombinator.com/item?id=5352608)
- AppleVis — [Announcing TDSR: A Command Line Screen Reader](https://www.applevis.com/blog/announcing-tdsr-command-line-screen-reader-macintosh-gnulinux)
- AppleVis / iAccessibility — [iTerm2 for Mac](https://iaccessibility.net/iterm2-for-mac-a-very-decent-terminal-replacement/)
- fireborn — [I Want to Love Linux. It Doesn't Love Me Back: Speakup, BRLTTY, and the Forgotten Infrastructure of Console Access](https://fireborn.mataroa.blog/blog/i-want-to-love-linux-it-doesnt-love-me-back-post-3-speakup-brltty-and-the-forgotten-infrastructure-of-console-access/)
- Blind Computing — [State of Linux CLI Accessibility](https://blindcomputing.org/linux/state-of-cli-accessibility/)
- luffah — [vim-accessibility plugin](https://github.com/luffah/vim-accessibility)
- xogium — [The text mode lie: why modern TUIs are a nightmare for accessibility](https://xogium.me/the-text-mode-lie-why-modern-tuis-are-a-nightmare-for-accessibility)

### CLI / TUI accessibility guidance

- Seirdy — [Best practices for inclusive CLIs](https://seirdy.one/posts/2022/06/10/cli-best-practices/)
- Pradhan, Mehta & Bigham — [Accessibility of Command Line Interfaces (CHI 2021)](https://dl.acm.org/doi/abs/10.1145/3411764.3445544)
- Sarah Higley — [Escaping 101](https://sarahmhigley.com/writing/escaping-101/)
- Evil Martians — [CLI UX best practices: 3 patterns for progress displays](https://evilmartians.com/chronicles/cli-ux-best-practices-3-patterns-for-improving-progress-displays)
- CSS-Tricks — [Comparing JAWS, NVDA, and VoiceOver (box-drawing announcements)](https://css-tricks.com/comparing-jaws-nvda-and-voiceover/)
- Deque — [Screen Readers: A Guide to Punctuation and Symbols](https://www.deque.com/blog/dont-screen-readers-read-whats-screen-part-1-punctuation-typographic-symbols/)
- WebAIM — [Responsive Design and Reflow](https://webaim.org/techniques/reflow/)

### Env-var conventions

- [no-color.org — NO_COLOR specification](https://no-color.org/)
- [bixense.com — CLICOLOR / CLICOLOR_FORCE convention](http://bixense.com/clicolors/)
- [Python.org — NO_COLOR / FORCE_COLOR precedence discussion](https://discuss.python.org/t/no-color-and-force-color-precedence/107166)
- [r-lib/cli — palettes article](https://cli.r-lib.org/articles/palettes.html)

### Standards and legal

- [Section508.gov — Laws and Policies](https://www.section508.gov/manage/laws-and-policies/)
- [GDS Way — Building accessible services](https://gds-way.digital.cabinet-office.gov.uk/manuals/accessibility.html)
- [bbc/bbc-a11y](https://github.com/bbc/bbc-a11y)
- [Assistiv Labs — Automating Screen Readers for Accessibility Testing](https://assistivlabs.com/articles/automating-screen-readers-for-accessibility-testing)

---

## Changelog

- 2026-05-04: Draft created from research findings on the
  `accessibility-investigation` branch. First version was a thin
  proposal; second version expanded to preserve the full research
  context (per-platform screen reader landscape, peer-framework
  comparison with code, full best-practices checklist with quotes,
  consolidated source bibliography).
- 2026-05-04: Synthesis pass after spawning two sister proposals
  ([`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md) and
  [`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md)). Strategic shape
  expanded from three to four targets to recognize that the embedded
  web host (run-locally, view-in-browser-at-localhost) is a separate
  delivery vehicle from the WASM web target and is the **strongest
  accessibility delivery vehicle** for any compiled SwiftTUI binary
  because it requires no recompile and gives blind users on weak
  terminal-AT platforms (notably macOS) a credible browser-based
  workflow. Added "Relationship to other proposals" section. Renamed
  "What the Web and SwiftUI targets unlock" to "What the non-CLI
  targets unlock" and added an embedded-web-host subsection.
  Updated Q8 to reflect the new architecture. Phasing expanded from
  8 to 9 phases, with explicit cross-proposal dependencies marked.
  Env-var-contract section now cross-references the parsing rules in
  `ARGUMENT_PARSING.md`.
- 2026-05-04: Substrate audit pass. Read
  `Sources/SwiftTUICore/Semantics/Semantics.swift`, `SemanticRoleTypes.swift`,
  `RenderTreeAndSemanticsTypes.swift`, `FocusTracker.swift`, the
  `WASISurfaceBridge` encoder, and the existing env-var detection in
  `TerminalCapabilityProfile.detect`. Findings captured in
  [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) and pushed back into
  this proposal as `Audit correction (2026-05-04)` callouts in
  *What we already have*, *Proposed API surface
  (AccessibilityRole)*, and *Suggested phasing*. Headline updates:
  (a) `PresentationRole` already exists with 20 cases and is
  populated on built-ins — the proposal now extends/renames it
  rather than introducing a parallel `AccessibilityRole`;
  (b) `SemanticExtractor` does not yet propagate role data to
  `SemanticSnapshot` — Phase 3b adds an `accessibilityNodes`
  collection; (c) the `WebSurfaceFrameEncoder` is raster-only — the
  embedded-host ARIA story (Phase 6) requires a wire-format
  extension, not just transport reuse; (d) env-var detection partly
  exists for `NO_COLOR`/`TERM`/`COLORTERM`/`LANG` — Phase 1 now
  *extends* rather than *constructs*. Net effect: earlier phases
  smaller, Phase 6 larger, total scope unchanged.
- 2026-05-04: Two foundational decisions locked in as ADRs.
  [ADR-0011](../decisions/0011-accessibility-role-replaces-presentation-role.md)
  renames `PresentationRole` to `AccessibilityRole` and adds the
  missing ~15 cases — single role channel, single source of truth.
  [ADR-0012](../decisions/0012-accessibility-node-shape.md) locks in
  the `AccessibilityNode` shape: flat array on `SemanticSnapshot`,
  parent encoded via `parentIdentity: Identity?`, focus state
  computed by the consumer (not on the node), pruned to
  a11y-relevant nodes plus structural ancestors, document order =
  layout reading order, cursor anchor on the node in absolute
  surface coordinates. The *Proposed API surface
  (AccessibilityRole)* section updated to drop "rename pending"
  framing; open questions Q2 (role inference) and Q5 (cursor anchor)
  marked resolved with ADR cross-references. Phase 3a and Phase 3b
  no longer carry foundational decisions; they are now pure
  implementation phases.
- 2026-05-04: Merged the `refactor: reorganize source tree to make
  rendering pipeline visible` commit from main. Public modules
  renamed (`Core` → `SwiftTUICore`, `View` → `SwiftTUIViews`,
  `AnimatedImage` → `SwiftTUIAnimatedImage`); `Sources/SwiftTUICore/`
  reorganized into phase-named subdirectories
  (`Pipeline/`, `Resolve/`, `Measure/`, `Place/`, `Semantics/`,
  `Draw/`, `Raster/`, `Commit/`); `Sources/SwiftTUI/` reorganized
  into feature-named subdirectories (`RunLoop/`, `Lifecycle/`,
  `Scenes/`, `Terminal/`, `Input/`); several large files split
  (notably `RenderTreeAndSemanticsTypes` → 4 files, with
  `SemanticMetadata` and `TabItemLabel` now living in
  `Resolve/ResolvedNode.swift`). All file-path and module-name
  references in this proposal, the sister proposals
  (`SUBSTRATE_AUDIT.md`, `EMBEDDED_WEB_HOST.md`,
  `ARGUMENT_PARSING.md`), and ADRs 0011 / 0012 were updated to
  match. Line numbers for citations in the audit (e.g.
  `ValueControls.swift:88`, `TerminalPresentation.swift:84-135`,
  `TerminalHost.swift:1382-1440`) were preserved by the refactor;
  no semantic claims changed. The `TabItemLabel` line range shifted
  from `1-31` to `2-31` due to the file split.
- 2026-05-05: Current-state pass after argument-parsing implementation.
  `RuntimeConfiguration.detect(...)`, `SwiftTUIOptions`, and the
  `SwiftTUIArguments` peer package now parse the env/flag surface;
  color/glyph flags (`--no-color`, `--force-color`, `--ascii`,
  `--plain`) reach rendering. Marked the remaining behavior wiring
  explicitly, noted that ADR-0011/ADR-0012 are accepted but not yet
  implemented in source, and linked the new remaining-work plan
  [`2026-05-05-002-accessibility-remaining-work-plan.md`](../plans/2026-05-05-002-accessibility-remaining-work-plan.md).
- 2026-05-05: Shared accessibility substrate implementation landed.
  Source now uses `AccessibilityRole`, `SemanticMetadata.accessibilityRole`,
  and `accessibilityRole(_:)`; `SemanticMetadata` carries label,
  hint, hidden, and live-region fields; `View` exposes the matching
  authoring modifiers; `SemanticSnapshot` includes sparse
  `accessibilityNodes`. The remaining work is target-specific
  consumption: cursor-as-focus, linear accessible output,
  live-region announcements, embedded-host / WASM ARIA, and SwiftUI
  host bridging.
- 2026-05-06: Web/WASI accessibility consumption landed. The
  `web-surface` encoder emits v2 frames with `accessibilityTree` data,
  the browser runtime mounts ARIA beside the canvas, and the WebExample
  browser smoke test now asserts the details scene exposes an accessible
  button. SwiftUI host bridging was the next platform-target tranche,
  with native policy recorded in
  [ADR-0015](../decisions/0015-accessibility-swiftui-host-policy.md)
  before implementation.
- 2026-05-06: SwiftUI host accessibility consumption landed. Hosted
  sessions can publish semantic snapshots beside raster frames,
  `SwiftUIHostSceneHost` stores the latest snapshot and focused identity,
  and the host mounts a native accessibility overlay with role mapping,
  focus metadata, and live-region announcement handling. At that point, the
  unresolved follow-ups were public cursor-anchor authoring for custom anchors,
  imperative announcements, and listening/lint work.
- 2026-05-06: Text input caret anchoring landed. `TextField`,
  `SecureField`, and `TextEditor` publish real caret anchors into
  accessibility semantics, suppress their synthetic caret when
  `cursorFollowsFocus` is active, and keep secure values redacted.
- 2026-05-06: Public cursor-anchor authoring landed.
  `accessibilityCursorAnchor(_:)` accepts a local `CellPoint` for custom focus
  targets and writes the shared `AccessibilityNode.cursorAnchor` metadata.
- 2026-05-06: Imperative accessibility announcements landed.
  `AccessibilityAnnouncer.announce(_:)` queues
  `SemanticSnapshot.accessibilityAnnouncements` for CLI accessible output,
  Web/WASI ARIA, and SwiftUI host announcements.
- 2026-05-06: Accessibility guardrails landed.
  `Scripts/check_accessibility_guardrails.sh` validates listening-test docs and
  source manifests for raw glyphs, color-state styling, and visual-only content
  call sites.
- 2026-05-06: Visual-only content policy landed. `Canvas`, `Image`, and
  image-backed animated content require author labels or explicit hiding;
  default `SwiftTUICharts` summaries become image labels, while custom
  unlabeled visual charts are skipped in accessible output and reported as
  semantic warnings.
