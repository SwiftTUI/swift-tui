import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// Env-gated frame-pipeline trace sink.
///
/// When `SWIFTTUI_FRAME_TRACE=<path>` is set in the environment, the runtime
/// installs this sink (see `SceneSession`) and appends one tab-separated line
/// per committed, dropped/cancelled, or elided frame to `<path>`. It is a
/// low-overhead way to capture *what the frame pipeline actually did* during an
/// interaction — e.g. a tab switch that feels slow or flashes blank — in a real
/// terminal, where timing races that never appear under deterministic test
/// drivers do surface.
///
/// Diagnostic-only and entirely opt-in: with the env var unset nothing is
/// installed and the per-frame emit stays a single nil branch.
///
/// Columns: `seq`, `kind` (COMMIT / ZEROART / ELIDE), `frame`, `causes`
/// (scheduler wake causes), `tail` (frame-tail job state), `anim`
/// (active-animation-count / has-pending-work), `focusRerenders` (focus-sync
/// convergence passes), `drop` (completed-frame drop decision), `blockers`
/// (drop-eligibility blockers), and free-form `extra`. A `ZEROART` row is a
/// frame that produced no pixels — the prime suspect for a momentary blank.
@_spi(Runners) public final class EnvFrameTraceSink: FrameDiagnosticSink {
  #if !canImport(WASILibc)
    private let descriptor: Mutex<Int32>
  #endif
  private let seq = Mutex(0)

  #if !canImport(WASILibc)
    private init?(path: String) {
      let fd = unsafe path.withCString { pathPointer in
        unsafe open(pathPointer, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      }
      guard fd >= 0 else { return nil }
      descriptor = Mutex(fd)
      writeLine(
        "seq\tkind\tframe\tcauses\ttail\tanim(active/pending)\tfocusRerenders\tdrop\tblockers\textra"
      )
    }
  #endif

  /// Returns an installed sink when `SWIFTTUI_FRAME_TRACE` names a non-empty,
  /// writable path; otherwise `nil`. Safe to call on every session build.
  ///
  /// WASI has no path-based file sink — its capability model makes
  /// arbitrary-path `open` a no-op — so this always returns `nil` there.
  public static func fromEnvironment() -> EnvFrameTraceSink? {
    #if canImport(WASILibc)
      return nil
    #else
      guard let raw = unsafe getenv("SWIFTTUI_FRAME_TRACE") else {
        return nil
      }
      let path = unsafe String(cString: raw)
      guard !path.isEmpty else {
        return nil
      }
      return EnvFrameTraceSink(path: path)
    #endif
  }

  @MainActor
  public func record(_ sample: RuntimeFrameSample) {
    let n = seq.withLock { value -> Int in
      value += 1
      return value
    }
    switch sample {
    case .committed(let s):
      writeLine(
        row(
          seq: n, kind: "COMMIT", frame: s.frameNumber, causes: s.scheduledFrame.causes,
          tail: s.tailJobState.rawValue,
          animActive: s.animationControllerActiveAnimationCount,
          animPending: s.animationControllerHasPendingWork,
          focusRerenders: "\(s.focusSyncRerenders)",
          drop: s.completedFrameDropDecision?.action.rawValue ?? "-",
          blockers: s.dropEligibilityBlockers.map(\.rawValue),
          extra: "present=\(s.presentationDuration)"))
    case .zeroArtifact(let s):
      writeLine(
        row(
          seq: n, kind: "ZEROART", frame: s.frameNumber, causes: s.scheduledFrame.causes,
          tail: s.tailJobState,
          animActive: s.animationControllerActiveAnimationCount,
          animPending: s.animationControllerHasPendingWork,
          focusRerenders: "-",
          drop: s.dropDecision,
          blockers: s.dropEligibilityBlockers.map(\.rawValue),
          extra:
            "policy=\(s.staleFramePolicy);cancel=\(s.tailCancelReason);recon=\(s.dropReconciliationMode)"
        ))
    case .elided(let s):
      writeLine(
        row(
          seq: n, kind: "ELIDE", frame: s.frameNumber, causes: s.scheduledFrame.causes,
          tail: "-",
          animActive: s.animationControllerActiveAnimationCount,
          animPending: s.animationControllerHasPendingWork,
          focusRerenders: "-", drop: "-", blockers: [], extra: "-"))
    }
  }

  private func row(
    seq: Int, kind: String, frame: Int, causes: Set<WakeCause>, tail: String,
    animActive: Int, animPending: Bool, focusRerenders: String, drop: String,
    blockers: [String], extra: String
  ) -> String {
    let causeText = causes.map(\.rawValue).sorted().joined(separator: "+")
    let blockerText = blockers.sorted().joined(separator: ",")
    return
      "\(seq)\t\(kind)\t\(frame)\t\(causeText.isEmpty ? "-" : causeText)\t\(tail)\t\(animActive)/\(animPending)\t\(focusRerenders)\t\(drop)\t\(blockerText.isEmpty ? "-" : blockerText)\t\(extra)"
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      descriptor.withLock { fd in
        var message = line + "\n"
        message.withUTF8 { buffer in
          guard let base = buffer.baseAddress, buffer.count > 0 else {
            return
          }
          var offset = 0
          while offset < buffer.count {
            let written = unsafe write(fd, base.advanced(by: offset), buffer.count - offset)
            if written > 0 {
              offset += written
            } else if written == -1, errno == EINTR {
              continue
            } else {
              return
            }
          }
        }
      }
    #endif
  }
}
