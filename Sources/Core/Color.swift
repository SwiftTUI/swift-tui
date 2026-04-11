#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, Android, some older Wasm
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

public enum ColorError: Error, Sendable, Equatable {
  case invalidHexString(String)
  case unsupportedHexFormat(String)
  case nonFiniteComponent(String)
  case invalidChromaticity(String)
  case invalidProfile(String)
  case conversionFailure(String)
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

// MARK: - Public support types

public struct Chromaticity: Hashable, Sendable, Codable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    precondition(x.isFinite && y.isFinite, "Chromaticity components must be finite")
    precondition(
      x > 0 && y > 0 && x + y <= 1.0 + 1e-12, "Chromaticity must satisfy x > 0, y > 0, x + y <= 1")
    self.x = x
    self.y = y
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
  }
}

public struct RGBPrimaries: Hashable, Sendable, Codable {
  public let red: Chromaticity
  public let green: Chromaticity
  public let blue: Chromaticity

  public init(red: Chromaticity, green: Chromaticity, blue: Chromaticity) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      red: try c.decode(Chromaticity.self, forKey: .red),
      green: try c.decode(Chromaticity.self, forKey: .green),
      blue: try c.decode(Chromaticity.self, forKey: .blue)
    )
  }
}

public struct ReferenceWhite: Hashable, Sendable, Codable {
  public let name: String
  public let x: Double
  public let y: Double

  public init(name: String, x: Double, y: Double) {
    let trimmed = String(
      name.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    precondition(!trimmed.isEmpty, "Reference white name must not be empty")
    precondition(x.isFinite && y.isFinite, "Reference white components must be finite")
    precondition(
      x > 0 && y > 0 && x + y <= 1.0 + 1e-12,
      "Reference white must satisfy x > 0, y > 0, x + y <= 1")
    self.name = trimmed
    self.x = x
    self.y = y
  }

  public var xyz: XYZColor {
    XYZColor(x: x / y, y: 1.0, z: (1.0 - x - y) / y, whitePoint: self)
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      name: try c.decode(String.self, forKey: .name),
      x: try c.decode(Double.self, forKey: .x),
      y: try c.decode(Double.self, forKey: .y)
    )
  }
}

extension ReferenceWhite {
  public static let d50 = ReferenceWhite(name: "D50", x: 0.34567, y: 0.35850)
  public static let d55 = ReferenceWhite(name: "D55", x: 0.33242, y: 0.34743)
  public static let d60 = ReferenceWhite(name: "D60", x: 0.32168, y: 0.33767)
  public static let d65 = ReferenceWhite(name: "D65", x: 0.31270, y: 0.32900)
  public static let d75 = ReferenceWhite(name: "D75", x: 0.29903, y: 0.31488)
  public static let e = ReferenceWhite(name: "E", x: 1.0 / 3.0, y: 1.0 / 3.0)
}

public enum TransferFunction: Hashable, Sendable, Codable {
  case linear
  case gamma(Double)
  case sRGB
  case rec2020
  case proPhotoRGB

  private enum CodingKeys: String, CodingKey { case kind, gamma }
  private enum Kind: String, Codable { case linear, gamma, sRGB, rec2020, proPhotoRGB }

  internal var isValid: Bool {
    switch self {
    case .linear, .sRGB, .rec2020, .proPhotoRGB:
      return true
    case .gamma(let g):
      return g.isFinite && g > 0
    }
  }

  public func encode(_ linear: Double) -> Double {
    precondition(linear.isFinite, "Transfer-function input must be finite")
    switch self {
    case .linear:
      return linear
    case .gamma(let gamma):
      precondition(gamma.isFinite && gamma > 0, "Gamma must be finite and positive")
      return _PrismNumeric.signedPower(linear, exponent: 1.0 / gamma)
    case .sRGB:
      let a = abs(linear)
      if a <= 0.0031308 { return 12.92 * linear }
      return (linear < 0 ? -1.0 : 1.0) * (1.055 * pow(a, 1.0 / 2.4) - 0.055)
    case .rec2020:
      let alpha = 1.09929682680944
      let beta = 0.018053968510807
      let a = abs(linear)
      if a < beta { return 4.5 * linear }
      return (linear < 0 ? -1.0 : 1.0) * (alpha * pow(a, 0.45) - (alpha - 1.0))
    case .proPhotoRGB:
      let a = abs(linear)
      if a < 1.0 / 512.0 { return 16.0 * linear }
      return (linear < 0 ? -1.0 : 1.0) * pow(a, 1.0 / 1.8)
    }
  }

  public func decode(_ encoded: Double) -> Double {
    precondition(encoded.isFinite, "Transfer-function input must be finite")
    switch self {
    case .linear:
      return encoded
    case .gamma(let gamma):
      precondition(gamma.isFinite && gamma > 0, "Gamma must be finite and positive")
      return _PrismNumeric.signedPower(encoded, exponent: gamma)
    case .sRGB:
      let a = abs(encoded)
      if a <= 0.04045 { return encoded / 12.92 }
      return (encoded < 0 ? -1.0 : 1.0) * pow((a + 0.055) / 1.055, 2.4)
    case .rec2020:
      let alpha = 1.09929682680944
      let beta = 0.018053968510807
      let threshold = 4.5 * beta
      let a = abs(encoded)
      if a < threshold { return encoded / 4.5 }
      return (encoded < 0 ? -1.0 : 1.0) * pow((a + (alpha - 1.0)) / alpha, 1.0 / 0.45)
    case .proPhotoRGB:
      let a = abs(encoded)
      if a < 1.0 / 32.0 { return encoded / 16.0 }
      return (encoded < 0 ? -1.0 : 1.0) * pow(a, 1.8)
    }
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try c.decode(Kind.self, forKey: .kind)
    switch kind {
    case .linear: self = .linear
    case .gamma: self = .gamma(try c.decode(Double.self, forKey: .gamma))
    case .sRGB: self = .sRGB
    case .rec2020: self = .rec2020
    case .proPhotoRGB: self = .proPhotoRGB
    }
    guard isValid else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: c, debugDescription: "Invalid transfer function")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .linear:
      try c.encode(Kind.linear, forKey: .kind)
    case .gamma(let g):
      try c.encode(Kind.gamma, forKey: .kind)
      try c.encode(g, forKey: .gamma)
    case .sRGB:
      try c.encode(Kind.sRGB, forKey: .kind)
    case .rec2020:
      try c.encode(Kind.rec2020, forKey: .kind)
    case .proPhotoRGB:
      try c.encode(Kind.proPhotoRGB, forKey: .kind)
    }
  }
}

