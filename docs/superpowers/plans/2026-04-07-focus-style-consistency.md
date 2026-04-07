# Focus Style Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make focus treatments visible in plain-text terminal modes using border weight escalation — heavier stroke characters for focused controls.

**Architecture:** Container controls promote their border from single/rounded to heavy (`StrokeStyle.thick`) when focused. TabView adds a heavy top rule above the tab strip. Plain-style buttons and links gain a `controlFocusRow` rail. All existing color treatments remain as color-mode reinforcement.

**Tech Stack:** Swift, TerminalUI framework internals (View layer)

---

### Task 1: Picker container borders — segmented, inline, radio group

**Files:**
- Modify: `Sources/View/Controls/PickerRendering.swift:194-197` (inline), `417-420` (segmented), `466-469` (radio group)
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

Each picker style has a `.overlay { RoundedRectangle(...).chromeStrokeBorder(...) }` that needs a focused stroke style. The `isFocused` and `showsFocusEffect` booleans are already available in each method's scope.

- [ ] **Step 1: Write the failing test**

Add to `FocusTransitionTests.swift`:

```swift
@Test("segmented picker uses heavy border when focused")
func segmentedPickerUsesHeavyBorderWhenFocused() {
  let unfocusedArtifacts = renderArtifacts()
  let focusRegions = unfocusedArtifacts.semanticSnapshot.focusRegions
  guard let pickerRegion = focusRegions.first(where: { $0.identity != testIdentity("Tabs") })
  else {
    Issue.record("Picker focus region not found")
    return
  }

  let pickerFocusedArtifacts = renderArtifacts(focusedIdentity: pickerRegion.identity)
  let focusedLines = pickerFocusedArtifacts.rasterSurface.lines

  // Heavy border characters should appear when focused
  let hasHeavyBorder = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
  #expect(hasHeavyBorder, "Focused segmented picker should use heavy border characters (┏┗)")

  // Unfocused should NOT have heavy border
  let unfocusedLines = unfocusedArtifacts.rasterSurface.lines
  let unfocusedHasHeavy = unfocusedLines.contains { $0.contains("┏") || $0.contains("┗") }
  #expect(!unfocusedHasHeavy, "Unfocused picker should not use heavy border characters")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter segmentedPickerUsesHeavyBorderWhenFocused`
Expected: FAIL — focused picker still uses `╭╰` not `┏┗`

- [ ] **Step 3: Add heavy stroke to segmented picker overlay**

In `PickerRendering.swift`, in `segmentedPickerBody`, change the overlay (lines 416-420):

```swift
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
        )
      }
```

- [ ] **Step 4: Add heavy stroke to inline picker overlay**

In `PickerRendering.swift`, in `inlinePickerBody`, change the overlay (lines 193-197):

```swift
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
        )
      }
```

- [ ] **Step 5: Add heavy stroke to radio group picker overlay**

In `PickerRendering.swift`, in `radioGroupPickerBody`, change the overlay (lines 465-469):

```swift
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
        )
      }
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter FocusTransitionTests`
Expected: All pass including the new heavy border test

- [ ] **Step 7: Commit**

```
git add Sources/View/Controls/PickerRendering.swift Tests/TerminalUITests/FocusTransitionTests.swift
git commit -m "feat: picker focus uses heavy border for plain-text visibility"
```

---

### Task 2: TextField, SecureField, TextEditor container borders

**Files:**
- Modify: `Sources/View/Controls/ValueControls.swift:197-200` (textEntryFieldBody)
- Modify: `Sources/View/Controls/SelectionAndValueSupport.swift:706-709` (textEditorBody)
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

Both `textEntryFieldBody` and `textEditorBody` receive a `chrome: ControlChrome` but not `isFocused`. The chrome already reflects focus (border color changes), but to pass a focused stroke style we need a `focusActive` boolean.

- [ ] **Step 1: Write the failing test**

Add to `FocusTransitionTests.swift`:

```swift
@Test("focused TextField uses heavy border")
func focusedTextFieldUsesHeavyBorder() {
  var env = EnvironmentValues()
  env.focusedIdentity = testIdentity("Field")

  let focused = DefaultRenderer().render(
    TextField("Name", text: .constant("hello"))
      .textFieldStyle(.roundedBorder)
      .id(testIdentity("Field")),
    context: .init(identity: testIdentity("Root"), environmentValues: env),
    proposal: .init(width: 20, height: 4)
  )

  let focusedLines = focused.rasterSurface.lines
  let hasHeavy = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
  #expect(hasHeavy, "Focused TextField should use heavy border")

  let unfocused = DefaultRenderer().render(
    TextField("Name", text: .constant("hello"))
      .textFieldStyle(.roundedBorder)
      .id(testIdentity("Field")),
    context: .init(identity: testIdentity("Root")),
    proposal: .init(width: 20, height: 4)
  )

  let unfocusedLines = unfocused.rasterSurface.lines
  let unfocusedHasHeavy = unfocusedLines.contains { $0.contains("┏") || $0.contains("┗") }
  #expect(!unfocusedHasHeavy, "Unfocused TextField should not use heavy border")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter focusedTextFieldUsesHeavyBorder`
