# TabView Style Consumer Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make public `TabViewStyle` powerful enough that built-in tab styles use the same public hooks available to package consumers.

**Architecture:** Replace the current fragment-oriented style API with a full-body style API. `TabView` continues to own selection, focus, metadata peeking, active-content laziness, and action registration; each `TabViewStyle` owns the complete visual composition through public configuration values, route wrappers, presentation metadata, and an active-content placeholder.

**Tech Stack:** Swift 6.3.1, SwiftTUIViews, SwiftTUICore, Swift Testing, repo validation through `swiftly run swift ...` and `bun run test`.

---

## Current Problem

The `FIXME` in `Sources/SwiftTUIViews/TabViews/BuiltinTabViewStyles.swift` points at `TabStripItemView`. That view switches over `TabStripChromeStyle` to render underline, literal-tabs, and powerline chrome. Removing only that private helper would clean up built-in code, but it would not give consumers parity because `Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift` still owns the strip `HStack`, pointer-route wrapping, overflow overlay placement, and content-slot layout.

The target state is stricter: if a built-in style can do something, an external `TabViewStyle` conformer can do it through public API. Built-ins may still use package-private implementation helpers for leaf drawing, but not private capabilities unavailable to consumers.

## File Structure

- Modify `Sources/SwiftTUIViews/TabViews/TabViewStyles.swift`
  - Replace fragment-associated types with a full-body `Body`.
  - Add `TabViewStyleBodyConfiguration`.
  - Add public route wrapper methods on tab item and overflow trigger/item configuration values.
  - Add a public active-content placeholder view.
- Modify `Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift`
  - Remove framework-owned strip/overflow/container host views.
  - Keep only type-erased style dispatch and shared route identity helpers.
- Modify `Sources/SwiftTUIViews/TabViews/TabView.swift`
  - Build both the presentation input configuration and full body configuration.
  - Register pointer handlers for all public route identities, independent of the chosen style layout.
  - Continue resolving only the active tab content.
- Modify `Sources/SwiftTUIViews/TabViews/BuiltinTabViewStyles.swift`
  - Rebuild underline, literal-tabs, and powerline styles as complete `makeBody` implementations.
  - Delete `TabStripItemView` and `TabStripChromeStyle`.
- Add `Tests/SwiftTUITests/TabViewStyleParityTests.swift`
  - Consumer full-body style can place active content anywhere and still select tabs by pointer.
  - Consumer overflow style can render its own trigger/menu and still use framework selection actions.
- Modify `Tests/SwiftTUITests/TabViewSurfaceTests.swift`
  - Keep existing built-in glyph and interaction coverage green.
- Modify `Scripts/check_public_surface_policies.sh`
  - Add guardrails that prevent built-ins from regressing to private fragment-hosted style power.
- Modify `docs/PUBLIC-API.md`
  - Document that `TabViewStyle` is a full-body container style and built-ins use the same public route/content hooks.
- Regenerate `docs/PUBLIC_API_BASELINE.md` and `docs/.public-api-baseline.txt` with `Scripts/generate_public_api_inventory.sh` after the API shape changes.

---

### Task 1: Lock Consumer-Parity Failures First

**Files:**
- Create: `Tests/SwiftTUITests/TabViewStyleParityTests.swift`

- [x] **Step 1: Add a failing custom full-body style test**

Add this test file. It should fail to compile before the API change because `TabViewStyleBodyConfiguration`, `configuration.content`, and routeable item configuration do not exist yet.

