#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, Android, some older Wasm
#elseif canImport(WASILibc)
  internal import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  internal import ucrt  // Windows
#endif

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
  internal func _workingLinearProfile(with other: Color) -> RGBColorProfile {
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
  internal static func _blend(_ source: Double, _ backdrop: Double, mode: BlendMode) -> Double {
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

  internal func _workingProfile(for space: CompositingSpace) -> RGBColorProfile {
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
