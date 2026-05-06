# Accessibility Listening Checks

This directory documents the manual listening surface that complements the
checked-in semantic, Web/WASI, SwiftUI host, and accessible-output tests.

Run `./Scripts/check_accessibility_guardrails.sh` before broad accessibility
changes. The script pins current source files that contain raw glyphs,
color-state styling, and visual-only surfaces so new entries require review.
Use `./Scripts/check_accessibility_guardrails.sh --update` only after the new
source has an accessible label, summary, hidden policy, or explicit acceptance.

## VoiceOver

Use VoiceOver on macOS for both terminal accessible output and the SwiftUI host.

1. Start the gallery in linear accessible mode:
   `swiftly run swift run --package-path Examples/gallery gallery-demo --accessible`
2. Confirm tab changes, focused controls, text input labels, live-region output,
   and `AccessibilityAnnouncer` messages are spoken in logical order.
3. Exercise visual-only screens such as images, charts, canvas demos, and
   animated content. They should expose meaningful labels or summaries, or be
   skipped when intentionally hidden.
4. Repeat the same flows in the SwiftUI host when the change touches native host
   mapping or platform announcements.

## Browser

The browser target is the preferred repeatable listening path because it mounts
the semantic stream as ARIA beside the raster canvas.

1. Start the gallery web surface:
   `swiftly run swift run --package-path Examples/gallery gallery-demo --web --no-open --port 8080`
2. Open `http://127.0.0.1:8080` and use the browser accessibility inspector to
   confirm roles, names, focus, and live regions.
3. Listen with VoiceOver, NVDA, or Orca depending on host platform.
4. Confirm imperative announcements use the expected `aria-live` priority and
   do not replay old live-region baselines.

## NVDA

Use NVDA on Windows against the browser target.

1. Run the app with `--web` from a reachable host or WASI/browser build.
2. Navigate with Tab and arrow keys through controls, tabs, text inputs, and
   menus.
3. Confirm state is not color-only: selected, focused, disabled, success,
   warning, and error states must have text, glyph, role, label, or position
   cues in addition to color.

## Orca

Use Orca on Linux against the browser target, and against terminal accessible
output when the terminal and shell combination is known to be readable.

1. Start with `--accessible --ascii --no-progress` when testing terminal output.
2. Prefer the browser target for role/focus regressions.
3. Confirm visual-only content is either summarized or skipped consistently.

## Release Evidence

Record the screen reader, target, OS, browser or terminal, app command, and
observed pass/fail notes in the PR or release checklist. Listening failures
should be converted into semantic snapshot tests, Web/WASI transport tests, or
SwiftUI host mapping tests whenever the behavior is deterministic.
