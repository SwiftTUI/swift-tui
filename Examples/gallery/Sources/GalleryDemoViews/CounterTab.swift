import TerminalUI

struct CounterTab: View {
  @State private var count: Int = 0
  @State private var step: Int = 1

  var body: some View {
    VStack(alignment: .center, spacing: 1) {
      brandingHeader
      Divider()
      Spacer(minLength: 1)
      countDisplay
      Spacer(minLength: 1)
      controls
      stepSlider
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var brandingHeader: some View {
    VStack(alignment: .center, spacing: 0) {
      TextFigure("TerminalUI", font: .small)
      Text("A SwiftUI-shaped terminal UI")
        .foregroundStyle(.separator)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var countDisplay: some View {
    Text("\(count)")
      .bold()
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private var controls: some View {
    HStack(spacing: 2) {
      Button("−", role: .destructive) {
        withAnimation(.default) {
          count -= step
        }
      }
      Button("Reset") {
        withAnimation(.default) {
          count = 0
        }
      }
      Button("+") {
        withAnimation(.default) {
          count += step
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var stepSlider: some View {
    HStack(spacing: 1) {
      Text("Step")
        .foregroundStyle(.separator)
      Slider("Step", value: $step, in: 1...10, step: 1)
      Text("\(step)")
    }
    .padding(.horizontal, 2)
  }
}
