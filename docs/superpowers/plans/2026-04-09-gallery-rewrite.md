# Gallery Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `Examples/gallery` app (a figlet-font picker and color swatch reference) with a three-tab interactive demo (Counter, Todo, Calculator) that showcases the basics of the TerminalUI framework.

**Architecture:** A single `GalleryView` root hosting `TabView(selection:)` with three tag-driven tabs. Each tab is a self-contained view in its own file inside the `GalleryDemoViews` target, with local `@State`, no shared state, and no external I/O. The Todo tab uses `.sheet(isPresented:)` for task intake.

**Tech Stack:** Swift 6.3, SwiftPM, TerminalUI (`View` + `TerminalUI` library products), no new dependencies.

---

## Spec Reference

`docs/superpowers/specs/2026-04-09-gallery-rewrite-design.md`

## File Structure

All files live in `Examples/gallery/Sources/GalleryDemoViews/`.

| File | Role |
|---|---|
| `GalleryView.swift` | Root `View` hosting `TabView` with three tabs, owns `selection` state. |
| `CounterTab.swift` | Counter tab view: branding header (TextFigure + tagline), live count, +/−/Reset buttons, step slider. |
| `TodoModels.swift` | `TodoItem`, `TodoFilter`, `TodoPriority` value types, plus `TodoItem.seeds`. |
| `TodoTab.swift` | Todo tab view: filter picker, item rows (toggle + delete), "+ New task" button, `.sheet` for intake with auto-focused `TextField` + priority `Picker`. |
| `CalculatorTab.swift` | Calculator tab view: display row + 4-column button grid, plus the pure `CalculatorOp` enum and a small state machine evaluator. |

The current single file `Examples/gallery/Sources/GalleryDemoViews/GalleryViews.swift` is **deleted** in Task 1.

`Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift` keeps its structure (still hosts `GalleryView()`). Its `import Algorithms` line is removed in Task 6 because `swift-algorithms` is no longer used.

---

## API Crib Sheet (Verified Against Source)

The engineer may not be familiar with TerminalUI. These are the exact shapes the plan's code assumes, verified against `Sources/View`:

- `TabView(selection: Binding<SelectionValue>) { content }` — children use `.tabItem("Label")` and `.tag(value)` (both are `View` extensions). See `Sources/View/NavigationViews/TabView.swift` and `Tests/TerminalUITests/TabViewSurfaceTests.swift`.
- `Button(_ title: String, action: @MainActor @Sendable () -> Void)` and `Button(_ title: String, role: ButtonRole?, action:)`. `ButtonRole` = `.cancel`, `.destructive`, `.close`, `.confirm` (defined in `Sources/Core/Appearance.swift`).
- `Toggle(_ title: S, isOn: Binding<Bool>)` (`Sources/View/Controls/ValueControls.swift` line 4+).
- `Picker(_ title: S, selection: Binding<SelectionValue>) { content }` — children use `.tag(value)` (`Sources/View/Controls/Picker.swift`).
- `Slider(_ title: S, value: Binding<Int>, in: ClosedRange<Int>, step: Int = 1)` (`Sources/View/Controls/AdjustableValueControls.swift` line 334).
- `TextField(_ title: S, text: Binding<String>)` (`Sources/View/Controls/ValueControls.swift` line 243). There is **no** `.onSubmit` modifier — commit-on-Enter via TextField callbacks is not wired up, so the sheet relies on the Add button only. This is a deliberate simplification noted in the spec risks.
- `.sheet(_ title: S, isPresented: Binding<Bool>) { sheetContent }` — the sheet body is whatever you put in the closure; no built-in buttons. You must provide your own Cancel/Add buttons. (`Sources/View/Presentation/PresentationModifiers.swift` line 200.)
- `ForEach(_ data, id: \.id) { element in ... }` where `Data.Element: Identifiable` auto-synthesizes `id` (`Sources/View/Collections/ForEach.swift` line 43).
- `TextFigure(_ content: String, font: EmbeddedFigletFont = .standard)`. Compact fonts that exist: `.small`, `.mini`, `.thin`, `.standard`. Use `.small` for the branding headline.
- `withAnimation(_ animation: Animation? = .default, _ body: () -> Result)` (`Sources/View/Animation/WithAnimation.swift`).
- `@FocusState private var x: Bool` property wrapper exists (`Sources/View/State/FocusState.swift` line 107) — access the binding via `$x`.
- Text modifiers that exist and we use: `.bold()`, `.strikethrough(_ active: Bool = true)`, `.foregroundStyle(_ style)`.
- Semantic shape styles used in the demo: `.separator` for muted text (confirmed in `Sources/Core/Styling.swift` as `public static var separator: Self`). This matches the pattern already used in `Examples/todoist/Sources/TodoistDemo/TodoistViews.swift` (e.g. `.foregroundStyle(.separator)`). Do not use `.secondary` — it does not exist in TerminalUI's `ShapeStyle` extension set.

