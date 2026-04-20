# Cell-Pixel Geometry Research

This memo surveys the motivations for exposing pixel-level geometry information in a cell-based TUI framework, and their implications for TerminalUI specifically. It is a research document rather than a proposal: its purpose is to canvass the design space so that any subsequent API decision is made against the full field of trade-offs rather than a single triggering use case.

## Context

### The current geometry model

TerminalUI measures authored geometry in integer terminal cells. The `GeometryProxy` type exposed to `GeometryReader` today carries two pieces of information:

- `size: Size` — the current surface size in cells, read from `EnvironmentValues.terminalSize`
- `safeAreaInsets: EdgeInsets` — the cell-denominated safe-area

`Size`, `Point`, `Rect`, and `EdgeInsets` in `Sources/Core/GeometryTypes.swift` are all integer-cell types. The `Layout` protocol, placement algorithm, and alignment guides are all cell-denominated. This is a deliberate stance: integer-cell geometry is one of the "terminal-specific differences" `docs/VISION.md` explicitly endorses, on the grounds that it keeps layout predictable and the rasterizer simple.

### What the runtime already knows about pixels

Despite the authored API being cell-only, the runtime already detects and stores cell-pixel dimensions. `TerminalGraphicsCapabilities.cellPixelSize: Size?` is populated on startup using a three-method fallback in `Sources/TerminalUI/TerminalHost.swift`:

1. `ioctl(TIOCGWINSZ)` with `ws_xpixel`/`ws_ypixel` when the kernel reports them
2. A DECRQSS-style `CSI 16 t` query for cell pixel size
3. A `CSI 14 t` (text area in pixels) query divided by the cell count as a derived fallback

This value is plumbed through the resolve environment as `EnvironmentValues.terminalCellPixelSize` (currently `package` visibility) and consumed by image rendering. A hardcoded default of `Size(width: 8, height: 16)` is used when detection fails; this corresponds to the common convention that a terminal cell is roughly twice as tall as it is wide.

In other words: pixel information is detected, stored, and used internally. The outstanding question is what, if any, subset of it belongs on the authored API.

### The stated tension with VISION.md

`docs/VISION.md` explicitly names "pixel-precise layout or a second, non-terminal presentation model" as out of scope. That constraint is doing real work here. Any pixel-aware public API must be positioned as *advisory runtime metadata*, not as a new coordinate system or layout primitive. The constraint rules out things like `PixelPoint`, `PixelRect`, or a `.frame(pixelWidth:pixelHeight:)` modifier; it does not rule out a read-only side channel that authors can consult when building values or tuning motion.

This asymmetry — detection is complete, the vision restricts how the detected value may be surfaced — is what makes the design space interesting.

### The immediate trigger

The triggering use case was the "fullscreen" physics toy in the gallery (`Examples/gallery/Sources/GalleryDemoViews/FullScreen.swift`). Every physics decision in `FullScreenToyPhysics` is silently distorted by cell anisotropy:

- `gravityPerTick = 1` applies to `velocity.y` in cell-per-tick units, so vertical acceleration is roughly twice as fast visually as the equivalent horizontal impulse
- `blockSize = Size(width: 6, height: 3)` is the author hand-compensating for cell aspect to make the block look square on screen
- `DragGesture.velocity` is reported in cells/second, so a 45 degree flick decomposes into directionally biased release velocities
- Wall bounces and floor bounces use the same fractional coefficients but produce visibly different decays on each axis

The physics is perfectly correct in cell space and visually wrong in pixel space. What the author actually wants is a unit of motion that is isotropic on screen, which reduces to needing the cell's pixel dimensions (or, for the minimal case, the ratio between them).

That single case is narrow enough that a minimal API would cover it. The broader question of this memo is whether there are other motivations — present or latent — that would justify a richer API, and if so whether they converge on a single type or pull in different directions.

## Prior art

Most mature TUI frameworks land somewhere on a spectrum from "pixel information is entirely invisible to authors" to "pixel information is part of the core vocabulary."

### Notcurses

