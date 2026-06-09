import SwiftTUIViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

package func systemOpenLinkAction() -> OpenLinkAction {
  OpenLinkAction(
    snapshotLabel: "OpenLinkAction.systemDefault",
    isPlaceholder: false,
    handler: openLinkInSystem
  )
}

package func openLinkInSystem(
  _ destination: LinkDestination
) -> Bool {
  guard !destination.isEmpty else {
    return false
  }

  #if os(macOS)
    return spawnDetachedProcess(
      command: "/usr/bin/open",
      arguments: ["/usr/bin/open", destination.rawValue],
      searchPath: false
    )
  #elseif os(Linux)
    return spawnDetachedProcess(
      command: "xdg-open",
      arguments: ["xdg-open", destination.rawValue],
      searchPath: true
    )
  #else
    return false
  #endif
}

#if canImport(Darwin) || canImport(Glibc)
  private func spawnDetachedProcess(
    command: String,
    arguments: [String],
    searchPath: Bool
  ) -> Bool {
    var pid = pid_t()
    var cArguments: [UnsafeMutablePointer<CChar>?] = unsafe arguments.map { argument in
      unsafe argument.withCString { cString in
        unsafe strdup(cString)
      }
    }
    unsafe cArguments.append(nil)
    defer {
      let argumentCount = unsafe cArguments.count
      var index = 0
      while index < argumentCount {
        if let pointer = unsafe cArguments[index] {
          unsafe free(pointer)
        }
        index += 1
      }
    }

    let environment = unsafe environ
    let spawnResult: Int32 = unsafe cArguments.withUnsafeMutableBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return ENOENT
      }
      guard let executable = unsafe baseAddress[0] else {
        return ENOENT
      }

      if searchPath {
        return unsafe posix_spawnp(
          &pid,
          executable,
          nil,
          nil,
          baseAddress,
          environment
        )
      }

      return unsafe command.withCString { commandCString in
        unsafe posix_spawn(
          &pid,
          commandCString,
          nil,
          nil,
          baseAddress,
          environment
        )
      }
    }

    return spawnResult == 0
  }
#endif
