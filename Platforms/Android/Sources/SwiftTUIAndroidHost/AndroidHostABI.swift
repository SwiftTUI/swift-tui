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

@_cdecl("swift_tui_android_start")
public func swift_tui_android_start(
  _ handle: Int64
) {
  guard let host = AndroidHostHandleRegistry.host(for: handle) else {
    return
  }

  MainActor.assumeIsolated {
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

  MainActor.assumeIsolated {
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

  MainActor.assumeIsolated {
    host.stop()
  }
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

  MainActor.assumeIsolated {
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
  MainActor.assumeIsolated {
    host.sendInput(payload)
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
