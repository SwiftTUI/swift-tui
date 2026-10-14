import SwiftTUIRuntime
import Testing

@MainActor
struct SpacerMinimumAllocationTests {
  @Test("a reconciled input Spacer does not prevent a long list from fitting", arguments: [0, 3])
  func inputAndListFit(minimum: Int) throws {
    let rendered = DefaultRenderer().render(
      HStack(spacing: 2) {
        VStack(alignment: .leading, spacing: 0) {
          TextField("Filter reviews…", text: Binding<String>.constant(""))
            .textFieldStyle(SearchFieldStyle(minimum: minimum))
          List((0..<12).map { Row(id: $0) }, selection: Binding<Int?>.constant(0)) { _ in
            HStack(spacing: 1) {
              Text("›")
              Text("#214 ● Keep scroll position across theme changes")
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .listStyle(BareListStyle())
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          Text("12 of 12 items")
        }
        .padding(.horizontal, 1)
        .border(.blue, placement: .outset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .frame(width: 36, height: 18, alignment: .topLeading),
      proposal: ProposedViewSize(width: 36, height: 18)
    )

    #expect(rendered.rasterSurface.size == CellSize(width: 36, height: 18))
    let inputBorder = Array(try #require(rendered.rasterSurface.lines.dropFirst().first))
    #expect(inputBorder.firstIndex(of: "┌") == 2)
    #expect(inputBorder.lastIndex(of: "┐") == 33)
    #expect(rendered.rasterSurface.lines.contains { $0.contains("Filter reviews…") })
    #expect(rendered.rasterSurface.lines.contains { $0.contains("#214 ● Keep scroll positi…") })
    #expect(rendered.rasterSurface.lines.contains { $0.contains("12 of 12 items") })
  }

  @Test("a declared Spacer minimum survives an impossible deficit")
  func declaredMinimumIsPreserved() {
    let rendered = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L").fixedSize()
        Spacer(minLength: 3)
        Text("R").fixedSize()
      },
      proposal: ProposedViewSize(width: 4, height: 1)
    )

    #expect(rendered.rasterSurface.lines == ["L   R"])
    #expect(rendered.rasterSurface.size == CellSize(width: 5, height: 1))
  }

  @Test("Spacer minimum hints survive an impossible deficit")
  func minimumHintIsPreserved() {
    let rendered = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: 3).minimumIntrinsicSize(width: 12)
        Text("R")
      },
      proposal: ProposedViewSize(width: 8, height: 1)
    )

    #expect(rendered.rasterSurface.lines == ["L            R"])
    #expect(rendered.rasterSurface.size == CellSize(width: 14, height: 1))
  }

  @Test("a fixed-size wrapped Spacer preserves its authored extent")
  func fixedSizePreservesWrappedMinimum() {
    let rendered = DefaultRenderer().render(
      HStack(spacing: 0) {
        Spacer(minLength: 3).padding(.horizontal, 2).fixedSize()
        Text("end")
      },
      proposal: ProposedViewSize(width: 20, height: 1)
    )

    #expect(rendered.rasterSurface.lines == ["       end"])
    #expect(rendered.rasterSurface.size == CellSize(width: 20, height: 1))
  }

  private struct Row: Identifiable, Sendable {
    let id: Int
  }

  private struct BareListStyle: ListStyle {
    func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
      ListStylePresentation(
        contentInsets: EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1),
        showsRowSeparators: false,
        showsSectionSeparators: false
      )
    }
  }

  private struct SearchFieldStyle: TextFieldStyle {
    let minimum: Int

    func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
      HStack(spacing: 0) {
        configuration.fieldContent
        Spacer(minLength: minimum)
      }
      .padding(.horizontal, 1)
      .border(.blue, placement: .outset)
    }
  }
}
