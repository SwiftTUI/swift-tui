# Popover Presentation API

**Status:** Draft proposal; not implemented.

**Decision:** Add a small anchored popover surface that is close to SwiftUI's
binding-driven `popover` modifiers, plus a TipKit-inspired `popoverTip`
convenience that stays deliberately lighter than a full tip eligibility system.

**Related:** [VISION.md](../VISION.md), [RUNTIME.md](../RUNTIME.md),
[TODO.md](../TODO.md),
[ACTION_SCOPES_AND_COMMANDS.md](ACTION_SCOPES_AND_COMMANDS.md)

## Context

`VISION.md` defers popover-style presentation because the package did not yet
have a strong enough terminal interaction model. The current presentation stack
now has portal roots, overlay composition, interaction gates, dismiss stacks,
action scopes, source-frame geometry, and menu-style intrinsic overlays. That
makes a basic anchored popover feasible without inventing a separate
presentation system.

The missing distinction is source anchoring. `Menu` already uses a non-modal
portal entry, but its v1 caveat is that expanded content anchors at the
presentation host's top-leading rather than at the source control. A real
popover should resolve the source view's placed bounds and position compact
content adjacent to that rectangle.

## Goals

- Provide a SwiftUI-shaped modifier for anchored transient presentation.
- Keep popovers compact, intrinsic, and source-relative by default.
- Make keyboard behavior deterministic: Escape dismisses, focus restoration is
  explicit, and action scopes follow the existing presentation rules.
- Support binding-driven Boolean and item-driven presentation.
- Provide a TipKit-inspired convenience for lightweight guidance without taking
  on TipKit's rule engine, event donation, persistence, or display-frequency
  model.
- Preserve the option to add richer placement and adaptation policy later
  without source-breaking API churn.

## Non-Goals

- No full TipKit clone.
- No persistent tip store, rule DSL, event donation API, or automatic display
  throttling.
- No pixel-perfect arrow geometry. The terminal arrow is optional chrome, not
  part of layout identity.
- No pointer-first interaction requirement.
- No custom terminal-only DSL separate from the existing `View` modifier model.
- No implicit conversion of `Menu` into popover; menu semantics remain distinct.

## Proposed Popover Surface

The core API should be binding-driven and nearly match SwiftUI's basic shape:

```swift
extension View {
  public func popover<Content: View>(
    isPresented: Binding<Bool>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View

  public func popover<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content: (Item) -> Content
  ) -> some View
}
```

`arrowEdge` uses `Edge?` rather than a package-specific placement enum at the
public call site. `nil` means "choose the first edge that fits", which is more
natural in a terminal where available rows and columns vary widely.

The attachment type should also stay close to SwiftUI:

```swift
public enum PopoverAttachmentAnchor: Equatable, Sendable {
  case rect(UnitRect)
  case point(UnitPoint)
}

public struct UnitRect: Equatable, Hashable, Sendable {
  public var origin: UnitPoint
  public var size: UnitSize

  public static let bounds: UnitRect
}

public struct UnitSize: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double
}
```

`UnitPoint` already exists in the geometry layer. `UnitRect` is new only if the
current anchor-preference types cannot express SwiftUI's `.rect(.bounds)` call
site cleanly.

Example:

```swift
struct BuildButton: View {
  @State private var showsSettings = false
  @State private var usesCache = true

  var body: some View {
    Button("Build") {
      showsSettings = true
    }
    .popover(
      isPresented: $showsSettings,
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .trailing
    ) {
      VStack(alignment: .leading) {
        Text("Build settings")
        Toggle("Use cache", isOn: $usesCache)
        Button("Run") {
          showsSettings = false
        }
      }
      .frame(width: 28)
      .padding()
    }
  }
}
```

Item-driven presentation follows the existing optional-item pattern:

```swift
Text(package.name)
  .popover(item: $inspectedPackage, arrowEdge: .bottom) { package in
    VStack(alignment: .leading) {
      Text(package.name)
      Text(package.path)
    }
    .frame(width: 36)
    .padding()
  }
```

## Placement Semantics

Placement should run after source placement, not during resolve. The source
modifier contributes a presentation declaration plus an attachment request. Once
the base tree is placed, the presentation coordinator can resolve the source
identity to an absolute source rect and choose a popover rect.

Recommended v1 behavior:

- `.rect(.bounds)` attaches to the source view's placed bounds.
- `.point(.center)` attaches to a source-relative point.
- `arrowEdge` means "place the popover on this side of the source, with the
  arrow pointing back across that edge."
- `nil` tries `.trailing`, `.bottom`, `.leading`, then `.top`, choosing the
  first placement that fits the visible surface.
