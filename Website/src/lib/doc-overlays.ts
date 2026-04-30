// Overlays that map raw /docs/*.md files into site-facing metadata.
//
// /docs/ files don't carry frontmatter today. Rather than retrofit frontmatter
// across the whole repo (which would touch every doc and make every change a
// rebase target), we declare site-facing metadata here in one place. When a
// doc graduates from "raw repo doc" to "first-class site essay" we'd add
// frontmatter inline and remove its overlay.

export interface DocOverlay {
  /** Site-facing display title. */
  title: string;
  /** One-line lede for cards and meta tags. */
  description: string;
  /** Which audience track this doc primarily serves. */
  audience: "user" | "collaborator" | "both";
  /** Which site section it surfaces in. */
  section:
    | "principles"
    | "design"
    | "policy"
    | "research"
    | "platforms"
    | "contribute"
    | "reference";
  /** Display ordering within section. */
  order: number;
  /** Display path under the site (e.g., "design/runtime"). */
  slug: string;
}

// Keys are the slugs Astro generates from /docs/*.md (lowercased basename).
// To update which docs appear on the site, edit this map.
export const docOverlays: Record<string, DocOverlay> = {
  // ─── Doctrine + reference (linked from /principles and /design/) ───
  vision: {
    title: "Vision",
    description: "Philosophy, scope, and the deviation rule.",
    audience: "both",
    section: "principles",
    order: 10,
    slug: "principles/vision",
  },
  terminal_native_doctrine: {
    title: "Terminal-Native Doctrine",
    description:
      "The 10 principles for reinterpreting SwiftUI as terminal-native.",
    audience: "both",
    section: "principles",
    order: 20,
    slug: "principles/doctrine",
  },
  status: {
    title: "Status",
    description: "Shipped surface, current constraints, and deferred work.",
    audience: "both",
    section: "reference",
    order: 10,
    slug: "reference/status",
  },
  architecture: {
    title: "Architecture",
    description: "Target boundaries and the seven-phase frame pipeline.",
    audience: "both",
    section: "design",
    order: 10,
    slug: "design/architecture",
  },
  runtime: {
    title: "Runtime",
    description:
      "Lifecycle, state, observation, and the incremental rendering model.",
    audience: "collaborator",
    section: "design",
    order: 20,
    slug: "design/runtime",
  },
  async_rendering: {
    title: "Async Rendering",
    description: "Frame-tail offload, ordered commit, sendable layout.",
    audience: "collaborator",
    section: "design",
    order: 30,
    slug: "design/async-rendering",
  },
  state_keying: {
    title: "State Keying",
    description: "How @State is keyed by identity-path and source location.",
    audience: "collaborator",
    section: "design",
    order: 40,
    slug: "design/state-keying",
  },
  focus: {
    title: "Focus",
    description: "Focus chain, focused values, and default-focus behavior.",
    audience: "both",
    section: "design",
    order: 50,
    slug: "design/focus",
  },

  // ─── Source layout (collaborator) ───
  source_layout: {
    title: "Source Layout",
    description: "Per-target ownership map across the package.",
    audience: "collaborator",
    section: "contribute",
    order: 30,
    slug: "contribute/source-layout",
  },

  // ─── Policy ───
  public_surface_policy: {
    title: "Public Surface Policy",
    description:
      "Guardrails for new public APIs, AnyView/AnyScene rules, structured concurrency.",
    audience: "collaborator",
    section: "policy",
    order: 10,
    slug: "policy/public-surface",
  },
  public_api_inventory: {
    title: "Public API Inventory",
    description:
      "Canonical public surface, removed surface, and package-only seams.",
    audience: "collaborator",
    section: "policy",
    order: 20,
    slug: "policy/api-inventory",
  },
  testing_and_fixture_policy: {
    title: "Testing & Fixture Policy",
    description:
      "Fixture rules, performance gates, architecture regression policy.",
    audience: "collaborator",
    section: "policy",
    order: 30,
    slug: "policy/testing",
  },

  // ─── Platforms ───
  host_packages: {
    title: "Host Packages",
    description: "Runner-package and embedded-host packaging model.",
    audience: "user",
    section: "platforms",
    order: 10,
    slug: "platforms/overview",
  },
  toolchains: {
    title: "Toolchains",
    description: "Swift, swiftly, wasm SDK, Bun, Xcode, and Android toolchains.",
    audience: "both",
    section: "contribute",
    order: 20,
    slug: "contribute/toolchains",
  },
  android: {
    title: "Android",
    description: "Cross-compilation notes for Android targets.",
    audience: "user",
    section: "platforms",
    order: 50,
    slug: "platforms/android",
  },

  // ─── Research / background ───
  swiftui_layout: {
    title: "SwiftUI Layout Model",
    description: "The upstream layout model TerminalUI targets.",
    audience: "collaborator",
    section: "research",
    order: 10,
    slug: "research/swiftui-layout",
  },
  lipgloss_swiftui_equivalents: {
    title: "Lip Gloss ↔ SwiftUI Equivalents",
    description:
      "How TUI concepts in Lip Gloss map onto SwiftUI-shaped APIs in TerminalUI.",
    audience: "collaborator",
    section: "research",
    order: 20,
    slug: "research/lipgloss-equivalents",
  },
  terminal_native_ui_research: {
    title: "Terminal-Native UI Research",
    description: "Cross-framework TUI practice survey feeding the doctrine.",
    audience: "collaborator",
    section: "research",
    order: 30,
    slug: "research/terminal-native-ui",
  },
  terminal_native_ux_research: {
    title: "Terminal-Native UX Research",
    description:
      "Cross-app workspace and discovery practice survey feeding the doctrine.",
    audience: "collaborator",
    section: "research",
    order: 40,
    slug: "research/terminal-native-ux",
  },
  cell_pixel_geometry_research: {
    title: "Cell, Pixel, and Geometry Research",
    description:
      "Why TerminalUI exposes pixel-level geometry on a cell-based API.",
    audience: "collaborator",
    section: "research",
    order: 50,
    slug: "research/cell-pixel-geometry",
  },
};

/** Keys not in this list will not be rendered on the site. */
export const publishedDocIds = new Set(Object.keys(docOverlays));

export function findOverlayByDocId(id: string): DocOverlay | undefined {
  return docOverlays[id];
}

export function findOverlayBySlug(slug: string): DocOverlay | undefined {
  return Object.values(docOverlays).find((overlay) => overlay.slug === slug);
}