```swift
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TabViewStyleParityTests {
  @Test("consumer TabViewStyle owns full body layout and keeps tab routes active")
  func consumerStyleOwnsBodyLayoutAndRoutesTabs() throws {
    final class SelectionBox {
      var value = "home"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = pointerRegistry

    let surface = renderer.render(
      parityTabView(selection: selection)
        .tabViewStyle(ContentFirstConsumerTabViewStyle())
        .id(testIdentity("Tabs")),
      context: context,
      proposal: .init(width: 40, height: 6)
    )
    .rasterSurface.lines
    .prefix(3)
    .map(trimTrailingSpaces)

    #expect(
      Array(surface)
        == [
          "Home content",
          "[Home] Settings Logs",
          "",
        ]
    )

    let routeID = primaryRouteID(
      for: testIdentity("Tabs").child(.indexed("TabItem", index: 1))
    )
    #expect(pointerRegistry.hasHandler(routeID: routeID))
    #expect(
      pointerRegistry.dispatch(
        routeID: routeID,
        event: .init(kind: .down(.primary), location: .zero, targetRect: .zero)
      )
    )
    #expect(selectionBox.value == "settings")
  }

  @Test("consumer TabViewStyle owns overflow trigger and item layout")
  func consumerStyleOwnsOverflowLayoutAndRoutesOverflowItems() {
    final class SelectionBox {
      var value = "one"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = pointerRegistry

    _ = renderer.render(
      overflowParityTabView(selection: selection)
        .tabViewStyle(OverflowConsumerTabViewStyle())
        .id(testIdentity("Tabs")),
      context: context,
      proposal: .init(width: 30, height: 8)
    )

    let triggerRouteID = primaryRouteID(
      for: testIdentity("Tabs").child(.named("TabOverflowTrigger"))
    )
    #expect(pointerRegistry.hasHandler(routeID: triggerRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: triggerRouteID,
        event: .init(kind: .down(.primary), location: .zero, targetRect: .zero)
      )
    )

    let expanded = renderer.render(
      overflowParityTabView(selection: selection)
        .tabViewStyle(OverflowConsumerTabViewStyle())
        .id(testIdentity("Tabs")),
      context: context,
      proposal: .init(width: 30, height: 8)
    )
    .rasterSurface.lines
    .prefix(5)
    .map(trimTrailingSpaces)

    #expect(
      Array(expanded)
        == [
          "One More",
          "> Two",
          "> Three",
          "One content",
          "",
        ]
    )

    let overflowItemRouteID = primaryRouteID(
      for: testIdentity("Tabs").child(.indexed("TabOverflowItem", index: 2))
    )
    #expect(pointerRegistry.hasHandler(routeID: overflowItemRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: overflowItemRouteID,
        event: .init(kind: .down(.primary), location: .zero, targetRect: .zero)
      )
    )
    #expect(selectionBox.value == "three")
  }
}

private func parityTabView(
  selection: Binding<String>
) -> some View {
  TabView(selection: selection) {
    Tab("Home", value: "home") {
      Text("Home content")
    }

    Tab("Settings", value: "settings") {
      Text("Settings content")
    }

    Tab("Logs", value: "logs") {
      Text("Logs content")
    }
  }
}

private func overflowParityTabView(
  selection: Binding<String>
) -> some View {
  TabView(selection: selection) {
    Tab("One", value: "one") {
      Text("One content")
    }

    Tab("Two", value: "two") {
      Text("Two content")
    }

    Tab("Three", value: "three") {
      Text("Three content")
    }
  }
}

private struct ContentFirstConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "ContentFirstConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.content
      HStack(alignment: .top, spacing: 1) {
        ForEach(configuration.items.indices, id: \.self) { index in
          let item = configuration.items[index]
          item.route {
            Text(item.isSelected ? "[\(item.label.displayText)]" : item.label.displayText)
          }
        }
      }
    }
  }
}

private struct OverflowConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "OverflowConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    let overflowIndices = Array(configuration.options.indices.dropFirst())
    let selectedOverflowIndex =
      configuration.selectedIndex.flatMap { overflowIndices.contains($0) ? $0 : nil }
    let focusedOverflowIndex =
      configuration.focusedIndex.flatMap { overflowIndices.contains($0) ? $0 : nil }
    return .init(
      stripHeight: 1,
      visibleOptionIndices: [0],
      overflowMenu: .init(
        triggerLeadingWidth: 4,
        overflowIndices: overflowIndices,
        isExpanded: configuration.isOverflowMenuExpanded,
        selectedOverflowIndex: selectedOverflowIndex,
        focusedOverflowIndex: focusedOverflowIndex,
        triggerLabel: "More"
      )
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(configuration.visibleItems.indices, id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            Text(item.label.displayText)
          }
        }

        if let trigger = configuration.overflowTrigger {
          trigger.route {
            Text(trigger.label)
          }
        }
      }

      if configuration.overflowTrigger?.isExpanded == true {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(configuration.overflowItems.indices, id: \.self) { index in
            let item = configuration.overflowItems[index]
            item.overflowRoute {
              Text("> \(item.label.displayText)")
            }
          }
        }
      }

      configuration.content
    }
  }
}

private func trimTrailingSpaces(
  _ line: String
) -> String {
  String(line.reversed().drop(while: { $0 == " " }).reversed())
}
```

