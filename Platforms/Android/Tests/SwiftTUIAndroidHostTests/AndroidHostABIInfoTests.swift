import SwiftTUIAndroidHost
import Testing

@Suite struct AndroidHostABIInfoTests {
  @Test func queryAndEveryShortCopyRespectCallerCapacity() {
    #expect(swift_tui_android_get_abi_info(nil, 0) == 32)
    #expect(swift_tui_android_get_abi_info(nil, Int32.max) == 32)
    // Minor 1 advertises operation bits 5 and 6: copy open link (STUI-365)
    // and take clipboard (STUI-732).
    let expected: [UInt8] = [32, 1, 1, 64, 32, 64, 127, 0].flatMap {
      [UInt8($0), 0, 0, 0]
    }
    for capacity in -1...40 {
      var bytes = [UInt8](repeating: 0xA5, count: 40)
      let result = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_get_abi_info(buffer.baseAddress, Int32(capacity))
      }
      #expect(result == 32)
      let copied = max(0, min(capacity, 32))
      #expect(Array(bytes.prefix(copied)) == Array(expected.prefix(copied)))
      #expect(bytes.dropFirst(copied).allSatisfy { $0 == 0xA5 })
    }
  }
}
