import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PresentationSurfaceTests {
  @Test("dropdown presentations render content without title or close chrome")
  func dropdownPresentationsRenderContentWithoutTitleOrCloseChrome() throws {
    let artifacts = DefaultRenderer().render(
      Panel(id: "PaletteHost") {
        Text("Workspace")
      }
      .paletteSheet("Command palette", isPresented: .constant(true)) { _ in
        Text("palette sheet")
      },
      context: .init(identity: testIdentity("DropdownPresentationChromeRoot")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("palette sheet"))
    #expect(!surface.contains("Command palette"))
    #expect(!surface.contains("×"))
  }

  @Test("presentation overlays carry explicit surface composition metadata")
  func presentationOverlaysCarrySurfaceCompositionMetadata() throws {
    let contentRootIdentity = testIdentity("SurfaceCompositionRoot")
    let portalStructuralPath = StructuralPath(identity: contentRootIdentity)
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .sheet("Command palette", isPresented: .constant(true)) {
          Text("Filter commands")
        },
      context: .init(identity: contentRootIdentity),
      proposal: .init(width: 40, height: 10)
    )

    let entries = SurfaceTopologySignature(placedRoot: artifacts.placedTree).entries
    #expect(
      entries.contains {
        $0.role == .stackingContext
          && $0.stableKey == "overlay-stack:\(portalStructuralPath)"
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayHost
          && $0.stableKey == "overlay-host:\(portalStructuralPath)/PortalHost/overlays"
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayEntry
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
    #expect(
      entries.contains {
        $0.role == .detachedOverlayEntry
          && $0.stableKey?.isEmpty == false
      }
    )

    let portalRootIdentity = testIdentity("SurfaceCompositionPortalRoot")
    let portalRoot = composePresentationPortalTree(
      baseNode: ResolvedNode(
        identity: testIdentity("SurfaceCompositionContent"),
        kind: .view("Content")
      ),
      portalState: PresentationPortalState().makeDraft(),
      in: .init(identity: portalRootIdentity)
    )
    let portalRootTopology = SurfaceTopologySignature(
      placedRoot: PlacedNode(
        identity: portalRoot.identity,
        kind: portalRoot.kind,
        bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
        surfaceComposition: portalRoot.surfaceComposition
      )
    ).entries

    #expect(
      portalRootTopology.contains {
        $0.role == .detachedOverlayRoot
          && $0.stableKey == portalRootIdentity.path
          && $0.invalidationScope == .fullSurfaceDiff
      }
    )
  }

  @Test("compositing groups carry explicit surface composition metadata")
  func compositingGroupsCarrySurfaceCompositionMetadata() {
    let rootIdentity = testIdentity("SurfaceCompositionCompositingGroupRoot")
    let artifacts = DefaultRenderer().render(
      Text("Layer")
        .compositingGroup(),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 4)
    )

    let entries = SurfaceTopologySignature(placedRoot: artifacts.placedTree).entries
    #expect(
      entries.contains {
        $0.role == .isolatedCompositingGroup
          && $0.stableKey == rootIdentity.path
          && $0.invalidationScope == .compositedBounds
      }
    )
  }

  @Test("alert renders an overlay surface and suppresses background focus")
  func alertRendersAndSuppressesBackgroundFocus() throws {
    let artifacts = DefaultRenderer().render(
      Button("Background") {}
        .id(testIdentity("BackgroundButton"))
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
            Button("Cancel") {}
          },
          message: {
            Text("This cannot be undone.")
          }
        ),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusedPaths = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity.path))

    #expect(surface.contains("Delete project"))
    #expect(surface.contains("This cannot be undone."))
    #expect(surface.contains("Delete"))
    #expect(!focusedPaths.contains(testIdentity("BackgroundButton").path))
    #expect(focusedPaths.count >= 2)
  }

  @Test("confirmationDialog supplies a default cancel action")
  func confirmationDialogProvidesDefaultCancelAction() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .confirmationDialog(
          "Archive task",
          isPresented: .constant(true)
        ),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Archive task"))
    #expect(surface.contains("Cancel"))
  }

  @Test("confirmationDialog hoists above clipped ancestor content")
  func confirmationDialogHoistsAboveClippedAncestorContent() {
    let outsideIdentity = testIdentity("OutsideButton")
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Button("Outside") {}
          .id(outsideIdentity)

        HStack {
          Text("Attachment")
            .confirmationDialog(
              "Archive task",
              isPresented: .constant(true),
              actions: {
                Button("Archive") {}
              },
              message: {
                Text("Move the task out of the active list.")
              }
            )
        }
        .frame(width: 8, height: 1, alignment: .leading)
        .clipped()
      }
      .frame(width: 32, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 32, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusedPaths = Set(artifacts.semanticSnapshot.focusRegions.map(\.identity.path))

    #expect(surface.contains("Archive task"))
    #expect(surface.contains("Move the task out"))
    #expect(surface.contains("Archive"))
    #expect(!focusedPaths.contains(outsideIdentity.path))
  }

  @Test("alert keeps overflow-prone content inside a short terminal surface")
  func alertKeepsOverflowProneContentInsideShortSurface() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .alert(
          "Archive project",
          isPresented: .constant(true),
          actions: {
            Button("Archive") {}
            Button("Duplicate") {}
            Button("Export") {}
            Button("Cancel") {}
          },
          message: {
            VStack(alignment: .leading, spacing: 0) {
              Text("This workspace has several long notes.")
              Text("Scrolling should keep the overlay bounded.")
              Text("Nothing should spill past the viewport.")
            }
          }
        )
        .frame(width: 30, height: 6, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 30, height: 6)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Archive project"))
    #expect(surface.contains("This workspace has"))
    #expect(surface.contains("Archive"))
    #expect(surface.contains("█") || surface.contains("▼"))
  }

  @Test("toast and alert overlays share the first frame and use fixed family order")
  func toastAndAlertOverlaysUseFixedFamilyOrder() throws {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .toast(
          "Saved successfully",
          isPresented: .constant(true),
          style: .success,
          duration: nil
        )
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
          },
          message: {
            Text("This cannot be undone.")
          }
        )
        .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 10)
    )

    let kinds = viewKindNames(in: artifacts.resolvedTree)
    let toastIndex = try #require(kinds.firstIndex(of: "ToastPresentation"))
    let alertIndex = try #require(kinds.firstIndex(of: "AlertPresentation"))

    #expect(kinds.contains("ToastPresentation"))
    #expect(kinds.contains("AlertPresentation"))
    #expect(toastIndex < alertIndex)
  }

  @Test("sheet shell uses a single-line presentation chrome with a full-bleed surface background")
  func sheetShellUsesSingleLineChromeWithFullBleedBackground() throws {
    let proposal = ProposedSize(width: .finite(48), height: .finite(14))
    let rootIdentity = testIdentity("Root")

    let backgroundOnly = DefaultRenderer().render(
      Rectangle()
        .fill(.terminalAccent(.success))
        .frame(width: 48, height: 14, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let artifacts = DefaultRenderer().render(
      Rectangle()
        .fill(.terminalAccent(.success))
        .sheet("Inspector", isPresented: .constant(true)) {
          Text("Sheet body")
        }
        .frame(width: 48, height: 14, alignment: .topLeading),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    let cells = artifacts.rasterSurface.cells

    // The chrome is a square single-line box (no half-block glyphs). Anchor on
    // the two opposite corners, then read the edges off the derived bounds.
    let topLeadingCorner = try #require(
      findCharacter("┌", in: artifacts.rasterSurface.lines)
    )
    let bottomTrailingCorner = try #require(
      findCharacter("┘", in: artifacts.rasterSurface.lines)
    )
    let minX = topLeadingCorner.x
    let maxX = bottomTrailingCorner.x
    let minY = topLeadingCorner.y
    let maxY = bottomTrailingCorner.y

    #expect(cells[minY][maxX].character == "┐")
    #expect(cells[maxY][minX].character == "└")
    #expect(cells[minY][minX + 1].character == "─")  // top edge
    #expect(cells[minY + 2][minX].character == "│")  // left edge (a body row)
    #expect(cells[minY + 2][maxX].character == "│")  // right edge (a body row)

    // None of the legacy half-block chrome glyphs survive.
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(!surface.contains("▄"))
    #expect(!surface.contains("▌"))
    #expect(!surface.contains("▗"))
    #expect(!surface.contains("▘"))

    // Full bleed: every border cell carries the same surface fill as the
    // interior, and that fill is distinct from the backdrop behind the sheet.
    let interiorBackground = try #require(
      cells[minY + 2][minX + 2].style?.backgroundColor
    )
    let topBorderBackground = try #require(
      cells[minY][minX + 1].style?.backgroundColor
    )
    let leftBorderBackground = try #require(
      cells[minY + 2][minX].style?.backgroundColor
    )
    let rightBorderBackground = try #require(
      cells[minY + 2][maxX].style?.backgroundColor
    )
    let underlyingBackground = try #require(
      backgroundOnly.rasterSurface.cells[minY][minX + 1].style?.backgroundColor
    )

    #expect(topBorderBackground == interiorBackground)
    #expect(leftBorderBackground == interiorBackground)
    #expect(rightBorderBackground == interiorBackground)
    #expect(interiorBackground != underlyingBackground)
  }

  @Test("declarative reconciliation prunes stale overlays when the source subtree disappears")
  func declarativeReconciliationPrunesStaleSourceOverlays() {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("Root")

    let initial = renderer.render(
      ConditionalAlertPresentationView(showAlertSource: true),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 8)
    )
    let updated = renderer.render(
      ConditionalAlertPresentationView(showAlertSource: false),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 40, height: 8)
    )

    let initialSurface = initial.rasterSurface.lines.joined(separator: "\n")
    let updatedSurface = updated.rasterSurface.lines.joined(separator: "\n")

    #expect(initialSurface.contains("Delete project"))
    #expect(!updatedSurface.contains("Delete project"))
  }

  @Test("render-time coordinator mutation is rejected and does not surface the presentation")
  func renderTimeCoordinatorMutationIsRejected() {
    var recordedMessage: String?
    PresentationMutationGuard.onInvalidMutation = { message in
      recordedMessage = message
    }
    defer {
      PresentationMutationGuard.onInvalidMutation = nil
    }

    let artifacts = DefaultRenderer().render(
      RenderTimePresentationMutationProbe(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(
      recordedMessage
        == "AlertPresentationCoordinator.present(_:) must not be called during view update.")
    #expect(surface.contains("Workspace"))
    #expect(!surface.contains("Illegal mutation"))
  }

  @Test("toast renders in the bottom-left corner by default")
  func toastRendersInBottomLeftCorner() {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .toast(
          "Action performed",
          isPresented: .constant(true),
          style: .success
        )
        .frame(width: 24, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 24, height: 8)
    )

    let lines = artifacts.rasterSurface.lines
    let messageIndex = try! #require(
      lines.firstIndex(where: { $0.contains("Action performed") })
    )
    let messageLine = lines[messageIndex]

    #expect(messageIndex >= 3)
    #expect(messageLine.first != " ")
  }
}

