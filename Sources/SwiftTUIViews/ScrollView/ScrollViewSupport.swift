import SwiftTUICore

/// The fixed reference point captured when a drag-to-pan gesture begins.
///
/// Each subsequent `.dragged` event recomputes the offset from this anchor
/// (`startOffset` plus the fractional cell delta from `startLocation`) rather
/// than accumulating per-event deltas. Anchoring keeps panning robust against
/// dropped pointer events and re-clamps cleanly at the content edges. Stored in
/// `@State` so it survives the re-resolve each scroll mutation triggers.
///
/// `startLocation` is the continuous (sub-cell) pointer location, so panning
/// tracks the finger smoothly on sub-cell-precision hosts (iOS/native): the
/// rounded fractional delta crosses a cell boundary near the half-cell point
/// rather than only at whole-cell boundaries. On cell-only hosts the location
/// is the cell center, so deltas stay integer and behavior is unchanged.
struct ScrollPanAnchor: Equatable, Sendable {
  var startLocation: Point
  var startOffset: ScrollPosition
}

extension LocalPointerScrollContext {
  /// Maximum horizontal scroll offset (clamped to non-negative).
  var maxScrollX: Int {
    max(0, contentBounds.size.width - viewportRect.size.width)
  }

  /// Maximum vertical scroll offset (clamped to non-negative).
  var maxScrollY: Int {
    max(0, contentBounds.size.height - viewportRect.size.height)
  }
}

/// Clamps a scroll offset to `[0, maxScroll]` per axis for the given context.
///
/// Mirrors the clamp used by `LocalScrollPositionRegistry` and `ScrollViewLayout`
/// (`min(max(0, requested), max(0, content - viewport))`) so wheel, drag-pan,
/// imperative scrolling, and layout all agree on the scrollable range.
func clampedScrollOffset(
  _ offset: ScrollPosition,
  in context: LocalPointerScrollContext
) -> ScrollPosition {
  ScrollPosition(
    x: min(max(0, offset.x), context.maxScrollX),
    y: min(max(0, offset.y), context.maxScrollY)
  )
}

extension ScrollView {
  func effectiveIndicatorVisibility(
    environment: ScrollIndicatorVisibility
  ) -> ScrollIndicatorVisibility {
    guard showsIndicators else {
      return .hidden
    }
    return environment == .hidden ? .hidden : .visible
  }

  func applyScrollKey(
    _ event: KeyEvent,
    to position: inout ScrollPosition,
    targetAxis: ScrollIndicatorAxis?
  ) -> Bool {
    switch targetAxis {
    case .none:
      switch event {
      case .arrowLeft where axes.contains(.horizontal):
        guard position.x > 0 else { return false }
        position.scrollBy(x: -1)
      case .arrowRight where axes.contains(.horizontal):
        position.scrollBy(x: 1)
      case .arrowUp where axes.contains(.vertical):
        guard position.y > 0 else { return false }
        position.scrollBy(y: -1)
      case .arrowDown where axes.contains(.vertical):
        position.scrollBy(y: 1)
      case .home where axes.contains(.vertical):
        guard position.y > 0 else { return false }
        position.scrollTo(y: 0)
      case .home where axes.contains(.horizontal):
        guard position.x > 0 else { return false }
        position.scrollTo(x: 0)
      default:
        return false
      }
      return true
    case .vertical:
      guard axes.contains(.vertical) else {
        return false
      }

      switch event {
      case .home:
        guard position.y > 0 else { return false }
        position.scrollTo(y: 0)
      case .arrowUp:
        guard position.y > 0 else { return false }
        position.scrollBy(y: -1)
      case .arrowDown:
        position.scrollBy(y: 1)
      default:
        return false
      }
      return true
    case .horizontal:
      guard axes.contains(.horizontal) else {
        return false
      }

      switch event {
      case .home:
        guard position.x > 0 else { return false }
        position.scrollTo(x: 0)
      case .arrowLeft, .arrowUp:
        guard position.x > 0 else { return false }
        position.scrollBy(x: -1)
      case .arrowRight, .arrowDown:
        position.scrollBy(x: 1)
      default:
        return false
      }
      return true
    }
  }

  func scrollBoundaryEdge(
    for event: KeyEvent,
    targetAxis: ScrollIndicatorAxis?
  ) -> Edge? {
    switch targetAxis {
    case .vertical:
      guard axes.contains(.vertical) else {
        return nil
      }
      return event == .end ? .bottom : nil
    case .horizontal:
      guard axes.contains(.horizontal) else {
        return nil
      }
      return event == .end ? .trailing : nil
    case .none:
      guard event == .end else {
        return nil
      }
      if axes.contains(.vertical) {
        return .bottom
      }
      if axes.contains(.horizontal) {
        return .trailing
      }
      return nil
    }
  }
}
