#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, Android, some older Wasm
#elseif canImport(WASILibc)
  internal import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  internal import ucrt  // Windows
#endif

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
  internal static let _sRGBToXYZ = Matrix3x3(
    m11: 0.4124564, m12: 0.3575761, m13: 0.1804375,
    m21: 0.2126729, m22: 0.7151522, m23: 0.0721750,
    m31: 0.0193339, m32: 0.1191920, m33: 0.9503041
  )

  internal static let _displayP3ToXYZ = Matrix3x3(
    m11: 0.4865709486482162, m12: 0.2656676931690931, m13: 0.1982172852343625,
    m21: 0.2289745640697488, m22: 0.6917385218365064, m23: 0.0792869140937450,
    m31: 0.0, m32: 0.0451133818589026, m33: 1.0439443689009750
  )

  internal static let _rec2020ToXYZ = Matrix3x3(
    m11: 0.6369580483012914, m12: 0.1446169035862083, m13: 0.1688809751641721,
    m21: 0.2627002120112671, m22: 0.6779980715188708, m23: 0.05930171646986196,
    m31: 0.0, m32: 0.028072693049087428, m33: 1.0609850577107910
  )

  internal static func builtIn(named name: String) -> RGBColorProfile? {
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

  internal var builtInCanonicalName: String? {
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

  internal var linearized: RGBColorProfile {
    if isLinear { return self }
    if self == .sRGB { return .linearSRGB }
    if self == .displayP3 { return .linearDisplayP3 }
    return RGBColorProfile(
      name: "\(name) Linear", primaries: primaries, whitePoint: whitePoint,
      transferFunction: .linear)
  }
}