public enum GamutMappingPolicy: String, Hashable, Sendable, Codable {
  case preserve
  case clip
  case compressLightness
  case compressPerceptual
  case relativeColorimetric
  case absoluteColorimetric

  public static var `default`: GamutMappingPolicy { .compressPerceptual }
}

public enum HueInterpolationPath: String, Hashable, Sendable, Codable {
  case shortest
  case longest
  case increasing
  case decreasing
}

public enum DeltaEMethod: String, Hashable, Sendable, Codable {
  case cie76
  case cie94
  case ciede2000
  case ok
}

public enum HexFormat: String, Hashable, Sendable, Codable {
  case rgb
  case rgba
  case rrggbb
  case rrggbbaa
  case argb
  case aarrggbb
}

public enum HexLetterCase: String, Hashable, Sendable, Codable {
  case uppercase
  case lowercase
}

public enum BlendMode: String, Hashable, Sendable, Codable {
  case normal
  case multiply
  case screen
  case overlay
  case darken
  case lighten
}

public enum ChromaticAdaptationMethod: String, Hashable, Sendable, Codable {
  case bradford
  case cat02
}

public enum MixingMethod: Hashable, Sendable, Codable {
  case perceptual
  case perceptualPolar(huePath: HueInterpolationPath = .shortest)
  case linearLight
  case encodedRGB
  case lab

  private enum CodingKeys: String, CodingKey { case kind, huePath }
  private enum Kind: String, Codable {
    case perceptual, perceptualPolar, linearLight, encodedRGB, lab
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .perceptual: self = .perceptual
    case .perceptualPolar:
      self = .perceptualPolar(huePath: try c.decode(HueInterpolationPath.self, forKey: .huePath))
    case .linearLight: self = .linearLight
    case .encodedRGB: self = .encodedRGB
    case .lab: self = .lab
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .perceptual:
      try c.encode(Kind.perceptual, forKey: .kind)
    case .perceptualPolar(let huePath):
      try c.encode(Kind.perceptualPolar, forKey: .kind)
      try c.encode(huePath, forKey: .huePath)
    case .linearLight:
      try c.encode(Kind.linearLight, forKey: .kind)
    case .encodedRGB:
      try c.encode(Kind.encodedRGB, forKey: .kind)
    case .lab:
      try c.encode(Kind.lab, forKey: .kind)
    }
  }
}

public enum CompositingSpace: Hashable, Sendable, Codable {
  case linearSRGB
  case linearDisplayP3
  case profile(RGBColorProfile)

  private enum CodingKeys: String, CodingKey { case kind, profile }
  private enum Kind: String, Codable { case linearSRGB, linearDisplayP3, profile }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .linearSRGB: self = .linearSRGB
    case .linearDisplayP3: self = .linearDisplayP3
    case .profile: self = .profile(try c.decode(RGBColorProfile.self, forKey: .profile))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .linearSRGB:
      try c.encode(Kind.linearSRGB, forKey: .kind)
    case .linearDisplayP3:
      try c.encode(Kind.linearDisplayP3, forKey: .kind)
    case .profile(let profile):
      try c.encode(Kind.profile, forKey: .kind)
      try c.encode(profile, forKey: .profile)
    }
  }
}

public struct RGBColorProfile: Hashable, Sendable, Codable, Identifiable {
  public var id: String { name }

  public let name: String
  public let primaries: RGBPrimaries
  public let whitePoint: ReferenceWhite
  public let transferFunction: TransferFunction

  public init(
    name: String,
    primaries: RGBPrimaries,
    whitePoint: ReferenceWhite,
    transferFunction: TransferFunction
  ) {
    let trimmed = String(
      name.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    precondition(!trimmed.isEmpty, "Profile name must not be empty")
    precondition(transferFunction.isValid, "Transfer function must be valid")
    self.name = trimmed
    self.primaries = primaries
    self.whitePoint = whitePoint
    self.transferFunction = transferFunction
    let matrix = _makeRGBToXYZMatrix(primaries: primaries, whitePoint: whitePoint)
    precondition(
      matrix.determinant.isFinite && abs(matrix.determinant) > 1e-18,
      "Profile matrix must be invertible")
  }

  public var rgbToXYZMatrix: Matrix3x3 {
    if self == .sRGB || self == .linearSRGB { return Self._sRGBToXYZ }
    if self == .displayP3 || self == .linearDisplayP3 { return Self._displayP3ToXYZ }
    if self == .rec2020 { return Self._rec2020ToXYZ }
    return _makeRGBToXYZMatrix(primaries: primaries, whitePoint: whitePoint)
  }

  public var xyzToRGBMatrix: Matrix3x3 {
    if self == .sRGB || self == .linearSRGB { return Self._sRGBToXYZ.inverse }
    if self == .displayP3 || self == .linearDisplayP3 { return Self._displayP3ToXYZ.inverse }
    if self == .rec2020 { return Self._rec2020ToXYZ.inverse }
    return rgbToXYZMatrix.inverse
  }

  public var isLinear: Bool {
    switch transferFunction {
    case .linear:
      return true
    case .gamma(let g):
      return _PrismNumeric.approxEqual(g, 1.0)
    default:
      return false
    }
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      name: try c.decode(String.self, forKey: .name),
      primaries: try c.decode(RGBPrimaries.self, forKey: .primaries),
      whitePoint: try c.decode(ReferenceWhite.self, forKey: .whitePoint),
      transferFunction: try c.decode(TransferFunction.self, forKey: .transferFunction)
    )
  }
}