---

## Task 1: Scaffold Root TabView And Delete Old Gallery

**Files:**
- Delete: `Examples/gallery/Sources/GalleryDemoViews/GalleryViews.swift`
- Create: `Examples/gallery/Sources/GalleryDemoViews/GalleryView.swift`
- Create: `Examples/gallery/Sources/GalleryDemoViews/CounterTab.swift` (placeholder)
- Create: `Examples/gallery/Sources/GalleryDemoViews/TodoTab.swift` (placeholder)
- Create: `Examples/gallery/Sources/GalleryDemoViews/CalculatorTab.swift` (placeholder)

- [ ] **Step 1: Delete the old gallery views file**

```bash
rm Examples/gallery/Sources/GalleryDemoViews/GalleryViews.swift
```

- [ ] **Step 2: Create placeholder `CounterTab.swift`**

Contents:

```swift
import TerminalUI

struct CounterTab: View {
  var body: some View {
    Text("Counter — coming in Task 2")
      .padding(1)
  }
}
```

- [ ] **Step 3: Create placeholder `TodoTab.swift`**

Contents:

```swift
import TerminalUI

struct TodoTab: View {
  var body: some View {
    Text("Todo — coming in Task 3")
      .padding(1)
  }
}
```

- [ ] **Step 4: Create placeholder `CalculatorTab.swift`**

Contents:

```swift
import TerminalUI

struct CalculatorTab: View {
  var body: some View {
    Text("Calculator — coming in Task 5")
      .padding(1)
  }
}
```

- [ ] **Step 5: Create the root `GalleryView.swift`**

Contents:

```swift
import TerminalUI

public struct GalleryView: View {
  public init() {}

  @State private var selection: Tab = .counter

  public var body: some View {
    TabView(selection: $selection) {
      CounterTab()
        .tabItem("Counter")
        .tag(Tab.counter)

      TodoTab()
        .tabItem("Todo")
        .tag(Tab.todo)

      CalculatorTab()
        .tabItem("Calculator")
        .tag(Tab.calculator)
    }
  }
}

extension GalleryView {
  enum Tab: Hashable {
    case counter
    case todo
    case calculator
  }
}
```

- [ ] **Step 6: Build and verify**

Run from the repo root:

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build, no warnings about the deleted file or unresolved `GalleryView`.

- [ ] **Step 7: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/
git commit -m "refactor(gallery): scaffold three-tab root, drop old color demo"
```

---

## Task 2: Counter Tab

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/CounterTab.swift`

- [ ] **Step 1: Replace the `CounterTab.swift` placeholder with the full view**

Contents:

```swift
import TerminalUI

struct CounterTab: View {
  @State private var count: Int = 0
  @State private var step: Int = 1

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      brandingHeader
      Divider()
      Spacer(minLength: 1)
      countDisplay
      Spacer(minLength: 1)
      controls
      stepSlider
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var brandingHeader: some View {
    VStack(alignment: .center, spacing: 0) {
      TextFigure("TerminalUI", font: .small)
      Text("A SwiftUI-shaped terminal UI")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var countDisplay: some View {
    Text("\(count)")
      .bold()
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private var controls: some View {
    HStack(spacing: 2) {
      Button("−", role: .destructive) {
        withAnimation(.default) {
          count -= step
        }
      }
      Button("Reset") {
        withAnimation(.default) {
          count = 0
        }
      }
      Button("+") {
        withAnimation(.default) {
          count += step
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var stepSlider: some View {
    HStack(spacing: 1) {
      Text("Step")
        .foregroundStyle(.separator)
      Slider("Step", value: $step, in: 1...10, step: 1)
      Text("\(step)")
    }
    .padding(.horizontal, 2)
  }
}
```

