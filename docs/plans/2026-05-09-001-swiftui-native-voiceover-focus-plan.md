---
title: "feat: SwiftUI native VoiceOver focus by default"
type: feature
status: planned
date: 2026-05-09
depends_on:
  - "../ACCESSIBILITY.md"
  - "../decisions/0015-accessibility-swiftui-host-policy.md"
  - "2026-05-05-005-accessibility-swiftui-host-plan.md"
---

# SwiftUI Native VoiceOver Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Commit after each completed task.

**Goal:** Make SwiftTUI runtime focus movement move native VoiceOver focus in
the SwiftUI host by default.

**Architecture:** Keep `SemanticSnapshot.accessibilityNodes` as the source of
truth and keep the raster terminal surface visually unchanged. The SwiftUI host
will bind each hosted accessibility overlay element to a shared
`@AccessibilityFocusState` value, then set that value from the runtime's
focused identity after each semantic frame. This tranche is one-way
runtime-to-native focus; VoiceOver traversal back into SwiftTUI runtime focus
is a separate interaction contract.

**Tech Stack:** Swift 6.3 strict concurrency, SwiftUI,
`AccessibilityFocusState`, `.accessibilityFocused(_:equals:)`, Swift Testing,
`SwiftUIHostSceneHost`, `HostedAccessibilityOverlay`,
`AccessibilityNodeMapping`, and `SemanticSnapshot.accessibilityNodes`.

---

## Current State

`SwiftUIHostSceneHost` stores `focusedAccessibilityIdentity` from committed
semantic frames, and `HostedAccessibilityOverlay` maps that identity into
`AccessibilityNodeMapping.isFocused`. ADR-0015 deliberately documented this as
metadata-only v1 behavior. The new decision is to make native VoiceOver focus
movement the default SwiftUI-host behavior, so ADR-0015 and the shipped
accessibility guide must be updated before implementation.

Context7's current SwiftUI docs describe `AccessibilityFocusState` as the
property wrapper for reading and writing the focus of active accessibility
technologies, and `.accessibilityFocused(_:equals:)` as the modifier that binds
an accessibility element to a specific focus value.

## Files

### Modify

- `docs/decisions/0015-accessibility-swiftui-host-policy.md`
- `docs/ACCESSIBILITY.md`
- `docs/proposals/ACCESSIBILITY.md`
- `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/AccessibilityNodeMapping.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityOverlayTests.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/AccessibilityNodeMappingTests.swift`

### Create

- `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityFocusPolicy.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityFocusPolicyTests.swift`

## Task 1: Update The Policy Documents

**Files:**

- Modify: `docs/decisions/0015-accessibility-swiftui-host-policy.md`
- Modify: `docs/ACCESSIBILITY.md`
- Modify: `docs/proposals/ACCESSIBILITY.md`

- [ ] **Step 1: Rewrite the ADR-0015 focus decision**

Replace the metadata-only focus paragraph with this policy:

```markdown
SwiftUI host focus moves native accessibility focus by default. The host
cross-references the latest runtime focused identity with the current
`AccessibilityNode` mappings and writes the matching overlay element ID into a
host-owned `AccessibilityFocusState`. If the focused node is removed, the host
clears the native accessibility focus request for that frame.

This is a one-way runtime-to-native focus bridge in this tranche. VoiceOver
user traversal does not yet mutate SwiftTUI runtime focus because that requires
a separate interaction contract for mapping native accessibility focus changes
back into `FocusTracker` without synthesizing misleading pointer or keyboard
input.
```

- [ ] **Step 2: Update the shipped accessibility guide**

In `docs/ACCESSIBILITY.md`, replace the current SwiftUI-host metadata-only
sentence with:

```markdown
SwiftUI host focus moves native VoiceOver focus by default. The host binds each
overlay accessibility element to a shared `AccessibilityFocusState` value and
sets that value from the runtime focused identity after each committed semantic
frame. VoiceOver-originated focus traversal is not yet fed back into SwiftTUI
runtime focus.
```

- [ ] **Step 3: Update the historical proposal status**

In `docs/proposals/ACCESSIBILITY.md`, keep the research context but change the
remaining SwiftUI host focus note to say native focus is the planned default
and bidirectional native-to-runtime focus remains out of scope for this plan.

- [ ] **Step 4: Verify docs-only status**

