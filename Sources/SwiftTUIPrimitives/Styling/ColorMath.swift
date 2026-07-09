#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, some older Wasm
#elseif canImport(Android)
  internal import Android
#elseif canImport(WASILibc)
  internal import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  internal import ucrt  // Windows
#endif

public func pow(_ base: Int, _ exponent: Int) -> Int? {
  // Handle Negative Exponents (Standard Int power is 0 for exp < 0, except for 1 and -1)
  if exponent < 0 {
    if base == 1 { return 1 }
    if base == -1 { return exponent % 2 == 0 ? 1 : -1 }
    return 0
  }

  // Base Cases
  if exponent == 0 { return 1 }
  if base == 0 { return 0 }

  var result = 1
  var currentBase = base
  var currentExponent = exponent

  // Exponentiation by Squaring with Overflow Checks
  while currentExponent > 0 {
    if currentExponent % 2 == 1 {
      let (newResult, overflow) = result.multipliedReportingOverflow(by: currentBase)
      if overflow { return nil }
      result = newResult
    }

    currentExponent /= 2
    if currentExponent > 0 {
      let (newBase, overflow) = currentBase.multipliedReportingOverflow(by: currentBase)
      if overflow { return nil }
      currentBase = newBase
    }
  }

  return result
}

@usableFromInline
internal enum _PrismNumeric {
  static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
  }

  static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
  }

  static func isFinite(_ values: Double...) -> Bool {
    values.allSatisfy { $0.isFinite }
  }

  static func positiveMod(_ value: Double, modulus: Double) -> Double {
    let result = value.truncatingRemainder(dividingBy: modulus)
    return result >= 0 ? result : result + modulus
  }

  static func wrapDegrees(_ degrees: Double) -> Double {
    positiveMod(degrees, modulus: 360.0)
  }

  static func signedPower(_ value: Double, exponent: Double) -> Double {
    if value == 0 { return 0 }
    let sign = value < 0 ? -1.0 : 1.0
    return sign * pow(abs(value), exponent)
  }

  static func cbrtSigned(_ value: Double) -> Double {
    if value == 0 { return 0 }
    let sign = value < 0 ? -1.0 : 1.0
    return sign * pow(abs(value), 1.0 / 3.0)
  }

  static func approxEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-12)
    -> Bool
  {
    abs(lhs - rhs) <= tolerance
  }

  static func shortestHueDelta(from h1: Double, to h2: Double) -> Double {
    let delta = wrapDegrees(h2 - h1)
    return delta > 180 ? delta - 360 : delta
  }
}

// MARK: - Errors

public enum ColorError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidHexString(String)
  case unsupportedHexFormat(String)
  case nonFiniteComponent(String)
  case invalidChromaticity(String)
  case invalidProfile(String)
  case conversionFailure(String)

  public var description: String {
    switch self {
    case .invalidHexString(let value):
      "invalid hex color string: \(value)"
    case .unsupportedHexFormat(let value):
      "unsupported hex color format: \(value)"
    case .nonFiniteComponent(let value):
      "non-finite color component: \(value)"
    case .invalidChromaticity(let value):
      "invalid chromaticity: \(value)"
    case .invalidProfile(let value):
      "invalid color profile: \(value)"
    case .conversionFailure(let value):
      "color conversion failed: \(value)"
    }
  }
}

// MARK: - Core math primitives

public struct Vector3: Hashable, Sendable, Codable {
  public let x: Double
  public let y: Double
  public let z: Double

  public init(x: Double, y: Double, z: Double) {
    precondition(_PrismNumeric.isFinite(x, y, z), "Vector3 components must be finite")
    self.x = x
    self.y = y
    self.z = z
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      x: try c.decode(Double.self, forKey: .x),
      y: try c.decode(Double.self, forKey: .y),
      z: try c.decode(Double.self, forKey: .z)
    )
  }
}

public struct Matrix3x3: Hashable, Sendable, Codable {
  public let m11: Double
  public let m12: Double
  public let m13: Double
  public let m21: Double
  public let m22: Double
  public let m23: Double
  public let m31: Double
  public let m32: Double
  public let m33: Double