extension RGBColorProfile {
  public static let sRGB = RGBColorProfile(
    name: "sRGB",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.64, y: 0.33),
      green: Chromaticity(x: 0.30, y: 0.60),
      blue: Chromaticity(x: 0.15, y: 0.06)
    ),
    whitePoint: .d65,
    transferFunction: .sRGB
  )

  public static let displayP3 = RGBColorProfile(
    name: "Display P3",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.680, y: 0.320),
      green: Chromaticity(x: 0.265, y: 0.690),
      blue: Chromaticity(x: 0.150, y: 0.060)
    ),
    whitePoint: .d65,
    transferFunction: .sRGB
  )

  public static let adobeRGB = RGBColorProfile(
    name: "Adobe RGB",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.64, y: 0.33),
      green: Chromaticity(x: 0.21, y: 0.71),
      blue: Chromaticity(x: 0.15, y: 0.06)
    ),
    whitePoint: .d65,
    transferFunction: .gamma(2.2)
  )

  public static let rec2020 = RGBColorProfile(
    name: "Rec. 2020",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.708, y: 0.292),
      green: Chromaticity(x: 0.170, y: 0.797),
      blue: Chromaticity(x: 0.131, y: 0.046)
    ),
    whitePoint: .d65,
    transferFunction: .rec2020
  )

  public static let proPhotoRGB = RGBColorProfile(
    name: "ProPhoto RGB",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.7347, y: 0.2653),
      green: Chromaticity(x: 0.1596, y: 0.8404),
      blue: Chromaticity(x: 0.0366, y: 0.0001)
    ),
    whitePoint: .d50,
    transferFunction: .proPhotoRGB
  )

  public static let acescg = RGBColorProfile(
    name: "ACEScg",
    primaries: RGBPrimaries(
      red: Chromaticity(x: 0.713, y: 0.293),
      green: Chromaticity(x: 0.165, y: 0.830),
      blue: Chromaticity(x: 0.128, y: 0.044)
    ),
    whitePoint: .d60,
    transferFunction: .linear
  )

  public static let linearSRGB = RGBColorProfile(
    name: "Linear sRGB",
    primaries: sRGB.primaries,
    whitePoint: .d65,
    transferFunction: .linear
  )

  public static let linearDisplayP3 = RGBColorProfile(
    name: "Linear Display P3",
    primaries: displayP3.primaries,
    whitePoint: .d65,
    transferFunction: .linear
  )
}

extension RGBColorProfile {
  fileprivate static let _sRGBToXYZ = Matrix3x3(
    m11: 0.4124564, m12: 0.3575761, m13: 0.1804375,
    m21: 0.2126729, m22: 0.7151522, m23: 0.0721750,
    m31: 0.0193339, m32: 0.1191920, m33: 0.9503041
  )

  fileprivate static let _displayP3ToXYZ = Matrix3x3(
    m11: 0.4865709486482162, m12: 0.2656676931690931, m13: 0.1982172852343625,
    m21: 0.2289745640697488, m22: 0.6917385218365064, m23: 0.0792869140937450,
    m31: 0.0, m32: 0.0451133818589026, m33: 1.0439443689009750
  )

  fileprivate static let _rec2020ToXYZ = Matrix3x3(
    m11: 0.6369580483012914, m12: 0.1446169035862083, m13: 0.1688809751641721,
    m21: 0.2627002120112671, m22: 0.6779980715188708, m23: 0.05930171646986196,
    m31: 0.0, m32: 0.028072693049087428, m33: 1.0609850577107910
  )

  fileprivate static func builtIn(named name: String) -> RGBColorProfile? {
    var key = name.lowercased()
    key.removeAll(where: { it in [".", " "].contains(it) })
    switch key {
    case "srgb": return .sRGB
    case "displayp3", "p3": return .displayP3
    case "adobergb", "argb": return .adobeRGB
    case "rec2020", "bt2020": return .rec2020
    case "prophotorgb", "prophoto": return .proPhotoRGB
    case "acescg": return .acescg
    case "linearsrgb": return .linearSRGB
    case "lineardisplayp3": return .linearDisplayP3
    default: return nil
    }
  }

  fileprivate var builtInCanonicalName: String? {
    if self == .sRGB { return "sRGB" }
    if self == .displayP3 { return "Display P3" }
    if self == .adobeRGB { return "Adobe RGB" }
    if self == .rec2020 { return "Rec. 2020" }
    if self == .proPhotoRGB { return "ProPhoto RGB" }
    if self == .acescg { return "ACEScg" }
    if self == .linearSRGB { return "Linear sRGB" }
    if self == .linearDisplayP3 { return "Linear Display P3" }
    return nil
  }

  fileprivate var linearized: RGBColorProfile {
    if isLinear { return self }
    if self == .sRGB { return .linearSRGB }
    if self == .displayP3 { return .linearDisplayP3 }
    return RGBColorProfile(
      name: "\(name) Linear", primaries: primaries, whitePoint: whitePoint,
      transferFunction: .linear)
  }
}

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

// MARK: - Perceptual space conversions

internal func _xyzToLab(_ xyz: XYZColor, whitePoint: ReferenceWhite) -> LabColor {
  let adapted = xyz.whitePoint == whitePoint ? xyz : adapt(xyz, to: whitePoint)
  let white = whitePoint.xyz
  let xr = adapted.x / white.x
  let yr = adapted.y / white.y
  let zr = adapted.z / white.z

  let epsilon = 216.0 / 24389.0
  let kappa = 24389.0 / 27.0

  func f(_ t: Double) -> Double {
    if t > epsilon { return _PrismNumeric.cbrtSigned(t) }
    return (kappa * t + 16.0) / 116.0
  }

  let fx = f(xr)
  let fy = f(yr)
  let fz = f(zr)
  return LabColor(
    l: 116.0 * fy - 16.0,
    a: 500.0 * (fx - fy),
    b: 200.0 * (fy - fz),
    whitePoint: whitePoint
  )
}

internal func _labToXYZ(_ lab: LabColor) -> XYZColor {
  let epsilon = 216.0 / 24389.0
  let kappa = 24389.0 / 27.0
  let fy = (lab.l + 16.0) / 116.0
  let fx = fy + lab.a / 500.0
  let fz = fy - lab.b / 200.0

  func inverseF(_ f: Double) -> Double {
    let f3 = f * f * f
    if f3 > epsilon { return f3 }
    return (116.0 * f - 16.0) / kappa
  }

  let xr = inverseF(fx)
  let yr = inverseF(fy)
  let zr = inverseF(fz)
  let white = lab.whitePoint.xyz
  return XYZColor(
    x: xr * white.x,
    y: yr * white.y,
    z: zr * white.z,
    whitePoint: lab.whitePoint
  )
}

internal func _labToLCh(_ lab: LabColor) -> LChColor {
  let c = sqrt(lab.a * lab.a + lab.b * lab.b)
  let h = _PrismNumeric.wrapDegrees(atan2(lab.b, lab.a) * 180.0 / .pi)
  return LChColor(l: lab.l, c: c, h: h, whitePoint: lab.whitePoint)
}

internal func _lchToLab(_ lch: LChColor) -> LabColor {
  let radians = lch.h * .pi / 180.0
  return LabColor(
    l: lch.l,
    a: lch.c * cos(radians),
    b: lch.c * sin(radians),
    whitePoint: lch.whitePoint
  )
}