Run:

```bash
rg -n "metadata-only|does not programmatically move global VoiceOver focus|native focus" docs/ACCESSIBILITY.md docs/decisions/0015-accessibility-swiftui-host-policy.md docs/proposals/ACCESSIBILITY.md
```

Expected: no current-state doc still claims SwiftUI host focus is
metadata-only; historical proposal text may mention the old baseline only when
explicitly marked as superseded.

- [ ] **Step 5: Commit**

```bash
git add docs/ACCESSIBILITY.md docs/decisions/0015-accessibility-swiftui-host-policy.md docs/proposals/ACCESSIBILITY.md
git commit -m "docs: update SwiftUI host focus policy"
```

## Task 2: Add A Pure Native-Focus Policy

**Files:**

- Create: `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityFocusPolicy.swift`
- Create: `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityFocusPolicyTests.swift`

- [ ] **Step 1: Write focused policy tests**

Add tests that pin the host-owned mapping from current overlay mappings to a
native focus request:

```swift
import CoreGraphics
import Testing

import SwiftTUI

@testable import SwiftUIHost

@MainActor
@Suite
struct HostedAccessibilityFocusPolicyTests {
  @Test("requests the focused mapping id")
  func requestsFocusedMappingID() {
    let focused = mapping(id: "root.button", isFocused: true)
    let other = mapping(id: "root.other", isFocused: false)

    #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: [other, focused]) == "root.button")
  }

  @Test("clears focus when focused node is absent")
  func clearsFocusWhenFocusedNodeIsAbsent() {
    #expect(
      HostedAccessibilityFocusPolicy.requestedFocusID(
        in: [mapping(id: "root.button", isFocused: false)]
      ) == nil
    )
  }

  @Test("keeps the first focused mapping when duplicate focus metadata appears")
  func keepsFirstFocusedMapping() {
    let first = mapping(id: "root.first", isFocused: true)
    let second = mapping(id: "root.second", isFocused: true)

    #expect(HostedAccessibilityFocusPolicy.requestedFocusID(in: [first, second]) == "root.first")
  }
}
```

Reuse the existing mapping test helpers where possible; otherwise add a local
helper that constructs `AccessibilityNodeMapping` with a non-empty frame and
the requested `isFocused` value.

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.HostedAccessibilityFocusPolicyTests
```

Expected: FAIL because `HostedAccessibilityFocusPolicy` does not exist.

- [ ] **Step 3: Implement the pure policy**

Create `HostedAccessibilityFocusPolicy.swift`:

```swift
enum HostedAccessibilityFocusPolicy {
  static func requestedFocusID(
    in mappings: [AccessibilityNodeMapping]
  ) -> String? {
    mappings.first(where: \.isFocused)?.id
  }
}
```

- [ ] **Step 4: Verify the policy tests pass**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.HostedAccessibilityFocusPolicyTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityFocusPolicy.swift Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityFocusPolicyTests.swift
git commit -m "test: add SwiftUI host native focus policy"
```

## Task 3: Bind Overlay Elements To SwiftUI Accessibility Focus

**Files:**

- Modify: `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift`
- Modify: `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityOverlayTests.swift`

- [ ] **Step 1: Add overlay tests for requested native focus**

Extend `HostedAccessibilityOverlayTests` with tests that assert a focused
semantic node produces the expected native focus request and a removed focused
node clears it:

```swift
@Test("overlay exposes requested native focus id")
func overlayExposesRequestedNativeFocusID() {
  let focused = testIdentity("Overlay", "Focused")
  let overlay = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: focused,
          rect: rect(x: 1, y: 1, width: 4, height: 1),
          role: .button,
          label: "Run"
        )
      ]
    ),
    focusedIdentity: focused,
    cellSize: CGSize(width: 8, height: 16)
  )

  #expect(overlay.requestedNativeFocusID == focused.path)
}

@Test("overlay clears requested native focus when focused node disappears")
func overlayClearsRequestedNativeFocusWhenFocusedNodeDisappears() {
  let overlay = HostedAccessibilityOverlay(
    semanticSnapshot: SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: testIdentity("Overlay", "Other"),
          rect: rect(x: 1, y: 1, width: 4, height: 1),
          role: .button,
          label: "Other"
        )
      ]
    ),
    focusedIdentity: testIdentity("Overlay", "Missing"),
    cellSize: CGSize(width: 8, height: 16)
  )

  #expect(overlay.requestedNativeFocusID == nil)
}
```

