---
adr: "0011"
title: "AccessibilityRole replaces PresentationRole"
status: accepted
date: 2026-05-04
sources:
  - docs/proposals/ACCESSIBILITY.md
  - docs/proposals/SUBSTRATE_AUDIT.md
  - Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift
  - Sources/SwiftTUICore/Resolve/ResolvedNode.swift
---

# ADR-0011: AccessibilityRole replaces PresentationRole

## Context

`Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift` already defines a public
`PresentationRole` enum with 20 cases (`button`, `toggle`, `slider`,
`textField`, `secureField`, `textEditor`, `link`, `picker`,
`disclosureGroup`, `alert`, `confirmationDialog`, `menu`,
`scrollView`, `scrollViewWithIndicators`, `section`, `sheet`,
`stepper`, `table`, `tableRow`, `tabView`). Built-in widgets populate
it on `SemanticMetadata.presentationRole` end-to-end (see
[`SUBSTRATE_AUDIT.md`](../proposals/SUBSTRATE_AUDIT.md) Finding 1).

The accessibility proposal needs a role enum with substantially the
same shape plus ~13 additional cases (`image`, `progressBar`,
`timer`, `heading(level:)`, `status`, `region`, `separator`,
`columnHeader`, `rowHeader`, `cell`, `menuItem`, `tab`, `tabPanel`,
`group`, `custom(String)`, etc.). The first draft of
`ACCESSIBILITY.md` proposed `AccessibilityRole` as a new sibling
type. The substrate audit revealed this would create two parallel
role channels with overlapping semantics — and three call sites
that author them.

Two real options:

1. **Keep both types.** `AccessibilityRole` wraps or shadows
   `PresentationRole`. Built-ins continue to set `presentationRole`;
   accessibility consumers also set `accessibilityRole`; the two
   merge somewhere downstream.
2. **Rename and extend.** `PresentationRole` becomes
   `AccessibilityRole` and absorbs the missing cases. One field on
   `SemanticMetadata`. One modifier surface. One source of truth for
   "what kind of widget is this?"

Option 1 is *less disruptive in the short term* — no rename, no
existing call sites change. But it bakes drift into the substrate:
two role enums with overlapping cases and unclear precedence rules
when both are set. The existing `presentationRole` data is *exactly*
the data that wants to drive ARIA roles in the browser, VoiceOver
traits in the SwiftUI host, and AT exposure in the CLI. There is no
case in which a node has a different "presentation" role than its
"accessibility" role; calling them by different names is fiction.

The original "presentation" naming was a hint at the time — the
field was used by a few drawing-side branches and a few
interaction-side branches, and the framework author landed on a name
that didn't commit to either side. Now we know the field is used by
both sides for the same reason: *identifying what kind of widget the
user is looking at.* Accessibility is the most semantically precise
name for that.

## Decision

`PresentationRole` is renamed to `AccessibilityRole` and grows the
missing cases. There is **one** role enum and **one** field on
`SemanticMetadata`.

```swift
public enum AccessibilityRole: Equatable, Sendable, CustomStringConvertible {
  // Cases that exist today as PresentationRole — kept verbatim:
  case alert
  case button
  case confirmationDialog
  case disclosureGroup
  case link
  case list
  case menu
  case picker
  case scrollView
  case scrollViewWithIndicators
  case section
  case sheet
  case slider
  case stepper
  case table
  case tableRow
  case tabView
  case textEditor
  case textField
  case secureField        // new — currently aliased to .textField on SecureField
  case toggle

  // Cases added by ADR-0011:
  case checkbox           // alternative to .toggle for checkbox-style controls
  case image
  case progressBar
  case timer
  case heading(level: Int)
  case status
  case region
  case separator
  case columnHeader
  case rowHeader
  case cell
  case menuItem
  case tab                // a single tab item; .tabView is the container
  case tabPanel           // body of a tab
  case group              // generic container with no more specific role
  case custom(String)     // explicit escape hatch for app-specific roles

  // ... description impl ...
}
```

`SemanticMetadata.presentationRole: PresentationRole?` becomes
`SemanticMetadata.accessibilityRole: AccessibilityRole?`. The
modifier `presentationRole(_:)` becomes `accessibilityRole(_:)`.
All existing call sites
(`Sources/SwiftTUIViews/Controls/`, `Sources/SwiftTUIViews/Input/`,
`Sources/SwiftTUIViews/NavigationViews/TabView.swift`,
`Sources/SwiftTUIViews/ScrollView/ScrollView.swift`, etc.) are renamed in the
same patch.

`SecureField` keeps its mapping but the rename makes the distinction
explicit: it now reports `.secureField` rather than `.textField`. The
SwiftUI accessibility bridge maps `.secureField` to
`.isSecureTextEntry` traits; the embedded-host browser bundle maps
it to `<input type="password">` (vs `<input type="text">` for
`.textField`).

## Status

Accepted. Locked in before Phase 3a of the accessibility plan
([`ACCESSIBILITY.md`](../proposals/ACCESSIBILITY.md) §"Suggested
phasing"); Phase 3a depends on this decision.

## Consequences

**Enabled:**

- One source of truth for "what kind of widget is this?" Built-ins,
  consumer-authored views, and AT consumers all use the same enum.
- The accessibility ARIA / VoiceOver / NSAccessibility mappings have
  one input type to translate from, not two. The embedded-host
  encoder, the SwiftUI host bridge, and the linear-render mode all
  read `accessibilityRole` from the same field.
- Existing internal call sites that already author the role (Toggle,
  TextField, SecureField, TextEditor, Link, Picker, DisclosureGroup,
  TabView, ScrollView, etc.) light up the accessibility surface for
  free — the data is already in place; renaming the receiving field
  is enough.

**Foreclosed:**

- The framework cannot split "what the widget visually presents as"
  from "what the widget accessibly is" in the role channel. If we
  ever need to (we don't have a use case yet), it would be expressed
  through additional fields (`accessibilityRoleOverride`?), not a
  parallel type.
- Consumers cannot author `presentationRole(_:)` at all. The old
  name is removed, not deprecated — pre-1.0 framework, no public
  consumers depend on it. (If a deprecation period is needed later,
  we can re-add a typealias and modifier with a
  `@available(*, deprecated, renamed:)` shim.)

**Discipline imposed:**

- Adding a role to the framework requires adding it to
  `AccessibilityRole`. The naming, the documentation, and the
  ARIA/SwiftUI/CLI mapping live together.
- The migration is mechanical but touched several files; it lands as
  a single PR that also adds the new cases. No rolling rename.

**Migration:**

- Rename the type in
  `Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`.
- Rename the field in `SemanticMetadata`.
- Rename the modifier in `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
  and update all built-in callers.
- Update tests under `Tests/SwiftTUICoreTests/`, `Tests/SwiftTUIViewsTests/`,
  `Tests/SwiftTUITests/` that reference the old name.
- Update `docs/proposals/ACCESSIBILITY.md` and
  `docs/proposals/SUBSTRATE_AUDIT.md` to drop the "rename pending"
  language.

The bet: a single role channel with the right name avoids years of
"is this the presentation role or the accessibility role?" drift.
The cost is a one-time mechanical rename across ~15 files.
