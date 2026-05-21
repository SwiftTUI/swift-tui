/// Ordered draw effects that must survive until rasterization.
package enum DrawEffect: Equatable, Sendable {
  case blendMode(BlendMode)
  case compositingGroup
}

/// Compact ordered draw-effect storage.
package struct DrawEffects: Equatable, Sendable {
  package var ordered: [DrawEffect]

  package init(_ ordered: [DrawEffect] = []) {
    self.ordered = ordered
  }

  package var isEmpty: Bool {
    ordered.isEmpty
  }

  package mutating func append(_ effect: DrawEffect) {
    ordered.append(effect)
  }

  package func appending(_ effect: DrawEffect) -> Self {
    var copy = self
    copy.append(effect)
    return copy
  }
}