- [x] **Step 2: Run the focused test and confirm the expected compile failure**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.TabViewStyleParityTests
```

Expected: compile failure mentioning missing `TabViewStyleBodyConfiguration` or missing `makeBody(configuration:)` conformance.

- [ ] **Step 3: Commit the failing test**

```bash
git add Tests/SwiftTUITests/TabViewStyleParityTests.swift
git commit -m "test: lock tab view style consumer parity"
```

---

### Task 2: Replace Fragment Style API With Full-Body Configuration

**Files:**
- Modify: `Sources/SwiftTUIViews/TabViews/TabViewStyles.swift`

- [x] **Step 1: Update the public protocol**

Replace the existing `TabViewStyle` associated types and fragment methods with this shape:

```swift
public protocol TabViewStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @ViewBuilder @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> Body
}
```

Keep the existing default `snapshotLabel` implementation.

- [x] **Step 2: Add routeable item configuration**

Extend `TabViewStyleItemConfiguration` with package route identity storage and public route helpers:

```swift
public struct TabViewStyleItemConfiguration: Sendable {
  public var index: Int
  public var label: TabItemLabel
  public var isSelected: Bool
  public var isFocused: Bool
  package var controlIdentity: Identity?

  public init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    controlIdentity = nil
  }

  package init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool,
    controlIdentity: Identity
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.controlIdentity = controlIdentity
  }

  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabItemIdentity(for: controlIdentity, index: index),
        content: content()
      )
    } else {
      content()
    }
  }

  @ViewBuilder @MainActor
  public func overflowRoute<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabOverflowItemIdentity(for: controlIdentity, index: index),
        content: content()
      )
    } else {
      content()
    }
  }
}
```

- [x] **Step 3: Add routeable overflow trigger configuration**

Extend `TabViewOverflowTriggerConfiguration` with package route identity storage and a public route helper:

```swift
public struct TabViewOverflowTriggerConfiguration: Sendable {
  public var label: String
  public var isSelected: Bool
  public var isFocused: Bool
  public var isExpanded: Bool
  public var overflowIndices: [Int]
  public var leadingWidth: Int
  package var controlIdentity: Identity?

  public init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
    controlIdentity = nil
  }

  package init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int,
    controlIdentity: Identity
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
    self.controlIdentity = controlIdentity
  }

  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabOverflowTriggerIdentity(for: controlIdentity),
        content: content()
      )
    } else {
      content()
    }
  }
}
```

- [x] **Step 4: Add active content and body configuration**

Add this new public configuration type below `TabViewStyleConfiguration`:

```swift
public struct TabViewStyleBodyConfiguration: Sendable {
  public struct Content: View, Sendable {
    package var activeContentIndex: Int?
    package var payload: DeferredViewPayload?

    package init(
      activeContentIndex: Int?,
      payload: DeferredViewPayload?
    ) {
      self.activeContentIndex = activeContentIndex
      self.payload = payload
    }

    public var body: some View {
      TabViewStyleActiveContentView(
        activeContentIndex: activeContentIndex,
        payload: payload
      )
    }
  }

  public var options: [TabViewStyleOption]
  public var items: [TabViewStyleItemConfiguration]
  public var visibleItems: [TabViewStyleItemConfiguration]
  public var overflowItems: [TabViewStyleItemConfiguration]
  public var selectedIndex: Int?
  public var focusedIndex: Int?
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var availableWidth: Int
  public var isOverflowMenuExpanded: Bool
  public var presentation: TabViewStylePresentation
  public var overflowTrigger: TabViewOverflowTriggerConfiguration?
  public var content: Content

