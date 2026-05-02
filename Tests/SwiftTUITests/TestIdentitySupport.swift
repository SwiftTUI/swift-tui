import Core

func testIdentity(_ components: String...) -> Identity {
  Identity(components: components)
}

func testRoute(
  _ components: String...,
  kind: RouteKind = .primary
) -> RouteID {
  RouteID(identity: Identity(components: components), kind: kind)
}