internal func _xyzD65ToOklab(_ xyz: XYZColor) -> OklabColor {
  precondition(xyz.whitePoint == .d65, "Oklab requires D65-referenced XYZ")
  let l = _PrismNumeric.cbrtSigned(
    0.8189330101 * xyz.x + 0.3618667424 * xyz.y - 0.1288597137 * xyz.z)
  let m = _PrismNumeric.cbrtSigned(
    0.0329845436 * xyz.x + 0.9293118715 * xyz.y + 0.0361456387 * xyz.z)
  let s = _PrismNumeric.cbrtSigned(
    0.0482003018 * xyz.x + 0.2643662691 * xyz.y + 0.6338517070 * xyz.z)
  return OklabColor(
    l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  )
}

internal func _oklabToXYZD65(_ lab: OklabColor) -> XYZColor {
  let l = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
  let m = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
  let s = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
  let l3 = l * l * l
  let m3 = m * m * m
  let s3 = s * s * s
  return XYZColor(
    x: 1.2270138511 * l3 - 0.5577999807 * m3 + 0.2812561490 * s3,
    y: -0.0405801784 * l3 + 1.1122568696 * m3 - 0.0716766787 * s3,
    z: -0.0763812845 * l3 - 0.4214819784 * m3 + 1.5861632204 * s3,
    whitePoint: .d65
  )
}

internal func _oklabToOklch(_ lab: OklabColor) -> OklchColor {
  let c = sqrt(lab.a * lab.a + lab.b * lab.b)
  let h = _PrismNumeric.wrapDegrees(atan2(lab.b, lab.a) * 180.0 / .pi)
  return OklchColor(l: lab.l, c: c, h: h)
}

internal func _oklchToOklab(_ lch: OklchColor) -> OklabColor {
  let radians = lch.h * .pi / 180.0
  return OklabColor(l: lch.l, a: lch.c * cos(radians), b: lch.c * sin(radians))
}

internal func _effectiveHue(chroma: Double, hue: Double, epsilon: Double = 1e-9) -> Double? {
  chroma < epsilon ? nil : _PrismNumeric.wrapDegrees(hue)
}

public func interpolateHue(
  from h1: Double?,
  to h2: Double?,
  t: Double,
  path: HueInterpolationPath
) -> Double? {
  let t = _PrismNumeric.clamp(t, 0, 1)
  switch (h1, h2) {
  case (nil, nil):
    return nil
  case (let lhs?, nil):
    return _PrismNumeric.wrapDegrees(lhs)
  case (nil, let rhs?):
    return _PrismNumeric.wrapDegrees(rhs)
  case (let lhs?, let rhs?):
    let start = _PrismNumeric.wrapDegrees(lhs)
    let end = _PrismNumeric.wrapDegrees(rhs)
    let delta: Double
    switch path {
    case .shortest:
      delta = _PrismNumeric.shortestHueDelta(from: start, to: end)
    case .longest:
      let shortest = _PrismNumeric.shortestHueDelta(from: start, to: end)
      if abs(shortest) < 1e-12 {
        delta = 0
      } else {
        delta = shortest > 0 ? shortest - 360 : shortest + 360
      }
    case .increasing:
      delta = _PrismNumeric.wrapDegrees(end - start)
    case .decreasing:
      let inc = _PrismNumeric.wrapDegrees(end - start)
      delta = inc == 0 ? 0 : inc - 360
    }
    return _PrismNumeric.wrapDegrees(start + delta * t)
  }
}

// MARK: - Color

public struct Color: Hashable, Sendable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double
  public var profile: RGBColorProfile

  public init(
    red: Double, green: Double, blue: Double, alpha: Double = 1.0, profile: RGBColorProfile = .sRGB
  ) {
    precondition(_PrismNumeric.isFinite(red, green, blue, alpha), "Color components must be finite")
    precondition(profile.transferFunction.isValid, "Profile must be valid")
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = _PrismNumeric.clamp(alpha, 0.0, 1.0)
    self.profile = profile
  }

  public init(white: Double, alpha: Double = 1.0, profile: RGBColorProfile = .sRGB) {
    self.init(red: white, green: white, blue: white, alpha: alpha, profile: profile)
  }

  public init(hex: String, profile: RGBColorProfile = .sRGB) throws {
    let trimmed = String(
      hex.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    guard !normalized.isEmpty else { throw ColorError.invalidHexString(hex) }
    guard
      normalized.unicodeScalars.allSatisfy({ "0123456789ABCDEFabcdef".unicodeScalars.contains($0) })
    else {
      throw ColorError.invalidHexString(hex)
    }

    func byte(_ substring: Substring) -> Double {
      Double(UInt8(substring, radix: 16)!) / 255.0
    }

    switch normalized.count {
    case 3:
      let chars = Array(normalized)
      let r = String([chars[0], chars[0]])
      let g = String([chars[1], chars[1]])
      let b = String([chars[2], chars[2]])
      self.init(
        red: byte(r[...]), green: byte(g[...]), blue: byte(b[...]), alpha: 1.0, profile: profile)
    case 4:
      let chars = Array(normalized)
      let r = String([chars[0], chars[0]])
      let g = String([chars[1], chars[1]])
      let b = String([chars[2], chars[2]])
      let a = String([chars[3], chars[3]])
      self.init(
        red: byte(r[...]), green: byte(g[...]), blue: byte(b[...]), alpha: byte(a[...]),
        profile: profile)
    case 6:
      self.init(
        red: byte(normalized.prefix(2)),
        green: byte(normalized.dropFirst(2).prefix(2)),
        blue: byte(normalized.dropFirst(4).prefix(2)),
        alpha: 1.0,
        profile: profile
      )
    case 8:
      self.init(
        red: byte(normalized.prefix(2)),
        green: byte(normalized.dropFirst(2).prefix(2)),
        blue: byte(normalized.dropFirst(4).prefix(2)),
        alpha: byte(normalized.dropFirst(6).prefix(2)),
        profile: profile
      )
    default:
      throw ColorError.unsupportedHexFormat(hex)
    }
  }

  public init(hexRGB value: UInt32, alpha: Double = 1.0, profile: RGBColorProfile = .sRGB) {
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b, alpha: alpha, profile: profile)
  }

  public init(hexRGBA value: UInt32, profile: RGBColorProfile = .sRGB) {
    let r = Double((value >> 24) & 0xFF) / 255.0
    let g = Double((value >> 16) & 0xFF) / 255.0
    let b = Double((value >> 8) & 0xFF) / 255.0
    let a = Double(value & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b, alpha: a, profile: profile)
  }

  public init(hexARGB value: UInt32, profile: RGBColorProfile = .sRGB) {
    let a = Double((value >> 24) & 0xFF) / 255.0
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b, alpha: a, profile: profile)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case profile
    case red
    case green
    case blue
    case alpha
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let version = try c.decode(Int.self, forKey: .schemaVersion)
    guard version == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion, in: c,
        debugDescription: "Unsupported Color schema version: \(version)")
    }
    let profile: RGBColorProfile
    if let name = try? c.decode(String.self, forKey: .profile) {
      guard let builtIn = RGBColorProfile.builtIn(named: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: .profile, in: c, debugDescription: "Unknown built-in profile: \(name)")
      }
      profile = builtIn
    } else {
      profile = try c.decode(RGBColorProfile.self, forKey: .profile)
    }
    self.init(
      red: try c.decode(Double.self, forKey: .red),
      green: try c.decode(Double.self, forKey: .green),
      blue: try c.decode(Double.self, forKey: .blue),
      alpha: try c.decode(Double.self, forKey: .alpha),
      profile: profile
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(1, forKey: .schemaVersion)
    if let canonical = profile.builtInCanonicalName {
      try c.encode(canonical, forKey: .profile)
    } else {
      try c.encode(profile, forKey: .profile)
    }
    try c.encode(red, forKey: .red)
    try c.encode(green, forKey: .green)
    try c.encode(blue, forKey: .blue)
    try c.encode(alpha, forKey: .alpha)
  }
}

