import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct PresentationSurfaceTests {
  @Test("command palette backdrop spans the full terminal canvas")
  func commandPaletteBackdropSpansTheFullTerminalCanvas() {
    let proposal = Size(width: 40, height: 10)
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .command(
          id: "open-file",
          title: "Open File"
        )
        .frame(width: 12, height: 1, alignment: .leading)
        .commandPalette(isPresented: .constant(true)),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: proposal.width, height: proposal.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let expectedBounds = Rect(origin: .zero, size: proposal)

    #expect(surface.contains("Command Palette"))
    #expect(hasFillCommand(in: artifacts.drawTree, bounds: expectedBounds))
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

  @Test("command palette stays above the other built-in presentation families")
  func commandPaletteUsesTopmostFamilyLayer() throws {
    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .command(id: "open-file", title: "Open File")
        .toast(
          "Saved successfully",
          isPresented: .constant(true),
          style: .success,
          duration: nil
        )
        .sheet("Inspector", isPresented: .constant(true)) {
          Text("Sheet body")
        }
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
        .frame(width: 48, height: 14, alignment: .topLeading)
        .commandPalette(isPresented: .constant(true)),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 48, height: 14)
    )

    let kinds = viewKindNames(in: artifacts.resolvedTree)
    let toastIndex = try #require(kinds.firstIndex(of: "ToastPresentation"))
    let sheetIndex = try #require(kinds.firstIndex(of: "SheetPresentation"))
    let alertIndex = try #require(kinds.firstIndex(of: "AlertPresentation"))
    let paletteIndex = try #require(kinds.firstIndex(of: "CommandPalettePresentation"))

    #expect(toastIndex < sheetIndex)
    #expect(sheetIndex < alertIndex)
    #expect(alertIndex < paletteIndex)
  }

  @Test("sheet shell uses a joined inner-edge unicode border over colored background content")
  func sheetShellUsesAJoinedInnerEdgeUnicodeBorderOverColoredBackgroundContent() throws {
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

    let titleLocation = try #require(
      findSubstring("Inspector", in: artifacts.rasterSurface.lines)
    )
    let bodyLocation = try #require(
      findSubstring("Sheet body", in: artifacts.rasterSurface.lines)
    )

    let topBorderCell = artifacts.rasterSurface.cells[titleLocation.y - 1][titleLocation.x]
    let topLeadingCorner = try #require(
      findCharacter("▟", in: artifacts.rasterSurface.lines)
    )
    let rightBorderLocation = try #require(
      findCharacter("▌", in: artifacts.rasterSurface.lines)
    )
    let rightBorderCell = artifacts.rasterSurface.cells[rightBorderLocation.y][
      rightBorderLocation.x]
    let bottomTrailingCorner = try #require(
      findCharacter("▛", in: artifacts.rasterSurface.lines)
    )
    let borderBackground = try #require(
      topBorderCell.style?.backgroundColor
    )
    let contentBackground = try #require(
      artifacts.rasterSurface.cells[bodyLocation.y][bodyLocation.x].style?.backgroundColor
    )
    let underlyingBackground = try #require(
      backgroundOnly.rasterSurface.cells[titleLocation.y - 1][titleLocation.x].style?
        .backgroundColor
    )

    #expect(topBorderCell.character == "▄")
    #expect(artifacts.rasterSurface.cells[topLeadingCorner.y][topLeadingCorner.x].character == "▟")
    #expect(rightBorderCell.character == "▌")
    #expect(
      artifacts.rasterSurface.cells[bottomTrailingCorner.y][bottomTrailingCorner.x].character
        == "▛"
    )
    #expect(borderBackground == underlyingBackground)
    #expect(borderBackground != contentBackground)
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

private struct RenderTimePresentationMutationProbe: View, ResolvableView {
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
        actionPayloads: deferredDeclaredBuilderChildren(
          from: Button("Dismiss") {}
        ),
        messagePayloads: deferredDeclaredBuilderChildren(
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
  bounds: Rect
) -> Bool {
  if node.commands.contains(where: { hasFillCommand($0, bounds: bounds) }) {
    return true
  }

  return node.children.contains(where: { hasFillCommand(in: $0, bounds: bounds) })
}

private func hasFillCommand(
  _ command: DrawCommand,
  bounds: Rect
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
