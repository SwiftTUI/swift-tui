import TerminalUI

struct GalleryColorGallery: View {
  var body: some View {
    EnvironmentReader(\.terminalAppearance) { appearance in
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .top, spacing: 1) {
          namedColorsSection
            .frame(maxWidth: .infinity, alignment: .topLeading)
          semanticRolesSection
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        terminalPaletteSection(palette: appearance.palette)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
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
              .frame(maxWidth: .infinity, alignment: .leading)
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
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }
  }

  private func terminalPaletteSection(
    palette: [Int: Color]
  ) -> some View {
    GroupBox("Terminal palette") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach([Array(0...7), Array(8...15)], id: \.self) { row in
          HStack(alignment: .center, spacing: 1) {
            ForEach(row, id: \.self) { index in
              GalleryPaletteChip(
                index: index,
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
    HStack(alignment: .center, spacing: 1) {
      GalleryColorSwatch(style: style, width: 4)
      Text(title)
    }
  }
}

private struct GalleryPaletteChip: View {
  let index: Int
  let style: AnyShapeStyle

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      GalleryColorSwatch(style: style, width: 3)
      Text("\(index)")
        .foregroundStyle(.separator)
    }
  }
}

private struct GalleryColorSwatch: View {
  let style: AnyShapeStyle
  let width: Int

  init(
    style: AnyShapeStyle,
    width: Int = 8
  ) {
    self.style = style
    self.width = width
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(style)
      .overlay {
        RoundedRectangle(cornerRadius: 1)
          .strokeBorder(.terminalBorder(.neutral))
      }
      .frame(width: width, height: 1, alignment: .leading)
  }
}
