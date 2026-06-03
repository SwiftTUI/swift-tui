import SwiftTUI
import Testing

@testable import SwiftTUIPTYPrimitives

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("PTYPair", .serialized)
struct PTYPairTests {
  @Test("init from handles exposes masterFD and slavePath")
  func initFromHandles() async throws {
    try await withPTYPair(retainSlaveFD: false) { handles, pair in
      #expect(await pair.rawMasterFD >= 0)
      #expect(await pair.slavePath == handles.slavePath)
    }
  }

  @Test("write to master is readable on the slave")
  func writeMasterReadSlave() async throws {
    try await withPTYPair(retainSlaveFD: true) { handles, pair in
      try await pair.write(Array("hello\n".utf8))

      var buffer = [UInt8](repeating: 0, count: 16)
      let n = unsafe buffer.withUnsafeMutableBufferPointer { buf in
        unsafe read(handles.slaveFD, buf.baseAddress, buf.count)
      }
      #expect(n >= 5)
      let received = Array(buffer.prefix(Int(n)))
      #expect(received.starts(with: Array("hello".utf8)))
    }
  }

  @Test("resize updates the kernel winsize")
  func resize() async throws {
    try await withPTYPair(retainSlaveFD: true) { handles, pair in
      try await pair.resize(CellSize(width: 132, height: 50))

      var ws = winsize()
      _ = unsafe ioctl(handles.masterFD, UInt(TIOCGWINSZ), &ws)
      #expect(ws.ws_col == 132)
      #expect(ws.ws_row == 50)
    }
  }
}

private func withPTYPair<R>(
  retainSlaveFD: Bool,
  _ body: (PTYHandles, PTYPair) async throws -> R
) async throws -> R {
  let handles = try openPTY()
  let pair = PTYPair(handles: handles, retainSlaveFD: retainSlaveFD)
  do {
    let result = try await body(handles, pair)
    await pair.close()
    return result
  } catch {
    await pair.close()
    throw error
  }
}
