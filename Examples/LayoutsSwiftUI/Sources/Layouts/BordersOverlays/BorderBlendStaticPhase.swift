import SwiftUI

/// Two bordered boxes side-by-side that share the same `BorderBlend`
/// palette but differ only in the static `phase` parameter.
///
/// SwiftUI port: the original used SwiftTUI's `BorderBlend(_:)` —
/// a perimeter 1D gradient sampled clockwise around the rectangle
/// with an animatable `phase`. SwiftUI has no direct equivalent. The
/// closest one-liner is an `AngularGradient` overlay clipped to a
/// rectangle stroke. Layout shape (two side-by-side bordered boxes)
/// is preserved; the visual effect of `phase` shifts the gradient's
/// starting angle.
public struct BorderBlendStaticPhase: View {
  public init() {}

  private static let palette: [Color] = [.red, .yellow, .green, .cyan]

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Border blend static phase").foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 3) {
        VStack(alignment: .leading, spacing: 0) {
          Text("phase 0.0").foregroundStyle(.secondary)
          Text("X")
            .padding(2)
            .overlay(blendBorder(phase: 0.0))
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("phase 0.5").foregroundStyle(.secondary)
          Text("X")
            .padding(2)
            .overlay(blendBorder(phase: 0.5))
        }
      }
    }
    .padding(1)
  }

  private func blendBorder(phase: Double) -> some View {
    let stops = Self.palette.enumerated().map { index, color in
      Gradient.Stop(
        color: color,
        location: (Double(index) / Double(Self.palette.count - 1) + phase)
          .truncatingRemainder(dividingBy: 1.0)
      )
    }
    return RoundedRectangle(cornerRadius: 4)
      .strokeBorder(
        AngularGradient(
          gradient: Gradient(stops: stops.sorted { $0.location < $1.location }),
          center: .center
        ),
        lineWidth: 1
      )
  }
}