- [ ] **Step 2: Run the failing overlay tests**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.HostedAccessibilityOverlayTests
```

Expected: FAIL because `requestedNativeFocusID` and native focus bindings do
not exist.

- [ ] **Step 3: Add the focus state and per-element binding**

Update `HostedAccessibilityOverlay` with the shared focus state and a
test-visible computed request:

```swift
@AccessibilityFocusState private var nativeFocusedElementID: String?

var requestedNativeFocusID: String? {
  HostedAccessibilityFocusPolicy.requestedFocusID(in: mappings)
}
```

Pass `$nativeFocusedElementID` into each `HostedAccessibilityElement`, and in
the element body add:

```swift
.accessibilityFocused(nativeFocusedElementID, equals: mapping.id)
```

Use `AccessibilityFocusState<String?>.Binding` for the child parameter.

- [ ] **Step 4: Apply focus requests after mapping changes**

On the overlay container, set native focus when either the focused runtime
identity or the mapping set changes:

```swift
.onAppear {
  nativeFocusedElementID = requestedNativeFocusID
}
.onChange(of: requestedNativeFocusID) { _, newValue in
  nativeFocusedElementID = newValue
}
.onChange(of: mappings) { _, _ in
  nativeFocusedElementID = requestedNativeFocusID
}
```

This keeps native focus stable across geometry-only frame updates and clears
the request when the focused node is no longer in the overlay.

- [ ] **Step 5: Verify overlay tests pass**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.HostedAccessibilityOverlayTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityOverlayTests.swift
git commit -m "feat: bind SwiftUI host overlay to native focus"
```

## Task 4: Verify Host-Level Focus Flow

**Files:**

- Modify: `Platforms/SwiftUI/Tests/SwiftUIHostTests/SwiftUIHostAccessibilityTests.swift`
- Modify: `Platforms/SwiftUI/Tests/SwiftUIHostTests/AccessibilityNodeMappingTests.swift`

- [ ] **Step 1: Extend mapping coverage**

Add or update tests proving `AccessibilityNodeMapper.mapping(...)` still sets
`isFocused` only when the node identity matches the host's focused identity.
This protects the native-focus request from accidentally following visual order
or label matches.

- [ ] **Step 2: Extend host integration coverage**

Add a host-level test that renders a focusable control, waits for
`host.focusedAccessibilityIdentity`, then builds a `HostedAccessibilityOverlay`
from the host's latest snapshot and asserts:

```swift
#expect(overlay.requestedNativeFocusID == host.focusedAccessibilityIdentity?.path)
```

- [ ] **Step 3: Run the SwiftUI host accessibility tests**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.SwiftUIHostAccessibilityTests
swiftly run swift test --package-path Platforms/SwiftUI --filter SwiftUIHostTests.AccessibilityNodeMappingTests
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Platforms/SwiftUI/Tests/SwiftUIHostTests/SwiftUIHostAccessibilityTests.swift Platforms/SwiftUI/Tests/SwiftUIHostTests/AccessibilityNodeMappingTests.swift
git commit -m "test: cover SwiftUI host native focus flow"
```

## Task 5: Final Verification And Tracker Cleanup

**Files:**

- Modify: `active_work.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the platform package tests**

Run:

```bash
swiftly run swift test --package-path Platforms/SwiftUI
```

Expected: PASS.

- [ ] **Step 2: Run the repo gate**

Run:

```bash
bun run test
```

Expected: PASS.

- [ ] **Step 3: Manually verify native behavior**

Run a SwiftUI host example, enable VoiceOver, and move runtime focus between
two focusable controls. Expected: VoiceOver follows the newly focused overlay
element, announces its label/role, and does not traverse the hidden raster
terminal surface as character-grid text.

- [ ] **Step 4: Move completed active work to the changelog**

After implementation is committed, remove the SwiftUI native focus item from
`active_work.md` and add a concise `CHANGELOG.md` entry prefixed with the short
implementation commit hash. Link the ADR, overlay source, and host tests from
the changelog entry.

- [ ] **Step 5: Commit tracker cleanup**

```bash
git add active_work.md CHANGELOG.md
git commit -m "docs: close SwiftUI native focus active work"
```
