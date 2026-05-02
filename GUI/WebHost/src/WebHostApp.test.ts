import { expect, test } from "bun:test";

import { createWebHostApp, type WebHostAppOptions } from "./WebHostApp.ts";
import type {
  ResolvedWebHostTerminalStyle,
  WebHostTerminalStyle,
} from "./WebHostTerminalStyle.ts";
import type { WebHostSceneRuntimeOptions } from "./WebHostSceneRuntime.ts";

class FakeRuntime {
  readonly descriptorId: string;
  mountCount = 0;
  visible = false;
  styleUpdates: Array<WebHostTerminalStyle | ResolvedWebHostTerminalStyle> = [];
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

  setStyle(
    style: WebHostTerminalStyle | ResolvedWebHostTerminalStyle
  ): void {
    this.styleUpdates.push(style);
  }

  resize(_columns: number, _rows: number): void {}

  writeOutput(_text: string): void {}

  sendInput(_chunk: Uint8Array): void {}

  dispose(): void {
    this.disposed = true;
  }
}

test("app controller switches scenes and propagates active styles", async () => {
  const runtimes = new Map<string, FakeRuntime>();
  const seenRuntimeOptions = new Map<string, WebHostSceneRuntimeOptions>();
  const mount = makeElement("div");
  const options: WebHostAppOptions = {
    mount: mount as unknown as HTMLElement,
    manifest: {
      defaultSceneId: "dashboard",
      scenes: [
        { id: "dashboard", title: "Dashboard", isDefault: true },
        { id: "controls", title: "Controls", isDefault: false },
      ],
    },
    style: {
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
    createElement: (tagName: string) => makeElement(tagName) as unknown as HTMLElement,
    sceneRuntimeFactory: (runtimeOptions: WebHostSceneRuntimeOptions) => {
      const runtime = new FakeRuntime(runtimeOptions.descriptor.id);
      runtimes.set(runtimeOptions.descriptor.id, runtime);
      seenRuntimeOptions.set(runtimeOptions.descriptor.id, runtimeOptions);
      return runtime as unknown as never;
    },
  };

  const controller = await createWebHostApp(options);
  const dashboardRuntime = runtimes.get("dashboard");
  const dashboardOptions = seenRuntimeOptions.get("dashboard");

  expect(controller.selectedSceneId).toBe("dashboard");
  expect(dashboardOptions?.style.theme?.background).toBe("#f0f0f0");
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
    cursorBlink: true,
  });

  expect(dashboardRuntime?.styleUpdates.at(-1)?.cursorBlink).toBe(true);
  expect(controlsRuntime?.styleUpdates.at(-1)?.cursorBlink).toBe(true);

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
