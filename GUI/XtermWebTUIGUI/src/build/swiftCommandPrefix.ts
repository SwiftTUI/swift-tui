export function swiftCommandPrefix(): string[] {
  if (Bun.which("swiftly")) {
    return ["swiftly", "run", "swift"];
  }

  return ["swift"];
}