// MARK: - Internal conversion helpers

extension Color {
  internal var _linearRGB: Vector3 {
    Vector3(
      x: profile.transferFunction.decode(red),
      y: profile.transferFunction.decode(green),
      z: profile.transferFunction.decode(blue)
    )
  }

  internal static func _fromLinearRGB(_ linear: Vector3, alpha: Double, profile: RGBColorProfile)
    -> Color
  {
    Color(
      red: profile.transferFunction.encode(linear.x),
      green: profile.transferFunction.encode(linear.y),
      blue: profile.transferFunction.encode(linear.z),
      alpha: alpha,
      profile: profile
    )
  }

  internal static func _fromXYZPreservingGamut(
    _ xyz: XYZColor, alpha: Double, profile: RGBColorProfile
  ) -> Color {
    let adapted = xyz.whitePoint == profile.whitePoint ? xyz : adapt(xyz, to: profile.whitePoint)
    let linear = profile.xyzToRGBMatrix * Vector3(x: adapted.x, y: adapted.y, z: adapted.z)
    return _fromLinearRGB(linear, alpha: alpha, profile: profile)
  }

  internal static func _fromLab(_ lab: LabColor, alpha: Double, profile: RGBColorProfile) -> Color {
    _fromXYZPreservingGamut(_labToXYZ(lab), alpha: alpha, profile: profile)
  }

  internal static func _fromOklab(_ lab: OklabColor, alpha: Double, profile: RGBColorProfile)
    -> Color
  {
    let xyz = _oklabToXYZD65(lab)
    return _fromXYZPreservingGamut(xyz, alpha: alpha, profile: profile)
  }

  internal static func _fromOklch(_ lch: OklchColor, alpha: Double, profile: RGBColorProfile)
    -> Color
  {
    _fromOklab(_oklchToOklab(lch), alpha: alpha, profile: profile)
  }

  internal func _convertedPreservingGamut(to profile: RGBColorProfile) -> Color {
    if self.profile == profile { return self }
    let xyz = self.xyz()
    return Self._fromXYZPreservingGamut(xyz, alpha: alpha, profile: profile)
  }

  internal func _clippedChannels() -> Color {
    Color(
      red: _PrismNumeric.clamp(red, 0, 1),
      green: _PrismNumeric.clamp(green, 0, 1),
      blue: _PrismNumeric.clamp(blue, 0, 1),
      alpha: alpha,
      profile: profile
    )
  }

  internal func _isInGamutEncoded(tolerance: Double = 1e-9) -> Bool {
    red >= -tolerance && red <= 1 + tolerance && green >= -tolerance && green <= 1 + tolerance
      && blue >= -tolerance && blue <= 1 + tolerance
  }

  internal func _compressChroma(to targetProfile: RGBColorProfile, preserveLightness: Bool)
    -> Color?
  {
    let original = self.oklch()
    let preserved = self._convertedPreservingGamut(to: targetProfile)
    if preserved._isInGamutEncoded() { return preserved }

    var low = 0.0
    var high = max(0.0, original.c)
    var best: Color? = nil

    for _ in 0..<36 {
      let mid = (low + high) * 0.5
      let candidateL = preserveLightness ? original.l : _PrismNumeric.clamp(original.l, 0, 1)
      let candidate = Color._fromOklch(
        OklchColor(l: candidateL, c: mid, h: original.h),
        alpha: alpha,
        profile: targetProfile
      )
      if candidate._isInGamutEncoded() {
        best = candidate
        low = mid
      } else {
        high = mid
      }
    }
    if let best { return best }

    let achromatic = Color._fromOklch(
      OklchColor(l: _PrismNumeric.clamp(original.l, 0, 1), c: 0, h: original.h), alpha: alpha,
      profile: targetProfile)
    return achromatic._isInGamutEncoded() ? achromatic : nil
  }

  internal func _compressPerceptually(to targetProfile: RGBColorProfile) -> Color {
    let preserved = self._convertedPreservingGamut(to: targetProfile)
    if preserved._isInGamutEncoded() { return preserved }
    if let chromaReduced = _compressChroma(to: targetProfile, preserveLightness: true) {
      return chromaReduced
    }

    let clipped = preserved._clippedChannels()
    let source = self.oklab()
    let destination = clipped.oklab()
    var low = 0.0
    var high = 1.0
    var best = clipped
    for _ in 0..<36 {
      let mid = (low + high) * 0.5
      let candidate = Color._fromOklab(
        OklabColor(
          l: _PrismNumeric.lerp(source.l, destination.l, mid),
          a: _PrismNumeric.lerp(source.a, destination.a, mid),
          b: _PrismNumeric.lerp(source.b, destination.b, mid)
        ),
        alpha: alpha,
        profile: targetProfile
      )
      if candidate._isInGamutEncoded() {
        best = candidate
        high = mid
      } else {
        low = mid
      }
    }
    return best._clippedChannels()
  }

  internal func _mappedPreservedColor(
    _ preserved: Color, from original: Color, to targetProfile: RGBColorProfile,
    policy: GamutMappingPolicy
  ) -> Color {
    switch policy {
    case .preserve:
      return preserved
    case .clip, .relativeColorimetric, .absoluteColorimetric:
      return preserved._clippedChannels()
    case .compressLightness:
      return original._compressChroma(to: targetProfile, preserveLightness: false)
        ?? preserved._clippedChannels()
    case .compressPerceptual:
      return original._compressPerceptually(to: targetProfile)
    }
  }
}