Expected: FAIL

- [ ] **Step 3: Add focusActive parameter to textEntryFieldBody**

In `ValueControls.swift`, change the function signature and overlay (starting at line 163):

```swift
package func textEntryFieldBody<Label: View>(
  displayText: String,
  isShowingPrompt: Bool,
  label: Label,
  showsLabel: Bool,
  style: TextFieldStyle,
  chrome: ControlChrome,
  placeholderStyle: AnyShapeStyle,
  focusActive: Bool = false
) -> some View {
```

And change the overlay inside `fieldContent()` (around line 196):

```swift
        .overlay {
          RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
            chrome.borderStyle,
            style: focusActive ? .thick : .init(),
            backgroundStyle: chrome.borderBackgroundStyle
          )
        }
```

- [ ] **Step 4: Pass focusActive from TextField**

In `ValueControls.swift`, in `TextField.resolvedNode` (around line 294), pass the new parameter:

```swift
    let child = textEntryFieldBody(
      displayText: entryText.displayText,
      isShowingPrompt: entryText.isShowingPrompt,
      label: label,
      showsLabel: showsLabel,
      style: effectiveStyle,
      chrome: chrome,
      placeholderStyle: styleEnvironment.themeStyle(for: .placeholder),
      focusActive: isFocused && showsFocusEffect
    ).resolve(
```

- [ ] **Step 5: Pass focusActive from SecureField**

In `SecureField.swift`, the `resolvedNode` method (around line 63) also calls `textEntryFieldBody`. Pass the same parameter:

```swift
    let child = textEntryFieldBody(
      displayText: entryText.displayText,
      isShowingPrompt: entryText.isShowingPrompt,
      label: label,
      showsLabel: showsLabel,
      style: effectiveStyle,
      chrome: chrome,
      placeholderStyle: styleEnvironment.themeStyle(for: .placeholder),
      focusActive: isFocused && showsFocusEffect
    ).resolve(
```

- [ ] **Step 6: Add focusActive parameter to textEditorBody**

In `SelectionAndValueSupport.swift`, change `textEditorBody` (line 688):

```swift
package func textEditorBody(
  displayText: String,
  chrome: ControlChrome,
  scrollPosition: Binding<ScrollPosition>,
  focusActive: Bool = false
) -> some View {
```

And change its overlay (around line 706):

```swift
  .overlay {
    RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
      chrome.borderStyle,
      style: focusActive ? .thick : .init(),
      backgroundStyle: chrome.borderBackgroundStyle
    )
  }
```

- [ ] **Step 7: Pass focusActive from TextEditor**

In `TextEditor.swift`, the `resolvedNode` method (around line 49) calls `textEditorBody`. Pass the parameter:

```swift
    let child = textEditorBody(
      displayText: entryText.displayText,
      chrome: chrome,
      scrollPosition: $scrollPosition,
      focusActive: isFocused && showsFocusEffect
    ).resolve(
```

- [ ] **Step 8: Run tests**

Run: `swift test --filter FocusTransitionTests`
Expected: All pass

- [ ] **Step 9: Commit**

```
git add Sources/View/Controls/ValueControls.swift Sources/View/Controls/SelectionAndValueSupport.swift Sources/View/Input/SecureField.swift Sources/View/Input/TextEditor.swift Tests/TerminalUITests/FocusTransitionTests.swift
git commit -m "feat: text input focus uses heavy border for plain-text visibility"
```

---

### Task 3: Bordered button border

**Files:**
- Modify: `Sources/View/Controls/Button.swift:249-268` (ButtonChromeBorder)
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

`ButtonChromeBorder` draws the border for `.bordered` and `.borderedProminent` buttons. It needs a `focusActive` boolean to pass `.thick` stroke style.

- [ ] **Step 1: Write the failing test**

Add to `FocusTransitionTests.swift`:

```swift
@Test("focused bordered button uses heavy border")
func focusedBorderedButtonUsesHeavyBorder() {
  var env = EnvironmentValues()
  env.focusedIdentity = testIdentity("Btn")

  let focused = DefaultRenderer().render(
    Button("Submit") {}
      .buttonStyle(.bordered)
      .id(testIdentity("Btn")),
    context: .init(identity: testIdentity("Root"), environmentValues: env),
    proposal: .init(width: 14, height: 3)
  )

  let focusedLines = focused.rasterSurface.lines
  let hasHeavy = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
  #expect(hasHeavy, "Focused bordered button should use heavy border")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter focusedBorderedButtonUsesHeavyBorder`
