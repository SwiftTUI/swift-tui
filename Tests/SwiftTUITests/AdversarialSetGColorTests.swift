@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore

@MainActor
@Suite("Campaign F5 color properties", .serialized)
struct AdversarialSetGColorTests {
  @Test(arguments: Array(61...75))
  func color(id: Int) {
    setGCheck(id, setGNumbers) { n in
      let color = Color(
        red: Double(n[0]) / 255, green: Double(n[1]) / 255, blue: Double(n[2]) / 255,
        alpha: Double(n[3]) / 255)
      let hex = color.hexString(format: .rrggbbaa)
      switch id {
      case 61:
        let actual = try Color(hex: color.hexString())
        return actual == Color(red: color.red, green: color.green, blue: color.blue)
          ? nil : "RGB hex identity"
      case 62: return try Color(hex: hex) == color ? nil : "RGBA hex identity"
      case 63:
        let digits = n.prefix(3).map { $0 % 16 }
        let short = digits.map { String($0, radix: 16) }.joined()
        let actual = try Color(hex: short)
        return actual
          == Color(
            red: Double(digits[0]) / 15, green: Double(digits[1]) / 15, blue: Double(digits[2]) / 15
          ) ? nil : "short hex expansion"
      case 64:
        return try Color(hex: hex.lowercased()) == Color(hex: hex.uppercased()) ? nil : "hex case"
      case 65: return try Color(hex: " \t" + hex + "\n") == color ? nil : "hex outer whitespace"
      case 66:
        let actual = color.converted(to: .displayP3, gamutMapping: .preserve).converted(
          to: .sRGB, gamutMapping: .preserve)
        return setGNear(actual.red, color.red, tolerance: 1e-6)
          && setGNear(actual.green, color.green, tolerance: 1e-6)
          && setGNear(actual.blue, color.blue, tolerance: 1e-6) && actual.alpha == color.alpha
          ? nil : "profile inverse: \(color) -> \(actual)"
      case 67...71:
        let transfer: TransferFunction =
          id == 67
          ? .linear
          : id == 68
            ? .sRGB
            : id == 69 ? .gamma(Double(n[1] % 30 + 1) / 10) : id == 70 ? .rec2020 : .proPhotoRGB
        let value = Double(n[0] - 128) / 64
        let actual = transfer.decode(transfer.encode(value))
        return setGNear(actual, value, tolerance: 1e-6)
          ? nil : "transfer inverse: \(value) -> \(actual)"
      case 72:
        let other = Color(
          red: 1 - color.red, green: 1 - color.green, blue: 1 - color.blue, alpha: 1 - color.alpha)
        let t = Double(n[3]) / 255
        let actual = color.mixed(with: other, amount: t, method: .encodedRGB)
        let lhs = [color.red, color.green, color.blue, color.alpha]
        let rhs = [other.red, other.green, other.blue, other.alpha]
        let values = [actual.red, actual.green, actual.blue, actual.alpha]
        return zip(values, zip(lhs, rhs)).allSatisfy {
          setGNear($0.0, (1 - t) * $0.1.0 + t * $0.1.1)
        } ? nil : "encoded mix convexity"
      case 73:
        let other = Color(white: 0.25)
        return color.mixed(with: other, amount: -1, method: .encodedRGB) == color
          && color.mixed(with: other, amount: 2, method: .encodedRGB) == other ? nil : "mix clamp"
      case 74:
        let alpha = Double(n[0] - 128) / 64
        return Color(white: 0.25, alpha: alpha).alpha == min(1, max(0, alpha)) ? nil : "alpha clamp"
      default:
        return try SnapshotCoding.decode(Color.self, from: SnapshotCoding.encode(color)) == color
          ? nil : "color snapshot identity"
      }
    }
  }
}
