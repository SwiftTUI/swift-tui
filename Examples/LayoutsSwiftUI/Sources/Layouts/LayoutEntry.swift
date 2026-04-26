import SwiftUI

/// Metadata + factory for one layout example.
///
/// One `LayoutEntry` literal per layout is added to
/// ``LayoutCatalog/all``. The app picker reads the catalog to render
/// the list of entries and to open one full-screen; the parameterised
/// ``LayoutSmokeTests`` iterates the same catalog so "added a layout
/// but forgot to wire it up" is not possible.
///
/// AnyView policy: `makeView` must return `AnyView` because the
/// catalog is a heterogeneous `[LayoutEntry]`. The concrete view per
/// layout is still a strongly-typed `struct`; the erasure happens
/// at the catalog literal only (`AnyView(ConcreteLayout())`).
/// See `docs/PUBLIC_SURFACE_POLICY.md` for the AnyView policy.
public struct LayoutEntry: Identifiable, Hashable, Sendable {
  public let id: String
  public let category: Category
  public let title: String
  public let blurb: String
  /// Substring guaranteed to appear in the rendered raster; `LayoutSmokeTests` uses this to prove the layout produced output.
  public let marker: String
  public let tier: TestTier
  public let makeView: @MainActor @Sendable () -> AnyView

  public init(
    id: String,
    category: Category,
    title: String,
    blurb: String,
    marker: String,
    tier: TestTier,
    makeView: @escaping @MainActor @Sendable () -> AnyView
  ) {
    self.id = id
    self.category = category
    self.title = title
    self.blurb = blurb
    self.marker = marker
    self.tier = tier
    self.makeView = makeView
  }

  public static func == (lhs: LayoutEntry, rhs: LayoutEntry) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension LayoutEntry {
  public enum Category: String, CaseIterable, Sendable, Hashable {
    case stacks = "Stacks"
    case frames = "Frames & Sizing"
    case padding = "Padding & Safe Area"
    case bordersOverlays = "Borders & Overlays"
    case offsetPosition = "Offset · Position · Clip"
    case zStack = "ZStack"
    case spacers = "Spacers & Dividers"
    case scrolling = "Scrolling"
    case geometry = "GeometryReader"
    case viewThatFits = "ViewThatFits"
    case customLayout = "Custom Layout"
    case alignmentGuides = "Alignment Guides"
    case collections = "Collections"
    case shapesCanvas = "Shapes & Canvas"
    case presentationLayout = "Presentation × Layout"
    case matched = "Matched Geometry"
  }

  public enum TestTier: Sendable, Hashable {
    case smoke
    case behaviour
  }
}
