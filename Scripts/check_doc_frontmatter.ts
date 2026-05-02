#!/usr/bin/env bun
/*
 * check_doc_frontmatter.ts
 *
 * Validates YAML frontmatter on the curated subsets of docs/ that previously
 * had Zod schemas in Website/src/content.config.ts. Run from prek.
 *
 * Targets:
 *   - docs/decisions/[0-9]*.md  (ADRs)
 *   - docs/plans/**\/*.md       (date-stamped implementation plans)
 *
 * docs/proposals/ and top-level docs/*.md never had required schemas, so
 * they're intentionally not validated here.
 */

import { Glob } from "bun";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dir, "..");

type Issue = { file: string; problem: string };

function extractFrontmatter(source: string): string | null {
  if (!source.startsWith("---\n") && !source.startsWith("---\r\n")) return null;
  const closer = source.indexOf("\n---", 4);
  if (closer === -1) return null;
  return source.slice(4, closer);
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isParseableDate(value: unknown): boolean {
  if (value instanceof Date) return !Number.isNaN(value.valueOf());
  if (typeof value !== "string") return false;
  const parsed = new Date(value);
  return !Number.isNaN(parsed.valueOf());
}

function checkEnum(
  field: string,
  value: unknown,
  allowed: ReadonlyArray<string>,
): string | null {
  if (typeof value !== "string") return `${field}: expected string`;
  if (!allowed.includes(value)) {
    return `${field}: ${JSON.stringify(value)} not in [${allowed.join(", ")}]`;
  }
  return null;
}

function checkRequiredString(field: string, value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) {
    return `${field}: required, expected non-empty string`;
  }
  return null;
}

function validateDecision(data: unknown): string[] {
  const problems: string[] = [];
  if (!isPlainObject(data)) return ["frontmatter must be a YAML mapping"];

  const adrError = checkRequiredString("adr", data.adr);
  if (adrError) problems.push(adrError);

  const titleError = checkRequiredString("title", data.title);
  if (titleError) problems.push(titleError);

  const statusError = checkEnum("status", data.status, [
    "proposed",
    "accepted",
    "superseded",
    "reverted",
  ]);
  if (statusError) problems.push(statusError);

  if (!isParseableDate(data.date)) {
    problems.push("date: required, must be parseable as a date");
  }

  if (data.sources !== undefined) {
    if (
      !Array.isArray(data.sources) ||
      data.sources.some((entry) => typeof entry !== "string")
    ) {
      problems.push("sources: expected array of strings when present");
    }
  }

  return problems;
}

function validatePlan(data: unknown): string[] {
  const problems: string[] = [];
  if (!isPlainObject(data)) return ["frontmatter must be a YAML mapping"];

  const titleError = checkRequiredString("title", data.title);
  if (titleError) problems.push(titleError);

  const typeError = checkEnum("type", data.type, [
    "feature",
    "refactor",
    "fix",
    "docs",
    "test",
    "chore",
  ]);
  if (typeError) problems.push(typeError);

  const statusError = checkEnum("status", data.status, [
    "active",
    "design-approved",
    "shipped",
    "reverted",
  ]);
  if (statusError) problems.push(statusError);

  if (!isParseableDate(data.date)) {
    problems.push("date: required, must be parseable as a date");
  }

  if (data.proposal !== undefined && typeof data.proposal !== "string") {
    problems.push("proposal: expected string when present");
  }

  return problems;
}

async function validateFile(
  relPath: string,
  validate: (data: unknown) => string[],
): Promise<Issue[]> {
  const fullPath = resolve(repoRoot, relPath);
  const source = await Bun.file(fullPath).text();
  const fm = extractFrontmatter(source);
  if (fm === null) {
    return [{ file: relPath, problem: "missing YAML frontmatter delimiters" }];
  }

  let data: unknown;
  try {
    data = Bun.YAML.parse(fm);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return [{ file: relPath, problem: `unparseable YAML: ${message}` }];
  }

  return validate(data).map((problem) => ({ file: relPath, problem }));
}

async function collectMatches(
  baseDir: string,
  pattern: string,
): Promise<string[]> {
  const glob = new Glob(pattern);
  const matches: string[] = [];
  for await (const match of glob.scan({ cwd: resolve(repoRoot, baseDir) })) {
    matches.push(`${baseDir}/${match}`);
  }
  return matches.sort();
}

const decisionFiles = (await collectMatches("docs/decisions", "[0-9]*.md"));
const planFiles = (await collectMatches("docs/plans", "**/*.md"));

const issues: Issue[] = [];

for (const file of decisionFiles) {
  issues.push(...(await validateFile(file, validateDecision)));
}
for (const file of planFiles) {
  issues.push(...(await validateFile(file, validatePlan)));
}

if (issues.length > 0) {
  console.error(
    `[check_doc_frontmatter] ${issues.length} frontmatter issue(s):`,
  );
  for (const { file, problem } of issues) {
    console.error(`  ${file}: ${problem}`);
  }
  process.exit(1);
}

console.log(
  `[check_doc_frontmatter] ok — ${decisionFiles.length} ADR(s), ${planFiles.length} plan(s) validated`,
);