private struct ConditionalAlertPresentationView: View {
  var showAlertSource: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if showAlertSource {
        Text("Attachment")
          .alert(
            "Delete project",
            isPresented: .constant(true),
            actions: {
              Button("Delete") {}
            },
            message: {
              Text("This cannot be undone.")
            }
          )
      } else {
        Text("Attachment removed")
      }
    }
    .frame(width: 40, height: 8, alignment: .topLeading)
  }
}

private struct RenderTimePresentationMutationProbe: PrimitiveView, ResolvableView {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let spec = alertPromptPresentationSpec()
    let sourceIdentity = context.identity

    context.environmentValues.alertPresentationCoordinator.present(
      PromptPresentationItem(
        id: presentationAttachmentID(
          for: sourceIdentity,
          token: spec.token
        ),
        title: "Illegal mutation",
        descriptor: spec.descriptor,
        actionPayloads: portalDeclaredBuilderChildren(
          from: Button("Dismiss") {}
        ),
        messagePayloads: portalDeclaredBuilderChildren(
          from: Text("Should never render.")
        ),
        contentPayloads: [],
        dismiss: {}
      )
    )

    return Text("Workspace").resolveElements(in: context)
  }
}

private func hasFillCommand(
  in node: DrawNode,
  bounds: CellRect
) -> Bool {
  if node.commands.contains(where: { hasFillCommand($0, bounds: bounds) }) {
    return true
  }

  return node.children.contains(where: { hasFillCommand(in: $0, bounds: bounds) })
}

