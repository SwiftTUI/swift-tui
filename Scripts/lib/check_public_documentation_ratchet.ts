#!/usr/bin/env bun

type ManifestEntry = {
  description: string;
  path: string;
  pattern: RegExp;
};

function usage(): never {
  console.error(
    "Usage: Scripts/lib/check_public_documentation_ratchet.ts --manifest <path>"
  );
  process.exit(2);
}

let manifestPath: string | undefined;
for (let index = 2; index < process.argv.length; index += 1) {
  const arg = process.argv[index];
  if (arg === "--manifest") {
    manifestPath = process.argv[index + 1];
    index += 1;
    continue;
  }
  usage();
}

if (!manifestPath) {
  usage();
}

const manifestText = await Bun.file(manifestPath).text();
const entries: ManifestEntry[] = [];

for (const [index, rawLine] of manifestText.split(/\r?\n/).entries()) {
  const line = rawLine.trim();
  if (!line || line.startsWith("#")) {
    continue;
  }

  const pieces = rawLine.split("|");
  if (pieces.length !== 3) {
    console.error(`${manifestPath}:${index + 1}: expected description|path|regex`);
    process.exit(2);
  }

  const [description, path, pattern] = pieces.map((piece) => piece.trim());
  entries.push({
    description,
    path,
    pattern: new RegExp(pattern),
  });
}

function hasDocumentation(lines: string[], declarationLineIndex: number): boolean {
  for (let cursor = declarationLineIndex - 1; cursor >= 0; cursor -= 1) {
    const trimmed = lines[cursor].trim();
    if (
      trimmed === "" ||
      trimmed.startsWith("@") ||
      trimmed.startsWith("#if") ||
      trimmed.startsWith("#elseif") ||
      trimmed.startsWith("#else") ||
      trimmed.startsWith("#endif")
    ) {
      continue;
    }

    if (trimmed.startsWith("///")) {
      return true;
    }

    if (trimmed.endsWith("*/")) {
      for (let blockCursor = cursor; blockCursor >= 0; blockCursor -= 1) {
        if (lines[blockCursor].trim().startsWith("/**")) {
          return true;
        }
      }
    }

    return false;
  }

  return false;
}

let failures = 0;

for (const entry of entries) {
  const sourceFile = Bun.file(entry.path);
  if (!(await sourceFile.exists())) {
    console.error(`Missing source for documentation ratchet entry: ${entry.path}`);
    failures += 1;
    continue;
  }

  const lines = (await sourceFile.text()).split(/\r?\n/);
  const matches = lines
    .map((line, index) => ({ line, index }))
    .filter(({ line }) => entry.pattern.test(line));

  if (matches.length === 0) {
    console.error(`Missing declaration for documentation ratchet entry: ${entry.description}`);
    console.error(`  ${entry.path}`);
    console.error(`  /${entry.pattern.source}/`);
    failures += 1;
    continue;
  }

  for (const match of matches) {
    if (!hasDocumentation(lines, match.index)) {
      console.error(
        `${entry.path}:${match.index + 1}: missing documentation for ${entry.description}`
      );
      console.error(`  ${match.line.trim()}`);
      failures += 1;
    }
  }
}

if (failures > 0) {
  console.error(
    `Public documentation ratchet failed with ${failures} missing or stale entry.` +
      " Add a focused /// summary or update Scripts/lib/public_documentation_ratchet.txt."
  );
  process.exit(1);
}

console.error(`[check_public_documentation_ratchet] ok - ${entries.length} entries`);
