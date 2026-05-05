#if !canImport(WASILibc)
  internal import ArgumentParser

  /// Runner-internal subcommand surface used by the bare-mode `App.main()`.
  ///
  /// Not exposed to `SwiftTUIApp` consumers (they own their own argv and
  /// route through their own `ParsableCommand`).
  ///
  /// Subcommand form: `myapp instances`, `myapp scenes`, `myapp attach <id>`.
  ///
  /// Legacy flag form: `--instances`, `--scenes`, `--attach <id>` — still
  /// supported but deprecated; `CLIMode.parse` prints a warning to stderr the
  /// first time it sees a legacy flag in a process.
  struct RunnerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "swifttui-runner",
      abstract: "SwiftTUI runner-internal subcommands.",
      subcommands: [
        Instances.self,
        Scenes.self,
        Attach.self,
      ]
    )

    // Note: root-level `--instance` is intentionally *not* declared here.
    // The legacy `--instance NAME` app-launch flag is routed through the
    // hand-rolled parser by `usesLegacyFlagForm`, and putting `instance`
    // on both the root and the subcommands creates an option-name conflict
    // that caused subcommand-bound `--instance` values to bind to the root
    // instead of `Scenes` / `Attach`.

    struct Instances: ParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "instances",
        abstract: "List currently running instances of this app."
      )
    }

    struct Scenes: ParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "scenes",
        abstract: "List scenes for a running instance."
      )

      @Option(help: "Select instance by PID.")
      var pid: Int32?

      @Option(help: "Select instance by name.")
      var instance: String?
    }

    struct Attach: ParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach to a scene of a running instance."
      )

      @Argument(help: "Scene identifier.")
      var sceneID: String

      @Option(help: "Select instance by PID.")
      var pid: Int32?

      @Option(help: "Select instance by name.")
      var instance: String?
    }
  }
#endif
