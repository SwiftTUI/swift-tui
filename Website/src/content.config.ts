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

// Site-native essays that genuinely live in the Website (not /docs/).
//
// /docs/proposals/ and /docs/plans/ collections will be wired in when we
// build /proposals/ and /changelog pages. They are intentionally absent
// today — the proposals folder is partly archive, and a few plan files
// carry frontmatter with unquoted colons that need cleaning before they
// pass YAML validation. Those fixes belong in their own PRs.
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

export const collections = { docs, essays };
