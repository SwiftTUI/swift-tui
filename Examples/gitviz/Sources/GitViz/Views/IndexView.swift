import SwiftTUI
import SwiftTUICharts

/// Labeled index of available subcommands. Grouped into Basics / Activity /
/// Code / People / Diagnostics so users can scan-find the right command.
struct IndexView: View {
  struct Entry: Hashable {
    let name: String
    let description: String
  }

  struct Section: Hashable {
    let title: String
    let entries: [Entry]
  }

  let sections: [Section] = [
    Section(
      title: "Basics",
      entries: [
        Entry(name: "info", description: "Repository summary and tag count."),
        Entry(name: "index", description: "This list."),
      ]),
    Section(
      title: "Activity",
      entries: [
        Entry(name: "activity", description: "GitHub-style calendar heatmap."),
        Entry(name: "cadence", description: "Hour-of-day heat strip."),
        Entry(name: "tempo", description: "Weekly sparkline per top-N author."),
        Entry(name: "pulse", description: "Current vs trailing-median commits/week."),
      ]),
    Section(
      title: "Code",
      entries: [
        Entry(name: "deltas", description: "Insertions / deletions over time."),
        Entry(name: "loc", description: "Cumulative net LOC (ins - del)."),
        Entry(name: "volatility", description: "Top-N most-changed files."),
        Entry(name: "kinds", description: "Commit-kind counts."),
        Entry(name: "kinds-share", description: "Quarterly kind share."),
      ]),
    Section(
      title: "People",
      entries: [
        Entry(name: "recent-vs-all", description: "Recent vs all-time author share."),
        Entry(name: "concentration", description: "Bus factor / author concentration."),
        Entry(name: "health", description: "Percentage of code <1y old."),
      ]),
    Section(
      title: "Diagnostics",
      entries: [
        Entry(name: "releases", description: "Tag and release history."),
        Entry(name: "dag", description: "git log --graph DAG."),
        Entry(name: "dashboard", description: "Run everything."),
      ]),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("gitviz").bold()
      Text("Subcommands. Pass --help to any of these for details.")
        .foregroundStyle(.muted)
      Divider()
      ForEach(sections, id: \.title) { section in
        Text(section.title).bold()
        ForEach(section.entries, id: \.name) { entry in
          HStack(spacing: 2) {
            Text(entry.name).bold()
            Text(entry.description).foregroundStyle(.muted)
          }
        }
        Divider()
      }
    }
  }
}
