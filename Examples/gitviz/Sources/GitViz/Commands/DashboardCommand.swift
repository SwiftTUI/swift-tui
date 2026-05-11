import ArgumentParser

struct DashboardCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dashboard",
    abstract: "Run info, activity, deltas, kinds, volatility, and releases back-to-back.",
    discussion: """
      Long output. Pipe to `less -R` if you only want to scan parts of it.
      """
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    // Each child command's body is short; reuse them by parsing default
    // instances and substituting the shared options before invoking `run()`.
    try await runChild { (cmd: inout InfoCommand) in cmd.opts = opts }
    try await runChild { (cmd: inout ActivityCommand) in cmd.opts = opts }
    try await runChild { (cmd: inout DeltasCommand) in cmd.opts = opts }
    try await runChild { (cmd: inout KindsCommand) in cmd.opts = opts }
    try await runChild { (cmd: inout VolatilityCommand) in cmd.opts = opts }
    try await runChild { (cmd: inout ReleasesCommand) in cmd.opts = opts }
  }

  /// Parses a default-state instance of the child command type, lets the
  /// caller substitute fields, then invokes `run()`. Using `parseAsRoot([])`
  /// rather than the bare initializer ensures ArgumentParser-managed
  /// properties are fully populated (otherwise `@Flag verbose: Int` would
  /// trap on first access).
  @MainActor
  private func runChild<C: AsyncParsableCommand>(
    _ mutate: (inout C) -> Void
  ) async throws {
    guard var child = try C.parseAsRoot([]) as? C else { return }
    mutate(&child)
    try await child.run()
  }
}