Notcurses sits at the pixel-aware end. `ncplane_pixel_geom()` returns six values: plane size in pixels (`pxy`, `pxx`), per-cell pixel dimensions (`celldimy`, `celldimx`), and the largest bitmap the plane can display (`maxbmapy`, `maxbmapx`). `ncvisual_geom` extends this with rendered dimensions and per-blitter scaling factors. Notcurses is architecturally bitmap-first — bitmap blits are a core primitive — so pixel information is load-bearing. The API shape is a natural fit there but would be over-engineered for a framework where bitmap support is an accessory.

### Ratatui

Ratatui has a `window_size()` accessor that returns a struct with both `(columns, rows)` and `(width_px, height_px)`. The rest of Ratatui is cell-only. The companion `ratatui-image` crate uses the pixel dimensions to size image widgets and falls back to a hardcoded 4:8 aspect when detection fails. This is the closest shape to what TerminalUI might adopt: pixel information exists as a side channel consulted by specific components, not as a pervasive authoring concern.

### Textual

Textual keeps layout and mouse events fully cell-denominated. Pixel information surfaces internally to enable experiments like smoother scrolling and sub-cell mouse granularity, but the authored API does not expose it. This is the most conservative position: detection without surfacing.

### Kitty / iTerm2 / WezTerm / foot

These are terminals, not frameworks, but they matter because they are the source of truth for detection. Modern terminals respond to `CSI 16 t` (cell pixel size) and `CSI 14 t` (text area pixels); many also support the `1016h` SGR pixel-mouse mode that reports mouse coordinates in pixels rather than cells. The detection story has genuinely improved over the last several years; a framework designed today can assume pixel dimensions are available on most targets of interest.

### Conventions across the field

A conventional default emerges from the prior art: when detection fails, a 2:1 height:width cell aspect is the safe fallback. This is the `8 x 16` default TerminalUI already uses. It reflects the typical visual ratio of modern monospace fonts at common point sizes. A framework that needs to invent a fallback should use this ratio.

## The ratio-versus-absolute bifurcation

The single most important observation across the motivation space below is that almost every proposed use case for pixel information falls cleanly into one of two buckets:

- **Ratio-only.** The author needs to know how rectangular a cell is, but does not care about absolute pixel dimensions. Shape rendering, physics, motion, animation easing, and plot aspect all fit here. The ratio can be computed from any cell pixel size and has a stable, defensible default when detection fails.
- **Absolute pixels required.** The author needs a number that is meaningful in the same unit as some external pixel-denominated quantity: image resolution, target bitmap size, rendered PNG for a test, or a graphics protocol argument. These use cases cannot be served by a ratio; they need real pixel dimensions, and they require the author to reason about the confidence of the value.

A ratio-only API is smaller and always honest. An absolute-pixel API is strictly more powerful but must carry a confidence signal (was this value reported by the terminal, or estimated) or it will produce silent misuse. A good design accommodates both through a single type, letting ratio consumers derive what they need.

## Motivations, upside, downside, and fit

The following ten motivations cover the landscape of reasons one might ask for pixel information in a cell-based TUI framework. Each entry describes the concrete case, what shape of API it would imply, what it unlocks, what it risks, and how well it fits TerminalUI's stated vision.

### 1. Geometric honesty

**Concrete case.** A `Circle` that is not an oval. A `Square` that is square on screen. A scatter plot where equal data distances render as equal visual distances. A pie chart where a right angle looks right.

**API implication.** A single scalar — the cell's height-to-width ratio — is sufficient. The Shape rasterizer can apply the ratio internally when sampling the 2x4 Braille grid, or Canvas authors can apply it explicitly when computing geometry.

**Upside.** One value unlocks correctness across an entire family of primitives. Any future `Chart`, `Map`, or diagram-like surface inherits the fix. Shape primitives look right on terminals that report their cell size, and look no worse than today on terminals that do not.

**Downside.** Applying the correction changes existing behavior. Users who had manually compensated by drawing ellipses to get circles now get circles drawn as over-tall shapes. Pre-release, this is a feature; post-release, it would be a breaking change. There is also a small question of whether the correction belongs in the rasterizer (invisible to authors) or on the proxy (authors apply it), which is a style decision with testability implications.

