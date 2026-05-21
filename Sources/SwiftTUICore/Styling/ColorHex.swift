#if canImport(Darwin)
  internal import Darwin  // macOS, iOS, tvOS, watchOS
#elseif canImport(Glibc)
  internal import Glibc  // Linux, Android, some older Wasm
#elseif canImport(WASILibc)
  internal import WASILibc  // WebAssembly (WASI)
#elseif canImport(ucrt)
  internal import ucrt  // Windows
#endif

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
