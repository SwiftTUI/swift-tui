# Terminal Native UI Research

This memo synthesizes current terminal UI practice across framework and application ecosystems. The goal is not to imitate any one project, but to identify the highest-value paradigms for a SwiftUI-shaped terminal framework that wants to become genuinely terminal-native.

## Most Influential Paradigms

### 1. MVU remains the strongest runtime model for terminal apps

Bubble Tea still represents the cleanest event-driven mental model: a model holds state, update reacts to messages, and view renders from state. That separation keeps state transitions explicit and makes async work, focus, and re-rendering easier to reason about. Ratatui and Textual converge on a similar separation, even if they expose different APIs.

### 2. Terminal-native UIs are pane- and viewport-first, not page-first

The best terminal apps behave like a workspace, not a scrolling web page. tmux and Zellij make this obvious at the shell level. Yazi, lazygit, and k9s carry the same idea upward into application UX: a few stable panes, strong selection state, and predictable navigation between focused regions.

### 3. Discoverability is part of the UI, not documentation after the fact

Bubble Tea's ecosystem and Textual both emphasize generated help, command palettes, and visible keyboard affordances. In terminal UX, the control model must be self-explanatory because the user cannot hover to discover behavior.

### 4. Components should be composable, stateful, and narrow in responsibility

Ratatui's widget/stateful-widget split, Bubbles' component catalog, and Textual's widget tree all show the same lesson: a good terminal framework needs reusable units for input, tables, lists, viewports, previews, spinners, selection, and confirmation. The component is not the app shell; it is the building block.

### 5. Good terminal styling is semantic and restrained

Lip Gloss is useful evidence, but its best lesson is not decoration. It is that style should be value-based, composable, and capability-aware. The most convincing terminal apps use background, border, and accent as signals, not as default decoration everywhere.

## Notable Framework-Specific Ideas

### Bubble Tea / Bubbles / Lip Gloss

- Bubble Tea's MVU architecture is the canonical reference for terminal app runtime.
- Bubbles is strongest when it provides narrowly scoped, reusable components: text input, textarea, viewport, list, table, file picker, spinner, progress, paginator, help, timer, and stopwatch.
- Help generation is a major UX feature, not a nicety.
- Lip Gloss shows that style must be value-based and mergeable, with borders, padding, margins, width, alignment, and profile-aware color handling.

### Ratatui

- Ratatui's widget and stateful-widget traits are a strong signal for how to structure reusable terminal components.
- Layout is rectangle-first and nested; screen space is explicitly divided into areas before widgets are rendered.
- The builder-lite pattern is a subtle but important lesson: component configuration should be fluent, immutable, and readable.

### Textual

- Textual shows the value of a rich widget catalog, flexible layout, and a strong command palette.
- It treats async as a first-class runtime concern without forcing every app to think in async-first terms.
- Its dev console and browser runtime are notable because they improve observability and sharing, which are often missing in terminal app frameworks.

### Zellij / tmux / Neovim

- Zellij is the strongest current example of terminal-native workspace design: tabs, panes, layouts, plugins, session persistence, and built-in discovery surfaces.
- tmux remains the reference for session, pane, and key-table thinking, especially help access and structured key binding.
- Neovim is still the best exemplar of modal navigation, split windows, command-line entry, and fast keyboard-oriented command discovery.

### FZF / Lazygit / Yazi / K9s

- fzf is the canonical selection primitive: type-to-filter, keyboard-first navigation, preview integration, and strong default keybindings.
- lazygit is one of the best examples of a list-detail workflow that stays fast and legible under heavy keyboard use.
- Yazi demonstrates what a modern file manager should feel like: multi-tab, preview-centric, async, and pluginable.
- K9s shows the power of resource-centric dashboards, watch-driven updates, and log/detail panes for operational work.

## Anti-Patterns

- Treating the terminal like a browser and building page-like scroll experiences as the default.
- Making borders, gradients, and filled cards the baseline visual language instead of accents.
- Hiding keybindings or requiring the user to discover them externally.
- Splitting app state and render state too loosely, which makes focus and async work hard to reason about.
- Overusing fixed-width islands that do not adapt to the full terminal canvas.
- Copying GUI metaphors literally when the terminal has stronger native idioms such as panes, command palettes, and mode-aware navigation.
- Adding decorative widgets before the core navigation and selection model is good.

## What "Terminal Native" Actually Means

The strongest terminal-native apps do a few things consistently:

- They assume the terminal background is the canvas, not a canvas to paint over.
- They use panels only when panels encode meaning.
- They reserve borders and accent fills for emphasis, not default decoration.
- They keep keyboard navigation obvious and close to the surface.
- They make selection, focus, and mode explicit.
- They treat panes, tabs, preview areas, and session persistence as first-class UX.
- They degrade gracefully across terminal capabilities without collapsing their layout model.

This is the standard SwiftTUI should chase when it reinterprets SwiftUI APIs for a terminal domain.

## Implications for SwiftTUI

- Reinterpret SwiftUI shapes only where the terminal has a clearer native meaning, not where GUI wording happens to be familiar.
- Prefer full-screen, pane-based app shells over stacked card layouts in defaults and demos.
- Add first-class `TextEditor`, command/help surfaces, and stronger split/tab abstractions before adding more decorative components.
- Treat focus and selection as the primary visual system, with styling as a secondary signal.
- Keep `ScrollView` as a pane primitive, not a default whole-page pattern.
- Make component APIs biased toward selection, preview, discoverability, and keyboard movement.
- Avoid turning SwiftTUI into a theme wrapper around GUI metaphors; it should feel like the terminal's own native language.

## Sources

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - canonical MVU runtime and command/message model.
- [Bubbles](https://github.com/charmbracelet/bubbles) - component catalog with textarea, viewport, list, table, help, file picker, spinner, and progress.
- [Lip Gloss](https://github.com/charmbracelet/lipgloss) - style composition, border, padding, margin, width, alignment, and color-profile-aware terminal styling.
- [Ratatui](https://github.com/ratatui/ratatui) - widget/stateful-widget model and rectangle-based layout composition.
- [Ratatui Widgets](https://ratatui.rs/concepts/widgets/) - widget traits and rendering model.
- [Textual](https://github.com/Textualize/textual) - async widget-based framework with themes, dev console, and command palette.
- [Zellij](https://github.com/zellij-org/zellij) - terminal workspace model with panes, tabs, layouts, plugins, and session-oriented UX.
- [Zellij Layouts](https://zellij.dev/documentation/layouts.html) - layout file model for pane/tab arrangement.
- [Neovim](https://github.com/neovim/neovim) - modal, split-oriented, extensible editor with strong terminal-native navigation patterns.
- [fzf](https://github.com/junegunn/fzf) - selection-first interaction model with filtering, preview, and keyboard discoverability.
- [Lazygit](https://github.com/jesseduffield/lazygit) - list-detail git workflow with strong keybinding ergonomics and action visibility.
- [Yazi](https://github.com/sxyazi/yazi) - async file manager with tabs, previews, plugins, and session-like state.
- [K9s](https://github.com/derailed/k9s) - resource-centric operational dashboard with live navigation and log/detail panes.

