/// Determines which parts of earlier native placements a shader can sample.
/// The paint walk uses this record at each original image command, before any
/// higher text. Regions outside those reads keep their original native placement.
final class RasterBackdropImages {
  struct Key: Hashable {
    let identity: Identity
    let bounds: CellRect
    let visible: CellRect
  }
  struct Placement {
    var native: [CellRect]
    var projected: [CellRect] = []

    mutating func project(_ read: CellRect) {
      var remaining: [CellRect] = []
      for rect in native {
        guard let cut = rect.intersection(read) else {
          remaining.append(rect)
          continue
        }
        projected.append(cut)
        func keep(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
          guard left < right && top < bottom else { return }
          remaining.append(
            .init(
              origin: .init(x: left, y: top),
              size: .init(width: right - left, height: bottom - top)))
        }
        keep(rect.origin.x, rect.origin.y, rect.maxX, cut.origin.y)
        keep(rect.origin.x, cut.maxY, rect.maxX, rect.maxY)
        keep(rect.origin.x, cut.origin.y, cut.origin.x, cut.maxY)
        keep(cut.maxX, cut.origin.y, rect.maxX, cut.maxY)
      }
      native = remaining
    }
  }

  fileprivate(set) var needsPreparationReplay = false
  private let surface: CellRect

  fileprivate init(surface: CellRect) { self.surface = surface }

  fileprivate var placements: [Placement] = []
  fileprivate var occurrences: [Key: [Int]] = [:]
  private var visited: [Key: Int] = [:]

  func next(_ attachment: RasterImageAttachment) -> Placement? {
    // An unclipped native command retains its full offscreen destination.
    // The discovery walk visits just the raster surface; compare in that space.
    guard let visible = attachment.visibleBounds.intersection(surface) else { return nil }
    let key = Key(identity: attachment.identity, bounds: attachment.bounds, visible: visible)
    guard let occurrences = occurrences[key] else { return nil }
    let index = visited[key, default: 0]
    visited[key] = index + 1
    guard occurrences.indices.contains(index) else { return nil }
    let placement = placements[occurrences[index]]
    guard !placement.projected.isEmpty else { return nil }
    if visible == attachment.visibleBounds { return placement }
    var entire = Placement(native: [attachment.visibleBounds])
    for rect in placement.projected { entire.project(rect) }
    return entire
  }
}

extension Rasterizer {
  func backdropImagePlan(for draw: DrawNode, size: CellSize, includeUnknown: Bool = true)
    -> RasterBackdropImages?
  {
    guard draw.subtreeHasCellEffect, hasImageCommands(draw) else { return nil }
    final class Target { var lower: [Int] = [] }
    enum Event {
      case visit(DrawNode, CellRect, Target, native: Bool)
      case commands([DrawCommand], CellRect, Target)
      case flatten(Target, into: Target)
    }
    let surface = CellRect(origin: .zero, size: size)
    let plan = RasterBackdropImages(surface: surface)
    var stack: [Event] = [.visit(draw, surface, Target(), native: true)]
    while let event = stack.popLast() {
      switch event {
      case .flatten(let group, let target): target.lower.append(contentsOf: group.lower)
      case .commands(let commands, let clip, let target):
        for command in commands {
          guard case .image(let bounds, let identity, _) = command,
            let visible = bounds.intersection(clip)
          else { continue }
          let index = plan.placements.count
          plan.placements.append(.init(native: [visible]))
          plan.occurrences[.init(identity: identity, bounds: bounds, visible: visible), default: []]
            .append(index)
          target.lower.append(index)
        }
      case .visit(var node, let inheritedClip, let target, let native):
        guard let clip = inheritedClip.intersection(node.clipBounds ?? inheritedClip),
          node.subtreeDrawsInViewport || node.subtreeBounds.intersection(clip) != nil
        else { continue }
        if !node.metadata.shapeClips.isEmpty {
          let clips = shapeClipRegions(node: node, clip: clip)
          node.metadata.shapeClips = []
          for mask in clips.reversed() { stack.append(.visit(node, mask, target, native: native)) }
          continue
        }
        if let boundary = node.drawEffects.ordered.lastIndex(where: {
          if case .cellLayer = $0 { return true }
          return $0 == .compositingGroup
        }) {
          let effect = node.drawEffects.ordered[boundary]
          node.drawEffects = DrawEffects(Array(node.drawEffects.ordered[..<boundary]))
          switch effect {
          case .compositingGroup:
            let group = Target()
            stack.append(.flatten(group, into: target))
            stack.append(.visit(node, clip, group, native: native))
          case .cellLayer(let pass):
            var shader = pass.shader
            if case .prepared(let binding) = shader.program, !target.lower.isEmpty {
              if let frame = cellPreparationFrame, let ready = binding.cached(in: frame) {
                shader = ready
              } else if includeUnknown {
                plan.needsPreparationReplay = true
              } else {
                // No sample was produced in the conservative pass (e.g. an empty mask).
                stack.append(.visit(node, clip, target, native: false))
                continue
              }
            }
            if !node.bounds.isEmpty, pass.targetsBackdrop || shader.readsBackdrop {
              var bounds = node.subtreeHasCellEffect ? node.subtreeBounds : node.bounds
              if node.subtreeDrawsInViewport { bounds = bounds.union(clip) }
              let origin = node.bounds.origin
              let viewport = clip.relative(to: origin)
              let output = shader.region.bounds(
                source: bounds.relative(to: origin), viewport: viewport)
              if !output.isEmpty {
                let region: CellRect
                if pass.targetsBackdrop {
                  region = output
                } else {
                  switch pass.offset {
                  case .layerBounds: region = viewport
                  case .cells(let x, let y):
                    region = CellDrawingRegion.outset(x: x, y: y).bounds(
                      source: output, viewport: viewport)
                  }
                }
                let read = CellRect(
                  origin: .init(
                    x: SaturatingConversion.adding(origin.x, region.origin.x),
                    y: SaturatingConversion.adding(origin.y, region.origin.y)), size: region.size)
                for index in target.lower { plan.placements[index].project(read) }
              }
            }
            // Implicit captures retain access to the enclosing lower paint;
            // images inside the captured subject already use cell projection.
            stack.append(.visit(node, clip, target, native: native && pass.targetsBackdrop))
          case .blendMode: break
          }
          continue
        }
        if native { stack.append(.commands(node.postCommands, clip, target)) }
        for child in node.children.reversed() {
          stack.append(.visit(child, clip, target, native: native))
        }
        if native { stack.append(.commands(node.commands, clip, target)) }
      }
    }
    return plan.placements.contains { !$0.projected.isEmpty } ? plan : nil
  }
}
