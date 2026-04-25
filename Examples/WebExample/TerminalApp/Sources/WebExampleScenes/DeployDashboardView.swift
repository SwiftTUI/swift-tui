import TerminalUI

struct DeployDashboardView: View {
  @State private var successfulRuns: Int = 18
  @State private var trafficSplit: Int = 35
  @State private var autoPromote: Bool = true
  @State private var showCanary: Bool = true
  @State private var freezeWrites: Bool = false
  @State private var operatorNote: String = "Watching browser-hosted canary"
  @State private var selectedLane: ReleaseLane = .staging
  @State private var selectedRegion: ReleaseRegion = .ord

  private let totalRuns: Int = 24

  private var rolloutPercent: Int {
    Int((Double(successfulRuns) / Double(totalRuns)) * 100)
  }

  private var releaseSummary: String {
    "\(selectedLane.label) lane · \(showCanary ? "canary" : "full fleet") · \(trafficSplit)% traffic"
  }

  private var promotionSummary: String {
    "\(autoPromote ? "Auto-promote armed" : "Manual approval required") · \(freezeWrites ? "writes frozen" : "writes live")"
  }

  private var readinessLabel: String {
    switch successfulRuns {
    case totalRuns:
      "Ship window open"
    case 20...:
      "Final verification"
    case 12...:
      "Canary ramping"
    default:
      "Warming the lane"
    }
  }

  private var healthTone: Color {
    if freezeWrites { return .yellow }
    if successfulRuns == totalRuns { return .green }
    if successfulRuns >= 12 { return .cyan }
    return .magenta
  }

  private var activityFeed: [String] {
    [
      "[gate] \(selectedLane.label) lane is \(autoPromote ? "armed for autopromote" : "waiting for operator approval").",
      "[edge] \(trafficSplit)% traffic pinned to \(selectedRegion.label) while \(showCanary ? "canary remains enabled." : "the full fleet is exposed.").",
      "[db] Writes are \(freezeWrites ? "frozen for verification." : "open for the next deploy wave.").",
      "[note] \(trimmedOperatorNote)",
    ]
  }

  private var trimmedOperatorNote: String {
    let note = String(operatorNote.drop(while: { $0.isWhitespace }))
    if note.isEmpty {
      return "No operator note recorded."
    }
    return String(note.prefix(52))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
        .padding(1)
      ScrollView {
        ViewThatFits {
          HStack(alignment: .top, spacing: 1) {
            primaryColumn
            secondaryColumn
          }

          VStack(alignment: .leading, spacing: 1) {
            primaryColumn
            secondaryColumn
          }
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 2) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Deploy Dashboard")
          .bold()
        Text("A lightweight browser-safe control room for the wasm demo.")
          .foregroundStyle(.separator)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 0) {
        Text(readinessLabel)
          .foregroundStyle(healthTone)
        Text(releaseSummary)
          .foregroundStyle(.separator)
      }
    }
  }

  private var primaryColumn: some View {
    VStack(alignment: .leading, spacing: 1) {
      rolloutPanel
      controlsPanel
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var secondaryColumn: some View {
    VStack(alignment: .leading, spacing: 1) {
      statusPanel
      activityPanel
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var rolloutPanel: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Release train")
        .bold()
      Text(promotionSummary)
        .foregroundStyle(.separator)
      ProgressView("Checks", value: Double(successfulRuns), total: Double(totalRuns))
      HStack(spacing: 1) {
        Button("-1") {
          successfulRuns = max(0, successfulRuns - 1)
        }
        .buttonStyle(.bordered)

        Button("+1") {
          successfulRuns = min(totalRuns, successfulRuns + 1)
        }
        .buttonStyle(.bordered)

        Button("Ship it") {
          successfulRuns = totalRuns
          autoPromote = true
          showCanary = true
        }
        .buttonStyle(.borderedProminent)
      }
      Text("\(successfulRuns) / \(totalRuns) checks passed")
        .foregroundStyle(.separator)
    }
    .padding(1)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var controlsPanel: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Traffic control")
        .bold()

      Text("Lane")
        .foregroundStyle(.separator)
      HStack(spacing: 1) {
        laneButton(.canary)
        laneButton(.staging)
        laneButton(.production)
      }

      Text("Primary region")
        .foregroundStyle(.separator)
      HStack(spacing: 1) {
        regionButton(.iad)
        regionButton(.ord)
        regionButton(.dub)
      }

      Slider("Traffic split \(trafficSplit)%", value: $trafficSplit, in: 10...100, step: 5)
      Toggle("Auto-promote after checks", isOn: $autoPromote)
      Toggle("Keep canary wave enabled", isOn: $showCanary)
      Toggle("Freeze writes during handoff", isOn: $freezeWrites)

      Text("Operator note")
        .foregroundStyle(.separator)
      TextField("Deployment note", text: $operatorNote)
    }
    .padding(1)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var statusPanel: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Status board")
        .bold()

      HStack(alignment: .top, spacing: 2) {
        TextFigure("\(rolloutPercent)%", font: .future)
          .foregroundStyle(healthTone)

        VStack(alignment: .leading, spacing: 0) {
          Text(readinessLabel)
          Text(selectedRegion.summary)
            .foregroundStyle(.separator)
          Text(trafficMeter)
            .foregroundStyle(Color.cyan)
        }
      }

      Divider()

      Text("Active lane: \(selectedLane.label)")
      Text("Primary region: \(selectedRegion.label)")
      Text("Traffic shape: \(showCanary ? "staged canary" : "full-fleet release")")
      Text("Promotion mode: \(autoPromote ? "automatic" : "manual")")
      Text("Write mode: \(freezeWrites ? "frozen" : "live")")
    }
    .padding(1)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var activityPanel: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Activity feed")
        .bold()

      VStack(alignment: .leading, spacing: 0) {
        Text("Latest control-plane notes")
          .foregroundStyle(.separator)
        ForEach(activityFeed, id: \.self) { line in
          Text(line)
        }
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .border(.separator)
  }

  private var trafficMeter: String {
    let filled = max(1, trafficSplit / 10)
    let empty = max(0, 10 - filled)
    return
      "[\(String(repeating: "#", count: filled))\(String(repeating: ".", count: empty))] \(trafficSplit)%"
  }

  private func laneButton(_ lane: ReleaseLane) -> some View {
    Button(lane.label) {
      selectedLane = lane
    }
    .buttonStyle(selectedLane == lane ? .borderedProminent : .bordered)
  }

  private func regionButton(_ region: ReleaseRegion) -> some View {
    Button(region.label) {
      selectedRegion = region
    }
    .buttonStyle(selectedRegion == region ? .borderedProminent : .bordered)
  }
}

extension DeployDashboardView {
  enum ReleaseLane: String {
    case canary
    case staging
    case production

    var label: String {
      switch self {
      case .canary: "Canary"
      case .staging: "Staging"
      case .production: "Production"
      }
    }
  }

  enum ReleaseRegion {
    case iad
    case ord
    case dub

    var label: String {
      switch self {
      case .iad: "IAD"
      case .ord: "ORD"
      case .dub: "DUB"
      }
    }

    var summary: String {
      switch self {
      case .iad: "East coast edge is running synthetic checks."
      case .ord: "Midwest edge is acting as the primary canary."
      case .dub: "EU edge is held one wave behind for rollback safety."
      }
    }
  }
}
