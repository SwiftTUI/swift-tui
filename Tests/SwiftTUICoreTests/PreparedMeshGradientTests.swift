import SwiftTUICore
import Testing

@Test("identity 2x2 mesh covers every cell without subdivision")
func preparedMeshIdentityCoverage() {
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: identityPoints(width: 2, height: 2),
    colors: [.red, .green, .blue, .white],
    background: .black,
    bounds: meshBounds(width: 8, height: 4)
  )

  #expect(mesh.diagnostics.triangleCount == 2)
  #expect(mesh.diagnostics.maximumSubdivisionDepth == 0)
  #expect(mesh.diagnostics.coveredRowCount == 4)
  for y in 0..<4 {
    for x in 0..<8 {
      #expect(mesh.color(atCellX: x, y: y) != .black)
    }
  }
}

@Test("identity 3x3 mesh has no background seam at patch boundaries")
func preparedMeshIdentityPatchSeams() {
  let colors: [Color] = [
    .red, .green, .blue,
    .yellow, .magenta, .cyan,
    .white, .gray, .black,
  ]
  let background = Color(red: 0.0123, green: 0.0234, blue: 0.0345)
  let mesh = preparedMesh(
    width: 3,
    height: 3,
    points: identityPoints(width: 3, height: 3),
    colors: colors,
    background: background,
    bounds: meshBounds(width: 10, height: 6)
  )

  #expect(mesh.diagnostics.triangleCount == 8)
  for y in 0..<6 {
    for x in 0..<10 {
      #expect(mesh.color(atCellX: x, y: y) != background)
    }
  }
}

@Test("mesh sampling uses terminal cell centers")
func preparedMeshCellCenterConvention() {
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: identityPoints(width: 2, height: 2),
    colors: [
      Color(red: 0, green: 0, blue: 0),
      Color(red: 1, green: 0, blue: 0),
      Color(red: 0, green: 1, blue: 0),
      Color(red: 1, green: 1, blue: 0),
    ],
    bounds: meshBounds(width: 2, height: 2),
    smoothsColors: false
  )

  let sample = mesh.color(atCellX: 0, y: 0)
  #expect(abs(sample.red - 0.25) < 0.000_01)
  #expect(abs(sample.green - 0.25) < 0.000_01)
}

@Test("affine point deformation remains one leaf per patch")
func preparedMeshAffineGeometry() {
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: [
      SIMD2<Float>(-0.1, 0.1), SIMD2<Float>(0.9, 0.2),
      SIMD2<Float>(0.1, 0.9), SIMD2<Float>(1.1, 1.0),
    ],
    colors: [.red, .green, .blue, .white],
    bounds: meshBounds(width: 12, height: 8)
  )

  #expect(mesh.diagnostics.triangleCount == 2)
  #expect(mesh.diagnostics.maximumSubdivisionDepth == 0)
}

@Test("curved point deformation adaptively subdivides below the depth cap")
func preparedMeshCurvedGeometry() {
  let mesh = preparedMesh(
    width: 3,
    height: 3,
    points: [
      .init(0, 0), .init(0.5, 0), .init(1, 0),
      .init(0, 0.5), .init(0.85, 0.15), .init(1, 0.5),
      .init(0, 1), .init(0.5, 1), .init(1, 1),
    ],
    colors: Array(repeating: .cyan, count: 9),
    bounds: meshBounds(width: 40, height: 20)
  )

  #expect(mesh.diagnostics.triangleCount > 8)
  #expect(mesh.diagnostics.maximumSubdivisionDepth > 0)
  #expect(mesh.diagnostics.maximumSubdivisionDepth < 8)
}

@Test("folded 3x3 mesh with an identity boundary covers every cell")
func preparedMeshFoldedIdentityBoundaryCoverage() {
  let background = Color(red: 0.0123, green: 0.0234, blue: 0.0345)
  let mesh = preparedMesh(
    width: 3,
    height: 3,
    points: [
      .init(0, 0), .init(0.5, 0), .init(1, 0),
      .init(0, 0.5), .init(0.65, 0.05), .init(1, 0.5),
      .init(0, 1), .init(0.5, 1), .init(1, 1),
    ],
    colors: Array(repeating: .cyan, count: 9),
    background: background,
    bounds: meshBounds(width: 30, height: 9)
  )

  for y in 0..<9 {
    for x in 0..<30 {
      #expect(mesh.color(atCellX: x, y: y) != background)
    }
  }
}

