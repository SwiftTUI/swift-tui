/// Paint commands use absolute cell coordinates. Rebase off-surface input into
/// a bounded scratch grid before gathering. Both walks use heap stacks since
/// the raster worker also handles deeply nested client views.
extension DrawNode {
  func rebasedForCapture(at origin: CellPoint) -> Self {
    guard origin != .zero else { return self }
    var stack = [(node: self, assemble: false)]
    var results: [DrawNode] = []
    while let frame = stack.popLast() {
      let node = frame.node
      if !frame.assemble && !node.children.isEmpty {
        stack.append((node, true))
        for child in node.children.reversed() { stack.append((child, false)) }
        continue
      }
      let children = Array(results.suffix(node.children.count))
      results.removeLast(node.children.count)
      results.append(
        Self(
          viewNodeID: node.viewNodeID, identity: node.identity,
          environmentSnapshot: node.environmentSnapshot, bounds: node.bounds.relative(to: origin),
          clipBounds: node.clipBounds?.relative(to: origin), metadata: node.metadata,
          drawEffects: node.drawEffects,
          commands: node.commands.map { $0.rebasedForCapture(at: origin) },
          postCommands: node.postCommands.map { $0.rebasedForCapture(at: origin) },
          children: children, hasInheritedDrawContext: node.hasInheritedDrawContext,
          isTransient: node.isTransient))
    }
    return results[0]
  }
}

extension DrawCommand {
  fileprivate func rebasedForCapture(at origin: CellPoint) -> Self {
    enum Frame {
      case visit(DrawCommand)
      case clip(CellRect)
      case group(CellRect, Int)
    }
    var stack = [Frame.visit(self)]
    var results: [DrawCommand] = []
    while let frame = stack.popLast() {
      switch frame {
      case .clip(let bounds):
        let child = results.removeLast()
        results.append(.clip(bounds: bounds, child: child))
      case .group(let bounds, let count):
        let children = Array(results.suffix(count))
        results.removeLast(count)
        results.append(.group(bounds: bounds, children: children))
      case .visit(let command):
        func local(_ rect: CellRect) -> CellRect { rect.relative(to: origin) }
        switch command {
        case .group(let bounds, let children):
          stack.append(.group(local(bounds), children.count))
          for child in children.reversed() { stack.append(.visit(child)) }
        case .clip(let bounds, let child):
          stack.append(.clip(local(bounds)))
          stack.append(.visit(child))
        case .text(let b, let text, let style, let limit, let truncate, let wrap):
          results.append(
            .text(
              bounds: local(b), content: text, style: style, lineLimit: limit,
              truncationMode: truncate, wrappingStrategy: wrap))
        case .preformattedText(let b, let lines, let style):
          results.append(.preformattedText(bounds: local(b), lines: lines, style: style))
        case .styledPreformattedText(let b, let lines, let style):
          results.append(.styledPreformattedText(bounds: local(b), lines: lines, style: style))
        case .richText(let b, let payload, let limit, let truncate, let wrap):
          results.append(
            .richText(
              bounds: local(b), payload: payload, lineLimit: limit,
              truncationMode: truncate, wrappingStrategy: wrap))
        case .image(let b, let id, let payload):
          results.append(.image(bounds: local(b), identity: id, payload: payload))
        case .fill(let b, let geometry, let inset, let style, let mode):
          results.append(
            .fill(
              bounds: local(b), geometry: geometry, insetAmount: inset, style: style, mode: mode))
        case .stroke(
          let b, let geometry, let inset, let style, let stroke, let border, let background):
          results.append(
            .stroke(
              bounds: local(b), geometry: geometry, insetAmount: inset,
              style: style, strokeStyle: stroke, strokeBorder: border, backgroundStyle: background))
        case .rule(let b, let style, let stroke, let axis):
          results.append(
            .rule(bounds: local(b), style: style, strokeStyle: stroke, stackAxis: axis))
        case .border(let b, let stroke, let fg, let bg, let blend, let phase, let sides):
          results.append(
            .border(
              bounds: local(b), stroke: stroke, foreground: fg, background: bg,
              blend: blend, blendPhase: phase, sides: sides))
        case .canvas(let b, let payload, let fg):
          results.append(.canvas(bounds: local(b), payload: payload, foregroundStyle: fg))
        case .foreignSurface(let b, let payload):
          results.append(.foreignSurface(bounds: local(b), payload: payload))
        }
      }
    }
    return results[0]
  }
}
