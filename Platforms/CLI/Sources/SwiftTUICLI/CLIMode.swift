#if !canImport(WASILibc)
  internal import ArgumentParser

  enum InstanceSelector: Equatable, Sendable {
    case mostRecent
    case pid(Int32)
    case name(String)
  }

  enum CLIMode: Equatable, Sendable {
    case app(instanceName: String?)
    case listInstances
    case listScenes(selector: InstanceSelector)
    case attach(sceneID: String, selector: InstanceSelector)

    /// Parses `arguments` (typically `CommandLine.arguments`) into a `CLIMode`.
    ///
    /// The runner exposes four subcommands via `RunnerCLI`:
    ///
    /// - `myapp` / `myapp --instance NAME` — `.app(instanceName: ...)`
    ///   (the `Run` default subcommand picks up the bare invocation).
    /// - `myapp instances` — `.listInstances`.
    /// - `myapp scenes [--pid N | --instance NAME]` — `.listScenes(...)`.
    /// - `myapp attach <scene-id> [--pid N | --instance NAME]` — `.attach(...)`.
    ///
    /// When `arguments` doesn't match any of those (e.g., a `SwiftTUICommand`
    /// consumer's own flags appear in argv first), returns
    /// `.app(instanceName: nil)` — the consumer's parser owns argv, so the
    /// runner treats the invocation as plain "run mode".
    static func parse(_ arguments: [String]) -> CLIMode {
      // Skip argv[0]
      let args = Array(arguments.dropFirst())

      guard let parsed = try? RunnerCLI.parseAsRoot(args) else {
        return .app(instanceName: nil)
      }

      switch parsed {
      case let attach as RunnerCLI.Attach:
        return .attach(
          sceneID: attach.sceneID, selector: selector(pid: attach.pid, name: attach.instance))
      case let scenes as RunnerCLI.Scenes:
        return .listScenes(selector: selector(pid: scenes.pid, name: scenes.instance))
      case is RunnerCLI.Instances:
        return .listInstances
      case let run as RunnerCLI.Run:
        return .app(instanceName: run.instance)
      default:
        return .app(instanceName: nil)
      }
    }

    private static func selector(pid: Int32?, name: String?) -> InstanceSelector {
      if let pid {
        .pid(pid)
      } else if let name {
        .name(name)
      } else {
        .mostRecent
      }
    }
  }
#endif
