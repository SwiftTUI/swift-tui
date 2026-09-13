import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Public style authoring contracts", .serialized)
struct PublicStyleContractTests {
  @Test("public intrinsic-size hint reproduces rounded editor sizing under finite proposals")
  func roundedEditorSizing() {
    for text in ["", "Short", "One\nTwo\nThree", "A long line that needs to wrap"] {
      for height in [1, 3, 8, 20] {
        for width in [8, 25] {
          let proposal = ProposedSize(width: .finite(width), height: .finite(height))
          func render(_ style: AnyTextEditorStyle) -> RenderSnapshot {
            DefaultRenderer().render(
              VStack(spacing: 0) {
                TextEditor(text: .constant(text)).textEditorStyle(style)
                Text("After")
              }, context: .init(identity: testIdentity("EditorPublicLayout")), proposal: proposal)
          }
          let expected = render(.roundedBorder)
          let actual = render(.init(ConsumerRoundedEditorStyle()))
          #expect(
            actual.rasterSurface.lines == expected.rasterSurface.lines,
            "text=\(text), width=\(width), height=\(height)")
        }
      }
    }
  }

  @Test("public picker hints reach custom styles, normalize lower bounds, and reset with nil")
  func pickerHints() {
    for hints: (Int?, Int?, String) in [(5, 12, "5,12"), (0, -2, "3,1"), (nil, nil, "-1,-1")] {
      let frame = DefaultRenderer().render(
        Picker("Mode", selection: .constant(1)) { PickerOption("One", value: 1) }
          .pickerStyle(ConsumerPickerHintsStyle())
          .pickerViewportLineCount(hints.0).pickerLineWidth(hints.1),
        context: .init(identity: testIdentity("PickerHints")), proposal: .init(width: 30, height: 8)
      )
      #expect(frame.rasterSurface.lines.joined().contains("hints=\(hints.2)"))
    }
    let frame = DefaultRenderer().render(
      Picker("Mode", selection: .constant(3)) {
        ForEach(0..<10) { PickerOption("Option \($0)", value: $0) }
      }.pickerStyle(.inline).pickerViewportLineCount(5).pickerLineWidth(12),
      context: .init(identity: testIdentity("PickerInlineHints")),
      proposal: .init(width: 30, height: 12))
    let text = frame.rasterSurface.lines.joined()
    #expect(text.contains("Option 3"))
    #expect(!text.contains("Option 0"))
    #expect(text.contains("↑") && text.contains("↓"))
  }

  @Test("a public expanding slider track maps pointer endpoints at the placed width")
  func expandingSlider() throws {
    final class Value { var value = 5 }
    for width in [12, 37] {
      let value = Value()
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("ResponsiveSlider"), size: .init(width: width, height: 4)
      ) {
        Slider("Value", value: Binding(get: { value.value }, set: { value.value = $0 }), in: 0...10)
          .sliderStyle(ConsumerExpandingSliderStyle())
      }
      defer { harness.shutdown() }
      let region = try #require(
        harness.runLoop.latestSemanticSnapshot.interactionRegions.first {
          $0.identity.description.contains("SliderTrack")
        })
      #expect(region.rect.size.width == width)
      let start = Point(x: Double(region.rect.origin.x), y: Double(region.rect.origin.y))
      _ = try harness.sendMouse(.down(.primary), at: start)
      #expect(value.value == 0)
      _ = try harness.sendMouse(
        .dragged(.primary), at: .init(x: start.x + Double(width - 1), y: start.y))
      #expect(value.value == 10)
      _ = try harness.sendMouse(
        .up(.primary), at: .init(x: start.x + Double(width - 1), y: start.y))
    }
  }
}