private func hasFillCommand(
  _ command: DrawCommand,
  bounds: CellRect
) -> Bool {
  switch command {
  case .group(_, let children):
    return children.contains(where: { hasFillCommand($0, bounds: bounds) })
  case .fill(let commandBounds, _, _, _, _):
    return commandBounds == bounds
  case .clip(_, let child):
    return hasFillCommand(child, bounds: bounds)
  default:
    return false
  }
}

private func viewKindNames(
  in node: ResolvedNode
) -> [String] {
  var kinds: [String] = []
  collectViewKindNames(in: node, into: &kinds)
  return kinds
}

private func collectViewKindNames(
  in node: ResolvedNode,
  into kinds: inout [String]
) {
  if case .view(let name) = node.kind {
    kinds.append(name)
  }

  for child in node.children {
    collectViewKindNames(in: child, into: &kinds)
  }
}

private func findSubstring(
  _ substring: String,
  in lines: [String]
) -> (x: Int, y: Int)? {
  let needle = Array(substring)
  guard !needle.isEmpty else {
    return nil
  }

  for (y, line) in lines.enumerated() {
    let haystack = Array(line)
    guard haystack.count >= needle.count else {
      continue
    }
    let maxStart = haystack.count - needle.count
    for start in 0...maxStart {
      let end = start + needle.count
      if Array(haystack[start..<end]) == needle {
        return (x: start, y: y)
      }
    }
  }
  return nil
}

private func findCharacter(
  _ character: Character,
  in lines: [String]
) -> (x: Int, y: Int)? {
  for (y, line) in lines.enumerated() {
    for (x, candidate) in line.enumerated() where candidate == character {
      return (x: x, y: y)
    }
  }
  return nil
}
