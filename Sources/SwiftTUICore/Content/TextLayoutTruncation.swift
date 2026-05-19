func truncating(
  _ line: TextLayoutLine,
  to width: Int?,
  mode: TextTruncationMode,
  forceIndicator: Bool
) -> TextLayoutLine {
  guard forceIndicator, let width else {
    return line
  }

  guard width > 0 else {
    return .init()
  }

  let ellipsis = TextCluster(character: "…", cellWidth: 1)
  if width == 1 {
    return .init(clusters: [ellipsis])
  }

  let availableWidth = width - ellipsis.cellWidth
  if availableWidth <= 0 {
    return .init(clusters: [ellipsis])
  }

  switch mode {
  case .tail:
    return .init(
      clusters: fittingLeadingClusters(in: line.clusters, width: availableWidth) + [ellipsis])
  case .head:
    return .init(
      clusters: [ellipsis] + fittingTrailingClusters(in: line.clusters, width: availableWidth))
  case .middle:
    let leadingWidth = availableWidth / 2
    let trailingWidth = availableWidth - leadingWidth
    return .init(
      clusters: fittingLeadingClusters(in: line.clusters, width: leadingWidth)
        + [ellipsis]
        + fittingTrailingClusters(in: line.clusters, width: trailingWidth)
    )
  }
}

private func fittingLeadingClusters(
  in clusters: [TextCluster],
  width: Int
) -> [TextCluster] {
  guard width > 0 else {
    return []
  }

  var result: [TextCluster] = []
  var usedWidth = 0
  for cluster in clusters {
    guard usedWidth + cluster.cellWidth <= width else {
      break
    }
    result.append(cluster)
    usedWidth += cluster.cellWidth
  }
  return result
}

private func fittingTrailingClusters(
  in clusters: [TextCluster],
  width: Int
) -> [TextCluster] {
  guard width > 0 else {
    return []
  }

  var result: [TextCluster] = []
  var usedWidth = 0
  for cluster in clusters.reversed() {
    guard usedWidth + cluster.cellWidth <= width else {
      break
    }
    result.append(cluster)
    usedWidth += cluster.cellWidth
  }
  return result.reversed()
}
