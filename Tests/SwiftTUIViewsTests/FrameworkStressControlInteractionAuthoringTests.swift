import SwiftTUIPrimitives
import Testing

@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI control interaction authoring stress behavior", .serialized)
struct FrameworkStressControlInteractionAuthoringTests {
  @Test("stress control interaction 014 one-cell slider authors its lower bound")
  func controlInteraction014OneCellSliderAuthorsLowerBound() {
    // Hypothesis: degenerate track division can manufacture a midpoint or upper-bound value.
    let value = sliderValue(
      at: 40.5,
      in: .init(origin: .init(x: 40, y: 2), size: .init(width: 1, height: 1)),
      bounds: 3...11,
      step: 2
    )
    #expect(value == 3)
  }

  @Test("stress control interaction 015 three-cell slider reserves both border cells")
  func controlInteraction015ThreeCellSliderReservesBothBorders() {
    // Hypothesis: the minimum bordered slider can expose a phantom second selectable position.
    let value = sliderValue(
      at: 12.5,
      in: .init(origin: .init(x: 10, y: 0), size: .init(width: 3, height: 1)),
      bounds: 0...10,
      step: 1
    )
    #expect(value == 0)
  }

  @Test("stress control interaction 016 shifted slider midpoint ignores global origin")
  func controlInteraction016ShiftedSliderMidpointIgnoresGlobalOrigin() {
    // Hypothesis: normalization can use terminal X directly instead of subtracting track origin.
    let value = sliderValue(
      at: 105.5,
      in: .init(origin: .init(x: 100, y: 0), size: .init(width: 11, height: 1)),
      bounds: 0.0...1.0,
      step: 0.25
    )
    #expect(value == 0.5)
  }

  @Test("stress control interaction 017 nonfinite slider location maps to lower bound")
  func controlInteraction017NonfiniteSliderLocationMapsLowerBound() {
    // Hypothesis: NaN pointer coordinates can escape clamping and poison numeric conversion.
    let value = sliderValue(
      at: .nan,
      in: .init(origin: .zero, size: .init(width: 9, height: 1)),
      bounds: -4.0...4.0,
      step: 0.5
    )
    #expect(value == -4.0)
  }

  @Test("stress control interaction 018 integer slider reaches a nondivisible upper bound")
  func controlInteraction018IntegerSliderReachesNondivisibleUpperBound() {
    // Hypothesis: step snapping can leave the right edge below an upper bound off the step grid.
    let value = sliderValue(
      at: 20.5,
      in: .init(origin: .init(x: 10, y: 0), size: .init(width: 11, height: 1)),
      bounds: 3...10,
      step: 4
    )
    #expect(value == 10)
  }

  @Test("stress control interaction 019 zero-span slider track keeps one marker")
  func controlInteraction019ZeroSpanSliderTrackKeepsOneMarker() {
    // Hypothesis: a zero-span range can yield NaN and either trap or drop the authored marker.
    #expect(sliderTrack(value: 5, bounds: 5...5) == "●───────")
  }

  @Test("stress control interaction 020 selection delta gives vertical motion precedence")
  func controlInteraction020SelectionDeltaGivesVerticalMotionPrecedence() {
    // Hypothesis: diagonal pointer motion can select by horizontal drift instead of row movement.
    #expect(pointerSelectionDelta(deltaX: 7, deltaY: -2) == -2)
  }

  @Test("stress control interaction 021 value delta gives horizontal motion precedence")
  func controlInteraction021ValueDeltaGivesHorizontalMotionPrecedence() {
    // Hypothesis: a diagonal slider drag can invert vertical motion despite a horizontal sample.
    #expect(pointerValueDelta(deltaX: -3, deltaY: 8) == -3)
  }

  @Test("stress control interaction 022 clamped update performs no binding write")
  func controlInteraction022ClampedUpdatePerformsNoBindingWrite() {
    // Hypothesis: an outward adjustment at the bound can still call the user's setter.
    var value = 10
    var writes = 0
    let binding = Binding(
      get: { value },
      set: {
        value = $0
        writes += 1
      }
    )

    #expect(!updateBoundControlValue(binding, delta: 1, step: 2, bounds: 0...10))
    #expect(value == 10)
    #expect(writes == 0)
  }

  @Test("stress control interaction 023 effective update performs exactly one binding write")
  func controlInteraction023EffectiveUpdatePerformsExactlyOneBindingWrite() {
    // Hypothesis: re-reading a closure binding can cause duplicate setter calls for one adjustment.
    var value = 4
    var writes = 0
    let binding = Binding(
      get: { value },
      set: {
        value = $0
        writes += 1
      }
    )

    #expect(updateBoundControlValue(binding, delta: 2, step: 3, bounds: 0...12))
    #expect(value == 10)
    #expect(writes == 1)
  }

  @Test("stress control interaction 024 large selection step clamps to final tag")
  func controlInteraction024LargeSelectionStepClampsToFinalTag() {
    // Hypothesis: a multi-row delta can index beyond the ordered tag array before clamping.
    var selection = "B"
    let binding = Binding(get: { selection }, set: { selection = $0 })
    let tags = [
      SelectionTag(value: "A"),
      SelectionTag(value: "B"),
      SelectionTag(value: "C"),
    ]

    #expect(stepBoundSelection(binding, orderedTags: tags, delta: 100))
    #expect(selection == "C")
  }

  @Test("stress control interaction 025 scalar tag writes optional selection")
  func controlInteraction025ScalarTagWritesOptionalSelection() {
    // Hypothesis: optional bridging can match a scalar tag but fail when writing it to the binding.
    var selection: Int?
    let binding = Binding(get: { selection }, set: { selection = $0 })

    #expect(setBoundSelection(binding, to: SelectionTag(value: 42, includeOptional: true)))
    #expect(selection == 42)
  }
}
