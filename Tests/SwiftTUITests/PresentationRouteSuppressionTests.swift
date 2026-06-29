import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct PresentationRouteSuppressionTests {
  @Test(
    "Modal presentations suppress background focus and pointer routes",
    arguments: RouteSuppressingPresentationKind.allCases
  )
  func modalPresentationsSuppressBackgroundRoutes(
    kind: RouteSuppressingPresentationKind
  ) {
    let artifacts = DefaultRenderer().render(
      routeSuppressionFixture(kind: kind),
      context: .init(identity: testIdentity("PresentationRouteSuppressionRoot")),
      proposal: .init(width: 64, height: 14)
    )

    let focusIdentities = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity))
    let interactionIdentities = Set(
      artifacts.semanticSnapshot.interactionRegions.map(\.identity)
    )
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains(kind.markerText))
    if let modalActionID = kind.modalActionID {
      #expect(focusIdentities.contains(modalActionID))
    } else {
      #expect(
        focusIdentities.contains { $0 != PresentationRouteSuppressionIDs.baseAction }
      )
      #expect(
        interactionIdentities.contains { $0 != PresentationRouteSuppressionIDs.baseAction }
      )
    }
    #expect(!focusIdentities.contains(PresentationRouteSuppressionIDs.baseAction))
    #expect(!interactionIdentities.contains(PresentationRouteSuppressionIDs.baseAction))
  }

  @Test("Read-only popover tips keep background focus and pointer routes")
  func readOnlyPopoverTipsKeepBackgroundRoutes() {
    let artifacts = DefaultRenderer().render(
      readOnlyTipRouteSuppressionFixture(),
      context: .init(identity: testIdentity("ReadOnlyTipRouteSuppressionRoot")),
      proposal: .init(width: 64, height: 14)
    )

    let focusIdentities = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity))
    let interactionIdentities = Set(
      artifacts.semanticSnapshot.interactionRegions.map(\.identity)
    )

    #expect(focusIdentities.contains(PresentationRouteSuppressionIDs.baseAction))
    #expect(interactionIdentities.contains(PresentationRouteSuppressionIDs.baseAction))
  }
}

enum RouteSuppressingPresentationKind: CaseIterable, CustomStringConvertible, Sendable {
  case sheet
  case alert
  case confirmationDialog
  case paletteSheet
  case booleanPopover
  case itemPopover
  case actionTip

  var description: String {
    switch self {
    case .sheet:
      "sheet"
    case .alert:
      "alert"
    case .confirmationDialog:
      "confirmationDialog"
    case .paletteSheet:
      "paletteSheet"
    case .booleanPopover:
      "booleanPopover"
    case .itemPopover:
      "itemPopover"
    case .actionTip:
      "actionTip"
    }
  }

  var markerText: String {
    switch self {
    case .sheet:
      "Close Sheet"
    case .alert:
      "OK"
    case .confirmationDialog:
      "Reset"
    case .paletteSheet:
      "Close Palette"
    case .booleanPopover:
      "Close Popover"
    case .itemPopover:
      "Close Tool"
    case .actionTip:
      "Action tip"
    }
  }

  var modalActionID: Identity? {
    switch self {
    case .sheet:
      PresentationRouteSuppressionIDs.sheetAction
    case .alert:
      PresentationRouteSuppressionIDs.alertAction
    case .confirmationDialog:
      PresentationRouteSuppressionIDs.confirmationAction
    case .paletteSheet:
      PresentationRouteSuppressionIDs.paletteAction
    case .booleanPopover:
      PresentationRouteSuppressionIDs.popoverAction
    case .itemPopover:
      PresentationRouteSuppressionIDs.itemPopoverAction
    case .actionTip:
      nil
    }
  }
}

private enum PresentationRouteSuppressionIDs {
  static let baseAction = testIdentity("PresentationRouteSuppression", "BaseAction")
  static let sheetAction = testIdentity("PresentationRouteSuppression", "SheetAction")
  static let alertAction = testIdentity("PresentationRouteSuppression", "AlertAction")
  static let confirmationAction = testIdentity(
    "PresentationRouteSuppression",
    "ConfirmationAction"
  )
  static let paletteAction = testIdentity("PresentationRouteSuppression", "PaletteAction")
  static let popoverAction = testIdentity("PresentationRouteSuppression", "PopoverAction")
  static let itemPopoverAction = testIdentity(
    "PresentationRouteSuppression",
    "ItemPopoverAction"
  )
}

