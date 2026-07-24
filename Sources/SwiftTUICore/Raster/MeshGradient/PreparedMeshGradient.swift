package enum MeshGradientRasterColorSpace: Sendable {
  case device
  case perceptual
}

package struct MeshGradientRasterInput: Sendable {
  package var width: Int
  package var height: Int
  package var points: [SIMD2<Float>]
  package var colors: [Color]
  package var background: Color
  package var smoothsColors: Bool
  package var colorSpace: MeshGradientRasterColorSpace

  package init(
    width: Int,
    height: Int,
    points: [SIMD2<Float>],
    colors: [Color],
    background: Color,
    smoothsColors: Bool,
    colorSpace: MeshGradientRasterColorSpace
  ) {
    self.width = width
    self.height = height
    self.points = points
    self.colors = colors
    self.background = background
    self.smoothsColors = smoothsColors
    self.colorSpace = colorSpace
  }
}

/// Bounds-specialized geometry and color data for a single mesh paint command.
///
/// Preparation is deliberately separated from sampling: patch derivatives,
/// adaptive triangles, row bins, and working-space color vectors are all
/// produced once, while the rasterizer's inner loop performs only bounded
/// row-bin lookup and interpolation.
package struct PreparedMeshGradient: Sendable {
  package struct Diagnostics: Sendable, Equatable {
    package var triangleCount: Int
    package var maximumSubdivisionDepth: Int
    package var coveredRowCount: Int
  }

  private struct Patch: Sendable {
    var row: Int
    var column: Int
    var positions: HermitePatch
  }

  private struct Vertex: Sendable {
    var position: SIMD2<Float>
    var parameter: SIMD2<Float>
  }

  private struct Triangle: Sendable {
    var a: Vertex
    var b: Vertex
    var c: Vertex
    var patchIndex: Int
  }

  private struct HermitePatch: Sendable {
    var f00: SIMD2<Float>
    var f10: SIMD2<Float>
    var f01: SIMD2<Float>
    var f11: SIMD2<Float>
    var du00: SIMD2<Float>
    var du10: SIMD2<Float>
    var du01: SIMD2<Float>
    var du11: SIMD2<Float>
    var dv00: SIMD2<Float>
    var dv10: SIMD2<Float>
    var dv01: SIMD2<Float>
    var dv11: SIMD2<Float>
    var duv00: SIMD2<Float>
    var duv10: SIMD2<Float>
    var duv01: SIMD2<Float>
    var duv11: SIMD2<Float>

    func evaluate(u: Float, v: Float) -> SIMD2<Float> {
      let hu = Self.basis(u)
      let hv = Self.basis(v)
      var result = f00 * (hu.0 * hv.0)
      result += f10 * (hu.1 * hv.0)
      result += f01 * (hu.0 * hv.1)
      result += f11 * (hu.1 * hv.1)
      result += du00 * (hu.2 * hv.0)
      result += du10 * (hu.3 * hv.0)
      result += du01 * (hu.2 * hv.1)
      result += du11 * (hu.3 * hv.1)
      result += dv00 * (hu.0 * hv.2)
      result += dv10 * (hu.1 * hv.2)
      result += dv01 * (hu.0 * hv.3)
      result += dv11 * (hu.1 * hv.3)
      result += duv00 * (hu.2 * hv.2)
      result += duv10 * (hu.3 * hv.2)
      result += duv01 * (hu.2 * hv.3)
      result += duv11 * (hu.3 * hv.3)
      return result
    }

    private static func basis(_ t: Float) -> (Float, Float, Float, Float) {
      let t2 = t * t
      let t3 = t2 * t
      return (
        (2 * t3) - (3 * t2) + 1,
        (-2 * t3) + (3 * t2),
        t3 - (2 * t2) + t,
        t3 - t2
      )
    }
  }

  private struct ColorField: Sendable {
    var width: Int
    var height: Int
    var values: [SIMD4<Float>]
    var du: [SIMD4<Float>]
    var dv: [SIMD4<Float>]
    var duv: [SIMD4<Float>]
    var smooths: Bool
    var colorSpace: MeshGradientRasterColorSpace
    var profile: RGBColorProfile

    func sample(patchRow: Int, patchColumn: Int, u: Float, v: Float) -> Color {
      let i00 = index(column: patchColumn, row: patchRow)
      let i10 = index(column: patchColumn + 1, row: patchRow)
      let i01 = index(column: patchColumn, row: patchRow + 1)
      let i11 = index(column: patchColumn + 1, row: patchRow + 1)

      let vector: SIMD4<Float>
      if smooths {
        let hu = Self.basis(u)
        let hv = Self.basis(v)
        var result = values[i00] * (hu.0 * hv.0)
        result += values[i10] * (hu.1 * hv.0)
        result += values[i01] * (hu.0 * hv.1)
        result += values[i11] * (hu.1 * hv.1)
        result += du[i00] * (hu.2 * hv.0)
        result += du[i10] * (hu.3 * hv.0)
        result += du[i01] * (hu.2 * hv.1)
        result += du[i11] * (hu.3 * hv.1)
        result += dv[i00] * (hu.0 * hv.2)
        result += dv[i10] * (hu.1 * hv.2)
        result += dv[i01] * (hu.0 * hv.3)
        result += dv[i11] * (hu.1 * hv.3)
        result += duv[i00] * (hu.2 * hv.2)
        result += duv[i10] * (hu.3 * hv.2)
        result += duv[i01] * (hu.2 * hv.3)
        result += duv[i11] * (hu.3 * hv.3)
        vector = result
      } else {
        let top = values[i00] + ((values[i10] - values[i00]) * u)
        let bottom = values[i01] + ((values[i11] - values[i01]) * u)
        vector = top + ((bottom - top) * v)
      }

      let alpha = Double(Self.clampFinite(vector.w))
      switch colorSpace {
      case .device:
        return Color(
          red: Double(Self.finite(vector.x)),
          green: Double(Self.finite(vector.y)),
          blue: Double(Self.finite(vector.z)),
          alpha: alpha,
          profile: profile
        )
      case .perceptual:
        let reconstructed = Color._fromOklab(
          OklabColor(
            l: Double(Self.finite(vector.x)),
            a: Double(Self.finite(vector.y)),
            b: Double(Self.finite(vector.z))
          ),
          alpha: alpha,
          profile: profile
        )
        return reconstructed.mapped(to: profile, policy: .compressPerceptual)
      }
    }

    private func index(column: Int, row: Int) -> Int {
      (row * width) + column
    }

    private static func basis(_ t: Float) -> (Float, Float, Float, Float) {
      let t2 = t * t
      let t3 = t2 * t
      return (
        (2 * t3) - (3 * t2) + 1,
        (-2 * t3) + (3 * t2),
        t3 - (2 * t2) + t,
        t3 - t2
      )
    }

    private static func finite(_ value: Float) -> Float {
      value.isFinite ? value : 0
    }

    private static func clampFinite(_ value: Float) -> Float {
      min(1, max(0, finite(value)))
    }
  }

  private let bounds: CellRect
  private let patches: [Patch]
  private let triangles: [Triangle]
  private let rowBins: [[Int]]
  private let colors: ColorField
  private let background: Color
  package let diagnostics: Diagnostics

  package init(input: MeshGradientRasterInput, bounds: CellRect) {
    precondition(input.width >= 2 && input.height >= 2)
    let (count, overflow) = input.width.multipliedReportingOverflow(by: input.height)
    precondition(!overflow && input.points.count == count && input.colors.count == count)

    self.bounds = bounds
    let cellPoints = input.points.map { point in
      SIMD2<Float>(
        Float(bounds.origin.x) + (point.x * Float(bounds.size.width)),
        Float(bounds.origin.y) + (point.y * Float(bounds.size.height))
      )
    }
    let positionDerivatives = Self.derivatives(
      values: cellPoints,
      width: input.width,
      height: input.height
    )

    var preparedPatches: [Patch] = []
    preparedPatches.reserveCapacity((input.width - 1) * (input.height - 1))
    for row in 0..<(input.height - 1) {
      for column in 0..<(input.width - 1) {
        let i00 = (row * input.width) + column
        let i10 = i00 + 1
        let i01 = i00 + input.width
        let i11 = i01 + 1
        preparedPatches.append(
          Patch(
            row: row,
            column: column,
            positions: HermitePatch(
              f00: cellPoints[i00],
              f10: cellPoints[i10],
              f01: cellPoints[i01],
              f11: cellPoints[i11],
              du00: positionDerivatives.du[i00],
              du10: positionDerivatives.du[i10],
              du01: positionDerivatives.du[i01],
              du11: positionDerivatives.du[i11],
              dv00: positionDerivatives.dv[i00],
              dv10: positionDerivatives.dv[i10],
              dv01: positionDerivatives.dv[i01],
              dv11: positionDerivatives.dv[i11],
              duv00: positionDerivatives.duv[i00],
              duv10: positionDerivatives.duv[i10],
              duv01: positionDerivatives.duv[i01],
              duv11: positionDerivatives.duv[i11]
            )
          )
        )
      }
    }
    self.patches = preparedPatches

    var preparedTriangles: [Triangle] = []
    var maximumDepth = 0
    for patchIndex in preparedPatches.indices {
      Self.tessellate(
        patch: preparedPatches[patchIndex].positions,
        patchIndex: patchIndex,
        u0: 0,
        u1: 1,
        v0: 0,
        v1: 1,
        depth: 0,
        maximumDepth: &maximumDepth,
        triangles: &preparedTriangles
      )
    }
    self.triangles = preparedTriangles

    var bins = Array(repeating: [Int](), count: max(0, bounds.size.height))
    for triangleIndex in preparedTriangles.indices {
      let triangle = preparedTriangles[triangleIndex]
      let minY = min(triangle.a.position.y, min(triangle.b.position.y, triangle.c.position.y))
      let maxY = max(triangle.a.position.y, max(triangle.b.position.y, triangle.c.position.y))
      let first = max(
        bounds.origin.y,
        Int((minY - 0.5).rounded(.up))
      )
      let last = min(
        bounds.origin.y + bounds.size.height - 1,
        Int((maxY - 0.5).rounded(.down))
      )
      guard first <= last else { continue }
      for y in first...last {
        bins[y - bounds.origin.y].append(triangleIndex)
      }
    }
    self.rowBins = bins

    let profile = input.colors[0].profile
    let convertedColors = input.colors.map {
      $0.converted(to: profile, gamutMapping: .preserve)
    }
    let vectors: [SIMD4<Float>] = convertedColors.map { color in
      switch input.colorSpace {
      case .device:
        return SIMD4<Float>(
          Float(color.red),
          Float(color.green),
          Float(color.blue),
          Float(color.alpha)
        )
      case .perceptual:
        let lab = color.oklab()
        return SIMD4<Float>(
          Float(lab.l),
          Float(lab.a),
          Float(lab.b),
          Float(color.alpha)
        )
      }
    }
    let colorDerivatives = Self.derivatives(
      values: vectors,
      width: input.width,
      height: input.height
    )
    self.colors = ColorField(
      width: input.width,
      height: input.height,
      values: vectors,
      du: colorDerivatives.du,
      dv: colorDerivatives.dv,
      duv: colorDerivatives.duv,
      smooths: input.smoothsColors,
      colorSpace: input.colorSpace,
      profile: profile
    )
    self.background = input.background.converted(to: profile, gamutMapping: .preserve)
    self.diagnostics = Diagnostics(
      triangleCount: preparedTriangles.count,
      maximumSubdivisionDepth: maximumDepth,
      coveredRowCount: bins.reduce(into: 0) { count, bin in
        if !bin.isEmpty { count += 1 }
      }
    )
  }

  package func color(atCellX x: Int, y: Int) -> Color {
    guard
      x >= bounds.origin.x,
      x < bounds.origin.x + bounds.size.width,
      y >= bounds.origin.y,
      y < bounds.origin.y + bounds.size.height
    else {
      return background
    }

    let point = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
    var match: (patchIndex: Int, parameter: SIMD2<Float>)?
    for triangleIndex in rowBins[y - bounds.origin.y] {
      let triangle = triangles[triangleIndex]
      guard let weights = Self.barycentric(point, in: triangle) else {
        continue
      }
      let parameter =
        (triangle.a.parameter * weights.x)
        + (triangle.b.parameter * weights.y)
        + (triangle.c.parameter * weights.z)
      match = (triangle.patchIndex, parameter)
    }

    guard let match else {
      return background
    }
    let patch = patches[match.patchIndex]
    return colors.sample(
      patchRow: patch.row,
      patchColumn: patch.column,
      u: min(1, max(0, match.parameter.x)),
      v: min(1, max(0, match.parameter.y))
    )
  }

  private static func derivatives<Vector: SIMD>(
    values: [Vector],
    width: Int,
    height: Int
  ) -> (du: [Vector], dv: [Vector], duv: [Vector])
  where Vector.Scalar == Float {
    func index(_ column: Int, _ row: Int) -> Int {
      (row * width) + column
    }
    func horizontal(_ column: Int, _ row: Int) -> Vector {
      if column == 0 {
        return values[index(1, row)] - values[index(0, row)]
      }
      if column == width - 1 {
        return values[index(column, row)] - values[index(column - 1, row)]
      }
      return (values[index(column + 1, row)] - values[index(column - 1, row)]) * 0.5
    }
    func vertical(_ source: [Vector], _ column: Int, _ row: Int) -> Vector {
      if row == 0 {
        return source[index(column, 1)] - source[index(column, 0)]
      }
      if row == height - 1 {
        return source[index(column, row)] - source[index(column, row - 1)]
      }
      return (source[index(column, row + 1)] - source[index(column, row - 1)]) * 0.5
    }

    var du = values
    var dv = values
    for row in 0..<height {
      for column in 0..<width {
        du[index(column, row)] = horizontal(column, row)
        dv[index(column, row)] = vertical(values, column, row)
      }
    }

    var duv = values
    for row in 0..<height {
      for column in 0..<width {
        let verticalDu = vertical(du, column, row)
        let horizontalDv: Vector
        if column == 0 {
          horizontalDv = dv[index(1, row)] - dv[index(0, row)]
        } else if column == width - 1 {
          horizontalDv = dv[index(column, row)] - dv[index(column - 1, row)]
        } else {
          horizontalDv =
            (dv[index(column + 1, row)] - dv[index(column - 1, row)]) * 0.5
        }
        duv[index(column, row)] = (verticalDu + horizontalDv) * 0.5
      }
    }
    return (du, dv, duv)
  }

  private static func tessellate(
    patch: HermitePatch,
    patchIndex: Int,
    u0: Float,
    u1: Float,
    v0: Float,
    v1: Float,
    depth: Int,
    maximumDepth: inout Int,
    triangles: inout [Triangle]
  ) {
    maximumDepth = max(maximumDepth, depth)
    let um = (u0 + u1) * 0.5
    let vm = (v0 + v1) * 0.5
    let uError = max(
      midpointError(patch: patch, u0: u0, u1: u1, v: v0),
      max(
        midpointError(patch: patch, u0: u0, u1: u1, v: vm),
        midpointError(patch: patch, u0: u0, u1: u1, v: v1)
      )
    )
    let vError = max(
      midpointError(patch: patch, v0: v0, v1: v1, u: u0),
      max(
        midpointError(patch: patch, v0: v0, v1: v1, u: um),
        midpointError(patch: patch, v0: v0, v1: v1, u: u1)
      )
    )
    let planarError = planarCenterError(
      patch: patch,
      u0: u0,
      u1: u1,
      v0: v0,
      v1: v1
    )
    var splitU = uError > 0.25
    var splitV = vError > 0.25
    if planarError > 0.25 && !splitU && !splitV {
      splitU = true
      splitV = true
    }

    guard depth < 8, splitU || splitV else {
      appendLeaf(
        patch: patch,
        patchIndex: patchIndex,
        u0: u0,
        u1: u1,
        v0: v0,
        v1: v1,
        triangles: &triangles
      )
      return
    }

    if splitU && splitV {
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: u0, u1: um, v0: v0, v1: vm,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: um, u1: u1, v0: v0, v1: vm,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: u0, u1: um, v0: vm, v1: v1,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: um, u1: u1, v0: vm, v1: v1,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
    } else if splitU {
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: u0, u1: um, v0: v0, v1: v1,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: um, u1: u1, v0: v0, v1: v1,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
    } else {
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: u0, u1: u1, v0: v0, v1: vm,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
      tessellate(
        patch: patch, patchIndex: patchIndex,
        u0: u0, u1: u1, v0: vm, v1: v1,
        depth: depth + 1, maximumDepth: &maximumDepth, triangles: &triangles)
    }
  }

  private static func midpointError(
    patch: HermitePatch,
    u0: Float,
    u1: Float,
    v: Float
  ) -> Float {
    let midpoint = patch.evaluate(u: (u0 + u1) * 0.5, v: v)
    let chord = (patch.evaluate(u: u0, v: v) + patch.evaluate(u: u1, v: v)) * 0.5
    return length(midpoint - chord)
  }

  private static func midpointError(
    patch: HermitePatch,
    v0: Float,
    v1: Float,
    u: Float
  ) -> Float {
    let midpoint = patch.evaluate(u: u, v: (v0 + v1) * 0.5)
    let chord = (patch.evaluate(u: u, v: v0) + patch.evaluate(u: u, v: v1)) * 0.5
    return length(midpoint - chord)
  }

  private static func planarCenterError(
    patch: HermitePatch,
    u0: Float,
    u1: Float,
    v0: Float,
    v1: Float
  ) -> Float {
    let actual = patch.evaluate(u: (u0 + u1) * 0.5, v: (v0 + v1) * 0.5)
    let diagonal =
      (patch.evaluate(u: u0, v: v0) + patch.evaluate(u: u1, v: v1)) * 0.5
    return length(actual - diagonal)
  }

  private static func appendLeaf(
    patch: HermitePatch,
    patchIndex: Int,
    u0: Float,
    u1: Float,
    v0: Float,
    v1: Float,
    triangles: inout [Triangle]
  ) {
    let p00 = Vertex(position: patch.evaluate(u: u0, v: v0), parameter: .init(u0, v0))
    let p10 = Vertex(position: patch.evaluate(u: u1, v: v0), parameter: .init(u1, v0))
    let p01 = Vertex(position: patch.evaluate(u: u0, v: v1), parameter: .init(u0, v1))
    let p11 = Vertex(position: patch.evaluate(u: u1, v: v1), parameter: .init(u1, v1))
    appendOrientedTriangle(a: p00, b: p10, c: p11, patchIndex: patchIndex, to: &triangles)
    appendOrientedTriangle(a: p00, b: p11, c: p01, patchIndex: patchIndex, to: &triangles)
  }

  private static func appendOrientedTriangle(
    a: Vertex,
    b: Vertex,
    c: Vertex,
    patchIndex: Int,
    to triangles: inout [Triangle]
  ) {
    if cross(b.position - a.position, c.position - a.position) < 0 {
      triangles.append(Triangle(a: a, b: c, c: b, patchIndex: patchIndex))
    } else {
      triangles.append(Triangle(a: a, b: b, c: c, patchIndex: patchIndex))
    }
  }

  private static func barycentric(
    _ point: SIMD2<Float>,
    in triangle: Triangle
  ) -> SIMD3<Float>? {
    let area = cross(
      triangle.b.position - triangle.a.position,
      triangle.c.position - triangle.a.position
    )
    guard area.isFinite, area > 0.000_001 else {
      return nil
    }

    let edgeAB = cross(triangle.b.position - triangle.a.position, point - triangle.a.position)
    let edgeBC = cross(triangle.c.position - triangle.b.position, point - triangle.b.position)
    let edgeCA = cross(triangle.a.position - triangle.c.position, point - triangle.c.position)
    guard
      owns(edgeAB, edge: triangle.b.position - triangle.a.position),
      owns(edgeBC, edge: triangle.c.position - triangle.b.position),
      owns(edgeCA, edge: triangle.a.position - triangle.c.position)
    else {
      return nil
    }

    let wa = cross(triangle.b.position - point, triangle.c.position - point) / area
    let wb = cross(triangle.c.position - point, triangle.a.position - point) / area
    let wc = 1 - wa - wb
    return SIMD3<Float>(wa, wb, wc)
  }

  private static func owns(_ value: Float, edge: SIMD2<Float>) -> Bool {
    if value > 0 { return true }
    if value < 0 { return false }
    return edge.y > 0 || (edge.y == 0 && edge.x < 0)
  }

  private static func cross(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Float {
    (lhs.x * rhs.y) - (lhs.y * rhs.x)
  }

  private static func length(_ vector: SIMD2<Float>) -> Float {
    ((vector.x * vector.x) + (vector.y * vector.y)).squareRoot()
  }
}
