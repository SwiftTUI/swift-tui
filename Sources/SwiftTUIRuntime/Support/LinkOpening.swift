import SwiftTUIViews

#if os(macOS) || os(Linux)
  import Dispatch
#endif

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(ucrt)
  import CRT
#endif

/// A presentation surface whose host opens links for the runtime's default
/// open-link action, instead of this process spawning a platform opener.
package protocol LinkOpeningPresentationSurface: AnyObject {
  /// Whether the host installed an opener. Without one the default action
  /// keeps using the process-level system opener.
  @MainActor var opensLinksInHost: Bool { get }

  /// Hands `destination` to the host. The result reports whether the host
  /// accepted the request, which need not mean a destination opened.
  @MainActor func openLinkInHost(_ destination: LinkDestination) -> Bool
}

package func systemOpenLinkAction() -> OpenLinkAction {
  OpenLinkAction(
    snapshotLabel: "OpenLinkAction.systemDefault",
    isPlaceholder: false,
    usesHostDefault: true,
    handler: openLinkInSystem
  )
}

/// The default open-link action for a run loop presenting on `surface`. A
/// surface with a host opener receives the destination; every other surface
/// keeps the process-level system opener. Both are the same host-default
/// action to authored code: a custom `OpenLinkAction` replaces either.
@MainActor
package func systemOpenLinkAction(
  presentingOn surface: any PresentationSurfaceMetricsProvider
) -> OpenLinkAction {
  guard let surface = surface as? any LinkOpeningPresentationSurface,
    surface.opensLinksInHost
  else {
    return systemOpenLinkAction()
  }
  return OpenLinkAction(
    snapshotLabel: "OpenLinkAction.systemDefault",
    isPlaceholder: false,
    usesHostDefault: true
  ) { [weak surface] destination in
    guard !destination.isEmpty, let surface else {
      return false
    }
    return surface.openLinkInHost(destination)
  }
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

#if os(macOS) || os(Linux)
  // Internal completion hook lets tests observe reaping without polling process state.
  func spawnDetachedProcess(
    command: String,
    arguments: [String],
    searchPath: Bool,
    onExit: (@Sendable (pid_t) -> Void)? = nil
  ) -> Bool {
    #if canImport(Darwin)
      var fileActions: posix_spawn_file_actions_t? = nil
    #else
      var fileActions = unsafe posix_spawn_file_actions_t()
    #endif
    guard unsafe posix_spawn_file_actions_init(&fileActions) == 0 else { return false }
    defer { _ = unsafe posix_spawn_file_actions_destroy(&fileActions) }
    // The helper must neither consume terminal input nor interleave output
    // with the renderer. Open in the child so the parent owns no extra fd.
    for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
      let result = "/dev/null".withCString { path in
        unsafe posix_spawn_file_actions_addopen(
          &fileActions, descriptor, path, descriptor == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0)
      }
      guard result == 0 else { return false }
    }
    var pid = pid_t()
    var cArguments: [UnsafeMutablePointer<CChar>?] = unsafe arguments.map { argument in
      argument.withCString { cString in
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
    let spawnResult: Int32 = cArguments.withUnsafeMutableBufferPointer { buffer in
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
          &fileActions,
          nil,
          baseAddress,
          environment
        )
      }

      return command.withCString { commandCString in
        unsafe posix_spawn(
          &pid,
          commandCString,
          &fileActions,
          nil,
          baseAddress,
          environment
        )
      }
    }

    guard spawnResult == 0 else { return false }
    let childPID = pid
    // waitpid blocks until the helper exits. Keep it off the caller and the
    // cooperative executor, and reap only this child without changing SIGCHLD.
    DispatchQueue.global(qos: .background).async {
      var status: Int32 = 0
      while unsafe waitpid(childPID, &status, 0) == -1 {
        guard errno == EINTR else { break }
      }
      onExit?(childPID)
    }
    return true
  }
#endif
