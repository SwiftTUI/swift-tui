import { expect, test } from "bun:test";

import { createWebTUIApp, type WebTUIAppOptions } from "./WebTUIApp.ts";
import type { WebTUITerminalStyle } from "./WebTUITerminalStyle.ts";
import type { WebTUISceneRuntimeOptions } from "./WebTUISceneRuntime.ts";

class FakeRuntime {
  readonly descriptorId: string;
  mountCount = 0;
  visible = false;
  styleUpdates: WebTUITerminalStyle[] = [];
  disposed = false;

  constructor(
    descriptorId: string
  ) {
    this.descriptorId = descriptorId;
  }

  async mount(): Promise<void> {
    this.mountCount += 1;
  }

  setVisible(
    visible: boolean
  ): void {
    this.visible = visible;
  }

  setStyle(
    style: WebTUITerminalStyle
  ): void {
    this.styleUpdates.push(style);
  }

  resize(
    _columns: number,
    _rows: number
  ): void {}

  writeOutput(
    _text: string
  ): void {}

  sendInput(
    _chunk: Uint8Array
  ): void {}

  dispose(): void {
    this.disposed = true;
  }
}

test("app controller switches scenes without recreating retained runtimes", async () => {
  const runtimes = new Map<string, FakeRuntime>();
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
      fontSize: 13,
    },
    createElement: (tagName: string) => makeElement(tagName) as unknown as HTMLElement,
    sceneRuntimeFactory: (runtimeOptions: WebTUISceneRuntimeOptions) => {
      const runtime = new FakeRuntime(runtimeOptions.descriptor.id);
      runtimes.set(runtimeOptions.descriptor.id, runtime);
      return runtime as unknown as WebTUISceneRuntime;
    },
  };

  const controller = await createWebTUIApp(options);
  const dashboardRuntime = runtimes.get("dashboard");

  expect(controller.selectedSceneId).toBe("dashboard");
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
