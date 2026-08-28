import Testing

@testable import SwiftTUIPrimitives

// `StyleEnvironmentSnapshot.==` carries an identity fast path on the boxed heavy
// fields, and the fast path is sound only while it elides the *heavy*
// comparison alone. Two snapshots share a box whenever
// `EnvironmentValues.applying(to:reuseStyle:)` takes its reuse branch, which it
// does for every key `ResolveContext.isStyleKeyPath` does not name — including
// `cellPixelMetrics`, which has a public setter. A fast path that returned
// `true` on box identity alone let the reuse gate serve a subtree whose light
// fields had changed.
//
// Each case builds its shared box explicitly, so the invariant is pinned
// without depending on how any particular producer happens to allocate.

private let sharedBox = StyleHeavyFieldsStorage(
  appearance: .fallback,
  theme: TerminalAppearance.fallback.synthesizedTheme()
)

private func snapshot(
  foregroundStyle: AnyShapeStyle? = nil,
  tintStyle: AnyShapeStyle? = nil,
  isEnabled: Bool = true,
  cellPixelMetrics: CellPixelMetrics = .estimated
) -> StyleEnvironmentSnapshot {
  StyleEnvironmentSnapshot(
    heavyFields: sharedBox,
    foregroundStyle: foregroundStyle,
    tintStyle: tintStyle,
    isEnabled: isEnabled,
    cellPixelMetrics: cellPixelMetrics
  )
}

@Test("A shared heavy-fields box does not make differing foreground styles equal")
func sharedBoxStillComparesForegroundStyle() {
  let plain = snapshot()
  let red = snapshot(foregroundStyle: AnyShapeStyle(Color.red))
  #expect(plain.heavyFields === red.heavyFields)
  #expect(plain != red)
}

@Test("A shared heavy-fields box does not make differing tint styles equal")
func sharedBoxStillComparesTintStyle() {
  let plain = snapshot()
  let tinted = snapshot(tintStyle: AnyShapeStyle(Color.green))
  #expect(plain.heavyFields === tinted.heavyFields)
  #expect(plain != tinted)
}

@Test("A shared heavy-fields box does not make differing enablement equal")
func sharedBoxStillComparesIsEnabled() {
  let enabled = snapshot(isEnabled: true)
  let disabled = snapshot(isEnabled: false)
  #expect(enabled.heavyFields === disabled.heavyFields)
  #expect(enabled != disabled)
}

@Test("A shared heavy-fields box does not make differing cell metrics equal")
func sharedBoxStillComparesCellPixelMetrics() {
  let estimated = snapshot(cellPixelMetrics: .estimated)
  let reported = snapshot(
    cellPixelMetrics: CellPixelMetrics(width: 9, height: 19, source: .reported)
  )
  #expect(estimated.heavyFields === reported.heavyFields)
  #expect(estimated != reported)
}

@Test("Snapshots agreeing on every field compare equal")
func identicalSnapshotsCompareEqual() {
  #expect(snapshot() == snapshot())
  #expect(
    snapshot(foregroundStyle: AnyShapeStyle(Color.blue), isEnabled: false)
      == snapshot(foregroundStyle: AnyShapeStyle(Color.blue), isEnabled: false)
  )
}

@Test("Distinct boxes holding equal heavy fields still compare equal")
func distinctBoxesWithEqualContentCompareEqual() {
  let theme = TerminalAppearance.fallback.synthesizedTheme()
  let left = StyleEnvironmentSnapshot(
    heavyFields: StyleHeavyFieldsStorage(appearance: .fallback, theme: theme),
    foregroundStyle: nil,
    tintStyle: nil,
    isEnabled: true
  )
  let right = StyleEnvironmentSnapshot(
    heavyFields: StyleHeavyFieldsStorage(appearance: .fallback, theme: theme),
    foregroundStyle: nil,
    tintStyle: nil,
    isEnabled: true
  )
  #expect(left.heavyFields !== right.heavyFields)
  #expect(left == right)
}

@Test("A differing appearance compares unequal")
func differingAppearanceComparesUnequal() {
  var recoloured = TerminalAppearance.fallback
  recoloured.backgroundColor = .red
  #expect(
    StyleEnvironmentSnapshot(appearance: .fallback)
      != StyleEnvironmentSnapshot(appearance: recoloured)
  )
}