- [ ] **Step 2: Build**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build. If `TextFigure("TerminalUI", font: .small)` emits a warning about unsupported characters, downgrade to `font: .mini` or `font: .thin` — whichever renders within ~5 rows at 80 columns. Pick one and commit to it.

- [ ] **Step 3: Run and visually smoke-test**

```bash
swift run --package-path Examples/gallery gallery-demo
```

In the running app:
- The default tab is "Counter".
- The branding figlet shows "TerminalUI" without wrapping at 80 columns.
- Pressing the `+` button increments the count; `−` decrements by the same amount; `Reset` sets it to 0.
- Moving the slider changes the step size and the text next to it.
- Quit with `q` or `Ctrl-C`.

If the figlet is too wide for 80 columns, swap the font case and rebuild before committing.

- [ ] **Step 4: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/CounterTab.swift
git commit -m "feat(gallery): counter tab with branding header and step slider"
```

---

## Task 3: Todo Models

**Files:**
- Create: `Examples/gallery/Sources/GalleryDemoViews/TodoModels.swift`

- [ ] **Step 1: Create `TodoModels.swift`**

Contents:

```swift
import Foundation

struct TodoItem: Identifiable, Hashable {
  let id: UUID
  var title: String
  var priority: TodoPriority
  var done: Bool

  init(
    id: UUID = UUID(),
    title: String,
    priority: TodoPriority = .normal,
    done: Bool = false
  ) {
    self.id = id
    self.title = title
    self.priority = priority
    self.done = done
  }
}

extension TodoItem {
  static let seeds: [TodoItem] = [
    TodoItem(title: "Write docs", priority: .high),
    TodoItem(title: "Ship release", priority: .high, done: true),
    TodoItem(title: "Water plants", priority: .normal),
    TodoItem(title: "Call mum", priority: .low),
  ]
}

enum TodoFilter: String, CaseIterable, Identifiable, Hashable {
  case all
  case active
  case done

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: "All"
    case .active: "Active"
    case .done: "Done"
    }
  }

  func matches(_ item: TodoItem) -> Bool {
    switch self {
    case .all: true
    case .active: !item.done
    case .done: item.done
    }
  }
}

enum TodoPriority: String, CaseIterable, Identifiable, Hashable {
  case low
  case normal
  case high

  var id: String { rawValue }

  var label: String {
    switch self {
    case .low: "Low"
    case .normal: "Normal"
    case .high: "High"
    }
  }
}
```

Note on `Foundation`: the repo has a guardrail (`forbid Foundation imports in library layers`). `GalleryDemoViews` is an example target — not a library layer — so `import Foundation` is permitted here to access `UUID`. If a hook blocks the commit, the fallback is to replace `UUID` with a monotonically-incrementing `Int` ID generated by a small `private static var nextID: Int = 0` counter and a `TodoItem.makeID()` helper. Try `UUID` first.

- [ ] **Step 2: Build**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build. If the Foundation guardrail blocks the build, apply the `Int`-counter fallback and rebuild.

- [ ] **Step 3: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/TodoModels.swift
git commit -m "feat(gallery): todo model types and seed items"
```

---

## Task 4: Todo Tab — List, Filter, Delete, Clear Completed (no sheet yet)

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/TodoTab.swift`

- [ ] **Step 1: Replace the `TodoTab.swift` placeholder with the base tab**

Contents:

```swift
import TerminalUI

struct TodoTab: View {
  @State private var items: [TodoItem] = TodoItem.seeds
  @State private var filter: TodoFilter = .all

  private var visibleItems: [TodoItem] {
    items.filter(filter.matches)
  }

