# Theme-Only Styling Architecture

Last updated: April 6, 2026

Status: landed

## Goal

TerminalUI now treats styling as a theme-only system:

- app authors render semantic roles such as `.foreground`, `.background`,
  `.warning`, and `.tint`
- hosts provide one active semantic `Theme` plus one active `TerminalPalette`
- `TerminalAppearance` remains host metadata and fallback input, not the
  canonical styling surface
- runtime theme changes happen by replacing the active host style object
- the framework does not model built-in display modes or host color-scheme
  selection anywhere in the styling API

## Canonical Model

### `Theme`

`Theme` is the canonical semantic token map used during rendering.

- every token stores a concrete `Color`
- `Theme` is transport-safe and `Codable`
- semantic roles resolve through `Theme` during rendering
- local view styling may still use richer `ShapeStyle` values such as gradients
  or terminal chrome styles, but those richer graphs are not the public theme
  transport format

### `TerminalPalette`

`TerminalPalette` is the canonical host palette for terminal-emulator color
slots.

- it carries the concrete ANSI 16-color palette
- wrapper packages use it to configure embedded terminal widgets
- runtime transport uses it as part of `TerminalAppearance`

### `TerminalAppearance`

`TerminalAppearance` is host facts plus fallback synthesis input.

- it carries foreground, background, tint, ANSI palette, source, and contrast
  metadata
- it can synthesize a default semantic theme through
  `TerminalAppearance.synthesizedTheme()`
- app authors should not treat it as the primary styling API

## Runtime Model

`TerminalRenderStyle` is the runtime style bundle.

- `appearance: TerminalAppearance`
- `theme: Theme?`

The runtime injects both into the environment every frame.

- when `theme` is present, semantic roles resolve from that theme
- when `theme` is absent, the runtime synthesizes one from `appearance`
- hosted sessions, streaming hosts, and browser/WASI bridges all update style
  through the same single-style payload

## Wrapper Model

Wrapper packages now expose one active host style object at a time.

### SwiftUI host

`SwiftUITUITerminalStyle` owns:

- one palette
- one theme
- cursor, font, and background-opacity options

It no longer exposes built-in paired theme variants or host color-scheme routing.

### Web host

`WebTUITerminalStyle` owns:

- one palette
- one theme
- cursor, font, and background-opacity options

It no longer exposes built-in paired theme variants, system color-scheme
 detection, or scheme-switched runtime updates.

Hosts that want multiple themes swap complete style objects themselves.

## Authoring Rules

- TUI apps author against semantic roles and explicit local colors.
- TUI apps do not branch on host theme choice.
- Hosts own theme selection.
- Terminal-native execution keeps a sensible fallback look by synthesizing a
  theme from terminal appearance.
- Automatic chrome resolves from the active theme plus appearance facts rather
  than from discrete mode branches.

## Removed Concepts

The styling stack no longer includes:

- `ThemeColors`
- `ColorScheme`
- `.preferredColorScheme(...)`
- wrapper-level `lightVariant` / `darkVariant`
- wrapper-level `lightTheme` / `darkTheme`
- wrapper-level `lightPalette` / `darkPalette`
- web `colorSchemeMode`
- built-in system color-scheme listeners for choosing TUI theme state

This is a pre-release library, so these were removed directly instead of being
kept as compatibility shims.

## Verification

Required verification for this architecture remains:

```bash
swift test
cd GUI/SwiftUITUIGUI && swift test
cd GUI/WebTUIGUI && bun test
```

Key coverage areas:

- theme resolution falls back to `TerminalAppearance.synthesizedTheme()`
- runtime style transport round-trips a single theme payload
- hosted wrappers update running sessions without any mode argument
- repo guards fail if legacy mode-based styling APIs are reintroduced