@MainActor
@ViewBuilder
private func routeSuppressionFixture(kind: RouteSuppressingPresentationKind) -> some View {
  let base = routeSuppressionBase

  switch kind {
  case .sheet:
    base.sheet("Routing Sheet", isPresented: .constant(true)) {
      Button("Close Sheet") {}
        .id(PresentationRouteSuppressionIDs.sheetAction)
    }
  case .alert:
    base.alert(
      "Routing Alert",
      isPresented: .constant(true),
      actions: {
        Button("OK") {}
          .id(PresentationRouteSuppressionIDs.alertAction)
      },
      message: {
        Text("Alert body")
      }
    )
  case .confirmationDialog:
    base.confirmationDialog(
      "Routing Confirm",
      isPresented: .constant(true),
      actions: {
        Button("Reset") {}
          .id(PresentationRouteSuppressionIDs.confirmationAction)
      },
      message: {
        Text("Confirm body")
      }
    )
  case .paletteSheet:
    base
      .panel(id: "presentation-route-suppression")
      .paletteCommand(name: "Palette Action") {}
      .paletteSheet("Routing Palette", isPresented: .constant(true)) { _ in
        Button("Close Palette") {}
          .id(PresentationRouteSuppressionIDs.paletteAction)
      }
  case .booleanPopover:
    routeSuppressionBaseWithAnchor
      .popover(isPresented: .constant(true), arrowEdge: .trailing) {
        Button("Close Popover") {}
          .id(PresentationRouteSuppressionIDs.popoverAction)
      }
  case .itemPopover:
    routeSuppressionBaseWithAnchor
      .popover(
        item: .constant(Optional(PresentationRouteSuppressionItem(id: "tool"))),
        arrowEdge: .trailing
      ) { _ in
        Button("Close Tool") {}
          .id(PresentationRouteSuppressionIDs.itemPopoverAction)
      }
  case .actionTip:
    actionTipRouteSuppressionFixture()
  }
}

@MainActor
private var routeSuppressionBase: some View {
  VStack(alignment: .leading, spacing: 1) {
    Text("Background")
    Spacer()
    Button("Base Action") {}
      .id(PresentationRouteSuppressionIDs.baseAction)
  }
  .frame(width: 64, height: 14, alignment: .topLeading)
}

@MainActor
private var routeSuppressionBaseWithAnchor: some View {
  VStack(alignment: .leading, spacing: 1) {
    Text("Popover Anchor")
    Spacer()
    Button("Base Action") {}
      .id(PresentationRouteSuppressionIDs.baseAction)
  }
  .frame(width: 64, height: 14, alignment: .topLeading)
}

@MainActor
private func actionTipRouteSuppressionFixture() -> some View {
  let tip = PresentationRouteSuppressionTip(
    id: "action-tip",
    title: "Action tip",
    message: "Blocks background routes.",
    actions: [
      PopoverTipAction(id: "got-it", title: "Got it")
    ]
  )

  return VStack(alignment: .leading, spacing: 1) {
    Text("Tip Anchor")
      .popoverTip(tip, arrowEdge: .trailing) { _ in }
    Spacer()
    Button("Base Action") {}
      .id(PresentationRouteSuppressionIDs.baseAction)
  }
  .frame(width: 64, height: 14, alignment: .topLeading)
}

@MainActor
private func readOnlyTipRouteSuppressionFixture() -> some View {
  let tip = PresentationRouteSuppressionTip(
    id: "read-only-tip",
    title: "Read-only tip",
    message: "Leaves background routes available."
  )

  return VStack(alignment: .leading, spacing: 1) {
    Text("Tip Anchor")
      .popoverTip(tip, arrowEdge: .trailing)
    Spacer()
    Button("Base Action") {}
      .id(PresentationRouteSuppressionIDs.baseAction)
  }
  .frame(width: 64, height: 14, alignment: .topLeading)
}

private struct PresentationRouteSuppressionItem: Identifiable, Sendable {
  let id: String
}

private struct PresentationRouteSuppressionTip: PopoverTip {
  let id: String
  let titleText: String
  let messageText: String?
  let actions: [PopoverTipAction]

  init(
    id: String,
    title: String,
    message: String? = nil,
    actions: [PopoverTipAction] = []
  ) {
    self.id = id
    titleText = title
    messageText = message
    self.actions = actions
  }

  var title: Text {
    Text(titleText)
  }

  var message: Text? {
    messageText.map { Text($0) }
  }
}
