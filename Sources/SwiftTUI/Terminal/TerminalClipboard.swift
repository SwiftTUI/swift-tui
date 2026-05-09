#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

/// Host capability for clipboard writes initiated by authored views or embedded clients.
public protocol ClipboardWritingPresentationSurface: AnyObject {
  @discardableResult
  @MainActor
  func writeClipboard(_ text: String) throws -> Bool
}

package protocol ClipboardReadingPresentationSurface: AnyObject {
  @MainActor
  func readClipboard() throws -> String?
}

package func systemClipboardText() -> String? {
  #if os(macOS)
    readCommandOutput("/usr/bin/pbpaste")
  #else
    nil
  #endif
}

#if os(macOS)
  private func readCommandOutput(_ command: String) -> String? {
    var pipeFileDescriptors = [Int32](repeating: 0, count: 2)
    guard unsafe pipe(&pipeFileDescriptors) == 0 else {
      return nil
    }
    let readFileDescriptor = pipeFileDescriptors[0]
    let writeFileDescriptor = pipeFileDescriptors[1]

    var actions: posix_spawn_file_actions_t? = nil
    guard unsafe posix_spawn_file_actions_init(&actions) == 0 else {
      closeFileDescriptor(readFileDescriptor)
      closeFileDescriptor(writeFileDescriptor)
      return nil
    }
    defer {
      unsafe posix_spawn_file_actions_destroy(&actions)
    }

    guard
      unsafe posix_spawn_file_actions_addclose(&actions, readFileDescriptor) == 0,
      unsafe posix_spawn_file_actions_adddup2(&actions, writeFileDescriptor, STDOUT_FILENO) == 0,
      unsafe posix_spawn_file_actions_addclose(&actions, writeFileDescriptor) == 0
    else {
      closeFileDescriptor(readFileDescriptor)
      closeFileDescriptor(writeFileDescriptor)
      return nil
    }

    var arguments: [UnsafeMutablePointer<CChar>?] = unsafe [
      strdup(command),
      nil,
    ]
    defer {
      if let argument = unsafe arguments[0] {
        unsafe free(argument)
      }
    }

    var processID = pid_t()
    let spawnResult = unsafe arguments.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress,
        let executable = unsafe baseAddress[0]
      else {
        return ENOENT
      }
      return unsafe posix_spawn(
        &processID,
        executable,
        &actions,
        nil,
        baseAddress,
        environ
      )
    }
    closeFileDescriptor(writeFileDescriptor)
    guard spawnResult == 0 else {
      closeFileDescriptor(readFileDescriptor)
      return nil
    }

    let bytes = readAllBytes(from: readFileDescriptor)
    closeFileDescriptor(readFileDescriptor)

    var status: Int32 = 0
    while unsafe waitpid(processID, &status, 0) == -1 {
      guard errno == EINTR else {
        return nil
      }
    }
    guard status == 0 else {
      return nil
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private func readAllBytes(from fileDescriptor: Int32) -> [UInt8] {
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
        unsafe read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
      }
      guard count > 0 else {
        return bytes
      }
      bytes.append(contentsOf: buffer.prefix(count))
    }
  }

  private func closeFileDescriptor(_ fileDescriptor: Int32) {
    guard fileDescriptor >= 0 else {
      return
    }
    _ = close(fileDescriptor)
  }
#endif

package func terminalClipboardSequence(
  for text: String
) -> String {
  "\u{001B}]52;c;\(terminalClipboardBase64Encoded(Array(text.utf8)))\u{0007}"
}

private func terminalClipboardBase64Encoded(
  _ bytes: [UInt8]
) -> String {
  guard !bytes.isEmpty else {
    return ""
  }

  let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
  var result: [UInt8] = []
  result.reserveCapacity(((bytes.count + 2) / 3) * 4)

  var index = 0
  while index < bytes.count {
    let first = Int(bytes[index])
    let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
    let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
    let combined = (first << 16) | (second << 8) | third

    result.append(alphabet[(combined >> 18) & 0x3F])
    result.append(alphabet[(combined >> 12) & 0x3F])
    result.append(index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : UInt8(ascii: "="))
    result.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : UInt8(ascii: "="))
    index += 3
  }

  return String(decoding: result, as: UTF8.self)
}
