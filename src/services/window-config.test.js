import { describe, it, expect } from "vitest";
import config from "../../src-tauri/tauri.conf.json";

describe("default desktop window", () => {
  it("opens at the supported minimum size", () => {
    const main = config.app.windows.find((window) => window.label === "main");
    expect({ width: main.width, height: main.height }).toEqual({
      width: 860,
      height: 620,
    });
    expect(main.width).toBe(main.minWidth);
    expect(main.height).toBe(main.minHeight);
  });
});
