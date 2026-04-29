// Astro 6 content collections.
//
// The Website's central design rule: site narrative is sourced FROM the repo's
// canonical /docs/ markdown files. The site never duplicates them. When a
// /docs/ file is updated, the next build re-renders.
//
// Each curated site essay names which /docs/ source it pulls from in its
// frontmatter and overlays a site-facing slug, audience tag, and ordering hint.
// Site-native pages (landing, principles, start) live as .astro files under
// src/pages/.
import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

// /docs/*.md — top-level reference, doctrine, and policy.
//
// Note: glob's `base` is relative to the Astro project root (Website/), so
// "../docs" reaches up out of Website into the repo's docs/ tree.
const docs = defineCollection({
  loader: glob({
    pattern: "*.md",
    base: "../docs",
    // Only include files we want to publish. The /docs/README.md is an
    // internal index; we render our own.
    generateId: ({ entry }) => entry.replace(/\.md$/, "").toLowerCase(),
  }),
  schema: z.object({
    // /docs/ files don't currently use frontmatter. The site adds it via
    // overlay (see src/lib/doc-overlays.ts). Keep this schema permissive.
    title: z.string().optional(),
    description: z.string().optional(),
  }).passthrough(),
});

// /docs/plans/**/*.md — date-stamped implementation plans.
// All plans currently carry frontmatter with title/type/status/date keys.
// The site renders them at /changelog grouped by status.
const plans = defineCollection({
  loader: glob({
    pattern: "**/*.md",
    base: "../docs/plans",
    generateId: ({ entry }) => entry.replace(/\.md$/, "").toLowerCase(),
  }),
  schema: z.object({
    title: z.string(),
    type: z.enum(["feature", "refactor", "fix", "docs", "test", "chore"]),
    status: z.enum(["active", "design-approved", "shipped", "reverted"]),
    date: z.coerce.date(),
    proposal: z.string().optional(),
  }).passthrough(),
});

// /docs/proposals/**/*.md — design proposals.
//
// These files don't carry frontmatter today; we render only the curated
// active subset on /proposals (defined by the activeProposals list in
// src/lib/proposal-status.ts). Archive proposals stay in the repo but are
// not published.
const proposals = defineCollection({
  loader: glob({
    pattern: "**/*.md",
    base: "../docs/proposals",
    generateId: ({ entry }) => entry.replace(/\.md$/, "").toLowerCase(),
  }),
  // No schema — proposal content varies wildly by author and era.
  schema: z.object({}).passthrough(),
});

// Site-native essays that genuinely live in the Website (not /docs/).
// Examples: tutorials, decisions (ADRs), curated component pages.
const essays = defineCollection({
  loader: glob({
    pattern: "**/*.{md,mdx}",
    base: "./src/content/essays",
  }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    audience: z.enum(["user", "collaborator", "both"]),
    section: z.enum([
      "learn",
      "design",
      "decisions",
      "policy",
      "contribute",
      "research",
      "platforms",
      "components",
    ]),
    order: z.number().default(100),
    sources: z.array(z.string()).optional(),
    lastReviewed: z.coerce.date().optional(),
  }),
});

export const collections = { docs, plans, proposals, essays };
