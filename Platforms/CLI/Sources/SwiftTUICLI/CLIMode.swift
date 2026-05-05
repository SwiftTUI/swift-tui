#if !canImport(WASILibc)
  internal import ArgumentParser
  internal import Foundation

  enum CLIModeError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case invalidPID(String)
    case unknownFlag(String)

    var description: String {
      switch self {
      case .missingValue(let flag):
        "Missing value for \(flag)"
      case .invalidPID(let value):
        "Invalid PID: \(value)"
      case .unknownFlag(let flag):
        "Unknown flag: \(flag)"
      }
    }
  }

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
    /// Supports two surfaces:
    ///
    /// 1. **Subcommand form** (preferred): `myapp instances`,
    ///    `myapp scenes [--pid N | --instance NAME]`,
    ///    `myapp attach <scene-id> [--pid N | --instance NAME]`.
    /// 2. **Legacy flag form** (deprecated): `--instances`, `--scenes`,
    ///    `--attach <id>`, and the loose `--instance NAME` for app-launch
    ///    naming. Using any of these emits a one-time deprecation warning to
    ///    stderr.
    ///
    /// When neither form matches (e.g., the consumer's own argument parser
    /// owns argv), returns `.app(instanceName: nil)`.
    static func parse(_ arguments: [String]) throws(CLIModeError) -> CLIMode {
      // Skip argv[0]
      let args = Array(arguments.dropFirst())

      if usesLegacyFlagForm(args) {
        emitLegacyDeprecationWarningIfNeeded()
        return try parseLegacyFlagForm(args)
      }

      return parseSubcommandForm(args)
    }

    /// Returns true when `args` looks like the deprecated flag form.
    ///
    /// `--instances`, `--scenes`, and `--attach` are unambiguously legacy:
    /// the modern surface uses subcommand tokens (`instances`, `scenes`,
    /// `attach`) for those operations.
    ///
    /// `--pid` and `--instance` are *modifiers* — they appear in both the
    /// legacy form (`--scenes --pid 1234`) and the modern form
    /// (`scenes --pid 1234`). They count as legacy only when there is no
    /// runner subcommand token present in `args` to host them.
    private static func usesLegacyFlagForm(_ args: [String]) -> Bool {
      let unambiguousLegacyFlags: Set<String> = ["--instances", "--scenes", "--attach"]
      if args.contains(where: { unambiguousLegacyFlags.contains($0) }) {
        return true
      }

      let modifierFlags: Set<String> = ["--pid", "--instance"]
      let hasModifier = args.contains(where: { modifierFlags.contains($0) })
      guard hasModifier else { return false }

      let subcommandTokens: Set<String> = ["instances", "scenes", "attach"]
      let hasSubcommand = args.contains(where: { subcommandTokens.contains($0) })
      return !hasSubcommand
    }

    /// Hand-rolled parser for the legacy flag form. Preserved verbatim so
    /// existing scripts keep working — including the re-classification of
    /// `--instance NAME` when paired with a client flag.
    private static func parseLegacyFlagForm(_ args: [String]) throws(CLIModeError) -> CLIMode {
      var instanceName: String?
      var listInstances = false
      var listScenes = false
      var attachSceneID: String?
      var pid: Int32?
      var selectorName: String?

      var index = 0
      while index < args.count {
        let arg = args[index]
        switch arg {
        case "--instances":
          listInstances = true
        case "--scenes":
          listScenes = true
        case "--attach":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--attach")
          }
          attachSceneID = args[index]
        case "--pid":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--pid")
          }
          guard let parsedPID = Int32(args[index]) else {
            throw .invalidPID(args[index])
          }
          pid = parsedPID
        case "--instance":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--instance")
          }
          let name = args[index]
          // Determine if this is a launch-time name or a selector based on
          // whether a client flag is also present. We resolve this after parsing.
          if listScenes || attachSceneID != nil || listInstances {
            selectorName = name
          } else {
            // Could be either — store as instance name, re-classify below.
            instanceName = name
          }
        default:
          break
        }
        index += 1
      }

      // Re-classify --instance if a client flag was parsed after it.
      if let name = instanceName, listScenes || attachSceneID != nil {
        selectorName = name
        instanceName = nil
      }

      let selector: InstanceSelector =
        if let pid {
          .pid(pid)
        } else if let selectorName {
          .name(selectorName)
        } else {
          .mostRecent
        }

      if listInstances {
        return .listInstances
      }

      if let attachSceneID {
        return .attach(sceneID: attachSceneID, selector: selector)
      }

      if listScenes {
        return .listScenes(selector: selector)
      }

      return .app(instanceName: instanceName)
    }

    /// Parses the modern subcommand form via `RunnerCLI`. Falls back to
    /// `.app(instanceName: nil)` when `args` doesn't match — the consumer's
    /// own argument parser owns argv first, so any non-runner-subcommand
    /// input should be treated as 'run mode'.
    private static func parseSubcommandForm(_ args: [String]) -> CLIMode {
      guard let parsed = try? RunnerCLI.parseAsRoot(args) else {
        return .app(instanceName: nil)
      }

      switch parsed {
      case let attach as RunnerCLI.Attach:
        let selector: InstanceSelector =
          if let pid = attach.pid {
            .pid(pid)
          } else if let name = attach.instance {
            .name(name)
          } else {
            .mostRecent
          }
        return .attach(sceneID: attach.sceneID, selector: selector)
      case let scenes as RunnerCLI.Scenes:
        let selector: InstanceSelector =
          if let pid = scenes.pid {
            .pid(pid)
          } else if let name = scenes.instance {
            .name(name)
          } else {
            .mostRecent
          }
        return .listScenes(selector: selector)
      case is RunnerCLI.Instances:
        return .listInstances
      case is RunnerCLI:
        // Bare invocation with no subcommand. The named-instance app-launch
        // flag (`--instance NAME`) is owned by the legacy hand-rolled parser
        // (see `usesLegacyFlagForm`), so the only thing left here is the
        // empty-args case.
        return .app(instanceName: nil)
      default:
        return .app(instanceName: nil)
      }
    }
  }

  // MARK: - Legacy deprecation warning

  /// Set after the first legacy-flag invocation in this process so we only
  /// nag once per run. Accesses are wrapped in `unsafe` blocks because the
  /// `nonisolated(unsafe)` storage opts out of strict-concurrency tracking;
  /// races would only result in the warning being printed an extra time,
  /// which is harmless.
  private nonisolated(unsafe) var didEmitLegacyDeprecationWarning = false

  private func emitLegacyDeprecationWarningIfNeeded() {
    guard unsafe !didEmitLegacyDeprecationWarning else { return }
    unsafe didEmitLegacyDeprecationWarning = true
    let message = """
      warning: SwiftTUI runner-internal flags (--instances, --scenes, --attach, \
      --pid, --instance) are deprecated. Use subcommand form instead:
        myapp instances
        myapp scenes [--pid N | --instance NAME]
        myapp attach <scene-id> [--pid N | --instance NAME]
      The legacy flag form will be removed in a future release.

      """
    FileHandle.standardError.write(Data(message.utf8))
  }
#endif
