// @vitest-environment node
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { resolveConfig } from "vite";

describe("desktop webview resources", () => {
  it("builds only the main webview because the tray uses a native menu", async () => {
    const root = process.cwd();
    const config = await resolveConfig({ root, logLevel: "silent" }, "build");
    const input = config.build.rolldownOptions.input;
    const entries = typeof input === "object" ? Object.values(input) : [input];
    expect(entries.map((path) => path.replaceAll("\\", "/").split("/").at(-1))).toEqual(["index.html"]);
    const directory = join(root, "src-tauri/capabilities");
    const windows = readdirSync(directory).filter((name) => name.endsWith(".json"))
      .flatMap((name) => JSON.parse(readFileSync(join(directory, name), "utf8")).windows);
    expect([...new Set(windows)]).toEqual(["main"]);
  });
});