**Fit with TerminalUI.** High. This is probably the highest-leverage single motivation.

### 2. Physics, motion, and gestures

**Concrete case.** The gallery physics toy is the canonical example. Generalize it to: spring animations that feel the same on both axes, elastic bounces, flick-to-dismiss gestures, parallax scrolling, and any animation whose visual trajectory should match its mathematical description.

**API implication.** Ratio suffices for most purposes. A richer metrics type is preferable if authors want to write physics in pixel-units and project into cells once per frame, which is cleaner architecturally than sprinkling ratio corrections across the physics code.

**Upside.** Unlocks high-polish motion across an existing runtime that already supports real-time animation. The resolve-once-animate-through-pipeline architecture already isolates animation values from layout, which is the correct seam for this kind of unit conversion.

**Downside.** Tempts authors to write pixel-denominated physics in places where the terminal falls back to an estimated 8x16 cell size. On a terminal with a different aspect, the physics "feels different." This is less a design problem than a documentation one, but the fallback must be stable and called out.

**Fit with TerminalUI.** High. This is the immediate trigger, and it connects naturally to the animation and gesture subsystems that have already shipped.

### 3. Graphics-protocol integration and image sizing

**Concrete case.** An author shows an `Image` backed by a 600x400 PNG and wants to pick a cell size that does not force the terminal to upscale or downscale. Alternatively: an author generates a chart as a raster image and wants to render it at 1:1 on the terminal's pixel grid. Alternatively: an author wants to pre-scale a raster asset once to avoid the cache churn triggered by cell-size changes.

**API implication.** Absolute pixel dimensions, plus a confidence flag. A convenience helper that returns `surfaceSize * cellPixelSize` saves callers from multiplying manually.

**Upside.** Dramatic quality improvement for image-heavy UIs. Avoids double-resampling, gives authors explicit control over what the graphics protocol sees, and lets scale-aware resource pipelines target the right raster size.

**Downside.** Ties a public API to the behavior of the capability-gated graphics pipeline. Authors will write branches like "use graphics protocol if pixels > N, else ASCII" and run into portability surprises when detection fails. The reported-versus-estimated distinction must be part of the public type, not documented off to the side, or the misuse is guaranteed.

**Fit with TerminalUI.** Medium-high. The framework already does this internally; the outstanding work is exposing the honest version of what it already computes.

### 4. Sub-cell canvas drawing

**Concrete case.** `Canvas` draws on a 2x4 Braille grid, so each cell contains eight sub-cells. Other frameworks expose half-blocks (1x2), quadrants (2x2), sextants (2x3), or octants (2x4). Each virtual sub-pixel has a different real aspect ratio. Authors drawing plots, sparklines, or line art on these grids want to know how rectangular their sub-pixel actually is.

**API implication.** A derived convenience. Given a cell pixel size and a declared sub-cell grid, the effective sub-pixel dimensions are straightforward division. A `CanvasContext.subpixelSize` or similar accessor would expose it; nothing new is needed in the core metrics type.

**Upside.** Plots and sparklines get correct data-unit squareness without author intervention. Shape rendering through Braille becomes aspect-honest for free.

**Downside.** Canvas authors now need to be aware of pixel metrics — an implementation detail that Canvas has deliberately hidden until now. An alternative is to apply the correction inside the rasterizer, which keeps Canvas pure cell-space at the cost of less author control. The trade-off is about how much sub-cell fidelity authors are expected to reason about.

**Fit with TerminalUI.** Medium. Worth exposing only if Canvas authors have concrete need for control; otherwise, handle the correction inside `Rasterizer+CellSampling.swift`.

### 5. Sub-cell mouse precision

**Concrete case.** A draggable slider rendered on one cell's width has up to ten meaningful x-positions in pixel-mouse mode and one in cell-mouse mode. Scrubbing, hover feedback on graphics-protocol content, and image annotation all benefit from sub-cell pointer granularity where the terminal supports it. xterm's `1016h` SGR pixel mouse mode is supported by Kitty, iTerm2, WezTerm, and foot.

