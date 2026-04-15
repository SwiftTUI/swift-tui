import TerminalUI

struct CounterTab: View {
  @State private var count: Int = 0
  @State private var step: Int = 1
  @State private var color: Color = .red

  func mathButton(_ label: String, _ num: Int, _ act: @escaping (Int, Int) -> Int) -> some View {
    Button(label) {
      withAnimation(.default) {
        count = act(count, num)
      }
    }.buttonStyle(.bordered)
  }

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      brandingHeader
      Divider()
      Spacer(minLength: 1)
      HStack(alignment: .bottom) {
        mathButton(" - ", step, -)
        TextFigure("\(count)", font: .miniwi)
          .frame(minWidth: 14, alignment: .center)
        mathButton(" + ", step, +)
      }
      Spacer(minLength: 1)
      HStack(spacing: 2) {
        Slider("Step", value: $step, in: 1...9, step: 1)
        Button("Reset") {
          withAnimation(.default) {
            count = 0
          }
        }
        .buttonStyle(.borderedProminent)
      }
      Spacer(minLength: 0)
    }
    .padding(2)
    .padding(.horizontal, 2)
    .border(.separator)
    .padding(2)
    .fixedSize()
    .onChange(of: count) {
      withAnimation {
        color = color.rotatedHue(by: 30)
      }
    }
  }

  private var brandingHeader: some View {
    VStack(alignment: .center, spacing: 0) {
      TextFigure("TerminalUI", font: .future)
        .foregroundStyle(color)
      Text("A SwiftUI-shaped terminal UI")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

}