  private var remaining: Int {
    items.filter { !$0.done }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      list
      Spacer(minLength: 0)
      footer
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Picker("Filter", selection: $filter) {
        ForEach(TodoFilter.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      Spacer()
      Text("\(remaining) remaining")
        .foregroundStyle(.separator)
    }
  }

  private var list: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(visibleItems) { item in
        row(for: item)
      }
    }
  }

  private func row(for item: TodoItem) -> some View {
    HStack(spacing: 1) {
      Toggle(item.title, isOn: doneBinding(for: item))
      Spacer()
      Button("×", role: .destructive) {
        items.removeAll { $0.id == item.id }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 2) {
      // Placeholder — replaced with "New task" button in Task 5.
      Text(" ")
      Spacer()
      Button("Clear ✓") {
        items.removeAll { $0.done }
      }
    }
  }

  private func doneBinding(for item: TodoItem) -> Binding<Bool> {
    Binding<Bool>(
      get: {
        items.first(where: { $0.id == item.id })?.done ?? false
      },
      set: { newValue in
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
          return
        }
        items[index].done = newValue
      }
    )
  }
}
```

- [ ] **Step 2: Build**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build. If `Text(option.label).tag(option)` fails because `tag` isn't in scope, import the tag from `TerminalUI` (it already is — `tag` ships as a `View` extension in the `View` target). If the picker closure can't infer generics, annotate with `Picker<TodoFilter, Text, TupleView<...>>` — unlikely but possible.

- [ ] **Step 3: Run and visually smoke-test**

```bash
swift run --package-path Examples/gallery gallery-demo
```

- Switch to the "Todo" tab (arrow keys on the tab strip).
- Four seed items are visible, one (`Ship release`) is done and rendered with its toggle in the on state.
- Changing the filter hides items accordingly; `3 remaining` updates as items are toggled.
- Pressing `×` on a row deletes it.
- `Clear ✓` removes all done items.

- [ ] **Step 4: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/TodoTab.swift
git commit -m "feat(gallery): todo tab list, filter, delete, clear"
```

---

## Task 5: Todo Tab — Sheet Intake

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/TodoTab.swift`

- [ ] **Step 1: Add sheet state, sheet button, and sheet modifier to `TodoTab.swift`**

Replace the existing `TodoTab` struct body with the full version including the sheet. This version:
1. Adds `isPresentingNew`, `draftTitle`, `draftPriority`, and `titleFocused` state.
2. Replaces the footer placeholder with a `+ New task` button.
3. Attaches `.sheet("New task", isPresented: ...)` to the outer `VStack`.
4. Adds a nested `NewTaskSheet` view type inside the file scope.

Full replacement contents for `TodoTab.swift`:

```swift
import TerminalUI

struct TodoTab: View {
  @State private var items: [TodoItem] = TodoItem.seeds
  @State private var filter: TodoFilter = .all
  @State private var isPresentingNew: Bool = false
  @State private var draftTitle: String = ""
  @State private var draftPriority: TodoPriority = .normal
  @FocusState private var titleFocused: Bool

  private var visibleItems: [TodoItem] {
    items.filter(filter.matches)
  }

  private var remaining: Int {
    items.filter { !$0.done }.count
  }

  private var canAddDraft: Bool {
    !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      list
      Spacer(minLength: 0)
      footer
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .sheet("New task", isPresented: $isPresentingNew) {
      newTaskSheetBody
    }
  }

  private var header: some View {
    HStack(spacing: 2) {
      Picker("Filter", selection: $filter) {
        ForEach(TodoFilter.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      Spacer()
      Text("\(remaining) remaining")
        .foregroundStyle(.separator)
    }
  }

  private var list: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(visibleItems) { item in
        row(for: item)
      }
    }
  }

