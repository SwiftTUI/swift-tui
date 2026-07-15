package struct BuiltinLayoutChildPlacement: Sendable {
  package var proposal: ProposedSize
  package var bounds: CellRect
}

extension LayoutEngine {
  package func measureBuiltinLayout(
    behavior: LayoutBehavior,
    children: [ResolvedNode],
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    let container = builtinLayoutDelegationContainer(
      behavior: behavior,
      children: children
    )
    return measureIterative(
      container,
      proposal: proposal,
      passContext: passContext,
      allowsRootReuse: false
    )
  }

  package func placeBuiltinLayout(
    behavior: LayoutBehavior,
    children: [ResolvedNode],
    proposal: ProposedSize,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [BuiltinLayoutChildPlacement] {
    let container = builtinLayoutDelegationContainer(
      behavior: behavior,
      children: children
    )
    let measured = measureIterative(
      container,
      proposal: proposal,
      passContext: passContext,
      allowsRootReuse: false
    )
    return placementRequests(
      for: container,
      measured: measured,
      in: bounds,
      viewportContext: nil,
      passContext: passContext
    ).map { request in
      BuiltinLayoutChildPlacement(
        proposal: request.measured.proposal,
        bounds: request.bounds
      )
    }
  }

  private func builtinLayoutDelegationContainer(
    behavior: LayoutBehavior,
    children: [ResolvedNode]
  ) -> ResolvedNode {
    switch behavior {
    case .stack, .overlay:
      break
    default:
      preconditionFailure("builtin Layout delegation only supports stack and overlay behavior")
    }

    return ResolvedNode(
      identity: Identity(components: ["SwiftTUIBuiltinLayoutDelegation"]),
      kind: .view("BuiltinLayoutDelegation"),
      children: children,
      layoutBehavior: behavior
    )
  }
}
