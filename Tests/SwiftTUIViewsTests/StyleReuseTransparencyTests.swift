import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Reuse-equality contract for the four erased style families.
///
/// Every family's box answered this question with its own hardcoded list of
/// builtin style types, and nothing tested any of them. The lists looked like
/// an optimisation and are not: a stateless style struct conforms to neither
/// `Equatable` nor `TypedReuseEqualityProviding` and is not a class, so
/// `typedValuesAreEqualForReuse` finds no typed proof and returns its
/// conservative `false`. Drop a style from its list and that style's control
/// denies reuse on every frame — silently, and visible only as a performance
/// regression.
///
/// The lists are now one marker protocol (`ReuseTransparentStyle`). These tests
/// pin both directions: builtins are transparent, and everything else still
/// goes through value equality.
@MainActor
struct StyleReuseTransparencyTests {
  @Test("passive composition built-ins are reuse-transparent")
  func passiveBuiltInsAreReuseTransparent() {
    #expect(AnyLabelStyle.automatic.isEqualForReuse(to: AnyLabelStyle.automatic))
    #expect(AnyLabelStyle.titleAndIcon.isEqualForReuse(to: AnyLabelStyle.titleAndIcon))
    #expect(AnyLabelStyle.titleOnly.isEqualForReuse(to: AnyLabelStyle.titleOnly))
    #expect(AnyLabelStyle.iconOnly.isEqualForReuse(to: AnyLabelStyle.iconOnly))
    #expect(AnyLabeledContentStyle.automatic.isEqualForReuse(to: AnyLabeledContentStyle.automatic))
    #expect(AnyLabeledContentStyle.stacked.isEqualForReuse(to: AnyLabeledContentStyle.stacked))
    #expect(AnyGroupBoxStyle.automatic.isEqualForReuse(to: AnyGroupBoxStyle.automatic))
    #expect(AnyGroupBoxStyle.bordered.isEqualForReuse(to: AnyGroupBoxStyle.bordered))
    #expect(AnyGroupBoxStyle.plain.isEqualForReuse(to: AnyGroupBoxStyle.plain))
    #expect(!AnyLabelStyle.titleOnly.isEqualForReuse(to: AnyLabelStyle.iconOnly))
    #expect(!AnyLabeledContentStyle.automatic.isEqualForReuse(to: AnyLabeledContentStyle.stacked))
    #expect(!AnyGroupBoxStyle.bordered.isEqualForReuse(to: AnyGroupBoxStyle.plain))
  }

