import SwiftTUICore
import SwiftTUIRuntime
import Synchronization

private struct AndroidHostHandleRegistryState: Sendable {
  var nextHandle: Int64 = 1
  var hosts: [Int64: AndroidHostSceneHost] = [:]
}

public enum AndroidHostHandleRegistry {
  private static let state = Mutex(AndroidHostHandleRegistryState())

  public static func register(
    _ host: AndroidHostSceneHost
  ) -> Int64 {
    state.withLock { state in
      let handle = state.nextHandle
      state.nextHandle += 1
      state.hosts[handle] = host
      return handle
    }
  }

  public static func host(
    for handle: Int64
  ) -> AndroidHostSceneHost? {
    state.withLock { state in
      state.hosts[handle]
    }
  }

  @discardableResult
  public static func remove(
    _ handle: Int64
  ) -> AndroidHostSceneHost? {
    state.withLock { state in
      state.hosts.removeValue(forKey: handle)
    }
  }
}

// The `@_cdecl` entry points below are nonisolated → MainActor bridges whose
// thread contract is Kotlin caller discipline: every call arrives on the
// Android main looper (Compose lifecycle effects, the pollFrames tick, and UI
// input callbacks), matching the pthread `HostMainExecutor` captures at
// install. A bare `assumeIsolated` verified that contract in debug only —
// in release a mis-threaded caller became a silent data race. These routes
// go through `withCheckedMainActorAccess` (F50), whose
// `MainActor.preconditionIsolated` is release-checked: `HostMainExecutor`
// implements `checkIsolated` via `pthread_equal`, so a wrong-thread call
// traps loudly with an attributable accessor name instead. The two copy_*
// entry points and install/diag need no bridge (nonisolated Mutex-guarded
// state or pump-local work).
@_cdecl("swift_tui_android_start")
public func swift_tui_android_start(
  _ handle: Int64
) {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return
  }

  withCheckedMainActorAccess("swift_tui_android_start") {
    host.start()
  }
}

@_cdecl("swift_tui_android_stop")
public func swift_tui_android_stop(
  _ handle: Int64
) {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return
  }

  withCheckedMainActorAccess("swift_tui_android_stop") {
    host.stop()
  }
}

@_cdecl("swift_tui_android_destroy")
public func swift_tui_android_destroy(
  _ handle: Int64
) {
  guard let host = AndroidHostHandleRegistry.remove(handle) else {
    return
  }

  withCheckedMainActorAccess("swift_tui_android_destroy") {
    host.stop()
  }
}

/// Installs the host-driven main-actor executor. Called by the JNI bridge as
/// the very first thing in `createHost`, before any main-actor work, so every
/// Android host app gets a drivable Swift main executor without each app's
/// `create_host` having to remember to do it. Idempotent.
@_cdecl("swift_tui_android_install_executor")
public func swift_tui_android_install_executor() {
  #if os(Android)
    AndroidMainExecutorPump.installIfNeeded()
  #endif
}

@_cdecl("swift_tui_android_tick")
public func swift_tui_android_tick(
  _ handle: Int64
) -> Int32 {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return 0
  }

  return withCheckedMainActorAccess("swift_tui_android_tick") {
    host.tick()
  }
}

/// Packed main-executor diagnostics for the JNI bridge log. See
/// `AndroidMainExecutorPump.diagnostics()`.
@_cdecl("swift_tui_android_diag")
public func swift_tui_android_diag() -> Int64 {
  #if os(Android)
    return AndroidMainExecutorPump.diagnostics()
  #else
    return 0
  #endif
}

@_cdecl("swift_tui_android_resize")
public func swift_tui_android_resize(
  _ handle: Int64,
  _ columns: Int32,
  _ rows: Int32,
  _ cellPixelWidth: Double,
  _ cellPixelHeight: Double
) {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return
  }

  withCheckedMainActorAccess("swift_tui_android_resize") {
    host.resize(
      columns: Int(columns),
      rows: Int(rows),
      cellPixelWidth: cellPixelWidth,
      cellPixelHeight: cellPixelHeight
    )
  }
}

@_cdecl("swift_tui_android_send_input")
public func swift_tui_android_send_input(
  _ handle: Int64,
  _ bytes: UnsafePointer<UInt8>?,
  _ count: Int32
) {
  guard let host = AndroidHostHandleRegistry.host(for: handle),
    let bytes = unsafe bytes,
    count > 0
  else {
    return
  }

  let payload = unsafe Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
  withCheckedMainActorAccess("swift_tui_android_send_input") {
    host.sendInput(payload)
  }
}

@_cdecl("swift_tui_android_declare_capabilities")
public func swift_tui_android_declare_capabilities(
  _ handle: Int64,
  _ bytes: UnsafePointer<UInt8>?,
  _ count: Int32
) -> Int32 {
  guard let host = AndroidHostHandleRegistry.host(for: handle),
    let bytes = unsafe bytes,
    count > 0
  else {
    return 0
  }

  let payload = unsafe Array(UnsafeBufferPointer(start: bytes, count: Int(count)))
  return withCheckedMainActorAccess("swift_tui_android_declare_capabilities") {
    host.declareCapabilities(json: String(decoding: payload, as: UTF8.self)) ? 1 : 0
  }
}

@_cdecl("swift_tui_android_copy_latest_frame")
public func swift_tui_android_copy_latest_frame(
  _ handle: Int64,
  _ outBuffer: UnsafeMutablePointer<UInt8>?,
  _ capacity: Int32
) -> Int32 {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return 0
  }

  let needed = unsafe host.copyLatestFrameBytes(
    to: outBuffer,
    capacity: max(0, Int(capacity))
  )
  return Int32(clamping: needed)
}

@_cdecl("swift_tui_android_copy_clipboard_text")
public func swift_tui_android_copy_clipboard_text(
  _ handle: Int64,
  _ outBuffer: UnsafeMutablePointer<UInt8>?,
  _ capacity: Int32
) -> Int32 {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return 0
  }

  let needed = unsafe host.copyPendingClipboardText(
    to: outBuffer,
    capacity: max(0, Int(capacity))
  )
  return Int32(clamping: needed)
}
