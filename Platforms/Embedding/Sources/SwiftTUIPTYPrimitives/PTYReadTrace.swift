// Opt-in metadata only; never records terminal contents or input text.
#if !os(Windows)
  import Dispatch
  import Foundation
  import Synchronization

  final class PTYReadTrace: Sendable {
    private let file: Mutex<FileHandle>

    init?() {
      guard let directory = ProcessInfo.processInfo.environment["SWIFTTUI_PTY_DIAGNOSTICS"] else {
        return nil
      }
      let path = URL(fileURLWithPath: directory)
        .appendingPathComponent("pty-\(UUID().uuidString).tsv").path
      guard FileManager.default.createFile(atPath: path, contents: nil),
        let handle = FileHandle(forWritingAtPath: path)
      else { return nil }
      file = Mutex(handle)
      try? handle.write(
        contentsOf: Data(
          "time_ns\tevent\tslave\tbytes\tqueued_bytes\toldest_ns\tresidence_ns\n".utf8))
    }

    deinit { file.withLock { try? $0.close() } }

    func record(
      _ event: String, time: UInt64 = DispatchTime.now().uptimeNanoseconds,
      slave: String, bytes: Int, queued: Int = 0, oldest: UInt64 = 0, residence: UInt64 = 0
    ) {
      let line = "\(time)\t\(event)\t\(slave)\t\(bytes)\t\(queued)\t\(oldest)\t\(residence)\n"
      file.withLock { try? $0.write(contentsOf: Data(line.utf8)) }
    }
  }
#endif
