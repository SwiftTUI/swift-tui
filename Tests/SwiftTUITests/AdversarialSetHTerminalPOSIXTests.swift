// Adversarial set H, pass 1 (F6 platform edges): the POSIX terminal
// controller seam, discovered Linux-first and in release configuration
// (setH001–setH019). The hypotheses live in the F6 brief; every case names
// its contract there. Fixtures are a PTY pair from openpty(3) and plain pipes;
// nothing here waits on wall-clock sleeps — the only timing is the subject's
// own write budget.
#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @_spi(Testing) @testable import SwiftTUICore
  @_spi(Runners) @testable import SwiftTUIRuntime

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @Suite("Adversarial set H: POSIX terminal controller", .serialized)
  struct AdversarialSetHTerminalPOSIXTests {
    // Raw mode writes c_cc.16 and c_cc.17 by position. Those are Darwin's
    // VMIN/VTIME; on glibc they are VEOL2 and a reserved slot, so the test
    // compares every control character against cfmakeraw's own result.
    @Test func setH001RawModeLeavesOtherControlCharactersUntouched() throws {
      try withSetHPTY { pty in
        var reference = try setHAttributes(pty.slave)
        unsafe cfmakeraw(&reference)
        let controller = POSIXTerminalController()
        let snapshot = try controller.enterRawMode(input: pty.slave, output: pty.slave)
        defer { try? controller.restore(snapshot, input: pty.slave, output: pty.slave) }
        let raw = try setHAttributes(pty.slave)
        let controls = setHControlCharacters(raw)
        let expected = setHControlCharacters(reference)
        #expect(controls[Int(VMIN)] == 1)
        #expect(controls[Int(VTIME)] == 0)
        for index in controls.indices where index != Int(VMIN) && index != Int(VTIME) {
          let check = {
            #expect(
              controls[index] == expected[index],
              "c_cc[\(index)] = \(controls[index]), cfmakeraw leaves \(expected[index])")
          }
          #if os(Linux)
            if index == 16 {
              setHKnown(
                "STUI-1227: setH001: on Linux enterRawMode sets c_cc[16] (VEOL2) to 1; the positional c_cc.16/c_cc.17 writes are Darwin's VMIN/VTIME indices (TerminalPOSIXController.swift:99-102); contract: termios(3)/cfmakeraw raw mode changes only VMIN/VTIME; adjacent setA1076 (VMIN/VTIME only), no STUI"
              ) { check() }
            } else {
              check()
            }
          #else
            check()
          #endif
        }
      }
    }

    @Test func setH002CellPixelSizeFloorsDivision() throws {
      try withSetHPTY { pty in
        try setHSetWindowSize(pty.slave, columns: 80, rows: 24, xPixels: 639, yPixels: 383)
        let size = try POSIXTerminalController().cellPixelSize(of: pty.slave)
        #expect(size == PixelSize(width: 7, height: 15))
      }
    }

    @Test func setH003NegativeTimeoutReadsAvailableData() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      try pipe.send([0x61, 0x62])
      let bytes = try POSIXTerminalController().read(
        from: pipe.readEnd, maxBytes: 8, timeoutMilliseconds: -1)
      #expect(bytes == [0x61, 0x62])
    }

    @Test func setH004WindowSizeOnPipeReportsENOTTY() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      #expect(throws: TerminalHostError.failedToReadWindowSize(errno: ENOTTY)) {
        try POSIXTerminalController().windowSize(of: pipe.readEnd)
      }
    }

    @Test func setH005WindowSizeOnClosedDescriptorReportsEBADF() throws {
      let pipe = try SetHPipe()
      let closed = pipe.readEnd
      pipe.closeAll()
      #expect(throws: TerminalHostError.failedToReadWindowSize(errno: EBADF)) {
        try POSIXTerminalController().windowSize(of: closed)
      }
    }

    @Test func setH006ZeroWindowSizeClampsToOneCell() throws {
      try withSetHPTY { pty in
        try setHSetWindowSize(pty.slave, columns: 0, rows: 0, xPixels: 0, yPixels: 0)
        let size = try POSIXTerminalController().windowSize(of: pty.slave)
        #expect(size == CellSize(width: 1, height: 1))
      }
    }

    @Test func setH007CellPixelSizeClampsToOnePixel() throws {
      try withSetHPTY { pty in
        let controller = POSIXTerminalController()
        try setHSetWindowSize(pty.slave, columns: 10, rows: 10, xPixels: 7, yPixels: 7)
        #expect(try controller.cellPixelSize(of: pty.slave) == PixelSize(width: 1, height: 1))
        try setHSetWindowSize(pty.slave, columns: 0, rows: 24, xPixels: 640, yPixels: 384)
        #expect(try controller.cellPixelSize(of: pty.slave) == nil)
      }
    }

    @Test func setH008ZeroMaxBytesReadLeavesInputPending() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      try pipe.send([0x41])
      let controller = POSIXTerminalController()
      #expect(try controller.read(from: pipe.readEnd, maxBytes: 0, timeoutMilliseconds: 0) == [])
      #expect(
        try controller.read(from: pipe.readEnd, maxBytes: 1, timeoutMilliseconds: 0) == [0x41])
    }

    // The protocol takes an Int timeout; the POSIX arm converts it with
    // Int32(_). A value above Int32.max is representable at the seam but
    // traps inside the conversion.
    @Test func setH009ReadTimeoutBeyondInt32Traps() async {
      await setHKnown(
        "STUI-1227: setH009: read(timeoutMilliseconds: Int(Int32.max) + 1) traps; Int32(timeoutMilliseconds) is unchecked (TerminalPOSIXController.swift:247-251); contract: poll(2) takes int milliseconds, an Int timeout must clamp or reject, never trap; adjacent STUI-723 (unchecked numeric conversion class)"
      ) {
        await #expect(processExitsWith: .success) {
          let pipe = try SetHPipe()
          defer { pipe.closeAll() }
          try pipe.send([0x41])
          let bytes = try POSIXTerminalController().read(
            from: pipe.readEnd, maxBytes: 1, timeoutMilliseconds: Int(Int32.max) + 1)
          #expect(bytes == [0x41])
        }
      }
    }

    // EPIPE is documented as a clean disconnect: the write returns at once
    // instead of waiting out its budget.
    @Test func setH010DisconnectedWriteDoesNotWaitForBudget() async {
      await #expect(processExitsWith: .success) {
        let pipe = try SetHPipe()
        pipe.closeRead()
        defer { pipe.closeWrite() }
        let budget = TerminalWriteBudget(deadline: .now + .seconds(5))
        try POSIXTerminalController().write("x", to: pipe.writeEnd, budget: budget)
        #expect(!budget.expired)
      }
    }

    @Test func setH011PlatformWriteToRegularFileBypassesPolicy() throws {
      let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("setH011-\(UUID().uuidString)").path
      let descriptor = path.withCString { unsafe open($0, O_RDWR | O_CREAT | O_TRUNC, 0o600) }
      try #require(descriptor >= 0)
      defer {
        _ = close(descriptor)
        _ = path.withCString { unsafe unlink($0) }
      }
      let flagsBefore = setHStatusFlags(descriptor)
      let payload: [UInt8] = Array("hello".utf8)
      let written = payload.withUnsafeBytes {
        unsafe terminalPlatformWrite(descriptor, $0.baseAddress, $0.count)
      }
      #expect(written == 5)
      #expect(setHStatusFlags(descriptor) == flagsBefore)
      #expect(FileManager.default.contents(atPath: path).map { Array($0) } == payload)
    }

    @Test func setH012WindowSizeFromMasterMatchesSlave() throws {
      try withSetHPTY { pty in
        try setHSetWindowSize(pty.master, columns: 120, rows: 40, xPixels: 0, yPixels: 0)
        let controller = POSIXTerminalController()
        let fromMaster = try controller.windowSize(of: pty.master)
        let fromSlave = try controller.windowSize(of: pty.slave)
        #expect(fromMaster == CellSize(width: 120, height: 40))
        #expect(fromSlave == fromMaster)
      }
    }

    // A stalled peer: the pipe fills, poll never reports POLLOUT, and the
    // budget is the only thing that ends the write.
    @Test func setH013FullPipeWriteHonorsBudget() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let flags = setHStatusFlags(pipe.writeEnd)
      let payload = String(repeating: "x", count: 1 << 20)
      let budget = TerminalWriteBudget(deadline: .now + .milliseconds(50))
      #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
        try POSIXTerminalController().write(payload, to: pipe.writeEnd, budget: budget)
      }
      #expect(setHStatusFlags(pipe.writeEnd) == flags)
      let buffered = try pipe.drainAvailable()
      #expect(buffered > 0)
      #expect(buffered < payload.utf8.count)
    }

    @Test func setH014ReadRespectsMaxBytes() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      try pipe.send(Array(0..<10))
      let controller = POSIXTerminalController()
      #expect(
        try controller.read(from: pipe.readEnd, maxBytes: 4, timeoutMilliseconds: 0) == [
          0, 1, 2, 3,
        ])
      #expect(
        try controller.read(from: pipe.readEnd, maxBytes: 16, timeoutMilliseconds: 0)
          == [4, 5, 6, 7, 8, 9])
    }

    @Test func setH015WriteToReadEndReportsEBADF() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      #expect(throws: TerminalHostError.failedToWrite(errno: EBADF)) {
        try POSIXTerminalController().write("x", to: pipe.readEnd)
      }
    }

    @Test func setH016IsATTYClassifiesDescriptors() throws {
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      let controller = POSIXTerminalController()
      try withSetHPTY { pty in
        #expect(controller.isATTY(pty.slave))
      }
      #expect(!controller.isATTY(pipe.readEnd))
      #expect(!controller.isATTY(-1))
    }

    // Linux answers EIO on the master once the last slave closes; Darwin
    // answers EOF. The controller collapses both to an empty read.
    @Test func setH017MasterReadAfterSlaveCloseReturnsEmpty() throws {
      let pty = try SetHPTY()
      defer { pty.closeMaster() }
      pty.closeSlave()
      let bytes = try POSIXTerminalController().read(
        from: pty.master, maxBytes: 16, timeoutMilliseconds: 50)
      #expect(bytes == [])
    }

    @Test func setH018RestoreIsIdempotentAndReportsENOTTYOnPipe() throws {
      let controller = POSIXTerminalController()
      try withSetHPTY { pty in
        let snapshot = try controller.enterRawMode(input: pty.slave, output: pty.slave)
        try controller.restore(snapshot, input: pty.slave, output: pty.slave)
        try controller.restore(snapshot, input: pty.slave, output: pty.slave)
      }
      let pipe = try SetHPipe()
      defer { pipe.closeAll() }
      #expect(throws: TerminalHostError.failedToSetAttributes(errno: ENOTTY)) {
        try controller.restore(TerminalModeSnapshot(), input: pipe.writeEnd, output: pipe.writeEnd)
      }
    }

    @Test func setH019WriteBudgetOnlyShortens() {
      let budget = TerminalWriteBudget(deadline: .now + .seconds(60))
      #expect(!budget.expired)
      budget.finishWithin(.zero)
      #expect(budget.expired)
      budget.finishWithin(.seconds(60))
      #expect(budget.expired)
      #expect(throws: TerminalHostError.failedToWrite(errno: ETIMEDOUT)) {
        try budget.check()
      }
    }
  }

  // MARK: - Fixtures

  #if canImport(Darwin)
    private func setHRawWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
      unsafe Darwin.write(fd, buffer, count)
    }
    private func setHRawRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
      unsafe Darwin.read(fd, buffer, count)
    }
  #else
    private func setHRawWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
      unsafe Glibc.write(fd, buffer, count)
    }
    private func setHRawRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
      unsafe Glibc.read(fd, buffer, count)
    }
  #endif

  /// A PTY pair whose descriptors close at most once.
  final class SetHPTY {
    private(set) var master: Int32 = -1
    private(set) var slave: Int32 = -1

    init() throws {
      var master: Int32 = -1
      var slave: Int32 = -1
      try #require(unsafe openpty(&master, &slave, nil, nil, nil) == 0)
      self.master = master
      self.slave = slave
    }

    func closeSlave() {
      if slave >= 0 { _ = close(slave) }
      slave = -1
    }

    func closeMaster() {
      if master >= 0 { _ = close(master) }
      master = -1
    }

    func closeAll() {
      closeSlave()
      closeMaster()
    }
  }

  func withSetHPTY(_ body: (SetHPTY) throws -> Void) throws {
    let pty = try SetHPTY()
    defer { pty.closeAll() }
    try body(pty)
  }

  /// A pipe whose two ends close at most once.
  final class SetHPipe {
    private(set) var readEnd: Int32 = -1
    private(set) var writeEnd: Int32 = -1

    init() throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      readEnd = descriptors[0]
      writeEnd = descriptors[1]
    }

    func send(_ bytes: [UInt8]) throws {
      let written = bytes.withUnsafeBytes {
        unsafe setHRawWrite(writeEnd, $0.baseAddress, $0.count)
      }
      try #require(written == bytes.count)
    }

    /// Reads whatever the pipe holds without blocking and returns the count.
    func drainAvailable() throws -> Int {
      let flags = fcntl(readEnd, F_GETFL)
      try #require(fcntl(readEnd, F_SETFL, flags | O_NONBLOCK) == 0)
      defer { _ = fcntl(readEnd, F_SETFL, flags) }
      var total = 0
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        let count = buffer.withUnsafeMutableBytes {
          unsafe setHRawRead(readEnd, $0.baseAddress, $0.count)
        }
        if count <= 0 { return total }
        total += count
      }
    }

    func closeRead() {
      if readEnd >= 0 { _ = close(readEnd) }
      readEnd = -1
    }

    func closeWrite() {
      if writeEnd >= 0 { _ = close(writeEnd) }
      writeEnd = -1
    }

    func closeAll() {
      closeRead()
      closeWrite()
    }
  }

  /// Status flags without Darwin's kernel-set FWASWRITTEN (0x10000)
  /// bookkeeping bit, which F_GETFL reports after the first write to any
  /// descriptor (oracle correction for setH011/setH013).
  func setHStatusFlags(_ descriptor: Int32) -> Int32 {
    #if canImport(Darwin)
      fcntl(descriptor, F_GETFL) & ~0x0001_0000
    #else
      fcntl(descriptor, F_GETFL)
    #endif
  }

  func setHAttributes(_ descriptor: Int32) throws -> termios {
    var attributes = termios()
    try #require(unsafe tcgetattr(descriptor, &attributes) == 0)
    return attributes
  }

  func setHControlCharacters(_ attributes: termios) -> [UInt8] {
    withUnsafeBytes(of: attributes.c_cc) { unsafe Array($0) }
  }

  func setHSetWindowSize(
    _ descriptor: Int32, columns: Int, rows: Int, xPixels: Int, yPixels: Int
  ) throws {
    var size = winsize(
      ws_row: UInt16(rows), ws_col: UInt16(columns),
      ws_xpixel: UInt16(xPixels), ws_ypixel: UInt16(yPixels))
    try #require(unsafe ioctl(descriptor, UInt(TIOCSWINSZ), &size) == 0)
  }
#endif