// MARK: - Public conversion API

extension Color {
  public func xyz() -> XYZColor {
    let linear = _linearRGB
    let xyz = profile.rgbToXYZMatrix * linear
    return XYZColor(x: xyz.x, y: xyz.y, z: xyz.z, whitePoint: profile.whitePoint)
  }

  public func xyz(
    adaptedTo whitePoint: ReferenceWhite, method: ChromaticAdaptationMethod = .bradford
  ) -> XYZColor {
    adapt(xyz(), to: whitePoint, method: method)
  }

  public func lab(whitePoint: ReferenceWhite = .d50) -> LabColor {
    _xyzToLab(xyz(), whitePoint: whitePoint)
  }

  public func lch(whitePoint: ReferenceWhite = .d50) -> LChColor {
    _labToLCh(lab(whitePoint: whitePoint))
  }

  public func oklab() -> OklabColor {
    let d65XYZ = xyz().whitePoint == .d65 ? xyz() : xyz(adaptedTo: .d65, method: .bradford)
    return _xyzD65ToOklab(d65XYZ)
  }

  public func oklch() -> OklchColor {
    _oklabToOklch(oklab())
  }

  public func converted(to profile: RGBColorProfile, gamutMapping: GamutMappingPolicy = .default)
    -> Color
  {
    let preserved = _convertedPreservingGamut(to: profile)
    return _mappedPreservedColor(preserved, from: self, to: profile, policy: gamutMapping)
  }

  public func mapped(to profile: RGBColorProfile, policy: GamutMappingPolicy) -> Color {
    converted(to: profile, gamutMapping: policy)
  }

  public func clamped(to profile: RGBColorProfile) -> Color {
    converted(to: profile, gamutMapping: .clip)
  }

  public func isInGamut(for profile: RGBColorProfile, tolerance: Double = 1e-9) -> Bool {
    let converted = self.converted(to: profile, gamutMapping: .preserve)
    return converted.red >= -tolerance && converted.red <= 1.0 + tolerance
      && converted.green >= -tolerance && converted.green <= 1.0 + tolerance
      && converted.blue >= -tolerance && converted.blue <= 1.0 + tolerance
  }
}

// MARK: - Delta E

internal func _deltaE76(_ lhs: LabColor, _ rhs: LabColor) -> Double {
  let dl = lhs.l - rhs.l
  let da = lhs.a - rhs.a
  let db = lhs.b - rhs.b
  return sqrt(dl * dl + da * da + db * db)
}

internal func _deltaE94(_ lhs: LabColor, _ rhs: LabColor) -> Double {
  let kL = 1.0
  let kC = 1.0
  let kH = 1.0
  let k1 = 0.045
  let k2 = 0.015

  let c1 = sqrt(lhs.a * lhs.a + lhs.b * lhs.b)
  let c2 = sqrt(rhs.a * rhs.a + rhs.b * rhs.b)
  let deltaL = lhs.l - rhs.l
  let deltaC = c1 - c2
  let deltaA = lhs.a - rhs.a
  let deltaB = lhs.b - rhs.b
  let deltaHsq = max(0.0, deltaA * deltaA + deltaB * deltaB - deltaC * deltaC)
  let sL = 1.0
  let sC = 1.0 + k1 * c1
  let sH = 1.0 + k2 * c1
  return sqrt(
    pow(deltaL / (kL * sL), 2) + pow(deltaC / (kC * sC), 2) + deltaHsq / pow(kH * sH, 2)
  )
}

internal func _deltaE2000(_ lhs: LabColor, _ rhs: LabColor) -> Double {
  let l1 = lhs.l
  let a1 = lhs.a
  let b1 = lhs.b
  let l2 = rhs.l
  let a2 = rhs.a
  let b2 = rhs.b
  let c1 = sqrt(a1 * a1 + b1 * b1)
  let c2 = sqrt(a2 * a2 + b2 * b2)
  let avgC = (c1 + c2) / 2.0
  let g = 0.5 * (1.0 - sqrt(pow(avgC, 7.0) / (pow(avgC, 7.0) + pow(25.0, 7.0))))
  let a1p = (1.0 + g) * a1
  let a2p = (1.0 + g) * a2
  let c1p = sqrt(a1p * a1p + b1 * b1)
  let c2p = sqrt(a2p * a2p + b2 * b2)

  func hp(_ a: Double, _ b: Double) -> Double {
    if a == 0 && b == 0 { return 0 }
    return _PrismNumeric.wrapDegrees(atan2(b, a) * 180.0 / .pi)
  }

  let h1p = hp(a1p, b1)
  let h2p = hp(a2p, b2)
  let deltaLp = l2 - l1
  let deltaCp = c2p - c1p

  let deltahp: Double
  if c1p == 0 || c2p == 0 {
    deltahp = 0
  } else {
    let diff = h2p - h1p
    if abs(diff) <= 180 {
      deltahp = diff
    } else if diff > 180 {
      deltahp = diff - 360
    } else {
      deltahp = diff + 360
    }
  }

  let deltaHp = 2.0 * sqrt(c1p * c2p) * sin((deltahp * .pi / 180.0) / 2.0)
  let avgLpp = (l1 + l2) / 2.0
  let avgCpp = (c1p + c2p) / 2.0

  let avghp: Double
  if c1p == 0 || c2p == 0 {
    avghp = h1p + h2p
  } else {
    let diff = abs(h1p - h2p)
    if diff <= 180 {
      avghp = (h1p + h2p) / 2.0
    } else if h1p + h2p < 360 {
      avghp = (h1p + h2p + 360) / 2.0
    } else {
      avghp = (h1p + h2p - 360) / 2.0
    }
  }

  let t =
    1.0
    - 0.17 * cos((avghp - 30.0) * .pi / 180.0)
    + 0.24 * cos((2.0 * avghp) * .pi / 180.0)
    + 0.32 * cos((3.0 * avghp + 6.0) * .pi / 180.0)
    - 0.20 * cos((4.0 * avghp - 63.0) * .pi / 180.0)

  let deltaTheta = 30.0 * exp(-pow((avghp - 275.0) / 25.0, 2.0))
  let rc = 2.0 * sqrt(pow(avgCpp, 7.0) / (pow(avgCpp, 7.0) + pow(25.0, 7.0)))
  let sl = 1.0 + (0.015 * pow(avgLpp - 50.0, 2.0)) / sqrt(20.0 + pow(avgLpp - 50.0, 2.0))
  let sc = 1.0 + 0.045 * avgCpp
  let sh = 1.0 + 0.015 * avgCpp * t
  let rt = -sin(2.0 * deltaTheta * .pi / 180.0) * rc

  let kl = 1.0
  let kc = 1.0
  let kh = 1.0
  let termL = deltaLp / (kl * sl)
  let termC = deltaCp / (kc * sc)
  let termH = deltaHp / (kh * sh)
  return sqrt(termL * termL + termC * termC + termH * termH + rt * termC * termH)
}

