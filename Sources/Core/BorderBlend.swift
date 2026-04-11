/// A perimeter-sampled border blend (placeholder for Milestone 5).
///
/// M2 carries this type through ``LayoutBehavior/border(_:foreground:background:blend:blendPhase:sides:)``
/// so the layout engine can thread it to the rasterizer without the
/// downstream milestones needing to touch the enum again.  The real
/// sampling logic — color stops, perimeter parameterisation, and phase
/// shifting — lands in M5.
///
/// Until M5 this is intentionally a marker: an empty, ``Equatable``,
/// ``Sendable`` value.  The layout engine ignores it entirely (it does
/// not influence frame size), and the rasterizer will fall through to
/// the solid-color path whenever it sees the M2 stub.
// M5: real stops + perimeter sampling
public struct BorderBlend: Equatable, Sendable {
  public init() {}
}
