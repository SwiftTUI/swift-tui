 Highest-Leverage Next Steps for TerminalUI

  TerminalUI is already remarkably complete — it has TextField, TextEditor, List, Table, OutlineGroup, TabView,
  NavigationSplitView, ScrollView, ProgressView, Picker, Menu, Button, Toggle, focus system, charts, and
  multi-scene support. That puts it ahead of every TUI framework except Textual in breadth. The recommendations
  below focus on what would close the gap between "strong framework" and "apps built on it feel as polished as
  lazygit or k9s."

  Tier 1: Compound-Return Architectural Investments

  These aren't components — they're the connective tissue that makes every component better.

  1. Modal / Sheet Presentation with Focus Trapping
  - Every serious TUI app needs overlays: confirmations, detail panels, error dialogs. Ratatui's lack of this is
   its biggest pain point. Textual's Screen push/pop stack is the gold standard.
  - TerminalUI already has the focus system and ZStack to build this. The missing piece is a .sheet() / .alert()
   / .confirmationDialog() modifier that manages focus trapping and dismiss-on-escape automatically.
  - This unlocks: confirmation workflows, error boundaries, detail inspections, wizards.

  2. Keybinding Registry with Auto-Generated Help
  - Bubble Tea's single most praised UX pattern is the Help bubble that auto-generates from registered
  keybindings. Every terminal app that feels discoverable does this.
  - PrototypeUIComponents already has help-strip and command-palette experiments. Graduating a
  keybinding-to-help pipeline to first-class status would be the highest-leverage discoverability win.
  - The SwiftUI shape: .keyboardShortcut() modifier paired with a HelpView that reads registered shortcuts from
  the environment.

  3. Command Palette
  - Only Textual ships this built-in (ctrl+p fuzzy search over actions). It's become table stakes for dev tools
  since VS Code normalized it. The prototype exists; promoting it with fuzzy matching over registered actions
  would differentiate TerminalUI from every other TUI framework except Textual.

  Tier 2: Components That Separate Demos from Real Apps

  4. Toast / Transient Notification System
  - Timed, auto-dismissing status messages (success, error, info). Textual has this. No other framework does.
  It's the difference between "operation succeeded" as a log line vs. a polished UX moment.
  - SwiftUI shape: an environment-injected action like @Environment(\.showToast).

  5. Markdown Rendering View
  - With AI tools dominating TUI usage (Claude Code, Gemini CLI, OpenCode all use terminal UIs), rendering
  markdown inline is increasingly critical. OpenTUI and Textual both ship this.
  - SwiftUI shape: Markdown("# Hello") view that handles headings, code blocks, lists, bold/italic, and links.

  6. RichLog / Append-Only Log View
  - Textual's RichLog is a scrollable, append-only output pane — the natural fit for build output, chat
  messages, streaming AI responses, and operational logs.
  - Different from ScrollView+Text because it needs: auto-scroll-to-bottom, conditional scroll lock (don't
  scroll if user scrolled up), and efficient append without re-rendering everything.

  7. Diff View
  - Only OpenTUI has this. Essential for git tools, code review, and AI-assisted coding UIs. Side-by-side or
  unified format with line-number gutters and add/remove highlighting.

  Tier 3: Polish and Completeness

  8. Spinner / Activity Indicator Styles
  - ProgressView covers indeterminate progress, but the Bubble Tea ecosystem shows that spinner frame variety
  (dots, braille, line, bounce, etc.) is a cheap way to make apps feel alive. A SpinnerStyle protocol with
  preset frame sequences.

  9. Animated Transitions
  - Harmonica (Charm's animation library) and Textual's CSS transitions show that even subtle motion — fade,
  slide, expand — makes TUI apps feel dramatically more polished. This is hard to do well but has outsized
  perceptual impact.

  10. Focus-Aware Styling (:focused equivalent)
  - Textual's CSS :focused pseudo-class means any widget automatically changes appearance when focused.
  TerminalUI's style system could benefit from a .focused { } environment-driven style variant that containers
  apply automatically.

  Tier 4: Deferred but Watching

  11. NavigationStack — The vision doc correctly defers this. The terminal-native navigation model (panes + tabs
   + modals) doesn't map cleanly to iOS push/pop. Keep watching for the right terminal shape.

  12. Syntax-Highlighted Code View — High value for dev tools but depends on a highlighting engine. Could wrap
  tree-sitter or a simpler regex-based highlighter.

  13. File Picker — Bubble Tea ships one. Useful but niche; most apps that need file selection are better served
   by a filtered List over directory contents using OutlineGroup.

  Summary Priority Matrix

  ┌──────────┬──────────────────────────────┬────────┬──────────┬───────────────────────────────────────────┐
  │ Priority │             Item             │ Effort │  Impact  │                  Why Now                  │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 1        │ Modal/Sheet + focus trapping │ Medium │ Very     │ Unlocks every confirmation/detail/error   │
  │          │                              │        │ High     │ workflow                                  │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 2        │ Keybinding registry + Help   │ Medium │ Very     │ #1 discoverability pattern across all     │
  │          │ view                         │        │ High     │ frameworks                                │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 3        │ Command Palette              │ Medium │ High     │ Prototype exists; only Textual has this   │
  │          │                              │        │          │ built-in                                  │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 4        │ Toast/Notification           │ Low    │ High     │ Small surface, big UX payoff              │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 5        │ Markdown view                │ Medium │ High     │ AI tool era demands this                  │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 6        │ RichLog (append-only scroll) │ Medium │ High     │ Critical for streaming/operational UIs    │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 7        │ Diff view                    │ Medium │ Medium   │ Dev tool differentiator                   │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 8        │ Spinner styles               │ Low    │ Medium   │ Cheap polish                              │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 9        │ Transitions/animation        │ High   │ Medium   │ Perceptual quality leap                   │
  ├──────────┼──────────────────────────────┼────────┼──────────┼───────────────────────────────────────────┤
  │ 10       │ Focus-aware styling          │ Medium │ Medium   │ Reduces boilerplate in every app          │
  └──────────┴──────────────────────────────┴────────┴──────────┴───────────────────────────────────────────┘