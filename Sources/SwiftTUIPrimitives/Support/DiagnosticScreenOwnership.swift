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
/// destination's identity at acquisition so descriptor reuse cannot change an
/// entry's identity.
package enum DiagnosticScreenOwnership {
  /// What a presentation destination is, as far as diagnostics can tell.
  private enum Owner: Sendable, Equatable {
    /// A terminal with a concrete device number.
    case terminal(device: UInt64)
    /// A valid descriptor that is not a terminal (a pipe, file or socket),
    /// identified by its file.
    case stream(device: UInt64, inode: UInt64)
    /// A socket on macOS, identified by the kernel's handle for it. Darwin's
    /// `fstat(2)` reports `st_dev`/`st_ino` 0/0 for every inet socket, so the
    /// file identity cannot tell two of them apart; every descriptor of one
    /// socket (a `dup`) shares its handle.
    case socket(handle: UInt64)
    /// No descriptor, a terminal without a concrete device (`/dev/tty`,
    /// `/dev/console`), a failed query, or a host without POSIX terminals.
    /// It might be a terminal, so it stays protected.
    case unknown
  }
  private struct Entry: Sendable {
    var owner: Owner
    var count: Int
  }
  private static let entries = Mutex<[Int32: Entry]>([:])

  package static func acquire(_ descriptor: Int32 = -1) {
    let owner = classify(descriptor)
    entries.withLock { entries in
      if entries[descriptor] != nil {
        entries[descriptor]?.count += 1
      } else {
        entries[descriptor] = Entry(owner: owner, count: 1)
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

  /// Runtime issues stream to a redirected (non-terminal) destination unless
  /// it is a presentation's own stream; a terminal destination is refused
  /// while it presents, or while a non-terminal presentation that may feed a
  /// terminal downstream is active. Any owner of unknown kind refuses all.
  package static func allowsDiagnosticWrite(to descriptor: Int32 = 2) -> Bool {
    entries.withLock { entries in
      guard !entries.isEmpty else { return true }
      let owners = entries.values.map(\.owner)
      guard !owners.contains(.unknown) else { return false }
      #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
        if isatty(descriptor) == 0 {
          var info = stat()
          guard unsafe fstat(descriptor, &info) == 0,
            let destination = streamIdentity(of: descriptor, info)
          else { return false }
          return !owners.contains(destination)
        }
      #endif
      guard case .terminal(let device) = classify(descriptor) else { return false }
      return owners.allSatisfy { owner in
        if case .terminal(let owned) = owner { return owned != device }
        return false
      }
    }
  }

  private static func classify(_ descriptor: Int32) -> Owner {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      guard descriptor >= 0 else { return .unknown }
      var info = stat()
      guard unsafe fstat(descriptor, &info) == 0 else { return .unknown }
      guard isatty(descriptor) == 1 else {
        return streamIdentity(of: descriptor, info) ?? .unknown
      }
      // /dev/tty is a controlling-terminal indirection, not a unique device.
      // Conservatively protect it unless a concrete terminal path is known.
      var name = [CChar](repeating: 0, count: 1_024)
      let result = name.withUnsafeMutableBufferPointer { buffer in
        unsafe ttyname_r(descriptor, buffer.baseAddress!, buffer.count)
      }
      guard result == 0 else { return .unknown }
      let path = name.withUnsafeBufferPointer { unsafe String(cString: $0.baseAddress!) }
      guard path != "/dev/tty", path != "/dev/console" else { return .unknown }
      return .terminal(device: UInt64(truncatingIfNeeded: info.st_rdev))
    #else
      return .unknown
    #endif
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
    /// The identity of a non-terminal descriptor whose `fstat(2)` is `info`,
    /// or `nil` when it cannot be established. Linux's sockfs gives every
    /// socket its own inode, so the file identity serves there. macOS asks
    /// libproc for the socket's kernel handle (the one lsof reports). Other
    /// Apple platforms have no libproc and keep the file identity, which
    /// conservatively treats every inet socket as one file.
    private static func streamIdentity(of descriptor: Int32, _ info: stat) -> Owner? {
      #if os(macOS)
        if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) {
          var socketInfo = socket_fdinfo()
          let size = Int32(MemoryLayout<socket_fdinfo>.size)
          let filled = unsafe proc_pidfdinfo(
            getpid(), descriptor, PROC_PIDFDSOCKETINFO, &socketInfo, size)
          guard filled == size else { return nil }
          return .socket(handle: socketInfo.psi.soi_so)
        }
      #endif
      return .stream(
        device: UInt64(truncatingIfNeeded: info.st_dev),
        inode: UInt64(truncatingIfNeeded: info.st_ino))
    }
  #endif
}
