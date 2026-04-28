import Foundation
import TerminalUI

/// Showcases the ``Image`` primitive across its four rendering modes —
/// intrinsic size, ``Image/resizable()`` stretch, ``Image/scaledToFit()``,
/// and ``Image/scaledToFill()`` — using a single embedded PNG so the
/// gallery stays self-contained and has no external resource dependencies.
///
/// The PNG bytes are stored as a base64 string constant (``Self/brnPNGBase64``)
/// generated once at compile time and decoded to `[UInt8]` on first access via
/// ``Self/brnPNGBytes``. Feeding those bytes into `Image(pngData:)` exercises
/// the `.pngData` path of ``ImageSource`` — the same path the renderer takes
/// for attachments that need to survive without filesystem access.
struct ImagesTab: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        ImagesHeader()
        Divider()
        intrinsicSection
        Divider()
        resizableSection
        Divider()
        scaledToFitSection
        Divider()
        scaledToFillSection
        Spacer(minLength: 0)
      }
      .padding(1)
    }
  }

  // 1. Intrinsic — the image is measured in terminal cells using
  //    `ceil(pixelSize / cellPixelMetrics)`. With the default
  //    8×16 cell size, an 85×128 pixel PNG resolves to roughly
  //    11×8 cells and is placed unscaled.
  private var intrinsicSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("1. Intrinsic size — Image(pngData:)")
        .foregroundStyle(.muted)
      Image(pngData: Self.brnPNGBytes)
        .border(.separator)
    }
  }

  // 2. Resizable stretch — `.resizable()` opts the image into the
  //    flexible-size track with `scalingMode = .stretch`, so the
  //    resolver fills whatever frame the parent proposes (independent
  //    width and height).
  private var resizableSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("2. .resizable() — fills proposed frame (may distort)")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        resizableCard(width: 8, height: 4)
        resizableCard(width: 16, height: 8)
        resizableCard(width: 20, height: 12)
      }
    }
  }

  private func resizableCard(width: Int, height: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(pngData: Self.brnPNGBytes)
        .resizable()
        .frame(width: width, height: height)
        .border(.separator)
      Text("\(width)×\(height)")
        .foregroundStyle(.separator)
    }
  }

  // 3. scaledToFit — preserves aspect ratio and fits the longer axis
  //    inside the frame, centering the shorter axis. The frame here is
  //    wider than the image's aspect, so the image hugs the vertical
  //    dimension.
  private var scaledToFitSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("3. .scaledToFit() — preserves aspect, letterboxes")
        .foregroundStyle(.muted)
      Image(pngData: Self.brnPNGBytes)
        .scaledToFit()
        .frame(width: 30, height: 10)
        .border(.separator)
    }
  }

  // 4. scaledToFill — preserves aspect and covers the frame entirely;
  //    the longer axis overflows the frame on its own. `.clipped()` is
  //    what actually trims the overflow to the frame's bounds. The
  //    frame below is nearly square, so the tall source image is
  //    cropped top/bottom by the clip.
  private var scaledToFillSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("4. .scaledToFill() + .clipped() — fills frame, clip crops overflow")
        .foregroundStyle(.muted)
      Image(pngData: Self.brnPNGBytes)
        .scaledToFill()
        .frame(width: 20, height: 8)
        .clipped()
        .border(.separator)
    }
  }
}

private struct ImagesHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Images").foregroundStyle(.foreground)
      Text("Intrinsic, resizable, scaledToFit, scaledToFill — embedded PNG bytes.")
        .foregroundStyle(.separator)
    }
  }
}

extension ImagesTab {
  /// Lazily decoded bytes backing every `Image(pngData:)` in this tab.
  /// Foundation's `Data(base64Encoded:)` tolerates the line breaks we
  /// get from joining the pretty-printed constant below; the force-unwrap
  /// is safe because the blob is a compile-time constant and unit-tested
  /// by simply rendering the gallery.
  fileprivate static let brnPNGBytes: [UInt8] = {
    let joined = brnPNGBase64.joined()
    guard let data = Data(base64Encoded: joined) else {
      return []
    }
    return Array(data)
  }()

  /// Base64-encoded PNG (85×128, 8-bit colormap) — generated offline via
  /// `sips -Z 128` → `pngquant --quality 60-90` → `base64`, then split into
  /// 76-column lines so the source file stays readable.
  fileprivate static let brnPNGBase64: [String] = [
    "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",
  ]
}
