import TerminalUI

struct GalleryColorGallery: View {
  var body: some View {
    ScrollView {
      EnvironmentReader(\.terminalAppearance) { appearance in
        VStack(alignment: .leading, spacing: 1) {
          terminalPaletteSection(palette: appearance.palette)
          HStack(alignment: .top, spacing: 1) {
            namedColorsSection
            semanticRolesSection
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var namedColorsSection: some View {
    GroupBox("Named colors") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(namedColorRows.enumerated()), id: \.offset) { _, row in
          HStack(alignment: .center, spacing: 1) {
            ForEach(row) { namedColor in
              GalleryColorTile(
                title: namedColor.name,
                style: AnyShapeStyle(namedColor.color)
              )
            }
          }
        }
      }
    }
  }

  private var semanticRolesSection: some View {
    GroupBox("Semantic roles") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(semanticRoleRows.enumerated()), id: \.offset) { _, row in
          HStack(alignment: .center, spacing: 1) {
            ForEach(row) { role in
              GalleryColorTile(
                title: role.label,
                style: role.style
              )
            }
          }
        }
      }
    }
  }

  private func terminalPaletteSection(
    palette: [Int: Color]
  ) -> some View {
    GroupBox("Terminal palette (host)") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach([Array(0...4), Array(5...9), Array(10...14), Array(15...15)], id: \.self) { row in
          HStack(alignment: .center, spacing: 1) {
            ForEach(row, id: \.self) { index in
              GalleryColorTile(
                title: "\(index)",
                style: AnyShapeStyle(
                  palette[index] ?? TerminalAppearance.defaultPalette[index] ?? .black
                )
              )
            }
          }
        }
      }
    }
  }

  private var namedColorRows: [[GalleryNamedColor]] {
    [
      [
        .init(name: "black", color: .black),
        .init(name: "white", color: .white),
        .init(name: "red", color: .red),
      ],
      [
        .init(name: "green", color: .green),
        .init(name: "yellow", color: .yellow),
        .init(name: "blue", color: .blue),
      ],
      [
        .init(name: "magenta", color: .magenta),
        .init(name: "cyan", color: .cyan),
        .init(name: "gray", color: .gray),
      ],
    ]
  }

  private var semanticRoleRows: [[GallerySemanticRole]] {
    [
      [
        .init(label: "tint", style: .semantic(.tint)),
        .init(label: "success", style: .semantic(.success)),
        .init(label: "warning", style: .semantic(.warning)),
      ],
      [
        .init(label: "danger", style: .semantic(.danger)),
        .init(label: "info", style: .semantic(.info)),
        .init(label: "muted", style: .semantic(.muted)),
      ],
    ]
  }
}

private struct GalleryNamedColor: Identifiable {
  let name: String
  let color: Color

  var id: String {
    name
  }
}

private struct GallerySemanticRole: Identifiable {
  let label: String
  let style: AnyShapeStyle

  var id: String {
    label
  }
}

private struct GalleryColorTile: View {
  let title: String
  let style: AnyShapeStyle

  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      GalleryColorSwatch(style: style)
        .frame(width: 8, height: 4, alignment: .leading)
      Text(title)
        .frame(width: 8, height: 1, alignment: .leading)
        .background {
          TileBackground.init(width: 8, height: 1, tiles: ["_"], style: .separator, opacity: 0.3)
        }
    }
  }
}

private struct GalleryColorSwatch: View {
  let style: AnyShapeStyle

  init(
    style: AnyShapeStyle,
  ) {
    self.style = style
  }

  var body: some View {
    Rectangle()
      .fill(style)
      .padding(1)
      .overlay {
        RoundedRectangle(cornerRadius: 1)
          .strokeBorder(.terminalBorder(.neutral))
      }
  }
}
