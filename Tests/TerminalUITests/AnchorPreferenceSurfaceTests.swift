import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private enum BoundsAnchorPreferenceKey: PreferenceKey {
  static let defaultValue: Anchor<Rect>? = nil

  static func reduce(
    value: inout Anchor<Rect>?,
    nextValue: () -> Anchor<Rect>?
  ) {
    value = nextValue() ?? value
  }
}

private enum BoundsAnchorListPreferenceKey: PreferenceKey {
  static let defaultValue: [Anchor<Rect>] = []

  static func reduce(
    value: inout [Anchor<Rect>],
    nextValue: () -> [Anchor<Rect>]
  ) {
    value.append(contentsOf: nextValue())
  }
}

private enum PointAnchorPreferenceKey: PreferenceKey {
  static let defaultValue: Anchor<Point>? = nil

  static func reduce(
    value: inout Anchor<Point>?,
    nextValue: () -> Anchor<Point>?
  ) {
    value = nextValue() ?? value
  }
}

@MainActor
@Suite
struct AnchorPreferenceSurfaceTests {
  @Test("anchorPreference and transformAnchorPreference publish opaque tokens")
  func anchorPreferenceModifiersPublishOpaqueTokens() {
    let resolved = Resolver().resolve(
      Text("Base")
        .anchorPreference(
          key: BoundsAnchorListPreferenceKey.self,
          value: .bounds
        ) { anchor in
          [anchor]
        }
        .transformAnchorPreference(
          BoundsAnchorListPreferenceKey.self,
          value: .bounds
        ) { anchors, anchor in
          anchors.append(anchor)
        },
      in: .init(identity: testIdentity("AnchorPreferenceRoot"))
    )

    let anchors = resolved.preferenceValues[BoundsAnchorListPreferenceKey.self]
    #expect(anchors.count == 2)
    #expect(anchors.first == anchors.last)
  }

  @Test("GeometryProxy resolves bounds anchors from overlayPreferenceValue")
  func geometryProxyResolvesBoundsAnchorsFromOverlayPreferenceValue() {
    let artifacts = DefaultRenderer().render(
      Text("Base")
        .frame(width: 8, height: 3, alignment: .topLeading)
        .anchorPreference(
          key: BoundsAnchorPreferenceKey.self,
          value: .bounds
        ) { $0 }
        .overlayPreferenceValue(BoundsAnchorPreferenceKey.self, alignment: .topLeading) { anchor in
          GeometryReader { proxy in
            let rect = anchor.map { proxy[$0] } ?? .zero
            Text(
              "\(Int(rect.origin.x)),\(Int(rect.origin.y)) "
                + "\(Int(rect.size.width))x\(Int(rect.size.height))"
            )
          }
        },
      proposal: .init(width: 20, height: 5)
    )

    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("0,0 8x3")
      }
    )
  }

  @Test("GeometryProxy resolves point anchors from overlayPreferenceValue")
  func geometryProxyResolvesPointAnchorsFromOverlayPreferenceValue() {
    let artifacts = DefaultRenderer().render(
      Text("Base")
        .frame(width: 8, height: 3, alignment: .topLeading)
        .anchorPreference(
          key: PointAnchorPreferenceKey.self,
          value: .bottomTrailing
        ) { $0 }
        .overlayPreferenceValue(PointAnchorPreferenceKey.self, alignment: .topLeading) { anchor in
          GeometryReader { proxy in
            let point = anchor.map { proxy[$0] } ?? .zero
            Text("\(Int(point.x)),\(Int(point.y))")
          }
        },
      proposal: .init(width: 20, height: 5)
    )

    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("8,3")
      }
    )
  }

  @Test("GeometryProxy frame resolves local and global coordinate spaces")
  func geometryProxyFrameResolvesLocalAndGlobalCoordinateSpaces() {
    let artifacts = DefaultRenderer().render(
      HStack(alignment: .top, spacing: 2) {
        Text("A")
          .frame(width: 3, height: 1)
        GeometryReader { proxy in
          let local = proxy.frame(in: .local)
          let global = proxy.frame(in: .global)
          Text(
            "\(Int(local.origin.x)),\(Int(local.origin.y))|"
              + "\(Int(global.origin.x)),\(Int(global.origin.y))"
          )
        }
        .frame(width: 10, height: 1)
      },
      proposal: .init(width: 20, height: 1)
    )

    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("0,0|5,0")
      }
    )
  }

  @Test("GeometryProxy frame resolves named coordinate spaces")
  func geometryProxyFrameResolvesNamedCoordinateSpaces() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Board")
          .frame(width: 10, height: 1)
          .coordinateSpace(name: "board")
        GeometryReader { proxy in
          let frame = proxy.frame(in: .named("board"))
          Text("\(Int(frame.origin.x)),\(Int(frame.origin.y))")
        }
        .frame(width: 10, height: 1)
      },
      proposal: .init(width: 20, height: 2)
    )

    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("0,1")
      }
    )
  }
}
