import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(ucrt)
  import CRT
#endif

/// Diagnostic-only registry of every active presentation destination. Entries
/// belong to balanced host sessions, not a last-renderer global. Capture the
/// device at acquisition so descriptor reuse cannot change an entry's identity.
package enum DiagnosticScreenOwnership {
  private struct Entry: Sendable {
    var device: UInt64?
    var count: Int
  }
  private static let entries = Mutex<[Int32: Entry]>([:])

  package static func acquire(_ descriptor: Int32 = -1) {
    let device = terminalDevice(descriptor)
    entries.withLock { entries in
      if entries[descriptor] != nil {
        entries[descriptor]?.count += 1
      } else {
        entries[descriptor] = Entry(device: device, count: 1)
      }
    }
  }

  package static func release(_ descriptor: Int32 = -1) {
    entries.withLock { entries in
      guard let entry = entries[descriptor] else { return }
      if entry.count > 1 {
        entries[descriptor]?.count -= 1
      } else {
        entries.removeValue(forKey: descriptor)
      }
    }
  }

  package static var isScreenOwned: Bool { entries.withLock { !$0.isEmpty } }

  package static func allowsDiagnosticWrite(to descriptor: Int32 = 2) -> Bool {
    entries.withLock { entries in
      guard !entries.isEmpty else { return true }
      // Unknown ownership (including non-POSIX console hosts) is conservative.
      guard entries.values.allSatisfy({ $0.device != nil }) else { return false }
      #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
        if isatty(descriptor) == 0 {
          var info = stat()
          return unsafe fstat(descriptor, &info) == 0
        }
      #endif
      guard let device = terminalDevice(descriptor) else { return false }
      return !entries.values.contains { $0.device == device }
    }
  }

  private static func terminalDevice(_ descriptor: Int32) -> UInt64? {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      guard descriptor >= 0, isatty(descriptor) == 1 else { return nil }
      // /dev/tty is a controlling-terminal indirection, not a unique device.
      // Conservatively protect it unless a concrete terminal path is known.
      var name = [CChar](repeating: 0, count: 1_024)
      let result = name.withUnsafeMutableBufferPointer { buffer in
        unsafe ttyname_r(descriptor, buffer.baseAddress!, buffer.count)
      }
      guard result == 0 else { return nil }
      let path = name.withUnsafeBufferPointer { unsafe String(cString: $0.baseAddress!) }
      guard path != "/dev/tty", path != "/dev/console" else { return nil }
      var info = stat()
      guard unsafe fstat(descriptor, &info) == 0 else { return nil }
      return UInt64(truncatingIfNeeded: info.st_rdev)
    #else
      return nil
    #endif
  }
}
