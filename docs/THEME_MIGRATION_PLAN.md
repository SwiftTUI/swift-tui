# Theme Migration Plan

Last updated: April 1, 2026

Status: landed in the root runtime plus the SwiftUI and web wrapper packages.

## Goal

Move TerminalUI from an appearance-driven light/dark styling model to a
theme-first model where:

- semantic tokens such as `.foreground`, `.background`, `.warning`, and
  `.tint` resolve through an active `Theme`
- the wrapping host application owns that active theme
- the inner TUI app continues to author only against semantic tokens and does
  not branch on theme choice
- terminal-native execution still gets a default theme that matches the
  detected terminal colors
- hosted wrappers on SwiftUI and web can bind host light/dark mode to
  host-defined theme variants
- themes can switch at runtime without rebuilding the app
- direct hex color authoring is ergonomic and first-class

## Non-Negotiable Decisions

1. `Theme` is host-owned render configuration, not app-authored UI state.
2. TUI apps should not need to know which theme is active.
3. `TerminalAppearance` remains valuable, but as host metadata and terminal
   palette state rather than the canonical semantic styling source.
4. The framework must preserve the current default terminal look when no host
   theme is supplied.
5. Wrapper packages own the mapping from host light/dark mode to explicit theme
   variants.

## Current State

Today the repository already has:

- semantic roles in [Styling.swift](../Sources/Core/Styling.swift)
- a public `Theme` type in [Styling.swift](../Sources/Core/Styling.swift)
- terminal appearance detection and synthesis in
  [Appearance.swift](../Sources/Core/Appearance.swift)
- runtime appearance updates in
  [StreamingTerminalHost.swift](../Sources/TerminalUI/StreamingTerminalHost.swift)
  and
  [HostedSceneSession.swift](../Sources/TerminalUIScenes/HostedSceneSession.swift)
- SwiftUI and web wrapper style layers in
  [GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUITerminalStyle.swift](../GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUITerminalStyle.swift)
  and
  [GUI/WebTUIGUI/src/WebTUITerminalStyle.ts](../GUI/WebTUIGUI/src/WebTUITerminalStyle.ts)

The main mismatch is that semantic roles and terminal chrome are still partly
derived from `TerminalAppearance` and `ColorScheme`, which makes theme
selection feel like GUI light/dark mode instead of a host-controlled terminal
theme.

## Target Architecture

### Core Model

- `Theme` becomes the canonical semantic token map used during rendering.
- `TerminalAppearance` keeps:
  - foreground/background/tint colors
  - terminal palette
  - contrast and inferred scheme metadata
  - host inspection data for wrappers, demos, and diagnostics
- when the host does not supply a theme, the framework synthesizes one from
  `TerminalAppearance`

### Runtime Model

- terminal hosts carry both:
  - `TerminalAppearance`
  - optional host-supplied theme state
- `RunLoop` injects both values into resolve/raster state every frame
- hosted sessions can update appearance and theme together at runtime
- the WASI/browser control-message path can do the same

### Wrapper Model

- wrappers define explicit theme variants
- wrappers map host light/dark mode to those variants
- wrappers send both:
  - terminal-emulator palette settings
  - TerminalUI semantic theme settings

## Migration Phases

### Phase 1: Core Theme Ownership

Primary files:

- [Styling.swift](../Sources/Core/Styling.swift)
- [Appearance.swift](../Sources/Core/Appearance.swift)
- [TerminalChromeStyle.swift](../Sources/Core/TerminalChromeStyle.swift)
- [Rasterizer.swift](../Sources/Core/Rasterizer.swift)
- [Environment.swift](../Sources/View/Environment/Environment.swift)
- [StyleEnvironment.swift](../Sources/View/Environment/StyleEnvironment.swift)

Changes:

- add explicit active-theme state to the style environment snapshot
- resolve semantic roles from the active theme first
- keep `TerminalAppearance.semanticTheme()` as the default-theme fallback path
- remove the current dependency on `.preferredColorScheme(...)` for choosing
  semantic token values
- make terminal chrome styles such as `.terminalAccent(...)`,
  `.terminalSurface(...)`, and `.terminalBorder(...)` derive from the active
  theme rather than from hard-coded light/dark color branches

Expected result:

- semantic token styling and terminal chrome agree on the active theme
- theme selection is no longer equivalent to “pretend the app is in light or
  dark mode”

### Phase 2: Runtime Theme Updates

Primary files:

- [TerminalHost.swift](../Sources/TerminalUI/TerminalHost.swift)
- [StreamingTerminalHost.swift](../Sources/TerminalUI/StreamingTerminalHost.swift)
- [HostedSceneSession.swift](../Sources/TerminalUIScenes/HostedSceneSession.swift)
- [SceneSession.swift](../Sources/TerminalUIScenes/SceneSession.swift)
- [RunLoop+Rendering.swift](../Sources/TerminalUI/RunLoop+Rendering.swift)
- [TerminalControlMessages.swift](../Sources/TerminalUI/TerminalControlMessages.swift)
- [MultiSceneLauncher.swift](../Sources/TerminalUIScenes/MultiSceneLauncher.swift)

Changes:

- teach terminal hosts to carry host-supplied theme state
- add a paired runtime update API so hosted wrappers can switch appearance and
  theme together
- extend the browser/WASI control-message channel beyond resize so a running
  scene can receive host style updates

Expected result:

- wrappers can switch themes at runtime through the same invalidation path used
  for resize and hosted appearance changes

### Phase 3: Wrapper Migration

Primary files:

- [GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUITerminalStyle.swift](../GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUITerminalStyle.swift)
- [GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/GhosttySceneBridge.swift](../GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/GhosttySceneBridge.swift)
- [GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUISceneHost.swift](../GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/SwiftUITUISceneHost.swift)
- [GUI/WebTUIGUI/src/WebTUITerminalStyle.ts](../GUI/WebTUIGUI/src/WebTUITerminalStyle.ts)
- [GUI/WebTUIGUI/src/WebTUISceneRuntime.ts](../GUI/WebTUIGUI/src/WebTUISceneRuntime.ts)
- [GUI/WebTUIGUI/src/WebTUIApp.ts](../GUI/WebTUIGUI/src/WebTUIApp.ts)
- [GUI/WebTUIGUI/src/wasi/BrowserWASIBridge.ts](../GUI/WebTUIGUI/src/wasi/BrowserWASIBridge.ts)

Changes:

- replace wrapper “light palette / dark palette” semantics with explicit host
  variants that contain both:
  - terminal-emulator palette state
  - TerminalUI semantic theme state
- bind those variants to host light/dark mode in the wrapper, not in the TUI
  app
- preserve current defaults so wrappers still work out of the box

Expected result:

- the wrapper owns theme choice
- the TUI app still just renders semantic roles

### Phase 4: Hex Ergonomics And Cleanup

Primary files:

- [Color.swift](../Sources/Core/Color.swift)
- [Styling.swift](../Sources/Core/Styling.swift)
- wrapper style files listed above

Changes:

- add non-throwing or convenience APIs that make hex color theme authoring easy
  in Swift
- update wrapper APIs so hex theme construction is direct and pleasant
- remove or de-emphasize repository docs and examples that present light/dark
  mode as the core styling abstraction

## Verification

Root package:

- [SwiftUISurfaceTests.swift](../Tests/TerminalUITests/SwiftUISurfaceTests.swift)
- [StreamingTerminalHostTests.swift](../Tests/TerminalUITests/StreamingTerminalHostTests.swift)
- [HostedSceneSessionTests.swift](../Tests/TerminalUIScenesTests/HostedSceneSessionTests.swift)

Wrapper packages:

- [StyleMappingTests.swift](../GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/StyleMappingTests.swift)
- [ResizeBridgeTests.swift](../GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/ResizeBridgeTests.swift)
- [WebTUITerminalStyle.test.ts](../GUI/WebTUIGUI/src/WebTUITerminalStyle.test.ts)
- [WebTUIApp.test.ts](../GUI/WebTUIGUI/src/WebTUIApp.test.ts)

Required commands before considering the migration complete:

```bash
swift test
cd GUI/SwiftUITUIGUI && swift test
cd GUI/WebTUIGUI && bun test
```

## Success Criteria

- A consumer can supply a `Theme`-equivalent semantic token map without the TUI
  app knowing which theme is active.
- The default terminal experience still looks like today when no theme is
  provided.
- SwiftUI and web wrappers can bind host light/dark changes to wrapper-owned
  theme variants.
- Hosted sessions and browser sessions can switch themes at runtime.
- Hex colors are first-class in both Swift and web wrapper theme APIs.

## Landing Notes

- The root runtime now carries `TerminalRenderStyle`, which keeps terminal
  appearance metadata and optional semantic `ThemeColors` together.
- Hosted sessions, streaming hosts, and WASI/browser bridges all support
  runtime style updates through the shared control-message path.
- SwiftUI and web wrappers now own explicit light/dark theme variants and bind
  them to host color-scheme changes outside the inner TUI app.