  public init(
    m11: Double, m12: Double, m13: Double,
    m21: Double, m22: Double, m23: Double,
    m31: Double, m32: Double, m33: Double
  ) {
    precondition(
      _PrismNumeric.isFinite(m11, m12, m13, m21, m22, m23, m31, m32, m33),
      "Matrix3x3 components must be finite")
    self.m11 = m11
    self.m12 = m12
    self.m13 = m13
    self.m21 = m21
    self.m22 = m22
    self.m23 = m23
    self.m31 = m31
    self.m32 = m32
    self.m33 = m33
  }

  public var determinant: Double {
    m11 * (m22 * m33 - m23 * m32)
      - m12 * (m21 * m33 - m23 * m31)
      + m13 * (m21 * m32 - m22 * m31)
  }

  public func inverted() -> Matrix3x3 {
    let det = determinant
    precondition(det.isFinite && abs(det) > 1e-18, "Matrix is singular or ill-conditioned")
    let invDet = 1.0 / det
    return Matrix3x3(
      m11: (m22 * m33 - m23 * m32) * invDet,
      m12: -(m12 * m33 - m13 * m32) * invDet,
      m13: (m12 * m23 - m13 * m22) * invDet,
      m21: -(m21 * m33 - m23 * m31) * invDet,
      m22: (m11 * m33 - m13 * m31) * invDet,
      m23: -(m11 * m23 - m13 * m21) * invDet,
      m31: (m21 * m32 - m22 * m31) * invDet,
      m32: -(m11 * m32 - m12 * m31) * invDet,
      m33: (m11 * m22 - m12 * m21) * invDet
    )
  }

  public var inverse: Matrix3x3 { inverted() }

  public static func * (lhs: Matrix3x3, rhs: Vector3) -> Vector3 {
    Vector3(
      x: lhs.m11 * rhs.x + lhs.m12 * rhs.y + lhs.m13 * rhs.z,
      y: lhs.m21 * rhs.x + lhs.m22 * rhs.y + lhs.m23 * rhs.z,
      z: lhs.m31 * rhs.x + lhs.m32 * rhs.y + lhs.m33 * rhs.z
    )
  }

  public static func * (lhs: Matrix3x3, rhs: Matrix3x3) -> Matrix3x3 {
    Matrix3x3(
      m11: lhs.m11 * rhs.m11 + lhs.m12 * rhs.m21 + lhs.m13 * rhs.m31,
      m12: lhs.m11 * rhs.m12 + lhs.m12 * rhs.m22 + lhs.m13 * rhs.m32,
      m13: lhs.m11 * rhs.m13 + lhs.m12 * rhs.m23 + lhs.m13 * rhs.m33,
      m21: lhs.m21 * rhs.m11 + lhs.m22 * rhs.m21 + lhs.m23 * rhs.m31,
      m22: lhs.m21 * rhs.m12 + lhs.m22 * rhs.m22 + lhs.m23 * rhs.m32,
      m23: lhs.m21 * rhs.m13 + lhs.m22 * rhs.m23 + lhs.m23 * rhs.m33,
      m31: lhs.m31 * rhs.m11 + lhs.m32 * rhs.m21 + lhs.m33 * rhs.m31,
      m32: lhs.m31 * rhs.m12 + lhs.m32 * rhs.m22 + lhs.m33 * rhs.m32,
      m33: lhs.m31 * rhs.m13 + lhs.m32 * rhs.m23 + lhs.m33 * rhs.m33
    )
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      m11: try c.decode(Double.self, forKey: .m11),
      m12: try c.decode(Double.self, forKey: .m12),
      m13: try c.decode(Double.self, forKey: .m13),
      m21: try c.decode(Double.self, forKey: .m21),
      m22: try c.decode(Double.self, forKey: .m22),
      m23: try c.decode(Double.self, forKey: .m23),
      m31: try c.decode(Double.self, forKey: .m31),
      m32: try c.decode(Double.self, forKey: .m32),
      m33: try c.decode(Double.self, forKey: .m33)
    )
  }
}
