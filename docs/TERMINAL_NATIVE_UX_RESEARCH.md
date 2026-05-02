# Terminal Native UX Research

This memo gathers terminal-native UI paradigms from tmux, Zellij, GNU Screen, Neovim, Helix, Kakoune, WezTerm, Yazi, and Lazygit. The goal is not to copy any one project, but to identify the attainable best in navigation, workspace structure, discoverability, and keyboard-first UX for a SwiftUI-shaped TUI framework.

## Most Influential Paradigms

- `tmux` is the baseline for session persistence and workspace hierarchy. Its core model is still hard to beat: session -> window -> pane, with a status line, copy mode, command prompt, tree-style selection, and format-driven presentation.
- `Zellij` is the strongest modern example of terminal-native app chrome. It treats layouts as first-class, supports tabs, stacked and floating panes, command panes, a session manager, and built-in visual affordances that keep the workspace readable.
- `WezTerm` adds a modern workspace and command-discovery model. Its workspaces, multiplexer, right status area, command palette, quick select, and launcher are excellent examples of making navigation discoverable without sacrificing keyboard speed.
- `Helix` shows how a minimal terminal app can stay highly navigable. Its mode-aware statusline, selection-first editing model, popup borders, inline diagnostics, and smart-tab behavior are all useful signals for terminal-native interaction design.
- `Kakoune` is the cleanest statement of selection-first terminal UX. Its separation of selection, insertion, and command intent still feels unusually modern, and its client-server architecture is a useful reminder that terminal-native UIs can treat interaction state as a durable session, not just a transient input loop.
- `Neovim` is still a foundational reference for split/window semantics and statusline behavior. It is less a visual model than an interaction grammar: windows, tabs, commands, and status surfaces all operate as a coherent keyboard language.
- `Yazi` and `Lazygit` are the best examples of app-layer terminal UX polish. They show how previews, multi-pane layouts, key hints, action menus, and task-specific workflows can feel dense without becoming confusing.
- `GNU Screen` still matters as a historical baseline for detach/reattach and multiuser use, but it is mostly useful as a reminder of what feels dated rather than a model to emulate closely.

## Notable Project-Specific Ideas

- Make the top-level app feel like a workspace, not a document. The best terminal UIs present a persistent shell, mode, or workspace bar and then fill the rest of the screen with task-specific panes.
- Treat tabs, panes, and workspaces as explicit navigation entities. Zellij and WezTerm both show that users understand and value this distinction when it is visible and searchable.
- Make command discovery visible in the UI. Command palettes, key hint bars, and inline action overlays are stronger than hidden keymaps for terminal-native apps.
- Prefer full-width surfaces and pane-based composition over nested card stacks. Terminal apps are easier to understand when the screen has one obvious active region and one obvious context bar.
- Use selection, focus, and cursor state as first-class visual channels. Helix and Neovim both show that mode/state is part of the interface, not a hidden implementation detail.
- Provide a lightweight way to search and switch context. The best patterns here are fuzzy workspace switching, quick select, and searchable action menus.
- Treat scrollback and preview as part of the workspace, not as an afterthought. Yazi, Zellij, and WezTerm all make it clear that browsing output, previews, and logs are core terminal workflows.

## Anti-Patterns

- Decorative borders and gradients as default chrome. They quickly make a terminal app feel pasted on instead of native.
- Root-level scrollable pages. Terminal apps usually feel better as full-screen shells with internal viewports or panes.
- Fixed-width islands scattered across the screen. That fragments attention and wastes the strongest property of a terminal: the whole width of the canvas.
- Hidden mode changes and hidden bindings. Discoverability matters more in terminal UIs than in many desktop apps because keyboard state is easy to lose track of.
- Color-only state changes. The better projects combine color with labels, cursor shape, separators, status text, and motion.
- GNU Screen-style minimalism when it reduces legibility. Screen is valuable historically, but its UX conventions are not what users now praise as best in class.

## Source Notes

- tmux manual, sessions/windows/panes and status line: [tmux(1)](https://man7.org/linux/man-pages/man1/tmux.1.html)
- tmux format-driven status, choose-tree, and command prompt behavior: [Formats wiki](https://github.com/tmux/tmux/wiki/Formats)
- Zellij layouts, tabs, session management, and scrollback editing: [Features](https://zellij.dev/features/)
- Zellij layout templates and floating/command pane composition: [Creating a Layout](https://zellij.dev/documentation/creating-a-layout.html)
- WezTerm multiplexer and workspace model: [wezterm.mux](https://wezterm.org/config/lua/wezterm.mux/index.html)
- WezTerm command palette and workspace switching: [ActivateCommandPalette](https://wezterm.org/config/lua/keyassignment/ActivateCommandPalette.html), [SwitchToWorkspace](https://wezterm.org/config/lua/keyassignment/SwitchToWorkspace.html)
- Helix statusline, popup borders, smart-tab, and diagnostics configuration: [Editor docs](https://docs.helix-editor.com/editor.html)
- Kakoune selection model and philosophy: [Kakoune README](https://github.com/mawww/kakoune)
- Neovim splits, tabs, and statusline behavior: [windows.txt](https://neo.vimhelp.org/windows.txt.html)
- Yazi multi-tab, preview, and plugin-driven workflow: [Yazi README](https://github.com/sxyazi/yazi)
- Lazygit panel-driven git workflows and keybinding discoverability: [Lazygit README](https://github.com/jesseduffield/lazygit)

## Implications For SwiftTUI

- SwiftTUI should reinterpret SwiftUI APIs as terminal-native workspace primitives, not desktop cards translated into monospace.
- The likely long-term direction is a screen-wide shell with visible mode, workspace, and help surfaces, plus pane-based internal navigation.
- If a component does not improve keyboard discoverability, workspace clarity, or state visibility, it probably belongs as an opt-in style rather than a default.
- `tmux`, `Zellij`, `WezTerm`, `Helix`, `Kakoune`, `Neovim`, `Yazi`, and `Lazygit` together suggest a strong terminal-native baseline: visible state, searchable actions, explicit workspaces, dense but legible panels, and very little decorative chrome.
