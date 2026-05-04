#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, Android, some older Wasm
#elseif canImport(WASILibc)
  internal import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  internal import ucrt  // Windows
#endif

// MARK: - Science types

public struct XYZColor: Hashable, Sendable, Codable {
  public let x: Double
  public let y: Double
  public let z: Double
  public let whitePoint: ReferenceWhite

  public init(x: Double, y: Double, z: Double, whitePoint: ReferenceWhite) {
    precondition(_PrismNumeric.isFinite(x, y, z), "XYZ components must be finite")
    self.x = x
    self.y = y
    self.z = z
    self.whitePoint = whitePoint
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      x: try c.decode(Double.self, forKey: .x),
      y: try c.decode(Double.self, forKey: .y),
      z: try c.decode(Double.self, forKey: .z),
      whitePoint: try c.decode(ReferenceWhite.self, forKey: .whitePoint)
    )
  }
}

public struct LabColor: Hashable, Sendable, Codable {
  public let l: Double
  public let a: Double
  public let b: Double
  public let whitePoint: ReferenceWhite

  public init(l: Double, a: Double, b: Double, whitePoint: ReferenceWhite) {
    precondition(_PrismNumeric.isFinite(l, a, b), "Lab components must be finite")
    self.l = l
    self.a = a
    self.b = b
    self.whitePoint = whitePoint
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      l: try c.decode(Double.self, forKey: .l),
      a: try c.decode(Double.self, forKey: .a),
      b: try c.decode(Double.self, forKey: .b),
      whitePoint: try c.decode(ReferenceWhite.self, forKey: .whitePoint)
    )
  }
}

public struct LChColor: Hashable, Sendable, Codable {
  public let l: Double
  public let c: Double
  public let h: Double
  public let whitePoint: ReferenceWhite

  public init(l: Double, c: Double, h: Double, whitePoint: ReferenceWhite) {
    precondition(_PrismNumeric.isFinite(l, c, h), "LCh components must be finite")
    self.l = l
    self.c = c
    self.h = _PrismNumeric.wrapDegrees(h)
    self.whitePoint = whitePoint
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      l: try c.decode(Double.self, forKey: .l),
      c: try c.decode(Double.self, forKey: .c),
      h: try c.decode(Double.self, forKey: .h),
      whitePoint: try c.decode(ReferenceWhite.self, forKey: .whitePoint)
    )
  }
}

public struct OklabColor: Hashable, Sendable, Codable {
  public let l: Double
  public let a: Double
  public let b: Double

  public init(l: Double, a: Double, b: Double) {
    precondition(_PrismNumeric.isFinite(l, a, b), "Oklab components must be finite")
    self.l = l
    self.a = a
    self.b = b
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      l: try c.decode(Double.self, forKey: .l),
      a: try c.decode(Double.self, forKey: .a),
      b: try c.decode(Double.self, forKey: .b)
    )
  }
}

public struct OklchColor: Hashable, Sendable, Codable {
  public let l: Double
  public let c: Double
  public let h: Double

  public init(l: Double, c: Double, h: Double) {
    precondition(_PrismNumeric.isFinite(l, c, h), "Oklch components must be finite")
    self.l = l
    self.c = c
    self.h = _PrismNumeric.wrapDegrees(h)
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      l: try c.decode(Double.self, forKey: .l),
      c: try c.decode(Double.self, forKey: .c),
      h: try c.decode(Double.self, forKey: .h)
    )
  }
}

// MARK: - Matrix generation and adaptation

internal func _chromaticityToXYZ(_ c: Chromaticity) -> Vector3 {
  Vector3(x: c.x / c.y, y: 1.0, z: (1.0 - c.x - c.y) / c.y)
}

internal func _makeRGBToXYZMatrix(primaries: RGBPrimaries, whitePoint: ReferenceWhite) -> Matrix3x3
{
  let r = _chromaticityToXYZ(primaries.red)
  let g = _chromaticityToXYZ(primaries.green)
  let b = _chromaticityToXYZ(primaries.blue)
  let m = Matrix3x3(
    m11: r.x, m12: g.x, m13: b.x,
    m21: r.y, m22: g.y, m23: b.y,
    m31: r.z, m32: g.z, m33: b.z
  )
  let whiteXYZ = whitePoint.xyz
  let s = m.inverse * Vector3(x: whiteXYZ.x, y: whiteXYZ.y, z: whiteXYZ.z)
  return Matrix3x3(
    m11: m.m11 * s.x, m12: m.m12 * s.y, m13: m.m13 * s.z,
    m21: m.m21 * s.x, m22: m.m22 * s.y, m23: m.m23 * s.z,
    m31: m.m31 * s.x, m32: m.m32 * s.y, m33: m.m33 * s.z
  )
}

internal func _adaptationMatrix(_ method: ChromaticAdaptationMethod) -> Matrix3x3 {
  switch method {
  case .bradford:
    return Matrix3x3(
      m11: 0.8951, m12: 0.2664, m13: -0.1614,
      m21: -0.7502, m22: 1.7135, m23: 0.0367,
      m31: 0.0389, m32: -0.0685, m33: 1.0296
    )
  case .cat02:
    return Matrix3x3(
      m11: 0.7328, m12: 0.4296, m13: -0.1624,
      m21: -0.7036, m22: 1.6975, m23: 0.0061,
      m31: 0.0030, m32: 0.0136, m33: 0.9834
    )
  }
}

public func adapt(
  _ xyz: XYZColor,
  to targetWhite: ReferenceWhite,
  method: ChromaticAdaptationMethod = .bradford
) -> XYZColor {
  if xyz.whitePoint == targetWhite { return xyz }
  let m = _adaptationMatrix(method)
  let mInv = m.inverse
  let sourceCone =
    m * Vector3(x: xyz.whitePoint.xyz.x, y: xyz.whitePoint.xyz.y, z: xyz.whitePoint.xyz.z)
  let targetCone = m * Vector3(x: targetWhite.xyz.x, y: targetWhite.xyz.y, z: targetWhite.xyz.z)
  let scale = Matrix3x3(
    m11: targetCone.x / sourceCone.x, m12: 0, m13: 0,
    m21: 0, m22: targetCone.y / sourceCone.y, m23: 0,
    m31: 0, m32: 0, m33: targetCone.z / sourceCone.z
  )
  let adapted = mInv * (scale * (m * Vector3(x: xyz.x, y: xyz.y, z: xyz.z)))
  precondition(
    _PrismNumeric.isFinite(adapted.x, adapted.y, adapted.z),
    "Chromatic adaptation must preserve finiteness")
  return XYZColor(x: adapted.x, y: adapted.y, z: adapted.z, whitePoint: targetWhite)
}