**API implication.** Not a geometry API at all — a pointer-input API. `PointerEvent` would need an optional sub-cell offset, handlers would branch on precision availability, and the capability detection is separate from cell pixel detection (`?1016h` rather than `CSI 16 t`).

**Upside.** Enables a class of high-fidelity interactions that cell-mouse cannot support. Particularly valuable for any UI that displays graphics-protocol content and wants to respond to pointer position relative to it.

**Downside.** `VISION.md` explicitly de-emphasizes pointer-precise interaction. Building this well means authoring code must accommodate "sometimes I have one pixel of granularity, sometimes sixteen" — a nontrivial API problem. Pixel coordinate origins vary across terminals, and the parser is fussy. This is a whole input design on its own.

**Fit with TerminalUI.** Low for v1. It is right to flag this as a potential future need, but the design does not belong inside the geometry API; it belongs in the input pipeline, and should not constrain the shape of a cell-pixel metrics type.

### 6. Accessibility and physical size

**Concrete case.** Goals analogous to WCAG touch-target and text-size requirements: "this interactive region must be at least N millimeters," "this text must be at least N points."

**API implication.** Would require pixel dimensions plus a DPI estimate. Terminals do not report DPI; the best one could do is a heuristic default.

**Upside.** Gives accessibility-minded authors some handle on physical size, currently impossible to approximate.

**Downside.** The DPI estimate is effectively always a lie. User font-size changes — which the TUI cannot detect — invalidate any pixel-to-physical conversion. The framework would be shipping a measurement it cannot deliver on. `VISION.md` already names a full accessibility-tree as not in scope today.

**Fit with TerminalUI.** Low. Probably not worth building API around.

### 7. Density-aware responsive layout

**Concrete case.** The same cell count (say 100x30) on a 1080p window and a 4K window correspond to very different pixel dimensions. An author might want to pick denser content — smaller icons, more items per row, thinner dividers — on high-density windows.

**API implication.** Pixel dimensions plus an opinionated breakpoint primitive, or just the raw pixel data with the breakpoint logic left to consumers.

**Upside.** Lets authors respond when the user has pushed font size up for readability by giving larger controls, or respond to a very dense window with richer content.

**Downside.** The framework owning "what counts as high density" is an opinion that will not age well. Exposing raw pixels and letting consumers pick thresholds is more honest but produces brittle magic numbers in user code. Either position has costs.

**Fit with TerminalUI.** Low-to-medium. Worth having raw data available so that consumers who need this can build their own classifiers; there is no reason to ship opinionated helpers.

### 8. Snapshot and golden-image testing

**Concrete case.** Regression tests render the TUI surface to a raster image and diff against a baseline. The raster dimensions depend on cell count times cell pixel size. Tests need deterministic numbers.

**API implication.** Tests must be able to *set* cell pixel size for determinism, not merely read it. That is a runtime injection story, not an authoring story.

**Upside.** Enables a class of regression tests that are currently awkward to write. The fixture-based testing already in the project would gain an honest way to pin pixel-denominated outputs.

**Downside.** Crosses the line between authoring and runtime. Authors writing views should never set cell pixel size; test harnesses need to. Conflating them in a single API is a hazard. The clean answer is that test harnesses inject via `StreamingTerminalHost.init(graphicsCapabilities:)`, which is already `package` visibility, while the authored read-side stays strictly read-only.

**Fit with TerminalUI.** Medium. The injection path already exists privately; exposing the read side for authors makes the testing case workable almost for free.

### 9. Bridging to non-terminal design systems

**Concrete case.** A design specified in Figma units converted to cells by dividing out pixel dimensions. A cross-surface system that shares layout values between mobile and terminal. An import pipeline from a design tool whose units are pixels or points.

**API implication.** Absolute pixel dimensions are needed; additionally, a fictional "design pixel" concept would be useful but cannot be honest in the terminal context.

