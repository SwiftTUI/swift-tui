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

// NEXT COMPONENT STRESS TEST
