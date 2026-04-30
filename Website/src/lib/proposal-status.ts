// Proposal curation map.
//
// /docs/proposals/ is a mixed bag — partly active, mostly archive. The site
// publishes only what is genuinely shaping decisions today. Everything else
// stays in the repo as historical record but is not rendered.
//
// To publish a new proposal: add an entry below.
// To retire a proposal: remove its entry. The repo file stays.

export type ProposalStatus =
  | "active"
  | "shipped-record"
  | "post-mortem"
  | "superseded";

export interface ProposalEntry {
  /** Display title used on the index card and detail header. */
  title: string;
  /** One-line lede shown on the proposals index card. */
  summary: string;
  /** Curation status. Only "active" is shown on /proposals. */
  status: ProposalStatus;
  /** Optional ordering hint within /proposals. */
  order?: number;
}

// Keys are the slugs Astro generates from /docs/proposals/**/*.md (lowercased
// path relative to the proposals base, with `.md` stripped). For example:
//   docs/proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md
//     → key "async_render_generation_scheduler"
//   docs/proposals/layout/BEHAVIOUR_FINDINGS.md
//     → key "layout/behaviour_findings"
export const proposalEntries: Record<string, ProposalEntry> = {
  async_render_generation_scheduler: {
    title: "Async render-generation scheduler",
    summary:
      "Pre-start frame-tail cancellation design — what frame-head abort needs before it can land.",
    status: "active",
    order: 10,
  },
  type_erasure_deferral_plan: {
    title: "Type-erasure deferral plan",
    summary:
      "Reducing AnyView to a true escape hatch — what's left to do, what's intentional.",
    status: "active",
    order: 20,
  },
  "layout/behaviour_findings": {
    title: "Layout behaviour findings",
    summary:
      "Continually appended record of \"spec said X, library does Y\" findings from the layouts example.",
    status: "active",
    order: 40,
  },
};

/** Slugs that should appear on the public /proposals index. */
export function activeProposalSlugs(): string[] {
  return Object.entries(proposalEntries)
    .filter(([, entry]) => entry.status === "active")
    .sort(([, a], [, b]) => (a.order ?? 100) - (b.order ?? 100))
    .map(([slug]) => slug);
}
