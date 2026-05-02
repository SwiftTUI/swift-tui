import Foundation
import SwiftTUI

struct BuildSummary: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy Queue")
        .bold()
      Divider()
      ProgressView("Release", value: 18, total: 24)
      LabeledContent("Window", value: "staging")
      LabeledContent("Owner", value: "infra")
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

let output = await MainActor.run {
  let renderer = DefaultRenderer()
  let frame = renderer.render(
    BuildSummary(),
    proposal: .init(width: 40, height: 8)
  )

  // let profile: TerminalCapabilityProfile = TerminalHost().capabilityProfile
  // let profile: TerminalCapabilityProfile = .detect(environment: ProcessInfo.processInfo.environment, isTTY: true)
  let profile: TerminalCapabilityProfile = .ansi256

  return TerminalSurfaceRenderer(capabilityProfile: profile)
    .render(frame.rasterSurface)
}

print(output)
