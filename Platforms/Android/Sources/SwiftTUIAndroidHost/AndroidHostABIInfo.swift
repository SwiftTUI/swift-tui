/// Copies the native ABI descriptor's stable prefix into caller-owned storage.
/// The result is the complete descriptor size, including on a size-only query
/// or short copy. No host is created and no executor or lifecycle state changes.
/// See `Contracts/1/include/swift_tui_android.h` for field offsets and operation bits.
@_cdecl("swift_tui_android_get_abi_info")
public func swift_tui_android_get_abi_info(
  _ outBuffer: UnsafeMutablePointer<UInt8>?,
  _ capacity: Int32
) -> Int32 {
  // Eight little-endian uint32_t fields. Writing bytes avoids alignment and
  // Swift-struct-layout assumptions at this C boundary. Append-only within ABI 1.
  let fields: [UInt32] = [32, 1, 0, 64, 32, 64, 31, 0]
  let required: Int32 = 32
  guard let outBuffer = unsafe outBuffer, capacity > 0 else { return required }
  for offset in 0..<Int(min(capacity, required)) {
    let byte = UInt8(truncatingIfNeeded: fields[offset / 4] >> ((offset % 4) * 8))
    unsafe outBuffer[offset] = byte
  }
  return required
}
