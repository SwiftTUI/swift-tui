import SwiftTUICore

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
