import View

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

package func parallelSystemOpenLinkAction() -> OpenLinkAction {
  OpenLinkAction(
    snapshotLabel: "OpenLinkAction.systemDefault",
    isPlaceholder: false,
    handler: parallelOpenLinkInSystem
  )
}

package func parallelOpenLinkInSystem(
  _ destination: String
) -> Bool {
  guard !destination.isEmpty else {
    return false
  }

  #if os(macOS)
    return spawnDetachedProcess(
      command: "/usr/bin/open",
      arguments: ["/usr/bin/open", destination],
      searchPath: false
    )
  #elseif os(Linux) || os(Android)
    return spawnDetachedProcess(
      command: "xdg-open",
      arguments: ["xdg-open", destination],
      searchPath: true
    )
  #else
    return false
  #endif
}

#if canImport(Darwin) || canImport(Glibc) || canImport(Android)
  private func spawnDetachedProcess(
    command: String,
    arguments: [String],
    searchPath: Bool
  ) -> Bool {
    var pid = pid_t()
    var cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { argument in
      argument.withCString { cString in
        strdup(cString)
      }
    }
    cArguments.append(nil)
    defer {
      for case let pointer? in cArguments {
        free(pointer)
      }
    }

    let spawnResult: Int32 = cArguments.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return ENOENT
      }

      if searchPath {
        return posix_spawnp(
          &pid,
          baseAddress[0],
          nil,
          nil,
          baseAddress,
          environ
        )
      }

      return command.withCString { commandCString in
        posix_spawn(
          &pid,
          commandCString,
          nil,
          nil,
          baseAddress,
          environ
        )
      }
    }

    return spawnResult == 0
  }
#endif
