import TerminalUI

@testable import Layouts

/// Single-shot render helper used by every behaviour test file.
/// Identity is derived from `#function` so parallel test invocations
/// get unique identities.
@MainActor
func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = #function
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = Size(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["layouts.behaviour.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
