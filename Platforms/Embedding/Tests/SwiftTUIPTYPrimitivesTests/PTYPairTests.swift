// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

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
        let n = buffer.withUnsafeMutableBufferPointer { buf in
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

    @Test("openPTY resolves slave paths while other threads open PTYs")
    func concurrentOpenResolvesSlavePaths() async {
      let failures = await withTaskGroup(of: [String].self) { group in
        for _ in 0..<8 {
          group.addTask {
            var failures: [String] = []
            for _ in 0..<50 {
              do throws(PTYError) {
                let handles = try openPTY()
                if !handles.slavePath.hasPrefix("/dev/") {
                  failures.append("unexpected slave path \(handles.slavePath)")
                }
                closeFD(handles.masterFD)
                closeFD(handles.slaveFD)
              } catch {
                failures.append(error.description)
              }
            }
            return failures
          }
        }
        var failures: [String] = []
        for await taskFailures in group {
          failures += taskFailures
        }
        return failures
      }
      #expect(
        failures.isEmpty, "\(failures.count) of 400 opens failed; first: \(failures.first ?? "")")
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

#endif