- If the requested edge does not fit, the coordinator may flip to the opposite
  edge before falling back to the automatic order.
- The final rect is clamped to the visible surface, but clamping should not
  detach the popover so far that the source relationship becomes misleading.
- If no anchored placement can fit, fall back to centered sheet-style placement
  using popover chrome, not to the public `sheet` modifier.

This keeps the API stable while giving the implementation enough room to adapt
to narrow terminals.

## Interaction Semantics

A popover is a transient presentation scope, not just a decorative overlay.

Recommended v1 behavior:

- Opening a popover creates a presentation action scope.
- Interactive popovers are modal by default: base routes are gated while the
  popover is active, matching the existing modal presentation model.
- Escape dismisses the topmost popover through `DismissStack`.
- Dismissal restores focus to the source identity when that identity still
  exists.
- If popover content has no focusable controls, focus may remain visually on the
  source while Escape still dismisses the popover.
- Popovers should not re-resolve the displayed base subtree under a synthetic
  identity path. Presentation churn remains transparent to the source subtree.

`Menu` can remain non-modal. If a later use case needs non-modal popovers, add a
configuration axis after proving the routing behavior through real examples.

## Tip Convenience

The TipKit-inspired API should be a thin convenience over `popover`, not a
second presentation engine. The important call-site shape is attaching guidance
to the view it explains:

```swift
extension View {
  public func popoverTip<Tip: PopoverTip>(
    _ tip: Tip?,
    isPresented: Binding<Bool>? = nil,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdges: Edge.Set = .all,
    action: @escaping @MainActor @Sendable (PopoverTipAction) -> Void = { _ in }
  ) -> some View
}
```

Use a package-owned protocol name so this does not imply compatibility with
Apple TipKit:

```swift
public protocol PopoverTip: Identifiable, Sendable {
  var title: Text { get }
  var message: Text? { get }
  var icon: Text? { get }
  var actions: [PopoverTipAction] { get }
  var isEligible: Bool { get }
}

public struct PopoverTipAction: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
}
```

Protocol defaults keep simple tips terse:

```swift
extension PopoverTip {
  public var message: Text? { nil }
  public var icon: Text? { nil }
  public var actions: [PopoverTipAction] { [] }
  public var isEligible: Bool { true }
}
```

Example:

```swift
struct FavoriteTip: PopoverTip {
  var id: String { "favorite" }
  var title: Text { Text("Save as Favorite") }
  var message: Text? {
    Text("Favorites stay pinned at the top of the list.")
  }
}

Button("Favorite") {
  favorite()
}
.popoverTip(
  FavoriteTip(),
  isPresented: $showsFavoriteTip,
  arrowEdges: .vertical
)
```

`popoverTip` presentation rules:

- A `nil` tip never presents.
- `tip.isEligible == false` never presents.
- If `isPresented` is supplied, both the binding and eligibility must allow
  display.
- If `isPresented` is omitted, the modifier may use source-local ephemeral
  dismissal state, but it must not persist display history across app launches.
- Tip actions dismiss the tip after invoking `action` unless a later API adds an
  explicit action-dismissal policy.
- Tip chrome should be compact and read-only by default. It should not gate base
  routes unless it contains focusable actions.

## Implementation Shape

The likely implementation is an extension of the existing presentation
primitive stack:

1. Add a popover presentation descriptor/token next to alert, sheet, menu, and
   toast descriptors.
2. Capture the source identity and attachment request in the presentation item.
3. Resolve source frames from the placed-frame table after base placement.
4. Measure popover content with intrinsic sizing and terminal caps.
5. Place the popover using the edge/fallback policy above.
6. Compose through `OverlayStack`, gate through `InteractionGate` only when the
   popover is modal, and dismiss through `DismissStack`.
7. Add focused runtime tests that assert source-relative placement, edge
   fallback, focus restoration, Escape dismissal, and base-subtree stability.

## Open Decisions

- Should the first public popover include a `modal:` option, or should v1 ship
  modal-only and keep non-modal behavior reserved for `Menu` and tips?
- Should `arrowEdge` be `Edge?`, or should the public popover modifier mirror
  TipKit's `arrowEdges: Edge.Set` from the start?
- Should `UnitRect` be public, or can `PopoverAttachmentAnchor` provide
  `.bounds` and point cases without exposing a general unit-rect type?
- What is the smallest useful arrow rendering in cell-space: no arrow,
  one-cell border notch, or a glyph connector?
- Should tip dismissal state be purely source-local, or should the package offer
  an opt-in persistence hook later?