  package init(
    styleConfiguration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    items: [TabViewStyleItemConfiguration],
    overflowTrigger: TabViewOverflowTriggerConfiguration?,
    content: Content
  ) {
    options = styleConfiguration.options
    self.items = items
    visibleItems = presentation.visibleOptionIndices.compactMap { index in
      items.indices.contains(index) ? items[index] : nil
    }
    overflowItems = presentation.overflowMenu?.overflowIndices.compactMap { index in
      items.indices.contains(index) ? items[index] : nil
    } ?? []
    selectedIndex = styleConfiguration.selectedIndex
    focusedIndex = styleConfiguration.focusedIndex
    isFocused = styleConfiguration.isFocused
    showsFocusEffect = styleConfiguration.showsFocusEffect
    styleEnvironment = styleConfiguration.styleEnvironment
    availableWidth = styleConfiguration.availableWidth
    isOverflowMenuExpanded = styleConfiguration.isOverflowMenuExpanded
    self.presentation = presentation
    self.overflowTrigger = overflowTrigger
    self.content = content
  }
}
```

- [x] **Step 5: Add the active-content placeholder implementation**

Add this package implementation in the same file:

```swift
package struct TabViewStyleActiveContentView: PrimitiveView, ResolvableView {
  let activeContentIndex: Int?
  let payload: DeferredViewPayload?

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    guard let payload else {
      return []
    }

    return [
      resolveView(
        DeferredPayloadView(payload: payload),
        in: context.indexedChild(
          kind: .init(rawValue: "TabContentPayload"),
          index: activeContentIndex ?? 0
        )
      )
    ]
  }
}
```

- [x] **Step 6: Run the focused compile**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.TabViewStyleParityTests
```

Expected: compile advances past the missing public API and fails in existing built-in conformances or hosting code.

---

### Task 3: Simplify Type-Erased Style Hosting

**Files:**
- Modify: `Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift`
- Modify: `Sources/SwiftTUIViews/TabViews/TabViewStyles.swift`

- [x] **Step 1: Change type-erased resolve dispatch**

Change `AnyTabViewStyleBox.resolveBody` and `AnyTabViewStyle.resolveBody` to accept `TabViewStyleBodyConfiguration` instead of the active-content payload pieces:

```swift
@MainActor
package func resolveBody(
  configuration: TabViewStyleBodyConfiguration,
  in context: ResolveContext
) -> ResolvedNode {
  box.resolveBody(
    configuration: configuration,
    in: context
  )
}
```

The box protocol should match:

```swift
protocol AnyTabViewStyleBox: Sendable {
  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func resolveBody(
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}
```

- [x] **Step 2: Resolve the style body directly**

Replace `ConcreteAnyTabViewStyleBox.resolveBody` with direct body resolution:

```swift
@MainActor
func resolveBody(
  configuration: TabViewStyleBodyConfiguration,
  in context: ResolveContext
) -> ResolvedNode {
  normalizeResolvedElements(
    resolveViewElements(
      style.makeBody(configuration: configuration),
      in: context
    ),
    in: context
  )
}
```

- [x] **Step 3: Delete fixed framework-hosted style layout**

Delete these private types from `TabViewStyleHosting.swift`:

```swift
TabViewLayoutSubviewRole
TabViewLayoutSubviewRoleKey
tabViewContainerAnyLayout
TabViewContainerLayout
TabViewStyleBodyHost
TabViewLayoutSlotNode
FrameworkHostedTabStripView
FrameworkHostedTabOverflowSlotView
FrameworkHostedTabOverflowMenuView
```

Keep these helper functions in `TabViewStyleHosting.swift`:

```swift
tabItemIdentity(for:index:)
tabOverflowTriggerIdentity(for:)
tabOverflowItemIdentity(for:index:)
```