  private func row(for item: TodoItem) -> some View {
    HStack(spacing: 1) {
      Toggle(item.title, isOn: doneBinding(for: item))
      Spacer()
      Button("×", role: .destructive) {
        items.removeAll { $0.id == item.id }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 2) {
      Button("+ New task") {
        draftTitle = ""
        draftPriority = .normal
        isPresentingNew = true
        titleFocused = true
      }
      Spacer()
      Button("Clear ✓") {
        items.removeAll { $0.done }
      }
    }
  }

  private var newTaskSheetBody: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Title").foregroundStyle(.separator)
      TextField("What needs doing?", text: $draftTitle)
        .focused($titleFocused)

      Text("Priority").foregroundStyle(.separator)
      Picker("Priority", selection: $draftPriority) {
        ForEach(TodoPriority.allCases) { option in
          Text(option.label).tag(option)
        }
      }

      Spacer(minLength: 1)

      HStack(spacing: 2) {
        Spacer()
        Button("Cancel", role: .cancel) {
          isPresentingNew = false
        }
        Button("Add") {
          addDraft()
        }
        .disabled(!canAddDraft)
      }
    }
    .padding(1)
  }

  private func addDraft() {
    let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    items.append(
      TodoItem(title: trimmed, priority: draftPriority)
    )
    draftTitle = ""
    draftPriority = .normal
    isPresentingNew = false
  }

  private func doneBinding(for item: TodoItem) -> Binding<Bool> {
    Binding<Bool>(
      get: {
        items.first(where: { $0.id == item.id })?.done ?? false
      },
      set: { newValue in
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
          return
        }
        items[index].done = newValue
      }
    )
  }
}
```

- [ ] **Step 2: Build**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build. Possible failures and their fixes:

- `'focused' is not a member of 'TextField'` — the focus modifier may be named differently. Grep for it:

  ```bash
  ```
  Use Grep tool: pattern `public func focused`, path `Sources/View`, output `content`.

  Replace `.focused($titleFocused)` with whatever the actual modifier is (likely `.focusState($titleFocused)` or similar). If no equivalent exists at all, drop the `@FocusState` + `.focused(...)` lines and note it — the sheet still works, the field just isn't auto-focused.

- `trimmingCharacters(in:)` requires `Foundation`. Add `import Foundation` at the top of the file (same allowance as Task 3).

- If `.disabled(!canAddDraft)` fails, grep for `public func disabled`. If missing, remove the `.disabled` line — the `addDraft()` method already guards against empty titles, so a user clicking Add with an empty title is a no-op.

- [ ] **Step 3: Run and visually smoke-test**

```bash
swift run --package-path Examples/gallery gallery-demo
```

- On the Todo tab, activate the "+ New task" button.
- A sheet appears titled "New task" containing a text field, a priority picker, and Cancel / Add buttons.
- Type a title, press Add — sheet closes, new item appears at the bottom of the list.
- Opening the sheet again, pressing Cancel, leaves the list unchanged.
- Add with an empty title is either blocked (if `.disabled` works) or silently ignored.

- [ ] **Step 4: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/TodoTab.swift
git commit -m "feat(gallery): todo tab sheet-based task intake"
```

---

## Task 6: Calculator Tab

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/CalculatorTab.swift`

- [ ] **Step 1: Replace the `CalculatorTab.swift` placeholder with the full view and state machine**

Contents:

```swift
import TerminalUI

enum CalculatorOp: Hashable {
  case add
  case sub
  case mul
  case div

  var glyph: String {
    switch self {
    case .add: "+"
    case .sub: "−"
    case .mul: "×"
    case .div: "÷"
    }
  }

  func apply(_ lhs: Double, _ rhs: Double) -> Double? {
    switch self {
    case .add: lhs + rhs
    case .sub: lhs - rhs
    case .mul: lhs * rhs
    case .div:
      if rhs == 0 { nil } else { lhs / rhs }
    }
  }
}

