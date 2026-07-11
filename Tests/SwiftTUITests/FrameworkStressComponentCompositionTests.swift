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
