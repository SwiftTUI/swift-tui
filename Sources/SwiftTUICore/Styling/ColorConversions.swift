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
