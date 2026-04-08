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