- [x] **Step 4: Run the focused compile**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.TabViewStyleParityTests
```

Expected: compile fails in `TabView.swift` because it still calls the old `resolveBody` signature.

---

### Task 4: Build Body Configuration in TabView

**Files:**
- Modify: `Sources/SwiftTUIViews/TabViews/TabView.swift`

- [x] **Step 1: Create body configuration before resolving the style**

In `resolvedNode(in:)`, replace the old `tabStyle.resolveBody(...)` call with this flow:

```swift
let styleItems = options.indices.map { index in
  TabViewStyleItemConfiguration(
    index: index,
    label: options[index].label,
    isSelected: selectedIndex == index,
    isFocused: (isFocused && showsFocusEffect) && focusedIndex == index,
    controlIdentity: context.identity
  )
}
let overflowTrigger = stylePresentation.overflowMenu.map { overflow in
  TabViewOverflowTriggerConfiguration(
    label: overflow.triggerLabel,
    isSelected: overflow.isTriggerSelected,
    isFocused: overflow.isTriggerFocused,
    isExpanded: overflow.isExpanded,
    overflowIndices: overflow.overflowIndices,
    leadingWidth: overflow.triggerLeadingWidth,
    controlIdentity: context.identity
  )
}
let bodyConfiguration = TabViewStyleBodyConfiguration(
  styleConfiguration: styleConfiguration,
  presentation: stylePresentation,
  items: styleItems,
  overflowTrigger: overflowTrigger,
  content: .init(
    activeContentIndex: selectedIndex,
    payload: activeContentPayload
  )
)
let child = tabStyle.resolveBody(
  configuration: bodyConfiguration,
  in: context.child(component: .named("TabBody"))
)
```

- [x] **Step 2: Register route handlers independent of style layout**

Replace the visible-only pointer registration loop with all item routes:

```swift
for index in options.indices {
  let routeID = primaryRouteID(
    for: tabItemIdentity(
      for: context.identity,
      index: index
    )
  )
  context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
    guard case .down(.primary) = event.kind else {
      return false
    }

    return withAuthoringContext(dynamicPropertyScope) {
      setStoredTabOverflowMenuExpanded(false, in: ownerNode)
      setStoredFocusedTabIndex(index, in: ownerNode)
      return setBoundSelection(binding, to: options[index].tag)
    }
  }
}
```

Register overflow item routes for all options as well:

```swift
for index in options.indices {
  let routeID = primaryRouteID(
    for: tabOverflowItemIdentity(
      for: context.identity,
      index: index
    )
  )
  context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
    guard case .down(.primary) = event.kind else {
      return false
    }

    return withAuthoringContext(dynamicPropertyScope) {
      setStoredFocusedTabIndex(index, in: ownerNode)
      setStoredTabOverflowMenuExpanded(false, in: ownerNode)
      return setBoundSelection(binding, to: options[index].tag)
    }
  }
}
```

Keep the overflow-trigger handler, but register it whenever the style has an overflow presentation.

- [x] **Step 3: Run the parity tests**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.TabViewStyleParityTests
```

Expected: compile now fails only in built-in style conformances.

---

### Task 5: Rebuild Built-In Styles Through Public Full-Body API

**Files:**
- Modify: `Sources/SwiftTUIViews/TabViews/BuiltinTabViewStyles.swift`

- [x] **Step 1: Add full-body implementations for automatic and underline**

`AutomaticTabViewStyle.makeBody` and `UnderlineTabViewStyle.makeBody` should both delegate to underline chrome:

```swift
@MainActor
public func makeBody(
  configuration: TabViewStyleBodyConfiguration
) -> some View {
  UnderlineTabStyleBody(configuration: configuration)
}
```

Add this style body:

```swift
private struct UnderlineTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(configuration.visibleItems.indices, id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            UnderlineTabStyleItemView(
              configuration: configuration,
              item: item
            )
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}
```

- [x] **Step 2: Add full-body implementation for powerline**

`PowerlineTabViewStyle.makeBody` should return:

```swift
@MainActor
public func makeBody(
  configuration: TabViewStyleBodyConfiguration
) -> some View {
  PowerlineTabStyleBody(configuration: configuration)
}
```

Add:

```swift
private struct PowerlineTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(configuration.visibleItems.indices, id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            PowerlineTabStyleItemView(
              configuration: configuration,
              item: item
            )
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}
```

- [x] **Step 3: Add full-body implementation for literal tabs**

`LiteralTabsTabViewStyle.makeBody` should return:

```swift
@MainActor
public func makeBody(
  configuration: TabViewStyleBodyConfiguration
) -> some View {
  LiteralTabsTabStyleBody(configuration: configuration)
}
```

Add:

```swift
private struct LiteralTabsTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 0) {
          ForEach(configuration.visibleItems.indices, id: \.self) { index in
            let item = configuration.visibleItems[index]
            item.route {
              LiteralTabsTabStyleItemView(
                configuration: configuration,
                item: item
              )
            }
          }

          if let trigger = configuration.overflowTrigger {
            trigger.route {
              LiteralTabsOverflowTriggerView(
                configuration: configuration,
                trigger: trigger
              )
            }
          }

          Spacer(minLength: 0)
        }
        .frame(height: configuration.presentation.stripHeight, alignment: .leading)
        .background {
          LiteralTabsStripBackgroundView(presentation: configuration.presentation)
        }

        configuration.content
      }

      if configuration.overflowTrigger?.isExpanded == true {
        HStack(alignment: .top, spacing: 0) {
          Spacer(minLength: 0)
            .frame(width: configuration.overflowTrigger?.leadingWidth ?? 0)
          LiteralTabsOverflowMenuView(configuration: configuration)
          Spacer(minLength: 0)
        }
        .padding(
          .init(
            top: configuration.presentation.stripHeight,
            leading: 0,
            bottom: 0,
            trailing: 0
          )
        )
      }
    }
  }
}
```