// MARK: - Analysis API

extension Color {
  public var relativeLuminance: Double {
    let srgb = converted(to: .sRGB, gamutMapping: .preserve)
    let r = TransferFunction.sRGB.decode(srgb.red)
    let g = TransferFunction.sRGB.decode(srgb.green)
    let b = TransferFunction.sRGB.decode(srgb.blue)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  public func contrastRatio(to other: Color) -> Double {
    let l1 = relativeLuminance
    let l2 = other.relativeLuminance
    let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    return _PrismNumeric.clamp(ratio, 1.0, 21.0)
  }

  public func deltaE(to other: Color, method: DeltaEMethod = .ok) -> Double {
    switch method {
    case .ok:
      let a = oklab()
      let b = other.oklab()
      let dl = a.l - b.l
      let da = a.a - b.a
      let db = a.b - b.b
      return sqrt(dl * dl + da * da + db * db)
    case .cie76:
      return _deltaE76(lab(), other.lab())
    case .cie94:
      return _deltaE94(lab(), other.lab())
    case .ciede2000:
      return _deltaE2000(lab(), other.lab())
    }
  }

  public func isApproximatelyEqual(
    to other: Color, deltaE tolerance: Double = 0.5, method: DeltaEMethod = .ok
  ) -> Bool {
    deltaE(to: other, method: method) <= tolerance
  }
}

// MARK: - Mixing and interpolation

extension Color {
  fileprivate func _workingLinearProfile(with other: Color) -> RGBColorProfile {
    if self.profile == other.profile, self.profile != .sRGB {
      return self.profile.linearized
    }
    return .linearSRGB
  }
}

extension Color {
  public func mixed(with other: Color, amount: Double, method: MixingMethod = .perceptual) -> Color
  {
    interpolated(to: other, progress: amount, method: method)
  }

  public func interpolated(to other: Color, progress: Double, method: MixingMethod = .perceptual)
    -> Color
  {
    let t = _PrismNumeric.clamp(progress, 0.0, 1.0)
    let alpha = _PrismNumeric.lerp(self.alpha, other.alpha, t)

    switch method {
    case .perceptual:
      let a = self.oklab()
      let b = other.oklab()
      let mixed = OklabColor(
        l: _PrismNumeric.lerp(a.l, b.l, t),
        a: _PrismNumeric.lerp(a.a, b.a, t),
        b: _PrismNumeric.lerp(a.b, b.b, t)
      )
      return Color._fromOklab(mixed, alpha: alpha, profile: self.profile).mapped(
        to: self.profile, policy: .compressPerceptual)

    case .perceptualPolar(let huePath):
      let a = self.oklch()
      let b = other.oklch()
      let hue =
        interpolateHue(
          from: _effectiveHue(chroma: a.c, hue: a.h),
          to: _effectiveHue(chroma: b.c, hue: b.h),
          t: t,
          path: huePath
        ) ?? 0.0
      let mixed = OklchColor(
        l: _PrismNumeric.lerp(a.l, b.l, t),
        c: _PrismNumeric.lerp(a.c, b.c, t),
        h: hue
      )
      return Color._fromOklch(mixed, alpha: alpha, profile: self.profile).mapped(
        to: self.profile, policy: .compressPerceptual)

    case .linearLight:
      let working = _workingLinearProfile(with: other)
      let lhs = self.converted(to: working, gamutMapping: .preserve)
      let rhs = other.converted(to: working, gamutMapping: .preserve)
      let linear = Vector3(
        x: _PrismNumeric.lerp(
          lhs.profile.transferFunction.decode(lhs.red),
          rhs.profile.transferFunction.decode(rhs.red), t),
        y: _PrismNumeric.lerp(
          lhs.profile.transferFunction.decode(lhs.green),
          rhs.profile.transferFunction.decode(rhs.green), t),
        z: _PrismNumeric.lerp(
          lhs.profile.transferFunction.decode(lhs.blue),
          rhs.profile.transferFunction.decode(rhs.blue), t)
      )
      let mixed = Color._fromLinearRGB(linear, alpha: alpha, profile: working)
      return mixed.converted(to: self.profile, gamutMapping: .compressPerceptual)

    case .encodedRGB:
      let rhs = other.converted(to: self.profile, gamutMapping: .preserve)
      let mixed = Color(
        red: _PrismNumeric.lerp(self.red, rhs.red, t),
        green: _PrismNumeric.lerp(self.green, rhs.green, t),
        blue: _PrismNumeric.lerp(self.blue, rhs.blue, t),
        alpha: alpha,
        profile: self.profile
      )
      return mixed.isInGamut(for: self.profile)
        ? mixed : mixed.mapped(to: self.profile, policy: .compressPerceptual)

    case .lab:
      let a = self.lab(whitePoint: .d50)
      let b = other.lab(whitePoint: .d50)
      let mixed = LabColor(
        l: _PrismNumeric.lerp(a.l, b.l, t),
        a: _PrismNumeric.lerp(a.a, b.a, t),
        b: _PrismNumeric.lerp(a.b, b.b, t),
        whitePoint: .d50
      )
      return Color._fromLab(mixed, alpha: alpha, profile: self.profile).mapped(
        to: self.profile, policy: .compressPerceptual)
    }
  }
}

// MARK: - Editing API

extension Color {
  public func lightened(by amount: Double) -> Color {
    let t = _PrismNumeric.clamp(amount, 0, 1)
    let lch = oklch()
    let result = OklchColor(l: _PrismNumeric.lerp(lch.l, 1.0, t), c: lch.c, h: lch.h)
    return Color._fromOklch(result, alpha: alpha, profile: profile).mapped(
      to: profile, policy: .compressPerceptual)
  }

  public func darkened(by amount: Double) -> Color {
    let t = _PrismNumeric.clamp(amount, 0, 1)
    let lch = oklch()
    let result = OklchColor(l: _PrismNumeric.lerp(lch.l, 0.0, t), c: lch.c, h: lch.h)
    return Color._fromOklch(result, alpha: alpha, profile: profile).mapped(
      to: profile, policy: .compressPerceptual)
  }

