import Testing

@testable import Core

@Suite
struct LayoutEngineTests {
  @Test("measure leaf node with intrinsic size")
  func measureLeafWithIntrinsicSize() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("leaf"),
      kind: .view("Test"),
      environmentSnapshot: .init(),
      transactionSnapshot: .init(),
      intrinsicSize: Size(width: 10, height: 3)
    )

    let measured = engine.measure(resolved, proposal: .unspecified)
    #expect(measured.measuredSize == Size(width: 10, height: 3))
  }

  @Test("measure with explicit proposal clamps size")
  func measureWithExplicitProposal() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("leaf"),
      kind: .view("Test"),
      environmentSnapshot: .init(),
      transactionSnapshot: .init(),
      intrinsicSize: Size(width: 100, height: 50)
    )

    let measured = engine.measure(
      resolved,
      proposal: ProposedSize(width: 20, height: 10)
    )
    #expect(measured.measuredSize.width <= 20)
    #expect(measured.measuredSize.height <= 10)
  }

  @Test("place node at origin")
  func placeNodeAtOrigin() {
    let engine = LayoutEngine()
    let resolved = ResolvedNode(
      identity: testIdentity("leaf"),
      kind: .view("Test"),
      environmentSnapshot: .init(),
      transactionSnapshot: .init(),
      intrinsicSize: Size(width: 10, height: 3)
    )

    let measured = engine.measure(resolved)
    let placed = engine.place(resolved, measured: measured, origin: .zero)
    #expect(placed.bounds.origin == .zero)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("measurement cache returns cached result for same input")
  func measurementCacheHit() {
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)
    let resolved = ResolvedNode(
      identity: testIdentity("cached"),
      kind: .view("Test"),
      environmentSnapshot: .init(),
      transactionSnapshot: .init(),
      intrinsicSize: Size(width: 5, height: 2)
    )

    _ = engine.measure(resolved)
    let metrics1 = cache.metrics
    _ = engine.measure(resolved)
    let metrics2 = cache.metrics

    #expect(metrics2.hits == metrics1.hits + 1)
  }
}