- [x] **Step 4: Add literal overflow menu body**

```swift
private struct LiteralTabsOverflowMenuView: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(configuration.overflowItems.indices, id: \.self) { index in
        let item = configuration.overflowItems[index]
        item.overflowRoute {
          LiteralTabsOverflowMenuRowView(
            configuration: configuration,
            item: item,
            overflowIndices: configuration.presentation.overflowMenu?.overflowIndices ?? []
          )
        }
      }
    }
    .padding(configuration.presentation.overflowMenu?.contentPadding ?? .zero)
    .background {
      if let overflow = configuration.presentation.overflowMenu,
        let backgroundStyle = overflow.backgroundStyle
      {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .inset(by: overflow.borderInset)
          .fill(backgroundStyle)
      }
    }
    .overlay {
      if let overflow = configuration.presentation.overflowMenu,
        let borderStyle = overflow.borderStyle
      {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .strokeBorder(borderStyle)
      }
    }
    .fixedSize(horizontal: true, vertical: true)
  }
}
```

- [x] **Step 5: Delete the shared private chrome switch**

Delete:

```swift
TabStripChromeStyle
TabStripItemView
tabItemPrimaryChrome(...)
tabItemRuleChrome(...)
```

Keep leaf helpers such as:

```swift
underlineTabItem(...)
underlineRuleSegment(...)
literalTabItem(...)
literalTabRuleSegment(...)
literalTabBottomChrome(...)
powerlineTabItem(...)
powerlineSeparatorStyle(...)
literalTabOverflowTriggerLabel(...)
literalTabOverflowMenuWidth(...)
literalTabWidth(...)
```

- [x] **Step 6: Update item views to build their own layout directly**

`UnderlineTabStyleItemView.body` should be:

```swift
var body: some View {
  VStack(alignment: .leading, spacing: 0) {
    underlineTabItem(
      label: item.label.displayText,
      isSelected: item.isSelected,
      tone: .accent
    )
    underlineRuleSegment(
      label: item.label.displayText,
      isSelected: item.isSelected,
      isFocused: item.isFocused,
      tone: .accent
    )
  }
  .background {
    if item.isFocused {
      Rectangle()
        .fill(AnyShapeStyle(.terminalSurface(.accent)))
    }
  }
}
```

`LiteralTabsTabStyleItemView.body` should be:

```swift
var body: some View {
  VStack(alignment: .leading, spacing: 0) {
    literalTabItem(label: item.label.displayText)
    literalTabRuleSegment(
      label: item.label.displayText,
      isSelected: item.isSelected,
      tone: .accent
    )
    literalTabBottomChrome(
      label: item.label.displayText,
      isSelected: item.isSelected,
      tone: .accent
    )
  }
  .background {
    if item.isFocused {
      Rectangle()
        .fill(AnyShapeStyle(.terminalSurface(.accent)))
    }
  }
  .fixedSize(horizontal: true, vertical: true)
}
```

`LiteralTabsOverflowTriggerView.body` should mirror `LiteralTabsTabStyleItemView`, using `trigger.label`, `trigger.isSelected`, and `trigger.isFocused`.

`PowerlineTabStyleItemView.body` should be:

```swift
var body: some View {
  powerlineTabItem(
    label: item.label.displayText,
    isSelected: item.isSelected,
    showsTrailingSeparator: item.index < configuration.items.count - 1,
    trailingSeparatorStyle: powerlineSeparatorStyle(
      index: item.index,
      activeIndex: configuration.selectedIndex ?? 0
    ),
    tone: .accent,
    styleEnvironment: configuration.styleEnvironment
  )
  .background {
    if item.isFocused {
      Rectangle()
        .fill(AnyShapeStyle(.terminalSurface(.accent)))
    }
  }
}
```

- [x] **Step 7: Run built-in surface tests**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests
```

Expected: pass with unchanged literal-tabs, underline, powerline, overflow, focus, and pointer behavior.

---

### Task 6: Add Guardrails and Public Documentation

**Files:**
- Modify: `Scripts/check_public_surface_policies.sh`
- Modify: `docs/PUBLIC-API.md`
- Modify: `docs/PUBLIC_API_BASELINE.md`
- Modify: `docs/.public-api-baseline.txt`

- [x] **Step 1: Add policy checks for private TabView style hosts**

Add these checks after the existing TabViewStyle checks:

```bash
if rg -n -P --quiet -- 'TabStripItemView|TabStripChromeStyle' Sources/SwiftTUIViews/TabViews/BuiltinTabViewStyles.swift; then
  fail "Built-in TabView styles should not share a private chrome-switching TabStripItemView."
