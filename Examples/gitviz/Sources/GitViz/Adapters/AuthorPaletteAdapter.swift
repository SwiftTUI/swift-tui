import Foundation
import SwiftTUICharts

/// Deterministic palette assignment so the same author always lights up in
/// the same tone across subcommands.
enum AuthorPaletteAdapter {
  /// The cycling palette. `.automatic` is intentionally left out — it would
  /// hand the renderer's automatic tone to every author, which collapses to
  /// a single color.
  static let palette: [BannerTone] = [.success, .info, .warning, .critical]

  /// Returns a stable tone for `key` (case-insensitive). Uses a simple
  /// DJB2-style string hash so the mapping is reproducible across runs.
  static func tone(for key: String) -> BannerTone {
    var hash: UInt64 = 5381
    for byte in key.lowercased().utf8 {
      hash = (hash &* 33) &+ UInt64(byte)
    }
    let index = Int(hash % UInt64(palette.count))
    return palette[index]
  }

  /// Build a labeled palette pairing each `(author, values)` series with a
  /// stable tone. The output preserves the input order.
  static func assign(
    _ series: [(author: String, values: [Double])]
  ) -> [LabeledSeries] {
    series.map { entry in
      LabeledSeries(author: entry.author, values: entry.values, tone: tone(for: entry.author))
    }
  }
}

/// One author's labeled series with an assigned tone. Pulled out as a struct
/// (rather than a tuple) so SwiftUI's `ForEach(_:id:)` can key off `author`.
struct LabeledSeries: Hashable, Sendable {
  let author: String
  let values: [Double]
  let tone: BannerTone
}
