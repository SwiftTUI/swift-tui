public import SwiftTUIPTYPrimitives

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Attach-mode wrapper around `PTYPair`.
public final class ScenePty: Sendable {
  public let pair: PTYPair
  public let slavePath: String
  let masterFD: Int32

  public init() throws(PTYError) {
    let handles = try openPTY()
    slavePath = handles.slavePath
    masterFD = handles.masterFD
    pair = PTYPair(handles: handles, retainSlaveFD: false)
  }

  public func hasAttachedClient() async -> Bool {
    let fd = await pair.rawMasterFD
    return sceneHasAttachedClient(masterFD: fd)
  }

  public func close() async {
    await pair.close()
  }
}

private func sceneHasAttachedClient(masterFD fd: Int32) -> Bool {
  guard fd >= 0 else { return false }

  // PTY masters report a hangup when no slave is attached. That signal is
  // stable across Darwin and Linux, unlike zero-byte writes.
  var descriptor = pollfd(
    fd: fd,
    events: Int16(POLLHUP | POLLOUT),
    revents: 0
  )
  let result = unsafe poll(&descriptor, 1, 0)
  guard result > 0 else { return false }
  return (descriptor.revents & Int16(POLLHUP)) == 0
}
