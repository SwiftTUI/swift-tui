import Algorithms
import Observation
import TerminalUI
import TerminalUICLI

@main
struct GalleryDemoApp: App {

  var body: some Scene {
    WindowGroup {
      ColorGallery()
    }
  }
}

struct ColorGallery: View {

  @State var fontNumber: Int = EmbeddedFigletFont.allCases.firstIndex(of: .dosRebel)!
  @State var font: EmbeddedFigletFont = .dosRebel
  @State var color: Color = .red
  @State var showFigure: Bool = true
  var fontCount: Int { EmbeddedFigletFont.allCases.count }

  var body: some View {
    ScrollView {
      EnvironmentReader(\.terminalAppearance) { appearance in
        VStack(alignment: .leading, spacing: 1) {
          VStack(alignment: .leading) {
            HStack {
              Stepper("font", value: $fontNumber)
              Text(font.rawValue)
              Button("!") {
                withAnimation(.easeInOut) {
                  withAnimation(.easeInOut(duration: .seconds(2.0))) {
                    showFigure.toggle()
                  }
                }
              }
              Button("↴") {
                withAnimation(.easeInOut(duration: .seconds(2.0))) {
                  color = color.rotatedHue(by: 40.0)
                }
              }
            }
            .task(id: fontNumber) {
              if fontNumber < 0 {
                fontNumber = fontCount - 1
              } else if fontNumber > fontCount {
                fontNumber = 0
              }
              font = EmbeddedFigletFont.allCases[fontNumber]
            }
            Rectangle().fill(Color.clear).frame(height: 15).overlay(alignment: .leading) {
              if showFigure {
                TextFigure("Gallery", font: font)
                  .foregroundStyle(color)
                  .transition(.opacity)
              }
            }
          }
          terminalPaletteSection(palette: appearance.palette)
          namedColorsSection
          semanticRolesSection
        }
      }
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
    palette: TerminalPalette
  ) -> some View {
    GroupBox("Terminal palette (host)") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(0...15).chunks(ofCount: 3), id: \.self) { row in
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