  @Test("passive composition custom styles use value equality or conservatively invalidate")
  func passiveCustomStyleEquality() {
    #expect(
      AnyLabelStyle(EquatableLabelStyle(value: 1)).isEqualForReuse(
        to: AnyLabelStyle(EquatableLabelStyle(value: 1))))
    #expect(
      !AnyLabelStyle(EquatableLabelStyle(value: 1)).isEqualForReuse(
        to: AnyLabelStyle(EquatableLabelStyle(value: 2))))
    #expect(
      !AnyLabelStyle(OpaqueLabelStyle()).isEqualForReuse(
        to: AnyLabelStyle(OpaqueLabelStyle())))
    #expect(
      AnyLabeledContentStyle(EquatableLabeledContentStyle(value: 1)).isEqualForReuse(
        to: AnyLabeledContentStyle(EquatableLabeledContentStyle(value: 1))))
    #expect(
      !AnyLabeledContentStyle(EquatableLabeledContentStyle(value: 1)).isEqualForReuse(
        to: AnyLabeledContentStyle(EquatableLabeledContentStyle(value: 2))))
    #expect(
      !AnyLabeledContentStyle(OpaqueLabeledContentStyle()).isEqualForReuse(
        to: AnyLabeledContentStyle(OpaqueLabeledContentStyle())))
    #expect(
      AnyGroupBoxStyle(EquatableGroupBoxStyle(value: 1)).isEqualForReuse(
        to: AnyGroupBoxStyle(EquatableGroupBoxStyle(value: 1))))
    #expect(
      !AnyGroupBoxStyle(EquatableGroupBoxStyle(value: 1)).isEqualForReuse(
        to: AnyGroupBoxStyle(EquatableGroupBoxStyle(value: 2))))
    #expect(
      !AnyGroupBoxStyle(OpaqueGroupBoxStyle()).isEqualForReuse(
        to: AnyGroupBoxStyle(OpaqueGroupBoxStyle())))
  }

  @Test("builtin button styles are interchangeable across instances")
  func builtinButtonStylesAreReuseTransparent() {
    #expect(AnyButtonStyle.automatic.isEqualForReuse(to: AnyButtonStyle.automatic))
    #expect(AnyButtonStyle.plain.isEqualForReuse(to: AnyButtonStyle.plain))
    #expect(AnyButtonStyle.bordered.isEqualForReuse(to: AnyButtonStyle.bordered))
    #expect(
      AnyButtonStyle.borderedProminent.isEqualForReuse(to: AnyButtonStyle.borderedProminent)
    )
    #expect(AnyButtonStyle.link.isEqualForReuse(to: AnyButtonStyle.link))
  }

  @Test("builtin picker styles are interchangeable across instances")
  func builtinPickerStylesAreReuseTransparent() {
    #expect(AnyPickerStyle.automatic.isEqualForReuse(to: AnyPickerStyle.automatic))
    #expect(AnyPickerStyle.inline.isEqualForReuse(to: AnyPickerStyle.inline))
    #expect(AnyPickerStyle.segmented.isEqualForReuse(to: AnyPickerStyle.segmented))
    #expect(AnyPickerStyle.radioGroup.isEqualForReuse(to: AnyPickerStyle.radioGroup))
    #expect(AnyPickerStyle.menu.isEqualForReuse(to: AnyPickerStyle.menu))
  }

  @Test("builtin text-field styles are interchangeable across instances")
  func builtinTextFieldStylesAreReuseTransparent() {
    #expect(AnyTextFieldStyle.automatic.isEqualForReuse(to: AnyTextFieldStyle.automatic))
    #expect(AnyTextFieldStyle.plain.isEqualForReuse(to: AnyTextFieldStyle.plain))
    #expect(AnyTextFieldStyle.roundedBorder.isEqualForReuse(to: AnyTextFieldStyle.roundedBorder))
  }

  @Test("builtin tab-view styles are interchangeable across instances")
  func builtinTabViewStylesAreReuseTransparent() {
    #expect(AnyTabViewStyle.automatic.isEqualForReuse(to: AnyTabViewStyle.automatic))
    #expect(AnyTabViewStyle.underline.isEqualForReuse(to: AnyTabViewStyle.underline))
    #expect(AnyTabViewStyle.literalTabs.isEqualForReuse(to: AnyTabViewStyle.literalTabs))
    #expect(AnyTabViewStyle.powerline.isEqualForReuse(to: AnyTabViewStyle.powerline))
  }

  @Test("different builtin styles in a family are not interchangeable")
  func distinctBuiltinStylesAreNotReuseEqual() {
    // Transparency is per concrete type: the box establishes `as? Self` before
    // the marker is ever consulted, so a marker on both sides cannot collapse
    // two different styles into one.
    #expect(!AnyButtonStyle.plain.isEqualForReuse(to: AnyButtonStyle.bordered))
    #expect(!AnyPickerStyle.inline.isEqualForReuse(to: AnyPickerStyle.menu))
    #expect(!AnyTextFieldStyle.plain.isEqualForReuse(to: AnyTextFieldStyle.roundedBorder))
    #expect(!AnyTabViewStyle.underline.isEqualForReuse(to: AnyTabViewStyle.powerline))
  }

  @Test("a custom style with equatable state still compares by value")
  func customEquatableStyleComparesByValue() {
    // The red-proof for the marker: if `ReuseTransparentStyle` ever widened to
    // all styles, this pair would compare equal and a tint change would reuse
    // stale chrome.
    let one = AnyButtonStyle(TintedTestButtonStyle(tint: 1))
    let alsoOne = AnyButtonStyle(TintedTestButtonStyle(tint: 1))
    let two = AnyButtonStyle(TintedTestButtonStyle(tint: 2))

    #expect(one.isEqualForReuse(to: alsoOne))
    #expect(!one.isEqualForReuse(to: two))
  }

  @Test("a custom style with no typed equality proof is conservatively unequal")
  func customOpaqueStyleIsConservativelyUnequal() {
    // Documents the fallback the builtin marker exists to avoid: no `Equatable`
    // conformance, no `TypedReuseEqualityProviding`, not a class — so there is
    // no proof two values match, and reuse is denied rather than risked.
    let style = OpaqueTestButtonStyle(onTap: {})
    #expect(!AnyButtonStyle(style).isEqualForReuse(to: AnyButtonStyle(style)))
  }
}

