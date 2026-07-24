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

  package static func _fromOklab(_ lab: OklabColor, alpha: Double, profile: RGBColorProfile)
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

  internal func _convertedPreservingAbsoluteColorimetry(to profile: RGBColorProfile) -> Color {
    if self.profile == profile { return self }
    let xyz = self.xyz()
    let linear = profile.xyzToRGBMatrix * Vector3(x: xyz.x, y: xyz.y, z: xyz.z)
    return Self._fromLinearRGB(linear, alpha: alpha, profile: profile)
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
