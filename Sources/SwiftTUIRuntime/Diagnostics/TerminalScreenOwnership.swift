import Synchronization

/// Process-wide latch counting terminal hosts that currently own an
/// alternate-screen session.
///
/// `RuntimeIssueSink.standardError` consults the latch before writing: while
/// any host owns a screen, a raw stderr write lands on the same tty as the
/// owned alternate screen — it can splice mid-escape-sequence with the
/// background presentation writer and desynchronizes the incremental-damage
/// baseline — so issues route to the debug bundle or a deferred buffer
/// instead. The count nests for PTY-backed secondary scenes, which enter raw
/// mode on their own terminals while the primary scene owns the controlling
/// tty.
///
/// Acquire/release are balanced by `TerminalHost`'s raw-mode transitions,
/// including the restore-on-failure path, so the latch cannot leak past a
/// session: `release()` clamps at zero rather than trusting perfect pairing.
enum TerminalScreenOwnership {
  private static let ownedScreenCount = Mutex<Int>(0)

  /// Records entry into an alternate-screen session.
  static func acquire() {
    ownedScreenCount.withLock { count in
      count += 1
    }
  }

  /// Records exit from an alternate-screen session.
  static func release() {
    ownedScreenCount.withLock { count in
      count = max(0, count - 1)
    }
  }

  /// Whether any terminal host currently owns an alternate screen.
  static var isScreenOwned: Bool {
    ownedScreenCount.withLock { count in
      count > 0
    }
  }
}
