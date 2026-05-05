// Bare-mode rendering reference. This example deliberately does NOT use the
// scene runtime, App protocol, or SwiftTUIArguments. It exercises the lowest
// level of the rendering API (DefaultRenderer + TerminalSurfaceRenderer) so
// readers can see the layer that everything else is built on. See
// Examples/gallery for the SwiftTUIApp easy-mode pattern with argument
// parsing, or Examples/argparse for a focused arg-parsing demo.

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
