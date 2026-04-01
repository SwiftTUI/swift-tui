import { expect, mock, test } from "bun:test";

mock.module("ghostty-web", () => ({
  init: async () => {},
  Terminal: class {},
  FitAddon: class {},
}));

const { createWebTUIApp } = await import("./WebTUIApp.ts");

import type { WebTUIAppOptions } from "./WebTUIApp.ts";
import type {
  ResolvedWebTUITerminalStyle,
  WebTUIColorScheme,
  WebTUITerminalStyle,
} from "./WebTUITerminalStyle.ts";
import type { WebTUISceneRuntimeOptions } from "./WebTUISceneRuntime.ts";

class FakeRuntime {
  readonly descriptorId: string;
  mountCount = 0;
  visible = false;
  styleUpdates: Array<{
    style: WebTUITerminalStyle | ResolvedWebTUITerminalStyle;
    colorScheme: WebTUIColorScheme;
  }> = [];
  disposed = false;

  constructor(descriptorId: string) {
    this.descriptorId = descriptorId;
  }

  async mount(): Promise<void> {
    this.mountCount += 1;
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
  }

  setStyleAndScheme(
    style: WebTUITerminalStyle | ResolvedWebTUITerminalStyle,
    colorScheme: WebTUIColorScheme
  ): void {
    this.styleUpdates.push({ style, colorScheme });
  }

  resize(_columns: number, _rows: number): void {}

  writeOutput(_text: string): void {}

  sendInput(_chunk: Uint8Array): void {}

  dispose(): void {
    this.disposed = true;
  }
}

test("app controller switches scenes and propagates style variants", async () => {
  const runtimes = new Map<string, FakeRuntime>();
  const seenRuntimeOptions = new Map<string, WebTUISceneRuntimeOptions>();
  const mount = makeElement("div");
  const options: WebTUIAppOptions = {
    mount: mount as unknown as HTMLElement,
    manifest: {
      defaultSceneId: "dashboard",
      scenes: [
        { id: "dashboard", title: "Dashboard", isDefault: true },
        { id: "controls", title: "Controls", isDefault: false },
      ],
    },
    style: {
      colorSchemeMode: "dark",
      dark: {
        theme: {
          foreground: "#111111",
          background: "#f0f0f0",
          tint: "#0057b8",
          separator: "#cccccc",
          selection: "#ddeeff",
          placeholder: "#666666",
          link: "#0057b8",
          fill: "#f7f7f7",
          windowBackground: "#ffffff",
          success: "#1a7f37",
          warning: "#9a6700",
          danger: "#cf222e",
          info: "#0969da",
          muted: "#57606a",
        },
      },
    },
    createElement: (tagName: string) => makeElement(tagName) as unknown as HTMLElement,
    sceneRuntimeFactory: (options: WebTUISceneRuntimeOptions) => {
      const runtime = new FakeRuntime(options.descriptor.id);
      runtimes.set(options.descriptor.id, runtime);
      seenRuntimeOptions.set(options.descriptor.id, options);
      return runtime as unknown as never;
    },
  };

  const controller = await createWebTUIApp(options);
  const dashboardRuntime = runtimes.get("dashboard");
  const dashboardOptions = seenRuntimeOptions.get("dashboard");

  expect(controller.selectedSceneId).toBe("dashboard");
  expect(dashboardOptions?.colorScheme).toBe("dark");
  expect(dashboardRuntime?.visible).toBe(true);
  expect(dashboardRuntime?.mountCount).toBe(1);

  await controller.switchScene("controls");
  const controlsRuntime = runtimes.get("controls");

  expect(controller.selectedSceneId).toBe("controls");
  expect(dashboardRuntime?.visible).toBe(false);
  expect(controlsRuntime?.visible).toBe(true);
  expect(controlsRuntime?.mountCount).toBe(1);

  await controller.switchScene("dashboard");
  expect(runtimes.get("dashboard")).toBe(dashboardRuntime);
  expect(dashboardRuntime?.mountCount).toBe(1);

  controller.setStyle({
    colorSchemeMode: "light",
    cursorBlink: true,
  });

  expect(dashboardRuntime?.styleUpdates.at(-1)?.colorScheme).toBe("light");
  expect(controlsRuntime?.styleUpdates.at(-1)?.colorScheme).toBe("light");
  expect(dashboardRuntime?.styleUpdates.at(-1)?.style.cursorBlink).toBe(true);

  await controller.dispose();
  expect(dashboardRuntime?.disposed).toBe(true);
  expect(controlsRuntime?.disposed).toBe(true);
});

function makeElement(
  tagName: string
): Record<string, unknown> {
  return {
    tagName,
    className: "",
    dataset: {},
    hidden: false,
    style: {},
    replaceChildren: () => {},
    appendChild: () => {},
    remove: () => {},
    hasAttribute: () => false,
    setAttribute: () => {},
  };
}
