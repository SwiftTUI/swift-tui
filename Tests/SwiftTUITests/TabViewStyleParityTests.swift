import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TabViewStyleParityTests {
  @Test("consumer TabViewStyle owns full body layout and keeps tab routes active")
  func consumerStyleOwnsBodyLayoutAndRoutesTabs() throws {
    final class SelectionBox {
      var value = "home"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    let tabsIdentity = testIdentity("Tabs")
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = pointerRegistry

    let surface = renderer.render(
      parityTabView(selection: selection)
        .tabViewStyle(ContentFirstConsumerTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 40, height: 6)
    )
    .rasterSurface.lines
    .prefix(3)
    .map(trimTrailingSpaces)

    #expect(
      Array(surface)
        == [
          "Home content",
          "[Home] Settings Logs",
          "",
        ]
    )

    let routeID = tabItemRouteID(for: tabsIdentity, index: 1)
    #expect(pointerRegistry.hasHandler(pairingWith: routeID))
    #expect(
      pointerRegistry.dispatch(
        routeID: routeID,
        event: primaryPointerDownEvent()
      )
    )
    #expect(selectionBox.value == "settings")
  }

  @Test("consumer TabViewStyle owns overflow trigger and item layout")
  func consumerStyleOwnsOverflowLayoutAndRoutesOverflowItems() {
    final class SelectionBox {
      var value = "one"
    }

    let selectionBox = SelectionBox()
    let selection = Binding(
      get: { selectionBox.value },
      set: { selectionBox.value = $0 }
    )
    let renderer = DefaultRenderer()
    let pointerRegistry = LocalPointerHandlerRegistry()
    let tabsIdentity = testIdentity("Tabs")
    var context = ResolveContext(identity: testIdentity("Root"))
    context.localPointerHandlerRegistry = pointerRegistry

    _ = renderer.render(
      overflowParityTabView(selection: selection)
        .tabViewStyle(OverflowConsumerTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 30, height: 8)
    )

    let triggerRouteID = tabOverflowTriggerRouteID(for: tabsIdentity)
    #expect(pointerRegistry.hasHandler(pairingWith: triggerRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: triggerRouteID,
        event: primaryPointerDownEvent()
      )
    )

    let expanded = renderer.render(
      overflowParityTabView(selection: selection)
        .tabViewStyle(OverflowConsumerTabViewStyle())
        .id(tabsIdentity),
      context: context,
      proposal: .init(width: 30, height: 8)
    )
    .rasterSurface.lines
    .prefix(5)
    .map(trimTrailingSpaces)

    #expect(
      Array(expanded)
        == [
          "One More",
          "> Two",
          "> Three",
          "One content",
          "",
        ]
    )

    let overflowItemRouteID = tabOverflowItemRouteID(for: tabsIdentity, index: 2)
    #expect(pointerRegistry.hasHandler(pairingWith: overflowItemRouteID))
    #expect(
      pointerRegistry.dispatch(
        routeID: overflowItemRouteID,
        event: primaryPointerDownEvent()
      )
    )
    #expect(selectionBox.value == "three")
  }
}

@MainActor
private func parityTabView(
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

@MainActor
private func overflowParityTabView(
  selection: Binding<String>
) -> some View {
  TabView(selection: selection) {
    Tab("One", value: "one") {
      Text("One content")
    }

    Tab("Two", value: "two") {
      Text("Two content")
    }

    Tab("Three", value: "three") {
      Text("Three content")
    }
  }
}

private struct ContentFirstConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "ContentFirstConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.content
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          let item = configuration.items[index]
          item.route {
            Text(item.isSelected ? "[\(item.label.displayText)]" : item.label.displayText)
          }
        }
      }
    }
  }
}

private struct OverflowConsumerTabViewStyle: TabViewStyle {
  var snapshotLabel: String {
    "OverflowConsumerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    let overflowIndices = Array(configuration.options.indices.dropFirst())
    let selectedOverflowIndex =
      configuration.selectedIndex.flatMap { overflowIndices.contains($0) ? $0 : nil }
    let focusedOverflowIndex =
      configuration.focusedIndex.flatMap { overflowIndices.contains($0) ? $0 : nil }
    return .init(
      stripHeight: 1,
      visibleOptionIndices: [0],
      overflowMenu: .init(
        triggerLeadingWidth: 4,
        overflowIndices: overflowIndices,
        isExpanded: configuration.isOverflowMenuExpanded,
        selectedOverflowIndex: selectedOverflowIndex,
        focusedOverflowIndex: focusedOverflowIndex,
        triggerLabel: "More"
      )
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            Text(item.label.displayText)
          }
        }

        if let trigger = configuration.overflowTrigger {
          trigger.route {
            Text(trigger.label)
          }
        }
      }

      if configuration.overflowTrigger?.isExpanded == true {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(configuration.overflowItems.indices), id: \.self) { index in
            let item = configuration.overflowItems[index]
            item.overflowRoute {
              Text("> \(item.label.displayText)")
            }
          }
        }
      }

      configuration.content
    }
  }
}

private func trimTrailingSpaces(
  _ line: String
) -> String {
  String(line.reversed().drop(while: { $0 == " " }).reversed())
}

private func tabItemRouteID(
  for tabsIdentity: Identity,
  index: Int
) -> RouteID {
  primaryRouteID(
    for: tabsIdentity.child(.indexed("TabItem", index: index))
  )
}

private func tabOverflowTriggerRouteID(
  for tabsIdentity: Identity
) -> RouteID {
  primaryRouteID(
    for: tabsIdentity.child(.named("TabOverflowTrigger"))
  )
}

private func tabOverflowItemRouteID(
  for tabsIdentity: Identity,
  index: Int
) -> RouteID {
  primaryRouteID(
    for: tabsIdentity.child(.indexed("TabOverflowItem", index: index))
  )
}

private func primaryPointerDownEvent() -> LocalPointerEvent {
  .init(
    kind: .down(.primary),
    location: .zero,
    targetRect: .zero
  )
}
