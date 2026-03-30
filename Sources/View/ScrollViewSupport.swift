import Core

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
    _ event: LocalKeyEvent,
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
      default:
        return false
      }
      return true
    case .vertical:
      guard axes.contains(.vertical) else {
        return false
      }

      switch event {
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
}
