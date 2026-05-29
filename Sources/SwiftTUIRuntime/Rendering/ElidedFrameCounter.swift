/// A simple reference-type counter for elided frames, held by `DefaultRenderer`.
///
/// Stored as a reference type so the value-type `DefaultRenderer` struct can
/// mutate the count without copying — matching the pattern used by other
/// cross-frame mutable state (e.g. `FrameTailRetainedState`).
@MainActor
final class ElidedFrameCounter {
  private(set) var count: Int = 0

  func increment() {
    count += 1
  }
}
