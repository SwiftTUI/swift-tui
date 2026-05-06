import { expect, test } from "bun:test";
import { chromium } from "playwright";

import { serveBuiltWebExample } from "./built-app-server.ts";

test("WebExample renders WASI surface frames into a nonblank canvas", async () => {
  const server = serveBuiltWebExample();
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: {
      width: 1280,
      height: 900,
    },
  });
  const runtimeErrors: string[] = [];

  page.on("pageerror", (error) => {
    runtimeErrors.push(error.message);
  });
  page.on("console", (message) => {
    if (message.type() === "error") {
      runtimeErrors.push(message.text());
    }
  });

  try {
    await page.goto(server.url.href, { waitUntil: "domcontentloaded" });
    await page.waitForFunction(() => globalThis.crossOriginIsolated === true, undefined, {
      timeout: 10_000,
    });
    await page.waitForSelector(".webhost-scene__surface", {
      state: "attached",
      timeout: 30_000,
    });
    const canvasState = await page.waitForFunction(() => {
      const canvas = document.querySelector(".webhost-scene__surface");
      if (!(canvas instanceof HTMLCanvasElement)) {
        return false;
      }
      if (canvas.width <= 0 || canvas.height <= 0) {
        return false;
      }

      const context = canvas.getContext("2d", { willReadFrequently: true });
      if (!context) {
        return false;
      }

      const width = Math.min(canvas.width, 240);
      const height = Math.min(canvas.height, 180);
      const pixels = context.getImageData(0, 0, width, height).data;
      let firstPixel: string | undefined;
      let opaqueSamples = 0;
      let differingSamples = 0;

      for (let index = 0; index < pixels.length; index += 16) {
        const red = pixels[index] ?? 0;
        const green = pixels[index + 1] ?? 0;
        const blue = pixels[index + 2] ?? 0;
        const alpha = pixels[index + 3] ?? 0;
        if (alpha === 0) {
          continue;
        }

        opaqueSamples += 1;
        const pixel = `${red}:${green}:${blue}:${alpha}`;
        if (firstPixel === undefined) {
          firstPixel = pixel;
        } else if (pixel !== firstPixel) {
          differingSamples += 1;
        }

        if (opaqueSamples > 12 && differingSamples > 2) {
          return {
            width: canvas.width,
            height: canvas.height,
            opaqueSamples,
            differingSamples,
          };
        }
      }

      return false;
    }, undefined, {
      polling: 250,
      timeout: 60_000,
    });

    expect(await canvasState.jsonValue()).toMatchObject({
      opaqueSamples: expect.any(Number),
      differingSamples: expect.any(Number),
    });

    await page.click(".scene-select-trigger");
    await page.click('.scene-select-option[data-scene-id="details"]');
    const buttonAccessibleNode = await page.waitForFunction(() => {
      const activeScene = document.querySelector(".webhost-scene:not([hidden])");
      const buttons = activeScene?.querySelectorAll(
        '.webhost-scene__accessibility-tree [role="button"]',
      ) ?? [];
      return Array.from(buttons).some(
        (button) => button.getAttribute("aria-label") === "Refresh status",
      );
    }, undefined, {
      polling: 250,
      timeout: 30_000,
    });
    expect(await buttonAccessibleNode.jsonValue()).toBe(true);
    expect(runtimeErrors).toEqual([]);
  } finally {
    await page.close();
    await browser.close();
    server.stop(true);
  }
}, 120_000);
