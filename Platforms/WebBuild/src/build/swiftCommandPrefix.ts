import { findExecutable } from "./runCommand.ts";

export function swiftCommandPrefix(): string[] {
  if (findExecutable("swiftly")) {
    return ["swiftly", "run", "swift"];
  }

  return ["swift"];
}
