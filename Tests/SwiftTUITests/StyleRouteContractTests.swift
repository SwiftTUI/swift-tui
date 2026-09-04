import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

/// The shared route-wrapper contract (control-style plan 2026-08-12-002,
/// stage B0), pinned on the one family that ships route wrappers today.
///
/// Three rules, none of which may trap:
///
/// - installing the same route more than once in one style body emits
///   `style.duplicateRoute` and the first installation wins;
/// - omitting an optional route removes only the pointer target — keyboard
///   interaction is the primitive's and survives untouched;
/// - a fixture-constructed configuration's routes are inert.
@MainActor
@Suite("Style route contract")
struct StyleRouteContractTests {
  @Test("installing one route twice reports style.duplicateRoute and the first installation wins")
  func duplicateRouteReportsAndFirstInstallationWins() throws {
    let selectionBox = SelectionBox()
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    let tabsIdentity = testIdentity("Tabs")
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = pointerRegistry

    let artifacts = renderer.render(
      contractTabView(selection: selectionBox.binding)
        .tabViewStyle(DoubleRouteConsumerTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 48, height: 4)
    )

    // Both installations render their content; only the first is a route.
    let strip = trimTrailingSpaces(artifacts.rasterSurface.lines[0])
    #expect(strip == "Home (Home) Settings (Settings) Logs (Logs)")

    let issues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "style.duplicateRoute"
    }
    #expect(issues.count == 3, "one issue per item whose route was installed twice")
    let issue = try #require(issues.first)
    #expect(issue.severity == .warning)
    #expect(issue.message.contains("TabViewStyle"))
    #expect(issue.message.contains("DoubleRouteConsumerTabViewStyle"))
    #expect(issue.message.contains("item route"))
    #expect(issue.source == "TabViewStyle")
    #expect(
      Set(issues.compactMap(\.identity))
        == Set((0..<3).map { tabItemIdentity(for: tabsIdentity, index: $0) })
    )

    for index in 0..<3 {
      let routeIdentity = tabItemIdentity(for: tabsIdentity, index: index)
      #expect(
        artifacts.resolvedTree.pointerRouteCount(for: routeIdentity) == 1,
        "exactly one pointer route survives for item \(index)"
      )
    }

    // The surviving route is live: pointer selection still works.
    let routeID = primaryRouteID(for: tabItemIdentity(for: tabsIdentity, index: 1))
    #expect(pointerRegistry.hasHandler(pairingWith: routeID))
    #expect(
      pointerRegistry.dispatch(
        routeID: routeID,
        event: primaryPointerDownEvent()
      ).wantsPointerStream
    )
    #expect(selectionBox.value == "settings")
  }

  @Test("a style body that installs each route once reports nothing")
  func singleInstallationReportsNothing() {
    let selectionBox = SelectionBox()
    let tabsIdentity = testIdentity("Tabs")
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = LocalPointerHandlerRegistry()

    let artifacts = DefaultRenderer().render(
      contractTabView(selection: selectionBox.binding)
        .tabViewStyle(RouteOncePerItemTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 40, height: 4)
    )

    #expect(artifacts.diagnostics.runtime.issues.filter { $0.code.hasPrefix("style.") }.isEmpty)
    for index in 0..<3 {
      #expect(
        artifacts.resolvedTree.pointerRouteCount(
          for: tabItemIdentity(for: tabsIdentity, index: index)
        ) == 1
      )
    }
  }

  @Test("omitting the item route removes the pointer target and leaves keyboard navigation intact")
  func omittedRouteKeepsKeyboardNavigation() {
    let selectionBox = SelectionBox()
    let tabsIdentity = testIdentity("Tabs")
    let keyRegistry = LocalKeyHandlerRegistry()
    let actionRegistry = LocalActionRegistry()
    let pointerRegistry = LocalPointerHandlerRegistry()

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = tabsIdentity

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      localActionRegistry: actionRegistry,
      localKeyHandlerRegistry: keyRegistry,
      applyEnvironmentValues: true
    )
    context.localPointerHandlerRegistry = pointerRegistry

    let artifacts = DefaultRenderer().render(
      contractTabView(selection: selectionBox.binding)
        .tabViewStyle(RoutelessConsumerTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 40, height: 4)
    )

    #expect(trimTrailingSpaces(artifacts.rasterSurface.lines[0]) == "Home Settings Logs")
    #expect(artifacts.diagnostics.runtime.issues.filter { $0.code.hasPrefix("style.") }.isEmpty)
    for index in 0..<3 {
      let routeIdentity = tabItemIdentity(for: tabsIdentity, index: index)
      #expect(artifacts.resolvedTree.pointerRouteCount(for: routeIdentity) == 0)
      // The control still registers its item handler — that is the
      // primitive's business — but with no route node no cell is
      // hit-testable under the item identity, so no click can reach it.
      #expect(artifacts.resolvedTree.hitTestingNodeCount(for: routeIdentity) == 0)
      #expect(pointerRegistry.hasHandler(pairingWith: primaryRouteID(for: routeIdentity)))
    }

    // Keyboard interaction is the primitive's, not the style's.
    #expect(keyRegistry.hasHandler(identity: tabsIdentity))
    #expect(keyRegistry.dispatch(identity: tabsIdentity, keyPress: KeyPress(.arrowRight)))
    #expect(selectionBox.value == "home")
    #expect(actionRegistry.dispatch(identity: tabsIdentity))
    #expect(selectionBox.value == "settings")
  }

  @Test("a fixture-constructed item configuration renders its route content with no pointer target")
  func fixtureItemRouteIsInert() {
    let item = TabViewStyleItemConfiguration(
      index: 0,
      label: TabItemLabel("Home"),
      isSelected: true,
      isFocused: false
    )
    let pointerRegistry = LocalPointerHandlerRegistry()
    var context = ResolveContext(identity: testIdentity("Fixture"))
    context.localPointerHandlerRegistry = pointerRegistry

    let artifacts = DefaultRenderer().render(
      item.route {
        Text(item.isSelected ? "[\(item.label.displayText)]" : item.label.displayText)
      },
      context: context,
      proposal: .init(width: 12, height: 1)
    )

    #expect(trimTrailingSpaces(artifacts.rasterSurface.lines[0]) == "[Home]")
    #expect(artifacts.resolvedTree.totalPointerRouteCount() == 0)
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
  }

  @Test("a fixture-constructed body configuration resolves a custom style body with inert routes")
  func fixtureBodyConfigurationResolvesWithInertRoutes() {
    let items = ["Home", "Settings"].enumerated().map { index, title in
      TabViewStyleItemConfiguration(
        index: index,
        label: TabItemLabel(title),
        isSelected: index == 0,
        isFocused: false
      )
    }
    let configuration = TabViewStyleBodyConfiguration(
      styleConfiguration: TabViewStyleConfiguration(
        options: items.map { TabViewStyleOption(label: $0.label) },
        selectedIndex: 0,
        focusedIndex: nil,
        isFocused: false,
        showsFocusEffect: true,
        styleEnvironment: StyleEnvironmentSnapshot(),
        availableWidth: 40,
        isOverflowMenuExpanded: false
      ),
      presentation: TabViewStylePresentation(
        stripHeight: 1,
        visibleOptionIndices: [0, 1],
        overflowMenu: nil
      ),
      items: items,
      overflowTrigger: nil,
      content: TabViewStyleBodyConfiguration.Content {
        Text("fixture content")
      }
    )

    let pointerRegistry = LocalPointerHandlerRegistry()
    var context = ResolveContext(identity: testIdentity("Fixture"))
    context.localPointerHandlerRegistry = pointerRegistry

    let artifacts = DefaultRenderer().render(
      RouteOncePerItemTabViewStyle().makeBody(configuration: configuration),
      context: context,
      proposal: .init(width: 40, height: 3)
    )

    let lines = artifacts.rasterSurface.lines.prefix(2).map(trimTrailingSpaces)
    #expect(Array(lines) == ["[Home] Settings", "fixture content"])
    #expect(artifacts.resolvedTree.totalPointerRouteCount() == 0)
    #expect(artifacts.diagnostics.runtime.issues.isEmpty)
  }

  @Test("an empty fixture content slot resolves to nothing")
  func emptyFixtureContentSlotResolvesToNothing() {
    let artifacts = DefaultRenderer().render(
      VStack(spacing: 0) {
        Text("above")
        TabViewStyleBodyConfiguration.Content()
        Text("below")
      },
      context: .init(identity: testIdentity("Fixture")),
      proposal: .init(width: 10, height: 3)
    )
    let lines = artifacts.rasterSurface.lines.prefix(3).map(trimTrailingSpaces)
    #expect(Array(lines) == ["above", "below", ""])
  }
}

