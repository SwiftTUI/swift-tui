import type {
  WebHostAccessibilityAnnouncement,
  WebHostAccessibilityNode,
} from "./WebHostSurfaceTransport.ts";

interface AccessibilityTreeMetrics {
  cellWidth: number;
  cellHeight: number;
}

interface RoleMapping {
  role?: string;
  level?: number;
}

export class AccessibilityTreeMounter {
  readonly element: HTMLElement;
  readonly announcerElement: HTMLElement;

  private readonly nodesById = new Map<string, HTMLElement>();
  private previousLabelsById = new Map<string, string>();
  private hasLiveRegionBaseline = false;

  constructor() {
    this.element = document.createElement("div");
    this.element.className = "webhost-scene__accessibility-tree";
    applyScreenReaderOnlyStyle(this.element);

    this.announcerElement = document.createElement("div");
    this.announcerElement.className = "webhost-scene__accessibility-announcer";
    this.announcerElement.setAttribute("aria-atomic", "true");
    applyScreenReaderOnlyStyle(this.announcerElement);
  }

  present(
    nodes: WebHostAccessibilityNode[],
    metrics: AccessibilityTreeMetrics,
    announcements: WebHostAccessibilityAnnouncement[] = []
  ): void {
    this.element.replaceChildren();
    this.nodesById.clear();

    for (const node of nodes) {
      const element = this.elementForNode(node, metrics);
      this.nodesById.set(node.id, element);
    }

    for (const node of nodes) {
      const element = this.nodesById.get(node.id);
      if (!element) {
        continue;
      }

      const parent = node.parentId ? this.nodesById.get(node.parentId) : undefined;
      (parent ?? this.element).appendChild(element);
    }

    this.announceLiveRegionChanges(nodes, announcements);

    const focused = nodes.find((node) => node.isFocused);
    if (focused) {
      this.nodesById.get(focused.id)?.focus?.();
    }
  }

  private elementForNode(
    node: WebHostAccessibilityNode,
    metrics: AccessibilityTreeMetrics
  ): HTMLElement {
    const element = document.createElement("div");
    element.id = `swifttui-a11y-${stableDOMId(node.id)}`;
    element.dataset.accessibilityId = node.id;
    element.tabIndex = node.isFocused ? 0 : -1;

    const role = roleMapping(node.role);
    if (role.role) {
      element.setAttribute("role", role.role);
    }
    if (role.level !== undefined) {
      element.setAttribute("aria-level", String(role.level));
    }
    if (node.label) {
      element.setAttribute("aria-label", node.label);
    }
    if (node.hint) {
      element.setAttribute("aria-description", node.hint);
    }
    if (node.liveRegion) {
      element.setAttribute("aria-live", node.liveRegion);
    }
    if (node.isFocused) {
      element.dataset.focused = "true";
    }

    const [x, y, width, height] = node.rect;
    element.style.position = "absolute";
    element.style.left = `${x * metrics.cellWidth}px`;
    element.style.top = `${y * metrics.cellHeight}px`;
    element.style.width = `${Math.max(1, width) * metrics.cellWidth}px`;
    element.style.height = `${Math.max(1, height) * metrics.cellHeight}px`;

    return element;
  }

  private announceLiveRegionChanges(
    nodes: WebHostAccessibilityNode[],
    announcements: WebHostAccessibilityAnnouncement[]
  ): void {
    const candidates = nodes.filter(
      (node) => node.liveRegion && node.liveRegion !== "off" && node.label
    );
    const currentLabelsById = new Map(candidates.map((node) => [node.id, node.label ?? ""]));
    const imperativeAssertive = announcements.filter(
      (announcement) => announcement.politeness === "assertive"
    );
    const imperativePolite = announcements.filter(
      (announcement) => announcement.politeness === "polite"
    );

    if (!this.hasLiveRegionBaseline) {
      this.previousLabelsById = currentLabelsById;
      this.hasLiveRegionBaseline = true;
      this.publishAnnouncements([], imperativeAssertive, [], imperativePolite);
      return;
    }

    const changed = candidates.filter((node) => {
      const previous = this.previousLabelsById.get(node.id);
      return previous !== undefined && previous !== node.label;
    });
    this.previousLabelsById = currentLabelsById;

    const assertive = changed.filter((node) => node.liveRegion === "assertive");
    const polite = changed.filter((node) => node.liveRegion === "polite");
    this.publishAnnouncements(assertive, imperativeAssertive, polite, imperativePolite);
  }

  private publishAnnouncements(
    assertive: WebHostAccessibilityNode[],
    imperativeAssertive: WebHostAccessibilityAnnouncement[],
    polite: WebHostAccessibilityNode[],
    imperativePolite: WebHostAccessibilityAnnouncement[]
  ): void {
    const ordered = [...assertive, ...imperativeAssertive, ...polite, ...imperativePolite];
    if (ordered.length === 0) {
      return;
    }

    const politeness = assertive.length > 0 || imperativeAssertive.length > 0
      ? "assertive"
      : "polite";
    this.announcerElement.setAttribute("aria-live", politeness);
    this.announcerElement.textContent = ordered.map((entry) => {
      if ("message" in entry) {
        return entry.message;
      }
      return entry.label ?? "";
    }).join("\n");
  }
}

function applyScreenReaderOnlyStyle(
  element: HTMLElement
): void {
  element.style.position = "absolute";
  element.style.left = "0";
  element.style.top = "0";
  element.style.width = "1px";
  element.style.height = "1px";
  element.style.overflow = "hidden";
  element.style.clipPath = "inset(50%)";
  element.style.whiteSpace = "nowrap";
}

function roleMapping(
  role: string
): RoleMapping {
  const heading = /^heading\(level: ([0-9]+)\)$/.exec(role);
  if (heading) {
    return {
      role: "heading",
      level: Math.max(1, Math.min(6, Number(heading[1]))),
    };
  }

  const custom = /^custom\((.+)\)$/.exec(role);
  if (custom) {
    return { role: custom[1] };
  }

  switch (role) {
  case "alert":
  case "button":
  case "cell":
  case "checkbox":
  case "grid":
  case "group":
  case "link":
  case "list":
  case "menu":
  case "region":
  case "separator":
  case "slider":
  case "status":
  case "tab":
  case "table":
  case "timer":
    return { role };
  case "columnHeader":
    return { role: "columnheader" };
  case "confirmationDialog":
  case "sheet":
    return { role: "dialog" };
  case "disclosureGroup":
  case "scrollView":
  case "scrollViewWithIndicators":
  case "section":
    return { role: "region" };
  case "image":
    return { role: "img" };
  case "menuItem":
    return { role: "menuitem" };
  case "picker":
    return { role: "combobox" };
  case "progressBar":
    return { role: "progressbar" };
  case "rowHeader":
    return { role: "rowheader" };
  case "secureField":
  case "textEditor":
  case "textField":
    return { role: "textbox" };
  case "stepper":
    return { role: "spinbutton" };
  case "tabPanel":
    return { role: "tabpanel" };
  case "tableRow":
    return { role: "row" };
  case "tabView":
    return { role: "tablist" };
  case "toggle":
    return { role: "checkbox" };
  default:
    return { role: "group" };
  }
}

function stableDOMId(
  id: string
): string {
  return Array.from(id).map((character) => {
    if (/^[a-zA-Z0-9_-]$/.test(character)) {
      return character;
    }
    return `-${character.codePointAt(0)?.toString(16) ?? "0"}-`;
  }).join("");
}
