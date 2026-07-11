import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI component-composition stress behavior", .serialized)
struct FrameworkStressComponentCompositionTests {}

@MainActor
private func componentCompositionFrames<Content: View>(
  _ view: Content,
  renderer: DefaultRenderer,
  identity: Identity,
  generation: Int,
  size: CellSize = .init(width: 48, height: 12),
  environmentValues: EnvironmentValues = .init()
) -> (retained: RenderSnapshot, fresh: RenderSnapshot) {
  let proposal = ProposedSize(width: size.width, height: size.height)
  let retained = renderer.render(
    view,
    context: .init(
      identity: identity,
      environmentValues: environmentValues,
      invalidatedIdentities: generation == 0 ? [] : [identity]
    ),
    proposal: proposal
  )
  let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
    view,
    context: .init(identity: identity, environmentValues: environmentValues),
    proposal: proposal
  )
  return (retained, fresh)
}

private func componentCompositionText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: Label payload replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 001 Label publishes current icon and title")
  func componentComposition001LabelPublishesCurrentIconAndTitle() {
    // Hypothesis: Label's synthesized HStack can reuse either the icon or title
    // child when both values change behind a stable outer identity.
    struct Root: View {
      let generation: Int

      var body: some View {
        Label {
          Text("title-\(generation)")
        } icon: {
          Text("icon-\(generation % 3)")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition001")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(componentCompositionText(frames.retained).contains("title-\(generation)"))
      #expect(componentCompositionText(frames.retained).contains("icon-\(generation % 3)"))
    }
  }
}

// MARK: - Attempt 002: Label child-topology replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 002 Label replaces child topology without residue")
  func componentComposition002LabelReplacesChildTopologyWithoutResidue() {
    // Hypothesis: Label can retain a removed variadic child when its icon and
    // title builders alternate between one and two resolved elements.
    struct Root: View {
      let generation: Int

      var body: some View {
        Label {
          if generation.isMultiple(of: 2) {
            Text("single-title-\(generation)")
          } else {
            Text("first-title-\(generation)")
            Text("second-title-\(generation)")
          }
        } icon: {
          if generation.isMultiple(of: 3) {
            Text("single-icon")
          } else {
            Text("left-icon")
            Text("right-icon")
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition002")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("single-title-\(generation)") == generation.isMultiple(of: 2))
      if generation.isMultiple(of: 2), generation > 0 {
        #expect(!text.contains("second-title-\(generation - 1)"))
      }
      if generation.isMultiple(of: 3) {
        #expect(!text.contains("right-icon"))
      }
    }
  }
}

// MARK: - Attempt 003: LabeledContent width remeasurement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 003 LabeledContent remeasures both changing columns")
  func componentComposition003LabeledContentRemeasuresBothChangingColumns() {
    // Hypothesis: the synthesized Spacer allocation can retain an earlier
    // label width and overlap a replacement trailing value.
    struct Root: View {
      let generation: Int

      var body: some View {
        LabeledContent(
          generation.isMultiple(of: 2) ? "short" : "a much longer label",
          value: generation.isMultiple(of: 3) ? "tiny" : "value-\(generation)-expanded"
        )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition003")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
    }
  }
}

// MARK: - Attempt 004: LabeledContent content cardinality

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 004 LabeledContent drops removed trailing children")
  func componentComposition004LabeledContentDropsRemovedTrailingChildren() {
    // Hypothesis: changing the content builder's flattened child count can
    // leave a trailing value from the preceding generation in the HStack.
    struct Root: View {
      let generation: Int

      var body: some View {
        LabeledContent {
          Text("primary-\(generation)")
          if generation.isMultiple(of: 2) {
            Text("optional-\(generation)")
          }
        } label: {
          Text("label-\(generation)")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition004")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("primary-\(generation)"))
      #expect(text.contains("optional-\(generation)") == generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 005: LabeledContent entity reorder

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 005 reordered LabeledContent rows keep current values")
  func componentComposition005ReorderedLabeledContentRowsKeepCurrentValues() {
    // Hypothesis: the primitive's synthesized children can be reused by
    // occurrence after stable row entities reorder, swapping trailing values.
    struct Entry: Identifiable {
      let id: String
      let value: String
    }
    struct Root: View {
      let generation: Int

      var body: some View {
        let base = [
          Entry(id: "alpha", value: "A-\(generation)"),
          Entry(id: "beta", value: "B-\(generation)"),
          Entry(id: "gamma", value: "C-\(generation)"),
        ]
        VStack(alignment: .leading, spacing: 0) {
          ForEach(generation.isMultiple(of: 2) ? base : Array(base.reversed())) { entry in
            LabeledContent(entry.id, value: entry.value)
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition005")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation),
        renderer: renderer,
        identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("alpha") && text.contains("A-\(generation)"))
      #expect(text.contains("beta") && text.contains("B-\(generation)"))
      #expect(text.contains("gamma") && text.contains("C-\(generation)"))
    }
  }
}

// MARK: - Attempt 006: ControlGroup child cardinality

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 006 ControlGroup follows current child cardinality")
  func componentComposition006ControlGroupFollowsCurrentChildCardinality() {
    // Hypothesis: ControlGroup's nested variadic HStack can retain a removed control.
    struct Root: View {
      let generation: Int
      var body: some View {
        ControlGroup {
          Button("always-\(generation)") {}
          if generation.isMultiple(of: 2) {
            Button("optional-\(generation)") {}
          }
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition006")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("always-\(generation)"))
      #expect(text.contains("optional-\(generation)") == generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 007: ControlGroup label freshness

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 007 labeled ControlGroup refreshes label and controls")
  func componentComposition007LabeledControlGroupRefreshesLabelAndControls() {
    // Hypothesis: the label branch can be memo-reused independently of live control payloads.
    struct Root: View {
      let generation: Int
      var body: some View {
        ControlGroup {
          Button("control-\(generation)") {}
        } label: {
          Text("group-\(generation)")
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition007")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("group-\(generation)"))
      #expect(text.contains("control-\(generation)"))
    }
  }
}

// MARK: - Attempt 008: ControlGroup entity reorder

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 008 ControlGroup reorders stable controls by entity")
  func componentComposition008ControlGroupReordersStableControlsByEntity() {
    // Hypothesis: the compact HStack can retain occurrence order after stable controls reverse.
    struct Entry: Identifiable { let id: String }
    struct Root: View {
      let generation: Int
      var body: some View {
        let base = [Entry(id: "one"), Entry(id: "two"), Entry(id: "three")]
        ControlGroup {
          ForEach(generation.isMultiple(of: 2) ? base : Array(base.reversed())) { entry in
            Button("\(entry.id)-\(generation)") {}
          }
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition008")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
    }
  }
}

// MARK: - Attempt 009: ControlGroup enablement churn

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 009 ControlGroup enablement refreshes focus regions")
  func componentComposition009ControlGroupEnablementRefreshesFocusRegions() {
    // Hypothesis: disabling the group can leave one synthesized child focusable.
    struct Root: View {
      let generation: Int
      var body: some View {
        ControlGroup {
          Button("first") {}
          Button("second") {}
        }
        .disabled(!generation.isMultiple(of: 2))
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition009")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
    }
  }
}

// MARK: - Attempt 010: ControlGroup branch replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 010 labeled and unlabeled groups replace cleanly")
  func componentComposition010LabeledAndUnlabeledGroupsReplaceCleanly() {
    // Hypothesis: replacing the generic ControlGroup family under one explicit ID can retain
    // the removed label row or shift the current control identity.
    struct Root: View {
      let generation: Int
      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            ControlGroup("label-\(generation)") { Button("action-\(generation)") {} }
          } else {
            ControlGroup { Button("action-\(generation)") {} }
          }
        }
        .id("stable-control-group")
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition010")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("label-\(generation)") == generation.isMultiple(of: 2))
      #expect(text.contains("action-\(generation)"))
    }
  }
}

// MARK: - Attempt 011: GroupBox label freshness

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 011 GroupBox publishes current label and content")
  func componentComposition011GroupBoxPublishesCurrentLabelAndContent() {
    // Hypothesis: GroupBox's environment-reader wrappers can freeze its authored builders.
    struct Root: View {
      let generation: Int
      var body: some View {
        GroupBox {
          Text("content-\(generation)")
        } label: {
          Text("label-\(generation)")
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition011")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("label-\(generation)"))
      #expect(text.contains("content-\(generation)"))
    }
  }
}

// MARK: - Attempt 012: GroupBox content cardinality

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 012 GroupBox removes conditional content rows")
  func componentComposition012GroupBoxRemovesConditionalContentRows() {
    // Hypothesis: the nested content VStack can preserve a departed row behind stable chrome.
    struct Root: View {
      let generation: Int
      var body: some View {
        GroupBox("box") {
          Text("always-\(generation)")
          if generation.isMultiple(of: 2) {
            Text("optional-\(generation)")
          }
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition012")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("optional-\(generation)") == generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 013: GroupBox prominence replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 013 GroupBox chrome follows current prominence")
  func componentComposition013GroupBoxChromeFollowsCurrentProminence() {
    // Hypothesis: chrome resolved inside nested EnvironmentReaders can retain the first prominence.
    struct Root: View {
      let generation: Int
      var body: some View {
        GroupBox("box-\(generation)") { Text("payload") }
          .controlProminence(generation.isMultiple(of: 2) ? .standard : .increased)
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition013")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.drawTree == frames.fresh.drawTree)
    }
  }
}

// MARK: - Attempt 014: nested GroupBox replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 014 nested GroupBox churn keeps current borders")
  func componentComposition014NestedGroupBoxChurnKeepsCurrentBorders() {
    // Hypothesis: repeated nested chrome can reuse an inner border at obsolete bounds.
    struct Root: View {
      let generation: Int
      var body: some View {
        GroupBox("outer-\(generation)") {
          GroupBox("inner-\(generation)") {
            Text(String(repeating: "x", count: 3 + generation % 9))
          }
        }
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition014")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
      #expect(frames.retained.placedTree == frames.fresh.placedTree)
    }
  }
}

// MARK: - Attempt 015: labeled GroupBox family replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 015 labeled and unlabeled boxes replace cleanly")
  func componentComposition015LabeledAndUnlabeledBoxesReplaceCleanly() {
    // Hypothesis: swapping generic GroupBox families at one identity can retain label height.
    struct Root: View {
      let generation: Int
      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            GroupBox("label-\(generation)") { Text("body-\(generation)") }
          } else {
            GroupBox { Text("body-\(generation)") }
          }
        }
        .id("stable-group-box")
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition015")
    for generation in 0..<16 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
    }
  }
}

// MARK: - Attempt 016: ProgressView value-domain churn

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 016 ProgressView follows changing value domains")
  func componentComposition016ProgressViewFollowsChangingValueDomains() {
    // Hypothesis: the metric track can retain an earlier total when value and total alternate.
    struct Root: View {
      let generation: Int
      var body: some View {
        ProgressView(
          "progress-\(generation)",
          value: Double((generation * 7) % 23),
          total: generation.isMultiple(of: 2) ? 22 : 9,
          barWidth: 14
        )
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition016")
    for generation in 0..<20 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.drawTree == frames.fresh.drawTree)
    }
  }
}

// MARK: - Attempt 017: ProgressView bar-width replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 017 ProgressView remeasures replacement bar widths")
  func componentComposition017ProgressViewRemeasuresReplacementBarWidths() {
    // Hypothesis: changing only barWidth can reuse an obsolete metric-track measurement.
    struct Root: View {
      let generation: Int
      var body: some View {
        ProgressView(value: 0.5, total: 1, barWidth: [3, 17, 8][generation % 3])
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition017")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
    }
  }
}

// MARK: - Attempt 018: ProgressView suppression policy

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 018 ProgressView suppression removes and restores ornament")
  func componentComposition018ProgressViewSuppressionRemovesAndRestoresOrnament() {
    // Hypothesis: toggling no-progress policy can strand the decorated track or static summary.
    struct Root: View {
      let generation: Int
      var body: some View {
        ProgressView("job-\(generation)", value: Double(generation), total: 20, barWidth: 12)
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition018")
    for generation in 0..<18 {
      var environment = EnvironmentValues()
      environment.suppressesProgress = !generation.isMultiple(of: 2)
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation, environmentValues: environment
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
    }
  }
}

// MARK: - Attempt 019: indeterminate reduce-motion policy

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 019 indeterminate progress follows reduce-motion churn")
  func componentComposition019IndeterminateProgressFollowsReduceMotionChurn() {
    // Hypothesis: the indeterminate branch can retain animated track children after motion is reduced.
    struct Root: View {
      let generation: Int
      var body: some View { ProgressView("loading-\(generation)", barWidth: 11) }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition019")
    for generation in 0..<18 {
      var environment = EnvironmentValues()
      environment.accessibilityReduceMotion = !generation.isMultiple(of: 2)
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation, environmentValues: environment
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
    }
  }
}

// MARK: - Attempt 020: determinate family replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 020 determinate and indeterminate progress replace cleanly")
  func componentComposition020DeterminateAndIndeterminateProgressReplaceCleanly() {
    // Hypothesis: swapping ProgressView generic families at a stable identity can preserve
    // the prior summary or indeterminate track subtree.
    struct Root: View {
      let generation: Int
      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            ProgressView("fixed-\(generation)", value: 1, total: 4, barWidth: 10)
          } else {
            ProgressView("moving-\(generation)", barWidth: 10)
          }
        }
        .id("stable-progress")
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition020")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let text = componentCompositionText(frames.retained)
      #expect(text.contains("fixed-\(generation)") == generation.isMultiple(of: 2))
      #expect(text.contains("moving-\(generation)") == !generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 021: Spinner stage replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 021 Spinner stages publish their current terminal glyph")
  func componentComposition021SpinnerStagesPublishCurrentTerminalGlyph() {
    // Hypothesis: Spinner's State-backed body can preserve an active frame after stage changes.
    struct Root: View {
      let generation: Int
      var stage: Spinner.Stage {
        switch generation % 3 {
        case 0: .inactive
        case 1: .active
        default: .finished
        }
      }
      var body: some View {
        Spinner(.init(head: "H", "A", "B", tail: "T"), stage: stage)
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition021")
    for generation in 0..<18 {
      var environment = EnvironmentValues()
      environment.accessibilityReduceMotion = true
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation, environmentValues: environment
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let expected = ["H", "A", "T"][generation % 3]
      #expect(componentCompositionText(frames.retained).contains(expected))
    }
  }
}

// MARK: - Attempt 022: Spinner set replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 022 Spinner adopts each replacement glyph set")
  func componentComposition022SpinnerAdoptsEachReplacementGlyphSet() {
    // Hypothesis: a stable Spinner state slot can retain iteration from an earlier set and
    // index or render the wrong replacement body's first glyph.
    struct Root: View {
      let generation: Int
      var set: Spinner.SpinnerSet {
        generation.isMultiple(of: 2)
          ? .init(head: "x", "A", "B", tail: "X")
          : .init(head: "y", "C", "D", "E", tail: "Y")
      }
      var body: some View { Spinner(set, stage: .active) }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition022")
    for generation in 0..<18 {
      var environment = EnvironmentValues()
      environment.accessibilityReduceMotion = true
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation, environmentValues: environment
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        componentCompositionText(frames.retained).contains(
          generation.isMultiple(of: 2) ? "A" : "C"
        )
      )
    }
  }
}

// MARK: - Attempt 023: ForeignSurface same-size payload replacement

private struct ComponentCompositionForeignPayload: ForeignSurfacePayload {
  let grid: ForeignGrid
}

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 023 ForeignSurface publishes same-size payload changes")
  func componentComposition023ForeignSurfacePublishesSameSizePayloadChanges() {
    // Hypothesis: retained draw equivalence can key a foreign payload only by type and size.
    struct Root: View {
      let generation: Int
      var body: some View {
        let first = Character(String(generation % 10))
        let second = Character(String((generation + 1) % 10))
        ForeignSurface(
          payload: ComponentCompositionForeignPayload(
            grid: .init(
              size: .init(width: 2, height: 1),
              cells: [[RasterCell(character: first), RasterCell(character: second)]]
            )
          )
        )
        .frame(width: 2, height: 1)
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition023")
    withKnownIssue("ForeignSurface retains its first same-size payload across invalidations") {
      for generation in 0..<18 {
        let frames = componentCompositionFrames(
          Root(generation: generation), renderer: renderer, identity: identity,
          generation: generation
        )
        #expect(
          frames.retained.rasterSurface == frames.fresh.rasterSurface
            && componentCompositionText(frames.retained).contains(String(generation % 10))
        )
      }
    }
  }
}

// MARK: - Attempt 024: ForeignSurface grid geometry replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 024 ForeignSurface replaces grid geometry")
  func componentComposition024ForeignSurfaceReplacesGridGeometry() {
    // Hypothesis: an earlier foreign-grid extent can survive when rows shrink and regrow.
    struct Root: View {
      let generation: Int
      var body: some View {
        let width = [1, 4, 2][generation % 3]
        let cells = [Array(repeating: RasterCell(character: "G"), count: width)]
        ForeignSurface(
          payload: ComponentCompositionForeignPayload(
            grid: .init(size: .init(width: width, height: 1), cells: cells)
          )
        )
        .frame(width: width, height: 1)
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition024")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree == frames.fresh.measuredTree)
    }
  }
}

// MARK: - Attempt 025: EquatableView topology replacement

extension FrameworkStressComponentCompositionTests {
  @Test("stress component composition 025 EquatableView insertion leaves no identity residue")
  func componentComposition025EquatableViewInsertionLeavesNoIdentityResidue() {
    // Hypothesis: adding and removing the wrapper node at one explicit identity can revive
    // an obsolete memoized subtree when the wrapped value returns.
    struct Row: View, Equatable {
      let value: String
      var body: some View { Text(value) }
    }
    struct Root: View {
      let generation: Int
      var body: some View {
        Group {
          if generation.isMultiple(of: 2) {
            Row(value: "wrapped-\(generation)").equatable()
          } else {
            Row(value: "plain-\(generation)")
          }
        }
        .id("stable-equatable-row")
      }
    }
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ComponentComposition025")
    for generation in 0..<18 {
      let frames = componentCompositionFrames(
        Root(generation: generation), renderer: renderer, identity: identity,
        generation: generation
      )
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let expected = generation.isMultiple(of: 2) ? "wrapped-\(generation)" : "plain-\(generation)"
      #expect(componentCompositionText(frames.retained).contains(expected))
    }
  }
}
