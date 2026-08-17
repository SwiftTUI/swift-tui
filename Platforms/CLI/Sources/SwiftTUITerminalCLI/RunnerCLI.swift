#if !canImport(WASILibc)
  internal import ArgumentParser

  /// Runner-internal subcommand surface used by the bare-mode `App.main()`.
  ///
  /// Not exposed to `SwiftTUICommand` consumers — they own their own argv and
  /// route through their own `ParsableCommand`.
  ///
  /// Surface:
  ///
  /// - `myapp` / `myapp --instance NAME` — run the app (the `Run` default
  ///   subcommand picks up the bare invocation).
  /// - `myapp instances` — list running instances of this app.
  /// - `myapp scenes [--pid N | --instance NAME]` — list scenes for a
  ///   running instance.
  /// - `myapp attach <scene-id> [--pid N | --instance NAME]` — attach to a
  ///   scene of a running instance.
  struct RunnerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "swifttui-runner",
      abstract: "SwiftTUI runner-internal subcommands.",
      subcommands: [
        Run.self,
        Instances.self,
        Scenes.self,
        Attach.self,
      ],
      defaultSubcommand: Run.self
    )

    /// Default subcommand. `myapp` and `myapp --instance NAME` route here.
    ///
    /// `--instance` lives on `Run` rather than the root because a root-level
    /// `--instance` would conflict with the same-named selector on `Scenes`
    /// / `Attach` — ArgumentParser would bind subcommand-level `--instance`
    /// values to the parent command instead of the subcommand.
    struct Run: ParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the app (default)."
      )

      @Option(help: "Run as a named instance.")
      var instance: String?
    }

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