// MARK: - Roster totality

/// The marker roster must track the builtin roster.
///
/// The behavioural tests above name each builtin explicitly, which cannot catch
/// a *newly added* builtin that forgets the marker — the new style simply is
/// not mentioned anywhere. The public static factories on the four erased
/// wrappers are the builtin inventory, so pinning their count forces this file
/// to be revisited whenever one is added.
struct StyleReuseTransparencyRosterTests {
  private static let wrapperFactoryCounts = [
    "Sources/SwiftTUIViews/Primitives/LabelStyles.swift": 4,
    "Sources/SwiftTUIViews/Primitives/LabeledContentStyles.swift": 2,
    "Sources/SwiftTUIViews/Primitives/GroupBoxStyles.swift": 3,
    "Sources/SwiftTUIViews/Controls/ButtonStyles.swift": 5,
    "Sources/SwiftTUIViews/Controls/PickerStyles.swift": 5,
    "Sources/SwiftTUIViews/Controls/TextFieldStyles.swift": 3,
    "Sources/SwiftTUIViews/TabViews/TabViewStyles.swift": 4,
  ]

  private static let markerConformanceFiles = [
    "Sources/SwiftTUIViews/Primitives/LabelStyles.swift",
    "Sources/SwiftTUIViews/Primitives/LabeledContentStyles.swift",
    "Sources/SwiftTUIViews/Primitives/GroupBoxStyles.swift",
    "Sources/SwiftTUIViews/Controls/ButtonStyles.swift",
    "Sources/SwiftTUIViews/Controls/PickerStyles.swift",
    "Sources/SwiftTUIViews/Controls/TextFieldStyles.swift",
    "Sources/SwiftTUIViews/TabViews/TabViewStyleHosting.swift",
  ]

  @Test("each erased wrapper exposes exactly the builtin styles this file tests")
  func builtinFactoryCountsArePinned() throws {
    for (relativePath, expected) in Self.wrapperFactoryCounts {
      let source = try sourceText(relativePath: relativePath)
      let found = source.split(separator: "\n").count { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("public static var ") && trimmed.hasSuffix(": Self {")
      }
      #expect(
        found == expected,
        """
        \(relativePath) exposes \(found) builtin styles, expected \(expected). \
        A new builtin needs a `ReuseTransparentStyle` conformance and a case in \
        StyleReuseTransparencyTests — without the marker it silently denies reuse.
        """
      )
    }
  }

  @Test("every builtin style carries the reuse-transparency marker")
  func markerConformanceCountMatchesBuiltinRoster() throws {
    var conformances = 0
    for relativePath in Self.markerConformanceFiles {
      let source = try sourceText(relativePath: relativePath)
      conformances += source.split(separator: "\n").count { line in
        line.trimmingCharacters(in: .whitespacesAndNewlines)
          .hasSuffix(": ReuseTransparentStyle {}")
      }
    }
    let builtins = Self.wrapperFactoryCounts.values.reduce(0, +)
    #expect(
      conformances == builtins,
      """
      \(conformances) styles are marked reuse-transparent but \(builtins) builtin \
      styles are exposed — the marker roster and the builtin roster have diverged.
      """
    )
  }
}

// MARK: - Test styles

private struct TintedTestButtonStyle: ButtonStyle, Equatable {
  let tint: Int

  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

private struct OpaqueTestButtonStyle: ButtonStyle {
  let onTap: @Sendable () -> Void

  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}

private func sourceText(relativePath: String) throws -> String {
  let root = try repositoryRoot()
  return try String(
    contentsOf: root.appendingPathComponent(relativePath),
    encoding: .utf8
  )
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw StyleRosterParseError.missingPackageRoot
}

private enum StyleRosterParseError: Error {
  case missingPackageRoot
}

private struct EquatableLabelStyle: LabelStyle, Equatable {
  let value: Int
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    configuration.title
  }
}

private struct OpaqueLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    configuration.title
  }
}

private struct EquatableLabeledContentStyle: LabeledContentStyle, Equatable {
  let value: Int
  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    configuration.content
  }
}

private struct OpaqueLabeledContentStyle: LabeledContentStyle {
  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    configuration.content
  }
}

private struct EquatableGroupBoxStyle: GroupBoxStyle, Equatable {
  let value: Int
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    configuration.content
  }
}

private struct OpaqueGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    configuration.content
  }
}
