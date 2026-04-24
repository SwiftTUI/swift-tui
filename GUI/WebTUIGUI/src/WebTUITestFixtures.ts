import { readFileSync } from "node:fs";

export function transportFixture(
  basename: string
): string {
  return readFileSync(
    new URL(`../../../Fixtures/Transport/${basename}.txt`, import.meta.url),
    "utf8"
  ).replaceAll("\\u001E", "\u001E");
}
