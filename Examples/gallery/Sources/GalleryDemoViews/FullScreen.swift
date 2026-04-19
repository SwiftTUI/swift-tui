import TerminalUI

struct FullScreenTab: View {
  @State private var position = Point(x: 0, y: 0)
  @GestureState private var dragOffset = Size(width: 0, height: 0)

  var body: some View {
    let current = Point(
      x: position.x + dragOffset.width,
      y: position.y + dragOffset.height
    )
    ZStack(alignment: .topLeading) {
      Rectangle()
        .frame(width: 6, height: 3)
        .offset(x: current.x, y: current.y)
        .foregroundStyle(.cyan)
        .gesture(
          DragGesture()
            .updating($dragOffset) { value, state, _ in
              state = value.translation
            }
            .onEnded { value in
              position = Point(
                x: position.x + value.translation.width,
                y: position.y + value.translation.height
              )
            }
        )
    }
  }
}