@Test("folded patches use deterministic row-major later-wins ordering")
func preparedMeshFoldedLaterWins() {
  let mesh = preparedMesh(
    width: 3,
    height: 2,
    points: [
      .init(0, 0), .init(1, 0), .init(0, 0),
      .init(0, 1), .init(1, 1), .init(0, 1),
    ],
    colors: [.red, .blue, .blue, .red, .blue, .blue],
    bounds: meshBounds(width: 6, height: 4),
    smoothsColors: false
  )

  #expect(mesh.color(atCellX: 4, y: 2).blue > mesh.color(atCellX: 4, y: 2).red)
}

@Test("outside-bounds controls can cover the clipped surface")
func preparedMeshOutsideControls() {
  let background = Color(red: 0.01, green: 0.02, blue: 0.03)
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: [.init(-1, -1), .init(2, -1), .init(-1, 2), .init(2, 2)],
    colors: Array(repeating: .yellow, count: 4),
    background: background,
    bounds: meshBounds(width: 7, height: 5)
  )

  for y in 0..<5 {
    for x in 0..<7 {
      #expect(mesh.color(atCellX: x, y: y) != background)
    }
  }
}

@Test("uncovered and degenerate mesh samples return the background")
func preparedMeshBackgroundFallback() {
  let background = Color(red: 0.12, green: 0.23, blue: 0.34)
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: Array(repeating: .init(0, 0), count: 4),
    colors: [.red, .green, .blue, .white],
    background: background,
    bounds: meshBounds(width: 8, height: 4)
  )

  #expect(mesh.diagnostics.maximumSubdivisionDepth <= 8)
  #expect(mesh.color(atCellX: 4, y: 2) == background)
  #expect(mesh.color(atCellX: -1, y: 0) == background)
}

@Test("device-space center is the analytical bilinear color")
func preparedMeshDeviceColor() {
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: identityPoints(width: 2, height: 2),
    colors: [
      Color(red: 0, green: 0, blue: 0, alpha: 0),
      Color(red: 1, green: 0, blue: 0, alpha: 0.5),
      Color(red: 0, green: 1, blue: 0, alpha: 0.5),
      Color(red: 1, green: 1, blue: 1, alpha: 1),
    ],
    bounds: meshBounds(width: 1, height: 1),
    smoothsColors: false
  )

  let center = mesh.color(atCellX: 0, y: 0)
  #expect(abs(center.red - 0.5) < 0.000_01)
  #expect(abs(center.green - 0.5) < 0.000_01)
  #expect(abs(center.blue - 0.25) < 0.000_01)
  #expect(abs(center.alpha - 0.5) < 0.000_01)
}

@Test("perceptual center matches independently averaged Oklab controls")
func preparedMeshPerceptualColor() {
  let controls: [Color] = [.red, .green, .blue, .white]
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: identityPoints(width: 2, height: 2),
    colors: controls,
    bounds: meshBounds(width: 1, height: 1),
    smoothsColors: false,
    colorSpace: .perceptual
  )
  let labs = controls.map { $0.oklab() }
  let expected = Color._fromOklab(
    OklabColor(
      l: labs.reduce(0) { $0 + $1.l } / 4,
      a: labs.reduce(0) { $0 + $1.a } / 4,
      b: labs.reduce(0) { $0 + $1.b } / 4
    ),
    alpha: 1,
    profile: controls[0].profile
  ).mapped(to: controls[0].profile, policy: .compressPerceptual)
  let actual = mesh.color(atCellX: 0, y: 0)

  #expect(abs(actual.red - expected.red) < 0.000_01)
  #expect(abs(actual.green - expected.green) < 0.000_01)
  #expect(abs(actual.blue - expected.blue) < 0.000_01)
}

