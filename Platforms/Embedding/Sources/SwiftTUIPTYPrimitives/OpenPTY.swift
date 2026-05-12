#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct PTYHandles: Sendable {
  public let masterFD: Int32
  public let slaveFD: Int32
  public let slavePath: String

  public init(masterFD: Int32, slaveFD: Int32, slavePath: String) {
    self.masterFD = masterFD
    self.slaveFD = slaveFD
    self.slavePath = slavePath
  }
}

public func openPTY() throws(PTYError) -> PTYHandles {
  var masterFD: Int32 = -1
  var slaveFD: Int32 = -1

  guard unsafe openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
    throw .allocationFailed(errno: errno)
  }

  configureNoSigPipe(masterFD)
  configureNoSigPipe(slaveFD)

  guard let slavePath = ttyName(slaveFD) else {
    closeFD(masterFD)
    closeFD(slaveFD)
    throw .slavePathUnavailable
  }

  return PTYHandles(masterFD: masterFD, slaveFD: slaveFD, slavePath: slavePath)
}

public func ptyResize(masterFD: Int32, cols: Int, rows: Int) throws(PTYError) {
  var windowSize = winsize(
    ws_row: UInt16(rows),
    ws_col: UInt16(cols),
    ws_xpixel: 0,
    ws_ypixel: 0
  )

  guard unsafe ioctl(masterFD, UInt(TIOCSWINSZ), &windowSize) == 0 else {
    throw .resizeFailed(errno: errno)
  }
}

public func closeFD(_ fd: Int32) {
  if fd >= 0 {
    _ = close(fd)
  }
}

private func configureNoSigPipe(_ fd: Int32) {
  #if canImport(Darwin)
    _ = fcntl(fd, F_SETNOSIGPIPE, 1)
  #endif
}

private func ttyName(_ fd: Int32) -> String? {
  guard let cString = unsafe ttyname(fd) else {
    return nil
  }
  return unsafe String(cString: cString)
}
