import Testing

@testable import SwiftTUIViews

@MainActor
@Suite
struct GesturePointerCapturePolicyTests {
  @Test("built-in gesture capture requirements preserve their child composition")
  func builtInCaptureRequirements() {
    #expect(DragGesture._needsPointerCapture)
    #expect(LongPressGesture._needsPointerCapture)
    #expect(!TapGesture._needsPointerCapture)
    #expect(!SpatialTapGesture._needsPointerCapture)

    typealias Simultaneous = SimultaneousGesture<TapGesture, DragGesture>
    typealias Sequence = SequenceGesture<TapGesture, DragGesture>
    typealias Exclusive = ExclusiveGesture<_MapGesture<DragGesture, Void>, TapGesture>
    #expect(Simultaneous._needsPointerCapture)
    #expect(Sequence._needsPointerCapture)
    #expect(Exclusive._needsPointerCapture)

    typealias TapSimultaneous = SimultaneousGesture<TapGesture, SpatialTapGesture>
    typealias TapSequence = SequenceGesture<TapGesture, SpatialTapGesture>
    typealias TapExclusive = ExclusiveGesture<TapGesture, TapGesture>
    #expect(!TapSimultaneous._needsPointerCapture)
    #expect(!TapSequence._needsPointerCapture)
    #expect(!TapExclusive._needsPointerCapture)

    typealias ChangedDrag = _ChangedGesture<DragGesture>
    typealias EndedDrag = _EndedGesture<DragGesture>
    typealias MappedDrag = _MapGesture<DragGesture, Void>
    typealias UpdatingDrag = GestureStateGesture<DragGesture, Bool>
    #expect(ChangedDrag._needsPointerCapture)
    #expect(EndedDrag._needsPointerCapture)
    #expect(MappedDrag._needsPointerCapture)
    #expect(UpdatingDrag._needsPointerCapture)
  }
}
