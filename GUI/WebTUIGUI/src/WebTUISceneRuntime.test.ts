import { expect, mock, test } from "bun:test";

mock.module("ghostty-web", () => ({
  init: async () => {},
  Terminal: class {},
  FitAddon: class {},
}));

const { WebTUISceneRuntime } = await import("./WebTUISceneRuntime.ts");

test("hidden scenes stay out of layout even after style updates", () => {
  const mount = makeElement("div");
  const documentStub = {
    createElement: (tagName: string) => makeElement(tagName),
  };
  globalThis.document = documentStub as unknown as Document;
  const runtime = new WebTUISceneRuntime({
    mount: mount as unknown as HTMLElement,
    descriptor: { id: "details", title: "Details", isDefault: false },
    style: {},
    onInput: () => {},
  });

  expect(runtime.element.hidden).toBe(true);
  expect(runtime.element.style.getPropertyValue("display")).toBe("none");
  expect(runtime.element.style.getPropertyPriority("display")).toBe("important");

  runtime.setStyle({ fontSize: 18 });
  expect(runtime.element.hidden).toBe(true);
  expect(runtime.element.style.getPropertyValue("display")).toBe("none");

  runtime.setVisible(true);
  expect(runtime.element.hidden).toBe(false);
  expect(runtime.element.style.getPropertyValue("display")).toBe("grid");

  runtime.setVisible(false);
  expect(runtime.element.hidden).toBe(true);
  expect(runtime.element.style.getPropertyValue("display")).toBe("none");
});

function makeElement(tagName: string): Record<string, unknown> {
  const styleValues = new Map<string, string>();
  const stylePriorities = new Map<string, string>();

  return {
    tagName,
    className: "",
    textContent: "",
    dataset: {},
    hidden: false,
    style: {
      setProperty: (name: string, value: string, priority?: string) => {
        styleValues.set(name, value);
        stylePriorities.set(name, priority ?? "");
      },
      getPropertyValue: (name: string) => styleValues.get(name) ?? "",
      getPropertyPriority: (name: string) => stylePriorities.get(name) ?? "",
    },
    append: () => {},
    appendChild: () => {},
    remove: () => {},
  };
}
