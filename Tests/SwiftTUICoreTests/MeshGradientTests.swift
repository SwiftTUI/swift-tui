import Testing

@testable import SwiftTUICore

@Test("MeshGradient stores validated topology and erases without loss")
func meshGradientStoresAndErases() {
  let mesh = testMeshGradient()
  #expect(mesh.width == 2)
  #expect(mesh.height == 2)
  #expect(mesh.points.count == 4)
  #expect(mesh.colors == [.red, .green, .blue, .white])
  #expect(mesh.background == .black)
  #expect(mesh.smoothsColors)
  #expect(mesh.colorSpace == .device)
  #expect(AnyShapeStyle(mesh) == .meshGradient(mesh))
}

@Test("MeshGradient equality includes geometry, colors, background, smoothing, and color space")
func meshGradientEquality() {
  let base = testMeshGradient()
  #expect(base == testMeshGradient())
  #expect(
    base
      != MeshGradient(
        width: 2,
        height: 2,
        points: [.init(0, 0), .init(1, 0), .init(0.1, 1), .init(1, 1)],
        colors: [.red, .green, .blue, .white],
        background: .black
      ))
  #expect(
    base
      != MeshGradient(
        width: 2,
        height: 2,
        points: identityMeshPoints(),
        colors: [.red, .green, .blue, .white],
        background: .black,
        smoothsColors: false
      ))
  #expect(
    base
      != MeshGradient(
        width: 2,
        height: 2,
        points: identityMeshPoints(),
        colors: [.red, .green, .blue, .white],
        background: .black,
        colorSpace: .perceptual
      ))
}

@Test("MeshGradient opacity preserves its case and fades controls and background")
func meshGradientOpacity() throws {
  let faded = try #require(
    testMeshGradient().opacity(0.25).meshGradient
  )
  #expect(faded.points == identityMeshPoints())
  #expect(faded.colors.allSatisfy { abs($0.alpha - 0.25) < 0.000_01 })
  #expect(abs(faded.background.alpha - 0.25) < 0.000_01)
}

@Test("MeshGradient is the representative scalar and tile paint color")
func meshGradientRepresentativeColor() throws {
  let mesh = testMeshGradient()
  let resolved = try resolveStyleColorResult(
    style: .meshGradient(mesh),
    theme: .default
  ).get()
  #expect(resolved == .red)
  #expect(TileStyle.Paint(mesh).representativeColor == .red)
}

@Test("MeshGradient animatable data interpolates points colors and background")
func meshGradientAnimatableMidpoint() {
  let from = testMeshGradient()
  let to = MeshGradient(
    width: 2,
    height: 2,
    points: [.init(0, 0), .init(0.8, 0.2), .init(0.2, 0.8), .init(1, 1)],
    colors: [.blue, .yellow, .magenta, .black],
    background: .white
  )
  var result = from
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var data = from.animatableData
  data += delta
  result.animatableData = data

  #expect(abs(result.points[1].x - 0.9) < 0.000_1)
  #expect(abs(result.points[1].y - 0.1) < 0.000_1)
  #expect(result.colors[0] != from.colors[0])
  #expect(result.colors[0] != to.colors[0])
  #expect(result.background != from.background)
  #expect(result.background != to.background)
}

@Test("MeshGradient animatable setter rejects mismatched control counts atomically")
func meshGradientAnimatableCountGuard() {
  var mesh = testMeshGradient()
  let original = mesh
  let other = MeshGradient(
    width: 3,
    height: 2,
    points: [
      .init(0, 0), .init(0.5, 0), .init(1, 0),
      .init(0, 1), .init(0.5, 1), .init(1, 1),
    ],
    colors: [.red, .green, .blue, .yellow, .magenta, .cyan]
  )
  mesh.animatableData = other.animatableData
  #expect(mesh == original)
  #expect(!mesh.isInterpolable(to: other))
}

extension AnyShapeStyle {
  fileprivate var meshGradient: MeshGradient? {
    if case .meshGradient(let mesh) = self { return mesh }
    return nil
  }
}

private func testMeshGradient() -> MeshGradient {
  MeshGradient(
    width: 2,
    height: 2,
    points: identityMeshPoints(),
    colors: [.red, .green, .blue, .white],
    background: .black
  )
}

private func identityMeshPoints() -> [SIMD2<Float>] {
  [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)]
}