Expected: FAIL

- [ ] **Step 3: Add focusActive to ButtonChromeBorder**

In `Button.swift`, add the `focusActive` field and use it in the stroke call:

```swift
private struct ButtonChromeBorder: View {
  var chrome: ControlChrome
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape
  var focusActive: Bool

  @ViewBuilder
  var body: some View {
    let strokeStyle: StrokeStyle = focusActive ? .thick : .init()
    switch (borderShape, prominence) {
    case (.roundedRectangle, _), (.automatic, .increased):
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    default:
      Rectangle().chromeStrokeBorder(
        chrome.borderStyle,
        style: strokeStyle,
        backgroundStyle: chrome.borderBackgroundStyle
      )
    }
  }
}
```

- [ ] **Step 4: Pass focusActive from ButtonChromeBody**

In `ButtonChromeBody`, add the `focusActive` field and pass it through:

```swift
private struct ButtonChromeBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var buttonStyle: ButtonStyle
  var prominence: ControlProminence
  var borderShape: ButtonBorderShape
  var focusActive: Bool
```

And in its `body`, update the `ButtonChromeBorder` construction (around line 208):

```swift
          ButtonChromeBorder(
            chrome: chrome,
            prominence: prominence,
            borderShape: borderShape,
            focusActive: focusActive
          )
```

- [ ] **Step 5: Pass focusActive from Button.resolvedNode**

In `Button.resolvedNode` (around line 116), pass the value when constructing `ButtonChromeBody`:

```swift
    case .automatic, .bordered, .borderedProminent:
      child = ButtonChromeBody(
        label: label,
        chrome: chrome,
        buttonStyle: buttonStyle,
        prominence: effectiveProminence,
        borderShape: context.environmentValues.buttonBorderShape,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter FocusTransitionTests`
Expected: All pass

- [ ] **Step 7: Commit**

```
git add Sources/View/Controls/Button.swift Tests/TerminalUITests/FocusTransitionTests.swift
git commit -m "feat: bordered button focus uses heavy border for plain-text visibility"
```

---

### Task 4: Menu expanded container border

**Files:**
- Modify: `Sources/View/Controls/MenuRendering.swift:26-29`
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

The Menu's expanded dropdown has a `chromeStrokeBorder`. The `isFocused` boolean is already available in `menuBody`'s scope.

- [ ] **Step 1: Add heavy stroke to menu expanded overlay**

In `MenuRendering.swift`, change the overlay (lines 25-29):

```swift
          .overlay {
            RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
              chrome.borderStyle,
              style: isFocused ? .thick : .init(),
              backgroundStyle: chrome.borderBackgroundStyle
            )
          }
```

- [ ] **Step 2: Run full test suite to verify no regression**

Run: `swift test`
Expected: All 584+ tests pass

- [ ] **Step 3: Commit**

```
git add Sources/View/Controls/MenuRendering.swift
git commit -m "feat: menu expanded dropdown uses heavy border when focused"
```

---

### Task 5: TabView focus top rule

**Files:**
- Modify: `Sources/View/NavigationViews/TabView.swift:156-193`
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

Add a heavy `━` rule spanning the tab strip width above the tab labels when `focusActive` is true. This sits inside the existing VStack, before the HStack of tab items.

- [ ] **Step 1: Write the failing test**

Add to `FocusTransitionTests.swift`:

```swift
@Test("focused TabView adds heavy top rule above tab strip")
func focusedTabViewAddsTopRule() {
  var env = EnvironmentValues()
  env.focusedIdentity = testIdentity("Tabs")

  let focused = DefaultRenderer().render(
    Self.tabViewWithPicker(),
    context: .init(identity: testIdentity("Root"), environmentValues: env),
    proposal: .init(width: 50, height: 10)
  )

  let focusedLines = focused.rasterSurface.lines
  // The first line should be the heavy rule when focused
  let firstLine = focusedLines.first ?? ""
  let hasHeavyRule = firstLine.contains("━")
  #expect(hasHeavyRule, "Focused TabView should have a heavy rule above tab labels. First line: '\(firstLine)'")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter focusedTabViewAddsTopRule`
Expected: FAIL — no heavy rule in the first line

- [ ] **Step 3: Add the top focus rule to tabBody**

In `TabView.swift`, in `tabBody` (around line 156), add a heavy rule Text before the HStack inside the VStack. The `focusActive` variable is already computed at line 153. Use the same `━` character as existing tab underlines.

Change lines 156-187 from:

```swift
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
```

to:

