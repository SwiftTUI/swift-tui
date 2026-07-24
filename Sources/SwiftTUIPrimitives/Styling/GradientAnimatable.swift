extension Gradient.Stop: Animatable {
  public typealias AnimatableData = AnimatablePair<Color.AnimatableData, Double>

  public var animatableData: AnimatableData {
    get { AnimatablePair(color.animatableData, location) }
    set {
      color.animatableData = newValue.first
      location = newValue.second
    }
  }
}

extension Gradient: Animatable {
  public typealias AnimatableData = AnimatableArray<Gradient.Stop.AnimatableData>

  public var animatableData: AnimatableData {
    get {
      AnimatableArray(stops.map { $0.animatableData })
    }
    set {
      // Count mismatch → caller should have checked isInterpolable
      // first.  If they didn't, clamp to the current stop count so
      // we never produce a half-rebuilt gradient.
      guard newValue.elements.count == stops.count else { return }
      for i in stops.indices {
        stops[i].animatableData = newValue.elements[i]
      }
    }
  }
}

extension LinearGradient: Animatable {
  /// The start and end points as a paired animatable unit.
  public typealias EndpointsData = AnimatablePair<
    UnitPoint.AnimatableData,
    UnitPoint.AnimatableData
  >

  public typealias AnimatableData = AnimatablePair<
    Gradient.AnimatableData,
    EndpointsData
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        gradient.animatableData,
        EndpointsData(startPoint.animatableData, endPoint.animatableData)
      )
    }
    set {
      gradient.animatableData = newValue.first
      startPoint.animatableData = newValue.second.first
      endPoint.animatableData = newValue.second.second
    }
  }
}

extension RadialGradient: Animatable {
  /// Start and end radius as a paired animatable unit.
  public typealias RadiiData = AnimatablePair<Double, Double>

  /// Center plus radii, grouped so the outer pair only has two
  /// elements (gradient + geometry) instead of three.
  public typealias GeometryData = AnimatablePair<
    UnitPoint.AnimatableData,
    RadiiData
  >

  public typealias AnimatableData = AnimatablePair<
    Gradient.AnimatableData,
    GeometryData
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        gradient.animatableData,
        GeometryData(
          center.animatableData,
          RadiiData(startRadius, endRadius)
        )
      )
    }
    set {
      gradient.animatableData = newValue.first
      center.animatableData = newValue.second.first
      startRadius = newValue.second.second.first
      endRadius = newValue.second.second.second
    }
  }
}

extension MeshGradient: Animatable {
  public typealias PointData = AnimatablePair<Double, Double>
  public typealias PointsData = AnimatableArray<PointData>
  public typealias ColorsData = AnimatableArray<Color.AnimatableData>
  public typealias ControlsData = AnimatablePair<PointsData, ColorsData>
  public typealias AnimatableData = AnimatablePair<ControlsData, Color.AnimatableData>

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        ControlsData(
          PointsData(points.map { PointData(Double($0.x), Double($0.y)) }),
          ColorsData(colors.map(\.animatableData))
        ),
        background.animatableData
      )
    }
    set {
      guard
        newValue.first.first.elements.count == points.count,
        newValue.first.second.elements.count == colors.count
      else {
        return
      }
      var newPoints = points
      var newColors = colors
      var newBackground = background
      for index in newPoints.indices {
        let point = newValue.first.first.elements[index]
        newPoints[index] = SIMD2<Float>(Float(point.first), Float(point.second))
      }
      for index in newColors.indices {
        newColors[index].animatableData = newValue.first.second.elements[index]
      }
      newBackground.animatableData = newValue.second
      replaceAnimatedValues(
        points: newPoints,
        colors: newColors,
        background: newBackground
      )
    }
  }

  package func isInterpolable(to other: MeshGradient) -> Bool {
    width == other.width
      && height == other.height
      && points.count == other.points.count
      && colors.count == other.colors.count
      && smoothsColors == other.smoothsColors
      && colorSpace == other.colorSpace
  }
}