@Test("mixed profiles use the first control profile")
func preparedMeshFirstProfileWins() {
  let mesh = preparedMesh(
    width: 2,
    height: 2,
    points: identityPoints(width: 2, height: 2),
    colors: [
      Color(red: 1, green: 0, blue: 0, profile: .displayP3),
      Color(red: 0, green: 1, blue: 0, profile: .sRGB),
      Color(red: 0, green: 0, blue: 1, profile: .rec2020),
      Color(red: 1, green: 1, blue: 1, profile: .sRGB),
    ],
    bounds: meshBounds(width: 3, height: 3)
  )

  #expect(mesh.color(atCellX: 1, y: 1).profile == .displayP3)
}

@Test("smooth color remains continuous across an identity patch edge")
func preparedMeshSmoothColorContinuity() {
  let colors: [Color] = [
    .red, .green, .blue,
    .yellow, .white, .cyan,
    .magenta, .gray, .black,
  ]
  let mesh = preparedMesh(
    width: 3,
    height: 3,
    points: identityPoints(width: 3, height: 3),
    colors: colors,
    bounds: meshBounds(width: 100, height: 40)
  )

  let left = mesh.color(atCellX: 49, y: 19)
  let right = mesh.color(atCellX: 50, y: 19)
  #expect(abs(left.red - right.red) < 0.04)
  #expect(abs(left.green - right.green) < 0.04)
  #expect(abs(left.blue - right.blue) < 0.04)
}

@Test("sampled alpha is finite and clamped")
func preparedMeshAlphaIsBounded() {
  let mesh = preparedMesh(
    width: 3,
    height: 3,
    points: identityPoints(width: 3, height: 3),
    colors: [
      Color.red.opacity(0), Color.green.opacity(1), Color.blue.opacity(0),
      Color.yellow.opacity(1), Color.white.opacity(0), Color.cyan.opacity(1),
      Color.magenta.opacity(0), Color.gray.opacity(1), Color.black.opacity(0),
    ],
    bounds: meshBounds(width: 23, height: 11)
  )

  for y in 0..<11 {
    for x in 0..<23 {
      let alpha = mesh.color(atCellX: x, y: y).alpha
      #expect(alpha.isFinite)
      #expect((0...1).contains(alpha))
    }
  }
}

@Test("repeat preparation produces identical quantized cell colors")
func preparedMeshIsDeterministic() {
  let inputPoints: [SIMD2<Float>] = [
    .init(0, 0), .init(0.55, -0.1), .init(1, 0),
    .init(-0.1, 0.5), .init(0.45, 0.6), .init(1.1, 0.4),
    .init(0, 1), .init(0.5, 0.9), .init(1, 1),
  ]
  let colors: [Color] = [
    .red, .green, .blue,
    .yellow, .white, .cyan,
    .magenta, .gray, .black,
  ]
  let first = preparedMesh(
    width: 3,
    height: 3,
    points: inputPoints,
    colors: colors,
    bounds: meshBounds(width: 17, height: 9)
  )
  let second = preparedMesh(
    width: 3,
    height: 3,
    points: inputPoints,
    colors: colors,
    bounds: meshBounds(width: 17, height: 9)
  )

  for y in 0..<9 {
    for x in 0..<17 {
      #expect(
        first.color(atCellX: x, y: y).hexString(format: .rrggbbaa)
          == second.color(atCellX: x, y: y).hexString(format: .rrggbbaa)
      )
    }
  }
}

private func preparedMesh(
  width: Int,
  height: Int,
  points: [SIMD2<Float>],
  colors: [Color],
  background: Color = .clear,
  bounds: CellRect,
  smoothsColors: Bool = true,
  colorSpace: MeshGradientRasterColorSpace = .device
) -> PreparedMeshGradient {
  PreparedMeshGradient(
    input: MeshGradientRasterInput(
      width: width,
      height: height,
      points: points,
      colors: colors,
      background: background,
      smoothsColors: smoothsColors,
      colorSpace: colorSpace
    ),
    bounds: bounds
  )
}

private func identityPoints(width: Int, height: Int) -> [SIMD2<Float>] {
  (0..<height).flatMap { row in
    (0..<width).map { column in
      SIMD2<Float>(
        Float(column) / Float(width - 1),
        Float(row) / Float(height - 1)
      )
    }
  }
}

private func meshBounds(width: Int, height: Int) -> CellRect {
  CellRect(origin: .zero, size: CellSize(width: width, height: height))
}