struct CalculatorTab: View {
  @State private var display: String = "0"
  @State private var accumulator: Double? = nil
  @State private var pendingOp: CalculatorOp? = nil
  @State private var clearOnNextDigit: Bool = false
  @State private var isError: Bool = false

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      displayRow
      Spacer(minLength: 1)
      buttonGrid
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var displayRow: some View {
    Text(display)
      .bold()
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.horizontal, 1)
  }

  private var buttonGrid: some View {
    VStack(alignment: .center, spacing: 0) {
      HStack(spacing: 0) {
        calcButton("AC") { clearAll() }
        calcButton("+/−") { negate() }
        calcButton("%") { percent() }
        calcButton(CalculatorOp.div.glyph) { setOp(.div) }
      }
      HStack(spacing: 0) {
        calcButton("7") { enterDigit("7") }
        calcButton("8") { enterDigit("8") }
        calcButton("9") { enterDigit("9") }
        calcButton(CalculatorOp.mul.glyph) { setOp(.mul) }
      }
      HStack(spacing: 0) {
        calcButton("4") { enterDigit("4") }
        calcButton("5") { enterDigit("5") }
        calcButton("6") { enterDigit("6") }
        calcButton(CalculatorOp.sub.glyph) { setOp(.sub) }
      }
      HStack(spacing: 0) {
        calcButton("1") { enterDigit("1") }
        calcButton("2") { enterDigit("2") }
        calcButton("3") { enterDigit("3") }
        calcButton(CalculatorOp.add.glyph) { setOp(.add) }
      }
      HStack(spacing: 0) {
        calcButton("0") { enterDigit("0") }
        calcButton(".") { enterDot() }
        calcButton("=") { evaluate() }
        Spacer().frame(width: 6, height: 3)
      }
    }
  }

  private func calcButton(_ label: String, action: @escaping @MainActor @Sendable () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .frame(width: 6, height: 3, alignment: .center)
    }
  }

  // MARK: - State machine

  private func enterDigit(_ d: String) {
    if isError || clearOnNextDigit || display == "0" {
      display = d
      clearOnNextDigit = false
      isError = false
      return
    }
    display += d
  }

  private func enterDot() {
    if isError || clearOnNextDigit {
      display = "0."
      clearOnNextDigit = false
      isError = false
      return
    }
    if !display.contains(".") {
      display += "."
    }
  }

  private func setOp(_ op: CalculatorOp) {
    if let lhs = accumulator, let pending = pendingOp, !clearOnNextDigit {
      let rhs = Double(display) ?? 0
      if let result = pending.apply(lhs, rhs) {
        accumulator = result
        display = formatted(result)
      } else {
        showError()
      }
    } else {
      accumulator = Double(display) ?? 0
    }
    pendingOp = op
    clearOnNextDigit = true
  }

  private func evaluate() {
    guard let lhs = accumulator, let pending = pendingOp else {
      return
    }
    let rhs = Double(display) ?? 0
    if let result = pending.apply(lhs, rhs) {
      display = formatted(result)
      accumulator = result
    } else {
      showError()
    }
    pendingOp = nil
    clearOnNextDigit = true
  }

  private func clearAll() {
    display = "0"
    accumulator = nil
    pendingOp = nil
    clearOnNextDigit = false
    isError = false
  }

  private func negate() {
    guard !isError else { return }
    if display.hasPrefix("-") {
      display.removeFirst()
    } else if display != "0" {
      display = "-" + display
    }
  }

  private func percent() {
    guard let value = Double(display) else { return }
    display = formatted(value / 100)
  }

  private func showError() {
    display = "Error"
    accumulator = nil
    pendingOp = nil
    clearOnNextDigit = true
    isError = true
  }

  private func formatted(_ value: Double) -> String {
    if value.rounded() == value, abs(value) < 1e15 {
      return String(Int64(value))
    }
    return String(value)
  }
}
```

- [ ] **Step 2: Build**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build. Possible failures:

- If `Button(action:) { Text(...).frame(...) }` fails because the label closure doesn't accept a framed `Text`, replace `calcButton` with:

  ```swift
  private func calcButton(_ label: String, action: @escaping @MainActor @Sendable () -> Void) -> some View {
    Button(label, action: action)
      .frame(width: 6, height: 3)
  }
  ```

  This uses the simpler `Button(title, action:)` init and wraps the whole button with `.frame`, which is the pattern the todoist demo uses for sizing buttons.

- If `Spacer().frame(width: 6, height: 3)` fails because `Spacer` doesn't accept the fixed-size frame overload, replace with `Color.clear.frame(width: 6, height: 3)` or `Rectangle().fill(Color.clear).frame(width: 6, height: 3)`. The intent is just to occupy the gap where a "0" double-width key would go.

- [ ] **Step 3: Run and visually smoke-test**

```bash
swift run --package-path Examples/gallery gallery-demo
```

- Switch to the Calculator tab.
- Press `7`, `+`, `8`, `=` — display shows `15`.
- Press `AC` — display shows `0`.
- Press `6`, `÷`, `0`, `=` — display shows `Error`.
- Press any digit — display resets from `Error`.
- Press `1`, `+/−` — display shows `-1`.
- Press `5`, `0`, `%` — display shows `0.5`.

- [ ] **Step 4: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemoViews/CalculatorTab.swift
git commit -m "feat(gallery): calculator tab with four-function state machine"
```

---

## Task 7: Final Cleanup And Verification

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift`
- Modify: `Examples/gallery/Package.swift`

- [ ] **Step 1: Remove the unused `Algorithms` import from `GalleryDemoApp.swift`**

Current contents:

```swift
import Algorithms
import GalleryDemoViews
import TerminalUI

