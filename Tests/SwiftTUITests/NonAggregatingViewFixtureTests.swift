import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// AnyView policy: retain erased fixture roots here for test support only.
@Suite
@MainActor
struct NonAggregatingViewFixtureTests {
  @Test("non-aggregating view fixture matches", arguments: nonAggregatingFixtureNames)
  func renderedFixtureMatches(named fixtureName: String) throws {
    let fixture = fixture(named: fixtureName)

    try assertRenderedTextFixtures(
      named: fixture.name,
      size: fixture.size,
      view: fixture.view,
      identity: fixture.identity,
      environmentValues: fixture.environmentValues
    )
  }

  private func fixture(named name: String) -> FixtureSpec {
    switch name {
    case "empty-view":
      return FixtureSpec(
        name: name,
        size: .init(width: 4, height: 2),
        view: AnyView(EmptyView())
      )

    case "text":
      return FixtureSpec(
        name: name,
        size: .init(width: 14, height: 2),
        view: AnyView(Text("Wide: 界e\u{301}"))
      )

    case "spacer":
      return FixtureSpec(
        name: name,
        size: .init(width: 6, height: 2),
        view: AnyView(Spacer(minLength: 2))
      )

    case "divider":
      return FixtureSpec(
        name: name,
        size: .init(width: 14, height: 1),
        view: AnyView(Divider())
      )

    case "label":
      return FixtureSpec(
        name: name,
        size: .init(width: 16, height: 1),
        view: AnyView(
          Label("Endpoint", icon: { Text("◎") })
        )
      )

    case "labeled-content":
      return FixtureSpec(
        name: name,
        size: .init(width: 20, height: 1),
        view: AnyView(LabeledContent("Mode", value: "Inspect"))
      )

    case "toggle":
      return FixtureSpec(
        name: name,
        size: .init(width: 22, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Toggle("Accent Preview", isOn: .constant(true))
        )
      )

    case "stepper":
      return FixtureSpec(
        name: name,
        size: .init(width: 24, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Stepper("Retries", value: .constant(3), in: 0...9)
        )
      )

    case "text-field":
      return FixtureSpec(
        name: name,
        size: .init(width: 18, height: 3),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          TextField("Name", text: .constant("Ada"))
            .textFieldStyle(.roundedBorder)
            .frame(width: 14, alignment: .leading)
        )
      )

    case "slider":
      return FixtureSpec(
        name: name,
        size: .init(width: 26, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Slider("Blend", value: .constant(42), in: 0...100)
        )
      )

    case "button":
      return FixtureSpec(
        name: name,
        size: .init(width: 18, height: 3),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Button("Deploy", action: {})
            .buttonStyle(.borderedProminent)
        )
      )

    case "progress-view":
      return FixtureSpec(
        name: name,
        size: .init(width: 26, height: 1),
        view: AnyView(
          ProgressView("Rollout", value: 7, total: 10)
        )
      )

    case "full-screen-cover":
      return FixtureSpec(
        name: name,
        size: .init(width: 36, height: 8),
        view: AnyView(
          Text("Background")
            .fullScreenCover(isPresented: .constant(true)) {
              VStack(alignment: .leading, spacing: 1) {
                Text("Full-screen workspace")
                  .bold()
                Divider()
                Text("No card chrome")
              }
              .padding(1)
            }
        )
      )

    default:
      return FixtureSpec(
        name: name,
        size: .init(width: 1, height: 1),
        view: AnyView(Text("invalid"))
      )
    }
  }
}

private let nonAggregatingFixtureNames = [
  "empty-view",
  "text",
  "spacer",
  "divider",
  "label",
  "labeled-content",
  "toggle",
  "stepper",
  "text-field",
  "slider",
  "button",
  "progress-view",
  "full-screen-cover",
]

private struct FixtureSpec {
  let name: String
  let size: CellSize
  let identity: Identity
  let environmentValues: EnvironmentValues
  let view: AnyView

  init(
    name: String,
    size: CellSize,
    identity: Identity = testIdentity("Fixture"),
    environmentValues: EnvironmentValues = .init(),
    view: AnyView
  ) {
    self.name = name
    self.size = size
    self.identity = identity
    self.environmentValues = environmentValues
    self.view = view
  }
}

private func focusedEnvironmentValues(
  identity: Identity = testIdentity("Fixture")
) -> EnvironmentValues {
  var values = EnvironmentValues()
  values.focusedIdentity = identity
  return values
}
