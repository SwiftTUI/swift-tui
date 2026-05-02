import ExampleScenes
import SwiftUI
import SwiftUIHost

struct ContentView: SwiftUI::View {
  @SwiftUI::State var tuiState: SwiftUIHostAppState<ExampleApp>?
  @SwiftUI::State var error: (any Error)?
  var body: some SwiftUI::View {
    if let tuiState {
      SwiftUIHostAppView(state: tuiState)
    } else if let error {
      ContentUnavailableView {
        VStack {
          Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.yellow, .black)
            .symbolRenderingMode(.palette)
            .symbolVariableValueMode(.color)
            .symbolColorRenderingMode(.gradient)
            .symbolEffect(
              .variableColor.cumulative.dimInactiveLayers.nonReversing,
              options: .repeat(.continuous)
            )
            .frame(maxWidth: 100)
          Text(error.localizedDescription)
            .font(.title)
        }
      }
    } else {
      ProgressView("Starting TUI")
        .onAppear {
          do {
            self.tuiState = try .init(app: ExampleApp())
          } catch {
            self.error = error
          }
        }
    }
  }
}

#Preview {
  ContentView()
}
