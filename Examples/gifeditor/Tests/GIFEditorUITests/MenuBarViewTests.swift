import GIFEditorCore
import SwiftTUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor menu bar")
struct MenuBarViewTests {
  @Test("open dropdown paints above editor content rows")
  func openDropdownPaintsAboveEditorContentRows() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 4, height: 4))
    )
    let openMenu = Binding<MenuBarMenu?>.constant(.file)
    let rendered = render(
      ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 0) {
          MenuBarView(
            openMenu: openMenu,
            model: model,
            isHelpPresented: .constant(false),
            showsToolDock: .constant(true),
            showsRightPanel: .constant(true),
            showsTimeline: .constant(true),
            pixelGridMode: .constant(.verticalHalfBlock),
            isResizeSheetPresented: .constant(false),
            refresh: {}
          )
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
          Text("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
        }

        MenuBarDropdownView(
          menu: .file,
          openMenu: openMenu,
          model: model,
          isHelpPresented: .constant(false),
          showsToolDock: .constant(true),
          showsRightPanel: .constant(true),
          showsTimeline: .constant(true),
          pixelGridMode: .constant(.verticalHalfBlock),
          isResizeSheetPresented: .constant(false),
          refresh: {}
        )
        .offset(x: MenuBarMenu.file.dropdownOffset + 1, y: 1)
      },
      width: 40,
      height: 8
    )

    let lines = rendered.rasterSurface.lines
    #expect(lines[1].contains("Save"))
    #expect(lines[2].contains("Save As"))
    #expect(lines[4].contains("Resize Canvas"))
  }
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["gifeditor.menu.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
