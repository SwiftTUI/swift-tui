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
