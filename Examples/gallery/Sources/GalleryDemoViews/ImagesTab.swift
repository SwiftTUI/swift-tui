import Foundation
import SwiftTUI

/// Showcases the ``Image`` primitive across its four rendering modes —
/// intrinsic size, ``Image/resizable()`` stretch, ``Image/scaledToFit()``,
/// and ``Image/scaledToFill()`` — using a single embedded PNG so the
/// gallery stays self-contained and has no external resource dependencies.
///
/// The PNG bytes are stored as a base64 string constant (``Self/pngBase64``)
/// generated once at compile time and decoded to `[UInt8]` on first access via
/// ``Self/pngBytes``. Feeding those bytes into `Image(data:)` exercises
/// the `.data` path of ``ImageSource`` — the same path the renderer takes
/// for attachments that need to survive without filesystem access.
struct ImagesTab: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        ImagesHeader()
        Divider()
        formatRow
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

  // 0. Format dispatch — three Image(data:) instances side by side,
  //    one per supported container. The renderer's magic-byte sniff
  //    picks the right decoder, and the kitty path either ships PNG
  //    bytes verbatim (f=100) or serializes the decoded RGBA pixels
  //    (f=32). Visually identical output across formats is the proof.
  private var formatRow: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("0. Format dispatch — PNG, JPEG, GIF")
        .foregroundStyle(.muted)
      HStack(spacing: 2) {
        formatCard(name: "PNG", bytes: Self.pngBytes)
        formatCard(name: "JPEG", bytes: Self.jpegBytes)
        formatCard(name: "GIF (frame 0)", bytes: Self.gifBytes)
      }
    }
  }

  private func formatCard(name: String, bytes: [UInt8]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(data: bytes)
        .border(.separator)
      Text(name)
        .foregroundStyle(.separator)
    }
  }

  // 1. Intrinsic — the image is measured in terminal cells using
  //    `ceil(pixelSize / cellPixelMetrics)`. With the default
  //    8×16 cell size, an 85×128 pixel PNG resolves to roughly
  //    11×8 cells and is placed unscaled.
  private var intrinsicSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("1. Intrinsic size — Image(data:)")
        .foregroundStyle(.muted)
      Image(data: Self.pngBytes)
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
      Image(data: Self.pngBytes)
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
      Image(data: Self.pngBytes)
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
      Image(data: Self.pngBytes)
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
  /// Lazily decoded bytes backing every `Image(data:)` in this tab.
  /// Foundation's `Data(base64Encoded:)` tolerates the line breaks we
  /// get from joining the pretty-printed constant below; the force-unwrap
  /// is safe because the blob is a compile-time constant and unit-tested
  /// by simply rendering the gallery.
  fileprivate static let pngBytes: [UInt8] = {
    let joined = pngBase64.joined()
    guard let data = Data(base64Encoded: joined) else {
      return []
    }
    return Array(data)
  }()

  static let gifBytes: [UInt8] = {
    let joined = gifBase64.joined()
    guard let data = Data(base64Encoded: joined) else {
      return []
    }
    return Array(data)
  }()

  fileprivate static let jpegBytes: [UInt8] = {
    let joined = jpegBase64.joined()
    guard let data = Data(base64Encoded: joined) else {
      return []
    }
    return Array(data)
  }()

  /// Base64-encoded PNG (85×128, 8-bit colormap) — generated offline via
  /// `sips -Z 128` → `pngquant --quality 60-90` → `base64`, then split into
  /// 76-column lines so the source file stays readable.
  fileprivate static let pngBase64: [String] = [
    "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",
  ]

  /// base64 nyan.gif | pbcopy
  fileprivate static let gifBase64 = [
    "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",
    "8/7dQmKE4MFZDrtVfCMCADs=",
  ]

  /// Base64-encoded JPEG (70×70 baseline) — first frame of nyan.gif
  /// re-encoded via `sips -s format jpeg --resampleWidth 70 nyan.gif`.
  /// Drives the renderer's JPEG path through the kitty f=32 RGBA
  /// transmission so all three formats are exercised side by side.
  fileprivate static let jpegBase64 = [
    "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAA",
    "A6ABAAMAAAABAAEAAKACAAQAAAABAAAARqADAAQAAAABAAAARgAAAAD/7QA4UGhvdG9zaG9wIDMu",
    "MAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgARgBGAwEiAAIR",
    "AQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAAB",
    "fQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5",
    "OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeo",
    "qaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMB",
    "AQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYS",
    "QVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNU",
    "VVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5",
    "usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMF",
    "BgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgIC",
    "BAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ",
    "EBAQEP/dAAQABf/aAAwDAQACEQMRAD8A/Keiiiv6IPwcK9d0z4nGx0Nbh7PT28Q6bLpsOnhtA0aW",
    "xaxtre9inN2ktqzT3BaeIh3D+ZgvMWkht2TyKis6lOMlaSLp1JRd4sKKKK0ILsem6jLp0+sRWsr2",
    "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",
    "GPmFFFFdZyBRRRQAUUUUAf/Z",
  ]
}