**Upside.** Niche but real for teams building companion CLIs or cross-platform tooling. The capability exists on the system without any framework help, as long as pixel dimensions are readable.

**Downside.** The mental models do not line up. Design-tool units assume sub-glyph alignment, continuous positioning, and rasterization fidelity that terminals do not provide. Any bridge is lossy. Building API around this encourages authors to pretend the systems are commensurable.

**Fit with TerminalUI.** Low. Not worth designing around; leave it as something advanced users can compose on top of whatever read-only metrics API ships.

### 10. Diagnostics and debug overlays

**Concrete case.** A "show debug info" overlay that reports detected cell pixel size and graphics capabilities, so developers can see whether detection worked and reason about their terminal's behavior.

**API implication.** None beyond the read-only path any other motivation would already have built. This is purely a consumer.

**Upside.** Transparent debugging. Particularly valuable because pixel detection has known failure modes across terminals, and an author investigating a rendering bug should not have to instrument the framework to see what it is working with.

**Downside.** None.

**Fit with TerminalUI.** Trivially high. This comes for free as soon as the metric is exposed.

## Patterns across the motivations

### Ratio versus absolute

Motivations 1, 2, 4, and 7 are fully served by an aspect ratio. Motivations 3, 5, 6, 8, and 9 need absolute pixels and a confidence signal. A single type with a pixel-pair field plus a source enum serves both groups — ratio consumers derive `Double(height) / Double(width)` and ignore the rest.

### Authoring versus runtime

The motivations cluster along a second axis. Authoring-time cases (1, 2, 4) are expressed in view bodies and view builders; they want discoverability, so `GeometryProxy` is a natural home. Runtime and infrastructure cases (3, 5, 8) live in image caching, input dispatch, and test harnesses; they are fine with environment access or, in the case of test injection, with existing `package`-level configuration. Mixing the two cleanly requires either two entry points or a single type accessible from both.

### Tension with VISION.md

Some motivations are actively in tension with the stated vision. Pointer-first precision (5), a full accessibility story (6), and non-terminal presentation-model bridging (9) are each explicitly de-emphasized in `docs/VISION.md`. When a motivation is in that set, the question "does this fit the stated vision?" is a useful filter for whether the framework will regret shipping API for it.

## Which motivations justify an API

Strong fit: 1 (geometric honesty), 2 (physics and motion), 3 (image sizing), 10 (diagnostics).

Conditional fit: 4 (canvas sub-pixel) only if Canvas authors are expected to reason about sub-pixel aspect; otherwise handle it internally. 8 (snapshot testing) only if test determinism is a current priority.

Defer: 5 (pointer precision) belongs in an input design, not a geometry one. 6 (accessibility physical size) would ship a measurement the framework cannot honestly deliver. 7 (density-aware layout) can be built on top of any read-only metric; no opinionated helpers needed. 9 (cross-surface bridging) is composable on top of raw metrics.

A single read-only `CellPixelMetrics`-style type, exposed on both `GeometryProxy` and `EnvironmentValues`, covers every strong and conditional fit. The deferred motivations are either a different subsystem or derivable by callers, which is exactly the property one wants from a foundational read-API.

## Open questions

- Should the correction for motivation 1 (geometric honesty) live inside the Shape rasterizer, on the proxy, or both? This is primarily a style and testability question rather than a detectability one.
- If `CellPixelMetrics` ships with a `source: .reported | .estimated` flag, how should the public documentation steer authors toward checking it before making graphics-protocol decisions?
- Does the type name `CellPixelMetrics` carry enough of the "advisory, not layout" framing, or should the public type name explicitly include "display" or "advisory" in its name to head off misuse?
- How should the existing `package var EnvironmentValues.terminalCellPixelSize` be migrated — renamed and promoted, or deprecated alongside a new public key?
- If any of the deferred motivations ship later — particularly pointer precision — should they pass through the same metrics type, or acquire their own vocabulary to avoid overloading a "geometry" type with input semantics?

These are the questions a subsequent proposal under `docs/proposals/` would need to answer. This memo does not attempt to; it only establishes the field against which that proposal should be judged.
