# Terminal Native Doctrine

This document is the canonical synthesis of our current terminal-UX research.
It exists to guide a deliberate reinterpretation of SwiftUI APIs into
terminal-native behavior for TerminalUI.

The project goal is still the one described in [VISION.md](VISION.md): a
faithful and idiomatic, but not API-exact, SwiftUI subset that is genuinely
useful for TUIs. This document sharpens the "not API-exact" part. When the
terminal ecosystem has a clearly better answer than desktop GUI convention, we
should prefer the terminal answer.

## Why This Matters

The best terminal software does not feel like a tiny GUI rendered in monospace.
It feels like a workspace:

- full-screen
- mode-aware
- keyboard-first
- pane-oriented
- selection-driven
- preview-rich
- help-forward
- restrained in its chrome

That is the standard we should target when we reinterpret SwiftUI concepts for
the terminal domain.

## Ecosystem Signal

The projects below are not all trying to solve the same problem, but together
they are the highest-signal references for terminal-native UX today.

GitHub stars are a rough popularity signal, not a quality score. They were
captured from GitHub repository metadata on March 29, 2026.

| Project | Stars | Why It Matters |
| --- | ---: | --- |
| [Neovim](https://github.com/neovim/neovim) | 97.6k | Modal interaction grammar, splits, command entry, status surfaces |
| [fzf](https://github.com/junegunn/fzf) | 79.1k | The canonical filter-select-preview loop |
| [Lazygit](https://github.com/jesseduffield/lazygit) | 75.2k | Best-in-class action-centric git workflow |
| [tmux](https://github.com/tmux/tmux) | 43.7k | Session, window, pane, and status-line baseline |
| [Helix](https://github.com/helix-editor/helix) | 43.7k | Selection-first editing, mode visibility, compact status UX |
| [Bubble Tea](https://github.com/charmbracelet/bubbletea) | 41.0k | Strong runtime model and app architecture |
| [Yazi](https://github.com/sxyazi/yazi) | 35.6k | Modern file-manager UX with preview, tabs, and async polish |
| [Textual](https://github.com/Textualize/textual) | 35.1k | Rich widget catalog, command palette, and app-shell ambition |
| [K9s](https://github.com/derailed/k9s) | 33.2k | Dense operational navigation with live status and discoverability |
| [btop](https://github.com/aristocratos/btop) | 31.3k | High-density dashboards and live monitoring surfaces |
| [Zellij](https://github.com/zellij-org/zellij) | 30.7k | Best modern multiplexer-style workspace UX |
| [WezTerm](https://github.com/wezterm/wezterm) | 25.2k | Modern workspace, launcher, command palette, and mux model |
| [Glow](https://github.com/charmbracelet/glow) | 24.0k | Reader/pager UX and background-aware styling restraint |
| [Ratatui](https://github.com/ratatui/ratatui) | 19.4k | Strong widget/state model and rectangle-first layout thinking |
| [bottom](https://github.com/ClementTsang/bottom) | 13.1k | Configurable dashboard navigation and compact graph-heavy views |
| [Kakoune](https://github.com/mawww/kakoune) | 10.8k | The clearest expression of selection-first editing |

Historical note:

- GNU Screen still matters as an origin point for detach/reattach and
  multi-session terminal thinking, but it is more useful as a baseline than as
  a present-day visual or UX north star.

## The Attainable Best

Across multiplexers, editors, operational tools, and TUI frameworks, the best
terminal UX converges on a small set of principles.

### 1. Workspace First, Not Page First

The terminal wants to be a workspace, not a document.

The strongest apps claim the full screen and divide it into stable regions:

- a title or context bar
- one or more active panes
- a preview, detail, or inspector region
- a status or help bar

This is the common thread across tmux, Zellij, WezTerm, Neovim, Yazi, Lazygit,
and K9s. The app is a shell for work, not a stack of independently decorated
boxes.

### 2. The Core Interaction Loop Is Select, Preview, Act, Confirm, Stay Oriented

`fzf` makes the primitive obvious:

- select from a list
- preview the consequence or the content
- invoke an action
- confirm only when necessary
- remain anchored in place

This loop shows up everywhere:

- files with preview in Yazi
- commits, hunks, and diffs in Lazygit and GitUI
- pods, logs, and resource detail in K9s
- windows, buffers, and commands in editors

Selection is not a side effect. It is the primary navigation model.

### 3. Focus, Mode, and Scope Must Always Be Visible

The best TUIs make it obvious:

- which pane is active
- which list row or item is selected
- which mode the user is in
- which command surface is listening
- which scope an action will affect

This is where editors are especially instructive. Neovim, Helix, and Kakoune
all treat mode as part of the interface, not hidden state. Zellij and WezTerm
do the same for panes, tabs, sessions, and workspaces.

### 4. Discoverability Is Part Of The Interface

In terminal software, help is not optional polish.

The strongest examples keep help close to the work:

- a bottom key-hint bar
- a `?` help overlay
- an inline action legend
- a command palette
- searchable commands and workspace switching

Bubble Tea's `help` model, WezTerm's command palette, K9s aliases and hotkeys,
and Lazygit's contextual legends all point the same direction. A great TUI
teaches itself while it is being used.

### 5. Panes, Tabs, and Workspaces Are Native Navigation Primitives

Desktop GUI conventions over-index on windows, sheets, and cards. Terminal UX
works better with:

- panes
- splits
- tabs
- sessions
- workspaces
- command prompts
- transient overlays

That does not mean TerminalUI should copy tmux APIs. It does mean SwiftUI
concepts like `NavigationSplitView`, `TabView`, dialogs, and command surfaces
should be reinterpreted in a way that respects terminal-native navigation.

### 6. Full-Width Ownership Beats Floating Islands

The best TUIs use the whole canvas.

They avoid:

- narrow centered cards
- unused horizontal space
- stacks of small framed boxes
- fixed-width islands scattered across the terminal

Terminal screens are shallow in height and precious in width. Great apps own
that width and use it to preserve context, preview information, and multi-pane
navigation.

### 7. Scrolling Is Usually Pane-Local, Not Page-Level

Root-page scroll is usually the wrong mental model for a TUI.

What users expect instead is:

- a list that scrolls
- a log pane that scrolls
- a preview that scrolls
- a document viewer that scrolls
- a table or tree that scrolls

The shell itself usually stays put. Bubble Tea's viewport, Ratatui's rect-based
composition, Glow's reader flow, Yazi's preview panes, and K9s' operational
surfaces all reinforce this pattern.

### 8. Async State Belongs In The UI

Terminal apps often deal with long-running, remote, or watch-driven work.

The best TUIs make that explicit:

- loading states
- indeterminate progress
- refresh timestamps
- connected or disconnected state
- empty states
- transient notifications
- task progress

K9s, btop, bottom, WezTerm, and editor LSP surfaces all show that users trust
the app more when the runtime state is visible.

### 9. Defaults Should Be Restrained

The terminal background is usually the canvas.

The best apps use:

- little or no default fill
- borders only where they clarify structure
- accent colors for focus, selection, or one primary action
- status lines and separators more than decorative cards
- text weight, inversion, or rails before ornamental border effects

This is where Lip Gloss is often misunderstood. Its strongest lesson is not
"use more decoration." Its strongest lesson is "make styling composable and
semantic, then apply it deliberately."

### 10. Domain-Native Navigation Beats Generic Navigation

The best TUI apps are opinionated about how their domain is explored.

Examples:

- Lazygit navigates branches, commits, hunks, stashes, and rebases
- K9s navigates clusters, namespaces, resources, logs, and events
- Yazi navigates directories, previews, tabs, and selections
- editors navigate selections, buffers, splits, jumps, and commands

This matters for TerminalUI because "SwiftUI-shaped" should not mean
"domain-neutral to a fault." We should allow terminal-native workflows to read
cleanly in the API surface.

## What Each Reference Family Teaches

### Multiplexers And Terminal Shells

Key references:

- tmux
- Zellij
- WezTerm
- GNU Screen

What they teach:

- screen-wide shell ownership
- session persistence
- visible pane and tab hierarchy
- status bars that do real work
- quick switching between contexts
- command launchers and workspaces

What to emulate:

- stable shell structure
- clear active-pane indication
- searchable context switching
- persistent workspace mental model

What not to emulate literally:

- prefix-heavy discoverability debt
- cryptic status surfaces
- overly modal command entry with poor guidance

### Editors

Key references:

- Neovim
- Helix
- Kakoune

What they teach:

- selection-first interaction
- mode visibility
- split and tab semantics
- command-line and palette-style entry
- status lines as a navigational aid
- dense but legible information layout

What to emulate:

- mode as visible state
- strong split behavior
- compact status and help surfaces
- efficient jump and search patterns

What not to emulate literally:

- editor-specific jargon outside editor-like components
- interaction complexity without equivalent payoff

### High-Polish Task Apps

Key references:

- Lazygit
- Yazi
- K9s
- GitUI
- Glow
- btop
- bottom
- fzf

What they teach:

- list-detail-preview workflows
- contextual key hints
- domain-specific actions near the selection
- dense layouts that still preserve orientation
- pane-local scroll rather than whole-app scroll
- visible async status and refresh behavior

What to emulate:

- selection plus preview as the default pattern
- help bars and `?` overlays
- action-led workflows
- minimal confirmation friction

What not to emulate literally:

- domain-specific commands in the framework core
- dashboards as the default for every app

### Frameworks

Key references:

- Bubble Tea
- Bubbles
- Lip Gloss
- Ratatui
- Textual

What they teach:

- composable runtime and component models
- help and command discovery as core UX
- reusable viewports, lists, tables, text inputs, and spinners
- layout as explicit structure, not accidental stacking
- semantic styling instead of raw ANSI soup

What to emulate:

- narrow, reusable components
- strong internal runtime separation
- command/help surfaces
- scrollable pane primitives
- component state that is explicit and testable

What not to emulate literally:

- framework-shaped APIs that drift too far from SwiftUI unless the terminal
  value is overwhelming

## Anti-Patterns To Avoid

The research is unusually consistent about what makes a TUI feel wrong.

- Card-stack composition as a default app aesthetic
- Root-level document scrolling
- Background fills that fight the host terminal background
- Decorative gradients and ornamental borders as baseline chrome
- Fixed-width islands that waste horizontal space
- Hidden keybindings and hidden mode changes
- Color-only distinction for important state
- Generic navigation that ignores the domain's real workflow
- Framework features that privilege decoration over orientation
- Mouse-first assumptions in keyboard-first environments

## What This Means For TerminalUI

### Reinterpretation Rule

When SwiftUI and terminal-native practice disagree, keep the SwiftUI shape only
if it still produces terminal-native behavior.

If not, reinterpret.

That means:

- keep the public story recognizably SwiftUI
- prefer terminal-native defaults
- document deliberate deviations
- do not preserve GUI assumptions that degrade terminal UX

### Default App Shape

Our default examples and default component behavior should bias toward:

- a full-screen shell
- one primary active region
- optional side panes or detail panes
- pane-local scrolling
- visible focus and selection
- persistent status or help affordances
- restrained chrome

### Style Doctrine

Default styling should assume:

- the terminal background is the real background
- focus is more important than decoration
- selection is more important than ornament
- fill is for emphasis, not for every container
- borders are structural, not decorative
- gradients are opt-in, not the baseline
- high contrast in light and dark mode is non-negotiable

### API And Component Priorities

The highest-value additions or reinterpretations now look like:

- `TextEditor` for real multiline work
- `TabView` as a first-class terminal mode switcher
- stronger split-view and workspace composition
- help and keybinding surfaces
- command palette or searchable action surfaces
- indeterminate progress and live-status feedback
- alerts and confirmation flows that feel terminal-native

These are more important than adding more decorative styles or more boxed
container variants.

### Demo And Documentation Priorities

Our demos should stop looking like scrolled showcase pages.

They should instead demonstrate:

- shell-level composition
- pane-based navigation
- preview workflows
- compact status and help surfaces
- full-width ownership
- restrained color and chrome

## Success Criteria

We should consider the terminal-native reinterpretation successful when a new
app built with TerminalUI looks and behaves like it belongs in the same family
as the best modern terminal software.

In practice that means:

- it feels at home next to tmux, Zellij, WezTerm, Neovim, Yazi, and Lazygit
- it is self-discoverable from the keyboard
- it uses the full terminal thoughtfully
- it treats selection, focus, and mode as first-class
- it does not look like a web page trapped in a terminal

## Source Index

### Core references

- [Bubble Tea](https://github.com/charmbracelet/bubbletea)
- [Bubbles](https://github.com/charmbracelet/bubbles)
- [Lip Gloss](https://github.com/charmbracelet/lipgloss)
- [Ratatui](https://github.com/ratatui/ratatui)
- [Ratatui Widgets](https://ratatui.rs/concepts/widgets/)
- [Textual](https://github.com/Textualize/textual)

### Workspace and shell references

- [tmux](https://github.com/tmux/tmux)
- [tmux formats and status model](https://github.com/tmux/tmux/wiki/Formats)
- [tmux manual](https://man7.org/linux/man-pages/man1/tmux.1.html)
- [Zellij](https://github.com/zellij-org/zellij)
- [Zellij layouts and features](https://zellij.dev/documentation/layouts.html)
- [WezTerm mux and workspaces](https://wezterm.org/config/lua/wezterm.mux/index.html)
- [WezTerm command palette](https://wezterm.org/config/lua/keyassignment/ActivateCommandPalette.html)

### Editor references

- [Neovim](https://github.com/neovim/neovim)
- [Neovim window and split behavior](https://neo.vimhelp.org/windows.txt.html)
- [Helix editor docs](https://docs.helix-editor.com/editor.html)
- [Kakoune](https://github.com/mawww/kakoune)

### High-polish application references

- [fzf](https://github.com/junegunn/fzf)
- [Lazygit](https://github.com/jesseduffield/lazygit)
- [Yazi](https://github.com/sxyazi/yazi)
- [K9s](https://github.com/derailed/k9s)
- [GitUI](https://github.com/gitui-org/gitui)
- [Glow](https://github.com/charmbracelet/glow)
- [btop](https://github.com/aristocratos/btop)
- [bottom](https://github.com/ClementTsang/bottom)

## Working Notes

The earlier memos remain available as supporting notes:

- [TERMINAL_NATIVE_UI_RESEARCH.md](TERMINAL_NATIVE_UI_RESEARCH.md)
- [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md)
