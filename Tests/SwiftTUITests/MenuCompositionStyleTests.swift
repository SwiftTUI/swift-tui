import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct MenuCompositionStyleTests {
  @Test(
    "public consumer menu preserves every raster cell", arguments: [false, true], [false, true])
  func menuParity(enabled: Bool, focused: Bool) {
    for expanded in [false, true] {
      let actual = renderMenu(.automatic, enabled: enabled, focused: focused, expanded: expanded)
      let expected = renderMenu(
        .init(ConsumerAutomaticMenuStyle()),
        enabled: enabled, focused: focused, expanded: expanded)
      #expect(actual.rasterSurface == expected.rasterSurface)
    }
  }

  @Test("public consumer control-group compositions preserve every raster cell")
  func groupParity() {
    let pairs: [(AnyControlGroupStyle, AnyControlGroupStyle)] = [
      (.automatic, .init(ConsumerHorizontalControlGroupStyle())),
      (.horizontal, .init(ConsumerHorizontalControlGroupStyle())),
      (.vertical, .init(ConsumerVerticalControlGroupStyle())),
      (.compactMenu, .init(ConsumerCompactMenuControlGroupStyle())),
    ]
    for (actual, expected) in pairs {
      let a = DefaultRenderer().render(
        ControlGroup("Commands") {
          Text("First")
          Text("Second")
        }.controlGroupStyle(actual),
        context: .init(identity: testIdentity("Root")), proposal: .init(width: 30, height: 10))
      let b = DefaultRenderer().render(
        ControlGroup("Commands") {
          Text("First")
          Text("Second")
        }.controlGroupStyle(expected),
        context: .init(identity: testIdentity("Root")), proposal: .init(width: 30, height: 10))
      #expect(a.rasterSurface == b.rasterSurface)
    }
  }

  @Test("finite anchored height keeps short content intrinsic and scrolls overflow")
  func heightCap() throws {
    for count in [2, 12] {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("Root"),
        size: .init(width: 35, height: 16)
      ) {
        Menu("Commands") {
          ForEach(0..<count, id: \.self) { Text("Row \($0)") }
        }.menuStyle(SizedMenuStyle(presentation: .init(maximumHeight: 3)))
      }
      defer { harness.shutdown() }
      _ = try harness.clickText("Commands")
      #expect(harness.frame.contains("Row 0"))
      #expect(harness.frame.contains("Row 1"))
      if count == 12 {
        #expect(!harness.frame.contains("Row 3"))
        let point = try #require(harness.point(forText: "Row 1"))
        _ = try harness.scrollPointer(at: point, deltaY: 3)
        #expect(harness.frame.contains("Row 3"))
        #expect(!harness.frame.contains("Row 0"))
      } else {
        let nonEmptyRows = harness.frame.split(separator: "\n").filter {
          !$0.allSatisfy(\.isWhitespace)
        }
        #expect(nonEmptyRows.count <= 6)
      }
    }
  }

  @Test("anchored width constraints bound the floating surface")
  func widthBounds() throws {
    let intrinsic = renderMenu(
      .init(SizedMenuStyle(presentation: .init())),
      enabled: true, focused: false, expanded: true)
    let smallMinimum = renderMenu(
      .init(SizedMenuStyle(presentation: .init(minimumWidth: 2))),
      enabled: true, focused: false, expanded: true)
    let largeMaximum = renderMenu(
      .init(SizedMenuStyle(presentation: .init(maximumWidth: 30))),
      enabled: true, focused: false, expanded: true)
    let minimumMatches = smallMinimum.rasterSurface == intrinsic.rasterSurface
    let maximumMatches = largeMaximum.rasterSurface == intrinsic.rasterSurface
    #expect(
      minimumMatches, "small minimum changed intrinsic output: \(smallMinimum.rasterSurface.lines)")
    #expect(
      maximumMatches, "large maximum changed intrinsic output: \(largeMaximum.rasterSurface.lines)")
    let narrow = renderMenu(
      .init(SizedMenuStyle(presentation: .init(maximumWidth: 10))),
      enabled: true, focused: false, expanded: true)
    let wide = renderMenu(
      .init(SizedMenuStyle(presentation: .init(minimumWidth: 24))),
      enabled: true, focused: false, expanded: true)
    #expect(narrow.rasterSurface.lines.contains { $0.contains("▖") })
    let narrowBorder = narrow.rasterSurface.lines.first { $0.contains("▖") } ?? ""
    let wideBorder = wide.rasterSurface.lines.first { $0.contains("▖") } ?? ""
    #expect(narrowBorder.firstIndex(of: "▖") != nil)
    #expect(wideBorder.firstIndex(of: "▖") != nil)
    let narrowStart = try #require(narrowBorder.firstIndex(of: "▗"))
    let narrowEnd = try #require(narrowBorder.firstIndex(of: "▖"))
    #expect(narrowBorder.distance(from: narrowStart, to: narrowEnd) + 1 <= 10)
    let wideStart = try #require(wideBorder.firstIndex(of: "▗"))
    let wideEnd = try #require(wideBorder.firstIndex(of: "▖"))
    #expect(wideBorder.distance(from: wideStart, to: wideEnd) + 1 >= 24)
  }

  private func renderMenu(_ style: AnyMenuStyle, enabled: Bool, focused: Bool, expanded: Bool)
    -> RenderSnapshot
  {
    let renderer = DefaultRenderer()
    let actions = LocalActionRegistry()
    let identity = testIdentity("Menu")
    let menu = Menu("Commands") {
      Text("First command")
      Text("Second command")
    }
    .menuStyle(style).id(identity)
    var environment = EnvironmentValues()
    var context = ResolveContext(
      identity: testIdentity("Root"), environmentValues: environment,
      localActionRegistry: actions, applyEnvironmentValues: true)
    _ = renderer.render(menu, context: context, proposal: .init(width: 40, height: 14))
    if expanded { #expect(actions.dispatch(identity: identity)) }
    environment.isEnabled = enabled
    environment.focusedIdentity = focused ? identity : nil
    context.environmentValues = environment
    return renderer.render(menu, context: context, proposal: .init(width: 40, height: 14))
  }
}

private struct SizedMenuStyle: MenuStyle {
  let presentation: AnchoredSurfaceStylePresentation
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    SizedMenuBody(configuration: configuration, presentation: presentation)
  }
}
private struct SizedMenuBody: View {
  let configuration: MenuStyleConfiguration
  let presentation: AnchoredSurfaceStylePresentation
  var body: some View {
    configuration.portal(presentation: presentation) {
      configuration.trigger { configuration.label }
    }
  }
}
