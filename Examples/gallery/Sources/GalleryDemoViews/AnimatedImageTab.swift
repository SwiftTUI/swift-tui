import SwiftTUIAnimatedImage
import SwiftTUIRuntime

struct AnimatedImageTab: View {
  private static let sequence = try? AnimatedGIF.decode(data: ImagesTab.gifBytes)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header
        Divider()
        gifPreview
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Animated GIF").foregroundStyle(.foreground)
      Text("Embedded GIF decoded through SwiftTUIAnimatedImage.")
        .foregroundStyle(.separator)
    }
  }

  @ViewBuilder
  private var gifPreview: some View {
    if let sequence = Self.sequence {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nyan fixture")
          .foregroundStyle(.muted)
        AnimatedImage(sequence)
          .accessibilityLabel("Animated GIF preview of the embedded Nyan fixture")
          .border(.separator)
      }
    } else {
      Text("Embedded GIF failed to decode.")
        .foregroundStyle(.red)
    }
  }
}