  public func saturated(by amount: Double) -> Color {
    let t = _PrismNumeric.clamp(amount, 0, 1)
    let lch = oklch()
    let result = OklchColor(l: lch.l, c: lch.c * (1.0 + t), h: lch.h)
    return Color._fromOklch(result, alpha: alpha, profile: profile).mapped(
      to: profile, policy: .compressPerceptual)
  }

  public func desaturated(by amount: Double) -> Color {
    let t = _PrismNumeric.clamp(amount, 0, 1)
    let lch = oklch()
    let result = OklchColor(l: lch.l, c: lch.c * (1.0 - t), h: lch.h)
    return Color._fromOklch(result, alpha: alpha, profile: profile).mapped(
      to: profile, policy: .compressPerceptual)
  }

  public func rotatedHue(by degrees: Double) -> Color {
    let lch = oklch()
    if lch.c < 1e-9 { return self }
    let result = OklchColor(l: lch.l, c: lch.c, h: lch.h + degrees)
    return Color._fromOklch(result, alpha: alpha, profile: profile).mapped(
      to: profile, policy: .compressPerceptual)
  }

  public func withAlpha(_ alpha: Double) -> Color {
    Color(red: red, green: green, blue: blue, alpha: alpha, profile: profile)
  }

  public func accessibleTextColor(light: Color = .white, dark: Color = .black) -> Color {
    let lightContrast = contrastRatio(to: light)
    let darkContrast = contrastRatio(to: dark)
    return lightContrast >= darkContrast ? light : dark
  }
}

// MARK: - Compositing

extension Color {
  fileprivate static func _blend(_ source: Double, _ backdrop: Double, mode: BlendMode) -> Double {
    switch mode {
    case .normal:
      return source
    case .multiply:
      return source * backdrop
    case .screen:
      return source + backdrop - source * backdrop
    case .overlay:
      if backdrop <= 0.5 {
        return 2.0 * source * backdrop
      }
      return 1.0 - 2.0 * (1.0 - source) * (1.0 - backdrop)
    case .darken:
      return min(source, backdrop)
    case .lighten:
      return max(source, backdrop)
    }
  }

  fileprivate func _workingProfile(for space: CompositingSpace) -> RGBColorProfile {
    switch space {
    case .linearSRGB: return .linearSRGB
    case .linearDisplayP3: return .linearDisplayP3
    case .profile(let profile): return profile
    }
  }
}

extension Color {
  public func composited(
    over background: Color,
    mode: BlendMode = .normal,
    workingSpace: CompositingSpace = .linearSRGB
  ) -> Color {
    let working = _workingProfile(for: workingSpace)
    let fg = converted(to: working, gamutMapping: .preserve)
    let bg = background.converted(to: working, gamutMapping: .preserve)

    let sf = Vector3(
      x: working.transferFunction.decode(fg.red),
      y: working.transferFunction.decode(fg.green),
      z: working.transferFunction.decode(fg.blue)
    )
    let sb = Vector3(
      x: working.transferFunction.decode(bg.red),
      y: working.transferFunction.decode(bg.green),
      z: working.transferFunction.decode(bg.blue)
    )

    let blended = Vector3(
      x: Self._blend(sf.x, sb.x, mode: mode),
      y: Self._blend(sf.y, sb.y, mode: mode),
      z: Self._blend(sf.z, sb.z, mode: mode)
    )

    let outAlpha = fg.alpha + bg.alpha * (1.0 - fg.alpha)
    let outPre = Vector3(
      x: (1.0 - bg.alpha) * fg.alpha * sf.x + (1.0 - fg.alpha) * bg.alpha * sb.x + fg.alpha
        * bg.alpha * blended.x,
      y: (1.0 - bg.alpha) * fg.alpha * sf.y + (1.0 - fg.alpha) * bg.alpha * sb.y + fg.alpha
        * bg.alpha * blended.y,
      z: (1.0 - bg.alpha) * fg.alpha * sf.z + (1.0 - fg.alpha) * bg.alpha * sb.z + fg.alpha
        * bg.alpha * blended.z
    )

    let outLinear: Vector3
    if outAlpha > 0 {
      outLinear = Vector3(x: outPre.x / outAlpha, y: outPre.y / outAlpha, z: outPre.z / outAlpha)
    } else {
      outLinear = Vector3(x: 0, y: 0, z: 0)
    }

    let composed = Color._fromLinearRGB(outLinear, alpha: outAlpha, profile: working)
    return composed.converted(to: self.profile, gamutMapping: .compressPerceptual)
  }
}

// MARK: - Hex formatting

extension Color {
  public func hexString(
    format: HexFormat = .rrggbb,
    letterCase: HexLetterCase = .uppercase,
    prefix: Bool = true,
    exportProfile: RGBColorProfile = .sRGB,
    gamutMapping: GamutMappingPolicy = .default
  ) -> String {
    let exported = converted(to: exportProfile, gamutMapping: gamutMapping)
    let r = _PrismNumeric.clamp(exported.red, 0, 1)
    let g = _PrismNumeric.clamp(exported.green, 0, 1)
    let b = _PrismNumeric.clamp(exported.blue, 0, 1)
    let a = _PrismNumeric.clamp(exported.alpha, 0, 1)

    func nibble(_ value: Double) -> String {
      String(Int((_PrismNumeric.clamp(value, 0, 1) * 15.0).rounded()), radix: 16)
    }

    func byte(_ value: Double) -> String {
      let number = Int((_PrismNumeric.clamp(value, 0, 1) * 255.0).rounded())
      // Convert to Hex (Base 16) in uppercase
      var hexString = String(number, radix: 16, uppercase: true)

      if hexString.count < 2 {
        hexString = "0" + hexString
      }
      return hexString
    }

    var body: String
    switch format {
    case .rgb:
      body = nibble(r) + nibble(g) + nibble(b)
    case .rgba:
      body = nibble(r) + nibble(g) + nibble(b) + nibble(a)
    case .rrggbb:
      body = byte(r) + byte(g) + byte(b)
    case .rrggbbaa:
      body = byte(r) + byte(g) + byte(b) + byte(a)
    case .argb:
      body = nibble(a) + nibble(r) + nibble(g) + nibble(b)
    case .aarrggbb:
      body = byte(a) + byte(r) + byte(g) + byte(b)
    }

    if letterCase == .lowercase {
      body = body.lowercased()
    }
    return (prefix ? "#" : "") + body
  }
}
