/// Ordered draw effects that must survive until rasterization.
package enum DrawEffect: Equatable, Sendable {
  case blendMode(BlendMode)
  case compositingGroup
  case cellLayer(CellEffectPass)
}

/// Compact ordered draw-effect storage.
package struct DrawEffects: Equatable, Sendable {
  package var ordered: [DrawEffect]

  package init(_ ordered: [DrawEffect] = []) {
    self.ordered = ordered
  }

  package var hasPlacement: Bool {
    ordered.contains { effect in
      if case .cellLayer(let pass) = effect, case .placement = pass.shader.program { return true }
      return false
    }
  }

  package var removingIdlePlacement: Self {
    guard hasPlacement else { return self }
    return .init(
      ordered.filter { effect in
        if case .cellLayer(let pass) = effect, case .placement = pass.shader.program {
          return false
        }
        return true
      })
  }

  package var isEmpty: Bool {
    ordered.isEmpty
  }

  package mutating func append(_ effect: DrawEffect) {
    ordered.append(effect)
  }
}