@main
struct GalleryDemoApp: App {

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
```

Replace with:

```swift
import GalleryDemoViews
import TerminalUI

@main
struct GalleryDemoApp: App {

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
```

- [ ] **Step 2: Check whether anything in `GalleryDemoViews` still uses `Algorithms`**

Run a grep:

Use the Grep tool: pattern `Algorithms`, path `Examples/gallery/Sources`, output `files_with_matches`.

- If **no matches**: proceed to Step 3 and drop the dep.
- If **any match**: leave `Package.swift` alone and skip to Step 4.

- [ ] **Step 3: Drop `swift-algorithms` from `Package.swift` (only if Step 2 found no matches)**

Edit `Examples/gallery/Package.swift`:

Remove the dependency line:

```swift
    .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
```

And remove the product dependency from the `GalleryDemoViews` target:

```swift
        .product(name: "Algorithms", package: "swift-algorithms"),
```

Resulting `Package.swift`:

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gallery-demo",
      targets: ["GalleryDemo"]
    ),
    .library(
      name: "GalleryDemoViews",
      targets: ["GalleryDemoViews"]
    ),
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .target(
      name: "GalleryDemoViews",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
```

- [ ] **Step 4: Final build from repo root**

```bash
swiftly run swift build
```

Expected: clean build for the whole workspace.

- [ ] **Step 5: Final build of the gallery package explicitly**

```bash
swiftly run swift build --package-path Examples/gallery
```

Expected: clean build, no warnings.

- [ ] **Step 6: Final manual smoke test**

```bash
swift run --package-path Examples/gallery gallery-demo
```

Verify all three tabs render and behave as described in Tasks 2, 4, 5, and 6. Quit with `q` or `Ctrl-C`.

- [ ] **Step 7: Commit**

```bash
git add Examples/gallery/Sources/GalleryDemo/GalleryDemoApp.swift Examples/gallery/Package.swift
git commit -m "chore(gallery): drop unused swift-algorithms dep"
```

(If Step 3 was skipped, the `Package.swift` change is absent and the commit only covers the import cleanup — adjust the `git add` accordingly.)

---

## Notes For The Implementer

- **Run from repo root for cross-package sanity, but use `--package-path Examples/gallery` for fast iteration.** The gallery package has its own `Package.swift`.
- **Swift version:** this repo pins `6.3.0` via `.swift-version`, managed by `swiftly`. Prefer `swiftly run swift ...`.
- **If prek / hooks strip imports or reformat:** that's the `swift-format` hook running on commit. Let it. Do not `--no-verify`.
- **Never amend commits;** if a hook fails, fix the issue and create a new commit.
- **Scope discipline:** don't touch unrelated files. No refactoring `WebExample`, no touching `TerminalUI` internals to make the demo work — if an API friction pops up, work around it in the demo rather than changing the framework.

## Self-Review

Spec-coverage check vs `docs/superpowers/specs/2026-04-09-gallery-rewrite-design.md`:

- Three tabs (Counter, Todo, Calculator) — Tasks 1, 2, 4-5, 6.
- TabView root in its own file — Task 1.
- Counter with branding (TextFigure + tagline), count, ±/Reset buttons, step slider, withAnimation on changes — Task 2.
- Todo with segmented filter, items list with toggle + delete, remaining count, Clear Completed — Task 4.
- Todo sheet intake: isPresented binding, TextField with @FocusState, Priority picker, Cancel + Add, disabled-when-empty Add, commit into items — Task 5.
- Calculator with display, 4-column grid, AC/+/-/%, operators, =, state machine, division-by-zero "Error" — Task 6.
- One-file-per-tab under `GalleryDemoViews` — Tasks 1-6 file layout.
- No Package.swift changes except optionally dropping swift-algorithms — Task 7.
- `GalleryDemoApp.swift` unchanged structurally (only imports trimmed) — Task 7.

Non-goals confirmed unaddressed: no charts, no alerts, no confirmation dialogs, no toasts, no command palette, no tests for the demo itself, no new framework features.

Risks documented in the spec and handled in the plan:
- TextFigure sizing — Task 2 Step 2 has a fallback to a smaller font.
- Sheet sizing on narrow terminals — deferred; will visually verify during Task 5 smoke test.
- Grid `0` spanning two columns — the plan uses a uniform 4-column grid (simpler), with `Spacer` filling the unused cell. The spec called this out as a fallback; I'm adopting the fallback upfront to avoid guessing at layout quirks.