@MainActor
private final class SelectionBox {
  var value = "home"

  var binding: Binding<String> {
    Binding(
      get: { self.value },
      set: { self.value = $0 }
    )
  }
}

@MainActor
private func contractTabView(
  selection: Binding<String>
) -> some View {
  TabView(selection: selection) {
    Tab("Home", value: "home") {
      Text("Home content")
    }

    Tab("Settings", value: "settings") {
      Text("Settings content")
    }

    Tab("Logs", value: "logs") {
      Text("Logs content")
    }
  }
}

private struct FlatStripPresentation {
  @MainActor
  static func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }
}

/// Installs every item route twice: the misuse the shared rule reports.
private struct DoubleRouteConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "DoubleRouteConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    FlatStripPresentation.presentation(for: configuration)
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          let item = configuration.items[index]
          item.route {
            Text(item.label.displayText)
          }
          item.route {
            Text("(\(item.label.displayText))")
          }
        }
      }
      configuration.content
    }
  }
}

/// The conforming shape: one route per item.
private struct RouteOncePerItemTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "RouteOncePerItemTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    FlatStripPresentation.presentation(for: configuration)
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          let item = configuration.items[index]
          item.route {
            Text(item.isSelected ? "[\(item.label.displayText)]" : item.label.displayText)
          }
        }
      }
      configuration.content
    }
  }
}

/// Never installs a route: pointer targets vanish, keyboard stays.
private struct RoutelessConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "RoutelessConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    FlatStripPresentation.presentation(for: configuration)
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          Text(configuration.items[index].label.displayText)
        }
      }
      configuration.content
    }
  }
}

extension ResolvedNode {
  fileprivate func pointerRouteCount(for identity: Identity) -> Int {
    let own = (kind == .view("PointerRoute") && self.identity == identity) ? 1 : 0
    return children.reduce(own) { $0 + $1.pointerRouteCount(for: identity) }
  }

  fileprivate func totalPointerRouteCount() -> Int {
    let own = kind == .view("PointerRoute") ? 1 : 0
    return children.reduce(own) { $0 + $1.totalPointerRouteCount() }
  }

  fileprivate func hitTestingNodeCount(for identity: Identity) -> Int {
    let own =
      (semanticMetadata.participatesInPointerHitTesting && self.identity == identity) ? 1 : 0
    return children.reduce(own) { $0 + $1.hitTestingNodeCount(for: identity) }
  }
}

private func trimTrailingSpaces(
  _ line: String
) -> String {
  String(line.reversed().drop(while: { $0 == " " }).reversed())
}

private func primaryPointerDownEvent() -> LocalPointerEvent {
  .init(
    kind: .down(.primary),
    location: .zero,
    targetRect: .zero
  )
}
