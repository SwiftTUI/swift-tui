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
/// When the environment contains `SWIFTTUI_FRAME_TRACE=<path>`, the runtime installs this sink.
/// See `SceneSession` for the installation point.
/// The sink appends one tab-separated line to `<path>` for each committed, dropped, cancelled, or elided frame.
/// This trace records the actual frame-pipeline work during an interaction in a real terminal.
/// For example, it can record a slow tab switch or a blank flash.
/// A real terminal can expose timing races that deterministic test drivers do not expose.
///
/// This diagnostic is opt-in.
/// If the environment variable is absent, the runtime installs nothing.
/// The per-frame emit then stays a single nil branch.
///
/// The columns are `seq`, `kind` (COMMIT / ZEROART / ELIDE), `frame`, and `causes` (scheduler wake causes).
/// They also include `tail` (frame-tail job state) and `anim` (active-animation-count / has-pending-work).
/// The remaining columns are `focusRerenders`, `drop`, `blockers`, and free-form `extra`.
/// `focusRerenders` contains the number of focus-sync convergence passes.
/// `drop` contains the completed-frame drop decision, and `blockers` contains the drop-eligibility blockers.
/// A `ZEROART` row is a frame that produced no pixels and can identify a momentary blank.
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
  /// writable path — or, with the `frames` trace armed via `SWIFTTUI_TRACE`
  /// (or `debug` on and a debug bundle active), the bundle's `frames.tsv`.
  /// Otherwise, returns `nil`. Each session build can call this method safely.
  ///
  /// WASI has no path-based file sink — its capability model makes
  /// arbitrary-path `open` a no-op — so this always returns `nil` there.
  public static func fromEnvironment(debug: Bool = false) -> EnvFrameTraceSink? {
    #if canImport(WASILibc)
      return nil
    #else
      if let path = FeatureFlags.environmentValue(named: "SWIFTTUI_FRAME_TRACE"), !path.isEmpty {
        return EnvFrameTraceSink(path: path)
      }
      guard DebugTraceSelection.current.isArmed("frames") || debug,
        let bundlePath = DebugLogRouter.resolvedFilePath(
          override: nil, bundleFileName: "frames.tsv"
        )
      else {
        return nil
      }
      return EnvFrameTraceSink(path: bundlePath)
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
