@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite("Campaign F5 codec properties", .serialized)
struct AdversarialSetGCodecTests {
  @Test(arguments: Array(91...100))
  func codec(id: Int) {
    setGCheck(id, Gen<(String, [Int])>.zip(setGText, setGNumbers)) { value in
      let (text, n) = value
      switch id {
      case 91:
        let values = n.map { $0 - 128 }
        return try SnapshotCoding.decode([Int].self, from: SnapshotCoding.encode(values)) == values
          ? nil : "integer array identity"
      case 92:
        let values = ["界" + text: text, "emoji😀": "e\u{301}" + text]
        return try SnapshotCoding.decode([String: String].self, from: SnapshotCoding.encode(values))
          == values ? nil : "Unicode keyed identity"
      case 93:
        let values: [[Int]?] = [nil, [], [n[0]], nil, n]
        return try SnapshotCoding.decode([[Int]?].self, from: SnapshotCoding.encode(values))
          == values ? nil : "optional nesting"
      case 94:
        let values = [
          Double(n[0] - 128) / 3, 0, -0.0, Double.infinity, -Double.infinity,
          Double(bitPattern: 0x7ff8_0000_0000_0042),
        ]
        for original in values {
          let decoded = try SnapshotCoding.decode(
            Double.self, from: SnapshotCoding.encode(original))
          if decoded.bitPattern != original.bitPattern { return "Double bits changed" }
        }
        return nil
      case 95:
        let original = (Int128(n[0] - 128) << 80) + Int128(n[1])
        return try SnapshotCoding.decode(Int128.self, from: SnapshotCoding.encode(original))
          == original ? nil : "wide integer identity"
      case 96:
        let values = Array(n.prefix(n[0] % 5))
        let exact = SnapshotCodingLimits(maximumValues: values.count + 1)
        let encoded = try SnapshotCoding.encode(values, limits: exact)
        guard try SnapshotCoding.decode([Int].self, from: encoded, limits: exact) == values else {
          return "exact value budget changed values"
        }
        let short = SnapshotCodingLimits(maximumValues: values.count)
        do {
          _ = try SnapshotCoding.encode(values, limits: short)
          return "short encode value budget admitted"
        } catch SnapshotCodingError.limitExceeded {} catch { return "wrong encode error: \(error)" }
        do {
          _ = try SnapshotCoding.decode([Int].self, from: encoded, limits: short)
          return "short decode value budget admitted"
        } catch SnapshotCodingError.limitExceeded {} catch { return "wrong decode error: \(error)" }
        return nil
      case 97:
        let exact = SnapshotCodingLimits(maximumUTF8Bytes: text.utf8.count)
        let encoded = try SnapshotCoding.encode(text, limits: exact)
        guard try SnapshotCoding.decode(String.self, from: encoded, limits: exact) == text else {
          return "exact UTF-8 budget changed text"
        }
        let short = SnapshotCodingLimits(maximumUTF8Bytes: text.utf8.count - 1)
        do {
          _ = try SnapshotCoding.encode(text, limits: short)
          return "short encode byte budget admitted"
        } catch SnapshotCodingError.limitExceeded {} catch { return "wrong encode error: \(error)" }
        do {
          _ = try SnapshotCoding.decode(String.self, from: encoded, limits: short)
          return "short decode byte budget admitted"
        } catch SnapshotCodingError.limitExceeded {} catch { return "wrong decode error: \(error)" }
        return nil
      case 98:
        let integer = try SnapshotCoding.encode(n[0])
        let string = try SnapshotCoding.encode(text)
        do {
          _ = try SnapshotCoding.decode(String.self, from: integer)
          return "integer coerced to string"
        } catch {}
        do {
          _ = try SnapshotCoding.decode(Int.self, from: string)
          return "string coerced to integer"
        } catch {}
        return nil
      case 99:
        let choices = [Int.min, -1, 0, 1, 64, 256, 1024, 1025, Int.max, n[0]]
        for w in choices {
          for h in [0, 1, 64, 65, 1024, Int.max] {
            let size = CellSize(width: w, height: h)
            let expected =
              size.width >= 0 && size.height >= 0 && size.width <= 1024 && size.height <= 1024
              && (size.width == 0 || size.height <= 65536 / size.width)
            if HostWireBudget.admits(size) != expected { return "dimension admission: \(size)" }
          }
        }
        return nil
      default:
        // A fixed spelling table is independent of the production encoder.
        let pieces: [(String, Int)] = [
          ("a", 1), ("界", 3), ("😀", 4), ("\"", 2), ("\\", 2), ("\n", 2), ("\t", 2), ("\u{0}", 6),
          ("\u{7F}", 6), ("\u{85}", 6),
        ]
        let selected = n.map { pieces[$0 % pieces.count] }
        let value = selected.map(\.0).joined()
        let expected = 2 + selected.reduce(0) { $0 + $1.1 }
        return try HostWireBudget.jsonStringBytes(value) == expected
          ? nil : "escaped UTF-8 byte count"
      }
    }
  }
}