```swift
    VStack(alignment: .leading, spacing: 0) {
      if focusActive {
        HStack(alignment: .top, spacing: 0) {
          Spacer(minLength: 0)
        }
        .frame(height: 1)
        .overlay {
          Rectangle().fill(AnyShapeStyle(.terminalAccent(activeTone)))
        }
      }
      HStack(alignment: .top, spacing: 0) {
```

And update the `.frame(height:)` on the HStack+rule container (line 187) to account for the extra line:

```swift
      .frame(height: (hasRule ? 2 : 1) + (focusActive ? 1 : 0), alignment: .leading)
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter FocusTransitionTests`
Expected: All pass including the new top rule test. The existing TabView surface tests may need adjustment if they assert exact line positions — check and fix if needed.

- [ ] **Step 5: Run full test suite**

Run: `swift test`
Expected: All pass. If TabViewSurfaceTests fail due to the extra line, update the `stripBounds` helper to account for the focus rule height.

- [ ] **Step 6: Commit**

```
git add Sources/View/NavigationViews/TabView.swift Tests/TerminalUITests/FocusTransitionTests.swift
git commit -m "feat: focused TabView shows heavy top rule for plain-text visibility"
```

---

### Task 6: Plain-style button and link focus rail

**Files:**
- Modify: `Sources/View/Controls/Button.swift:140-148` (ButtonPlainBody)
- Modify: `Sources/View/Controls/Link.swift` (link text rendering)
- Test: `Tests/TerminalUITests/FocusTransitionTests.swift`

Plain-style buttons and links currently have no structural focus indicator — only color changes. Wrap their content in `controlFocusRow` to get the `▌` rail.

- [ ] **Step 1: Write the failing test**

Add to `FocusTransitionTests.swift`:

```swift
@Test("focused plain button shows focus rail")
func focusedPlainButtonShowsRail() {
  var env = EnvironmentValues()
  env.focusedIdentity = testIdentity("Btn")

  let focused = DefaultRenderer().render(
    Button("Submit") {}
      .buttonStyle(.plain)
      .id(testIdentity("Btn")),
    context: .init(identity: testIdentity("Root"), environmentValues: env),
    proposal: .init(width: 14, height: 1)
  )

  let focusedLines = focused.rasterSurface.lines
  let hasRail = focusedLines.contains { $0.contains("▌") }
  #expect(hasRail, "Focused plain button should show focus rail (▌)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter focusedPlainButtonShowsRail`
Expected: FAIL

- [ ] **Step 3: Add focusActive to ButtonPlainBody and wrap in controlFocusRow**

In `Button.swift`, change `ButtonPlainBody`:

```swift
private struct ButtonPlainBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var focusActive: Bool

  var body: some View {
    controlFocusRow(
      showsRail: focusActive,
      railStyle: chrome.borderStyle,
      isHighlighted: focusActive,
      backgroundStyle: chrome.backgroundStyle,
      reservesRailSpaceWhenHidden: false
    ) {
      label
    }
    .foregroundStyle(chrome.foregroundStyle)
    .drawMetadata(.init(opacity: chrome.opacity))
  }
}
```

- [ ] **Step 4: Update ButtonLinkBody**

`ButtonLinkBody` wraps `ButtonPlainBody`, so pass through:

```swift
private struct ButtonLinkBody<Label: View>: View {
  var label: Label
  var chrome: ControlChrome
  var focusActive: Bool

  var body: some View {
    ButtonPlainBody(
      label: label,
      chrome: chrome,
      focusActive: focusActive
    )
    .underline()
    .background {
      Rectangle().fill(chrome.backgroundStyle)
    }
  }
}
```

- [ ] **Step 5: Pass focusActive from Button.resolvedNode**

In `Button.resolvedNode`, pass `focusActive` to each body variant (around lines 103-124):

```swift
    case .plain:
      child = ButtonPlainBody(
        label: label,
        chrome: chrome,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
    case .link:
      child = ButtonLinkBody(
        label: label,
        chrome: chrome,
        focusActive: isFocused && showsFocusEffect
      )
      .resolve(in: childContext)
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter FocusTransitionTests`
Expected: All pass

- [ ] **Step 7: Run full test suite**

Run: `swift test`
Expected: All pass

- [ ] **Step 8: Commit**

```
git add Sources/View/Controls/Button.swift Tests/TerminalUITests/FocusTransitionTests.swift
git commit -m "feat: plain button and link focus shows rail for plain-text visibility"
```

---

### Task 7: Final verification

**Files:**
- Test: All test files

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Build the gallery demo**

Run: `cd Examples/gallery && swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit any remaining adjustments**

If any existing tests needed updating for the new focus treatments (e.g., TabViewSurfaceTests strip bounds), commit those fixes.