fi

if rg -n -P --quiet -- 'FrameworkHostedTabStripView|FrameworkHostedTabOverflowSlotView|FrameworkHostedTabOverflowMenuView|TabViewStyleBodyHost' Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift; then
  fail "TabViewStyleHosting should not own private strip or overflow layout; TabViewStyle must own full body composition."
fi

if rg -n -P --quiet -- 'makeTabBody|makeOverflowTriggerBody|makeOverflowItemBody|makeStripBackground' Sources/SwiftTUIViews/TabViews/TabViewStyles.swift; then
  fail "TabViewStyle should expose full-body composition rather than fragment-only hooks."
fi
```

- [x] **Step 2: Update public API docs**

In `docs/PUBLIC-API.md`, under `Authoring style families`, add:

```markdown
- `TabViewStyle` is a full-body container style. Styles receive routeable tab
  item configurations, a routeable overflow trigger, routeable overflow item
  configurations, presentation metadata, and an active-content placeholder.
  Built-in tab styles are implemented through those same public hooks.
```

- [x] **Step 3: Regenerate the public API baseline**

Run:

```bash
Scripts/generate_public_api_inventory.sh
```

Expected: `docs/PUBLIC_API_BASELINE.md` and `docs/.public-api-baseline.txt` reflect the new full-body `TabViewStyle` API.

- [ ] **Step 4: Commit docs and guardrails**

```bash
git add Scripts/check_public_surface_policies.sh docs/PUBLIC-API.md docs/PUBLIC_API_BASELINE.md docs/.public-api-baseline.txt
git commit -m "docs: document full body tab view styles"
```

---

### Task 7: Final Validation and Cleanup

**Files:**
- Verify: `Sources/SwiftTUIViews/TabViews/TabViewStyles.swift`
- Verify: `Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift`
- Verify: `Sources/SwiftTUIViews/TabViews/BuiltinTabViewStyles.swift`
- Verify: `Tests/SwiftTUITests/TabViewStyleParityTests.swift`
- Verify: `Tests/SwiftTUITests/TabViewSurfaceTests.swift`

- [x] **Step 1: Run focused parity tests**

```bash
swiftly run swift test --filter SwiftTUITests.TabViewStyleParityTests
```

Expected: pass.

- [x] **Step 2: Run focused built-in surface tests**

```bash
swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests
```

Expected: pass.

- [x] **Step 3: Run lifecycle tests to protect active-content laziness**

```bash
swiftly run swift test --filter SwiftTUITests.TabViewLifecycleTests
```

Expected: pass. Inactive tab `.onAppear` and `.task` tests must remain green.

- [x] **Step 4: Run public policy script through the repo gate**

```bash
bun run test
```

Expected: pass.

- [x] **Step 5: Check for forbidden private style power**

Run:

```bash
rg -n "TabStripItemView|TabStripChromeStyle|FrameworkHostedTabStripView|FrameworkHostedTabOverflowSlotView|FrameworkHostedTabOverflowMenuView|makeTabBody|makeOverflowTriggerBody|makeOverflowItemBody|makeStripBackground" Sources/SwiftTUIViews/TabViews
```

Expected: no matches.

- [ ] **Step 6: Commit implementation**

```bash
git add Sources/SwiftTUIViews/TabViews Tests/SwiftTUITests Scripts/check_public_surface_policies.sh docs/PUBLIC-API.md docs/PUBLIC_API_BASELINE.md docs/.public-api-baseline.txt
git commit -m "feat: make tab view styles own full body composition"
```

---

## Self-Review

- Spec coverage: The plan addresses consumer parity by moving full body composition, route wrappers, overflow trigger/item routes, and active content into public style configuration. It also requires built-ins to use those same hooks.
- Private API check: The plan removes `TabStripItemView`, `TabStripChromeStyle`, and framework-hosted strip/overflow layout, then adds policy checks to prevent regression.
- Active-content laziness: The active-content placeholder preserves the existing deferred payload path and indexes the selected tab content under `TabContentPayload`.
- Validation: Focused parity, surface, lifecycle, and full repo gate commands are included.
