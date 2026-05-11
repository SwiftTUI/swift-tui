# Examples

This directory keeps the maintained example apps and package shells.

- `gallery`: the primary terminal-native demo package and regression sandbox for the supported `View` surface
- `gifcat`: a tiny terminal-native GIF player that tiles command-line GIFs in argument order
- `gifeditor`: a frame-by-frame TUI GIF editor — pixel canvas, layers, timeline, pen/eraser/fill/gradient/marquee tools, and a vendored GIF89a encoder. This is the maintained Canvas example surface; read its [README](gifeditor/README.md) for keybindings and known framework gaps.
- `layouts`: a focused workbench of layout examples driven full-screen from a CLI runner
- `SwiftUIExample`: a host app plus terminal package that demonstrates embedding SwiftTUI scenes in SwiftUI via the root `SwiftUIHost` product (native surface)
- `WebExample`: a host app plus terminal package that demonstrates the Bun + WASI browser path used by `Platforms/Web`
