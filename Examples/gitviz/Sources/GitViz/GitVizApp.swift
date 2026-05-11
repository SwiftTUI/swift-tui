import ArgumentParser

@main
struct GitVizApp: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "gitviz",
    abstract: "Visualize information about a git repository using SwiftTUICharts.",
    discussion: """
      gitviz exercises every chart primitive in SwiftTUICharts against the
      current git repository. Run `gitviz` with no arguments for an index of
      available subcommands.
      """,
    subcommands: [
      IndexCommand.self,
      InfoCommand.self,
      ActivityCommand.self,
      CadenceCommand.self,
      TempoCommand.self,
      DeltasCommand.self,
      LocCommand.self,
      VolatilityCommand.self,
      KindsCommand.self,
      KindsShareCommand.self,
      PulseCommand.self,
      RecentVsAllCommand.self,
      HealthCommand.self,
      ConcentrationCommand.self,
      ReleasesCommand.self,
      DagCommand.self,
      DashboardCommand.self,
    ],
    defaultSubcommand: IndexCommand.self
  )
}
