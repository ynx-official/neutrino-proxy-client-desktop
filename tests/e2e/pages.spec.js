import { test, expect } from "@playwright/test";
import { defaultConfig } from "../../src/services/state.js";

async function bridge(page, connected = false) {
  await page.addInitScript(
    ({ connected, defaults }) => {
      const config = {
        ...defaults,
        server: connected ? "edge.example.com" : "",
        port: 9002,
        ssl: connected ? true : defaults.ssl,
        clientId: "test-client",
        reconnectSeconds: 10,
        unlimited: false,
        udpPortRange: "10000-10500",
        readIdleSeconds: 120,
        heartbeatSeconds: 20,
        certificatePath: "",
      };
      let snapshot = {
        config,
        state: connected ? "connected" : "idle",
        detail: "填写连接信息，开始第一次连接",
        revision: 1,
        logs: connected
          ? [
              {
                id: 1,
                time: "2026-10-15T02:24:08Z",
                level: "info",
                source: "连接",
                message: "连接已建立",
              },
              {
                id: 2,
                time: "2026-10-15T02:24:09Z",
                level: "info",
                source: "认证",
                message: "License 验证通过",
              },
              {
                id: 3,
                time: "2026-10-15T02:24:09Z",
                level: "info",
                source: "连接",
                message: "开始后台运行",
              },
            ]
          : [],
        hasLicense: connected,
        licenseHint: "•••• •••• •••• 8F2A",
        connectedAt: connected
          ? new Date(Date.now() - 8316000).toISOString()
          : null,
        retryAt: null,
        pendingConfig: false,
        version: "0.1.0",
      };
      let listener = () => {}, navigationListener = () => {}, pendingRoute = null;
      window.__navigateFromTray = (path) => { pendingRoute = path; navigationListener(); };
      window.__NEUTRINO_TEST_BRIDGE__ = {
        subscribeNavigation: (callback) => { navigationListener = callback; return () => {}; },
        subscribe: (callback) => {
          listener = callback;
          return () => {};
        },
        invoke: async (command, args) => {
          if (command === "get_app_settings") return JSON.parse(localStorage.getItem("appSettings") || '{"autoStart":false,"autoConnect":false}');
          if (command === "save_app_settings") {
            if (window.__settingsFailure) throw new Error("无法更新系统开机自启设置");
            const settings = { ...JSON.parse(localStorage.getItem("appSettings") || '{"autoStart":false,"autoConnect":false}'), ...args.request };
            localStorage.setItem("appSettings", JSON.stringify(settings));
            return settings;
          }
          if (command === "take_navigation") { const path = pendingRoute; pendingRoute = null; return path; }
          if (command === "get_snapshot") return structuredClone(snapshot);
          if (command === "import_config") return structuredClone(window.__importFixture);
          if (command === "apply_import") {
            snapshot = { ...snapshot, config: { ...config, ...window.__importFixture.config }, revision: snapshot.revision + 1 };
            listener(structuredClone(snapshot));
            return structuredClone(snapshot);
          }
          if (command === "save_config") {
            window.__lastSaved = structuredClone(args.request);
            snapshot = {
              ...snapshot,
              config: args.request.config,
              hasLicense: true,
              state: args.request.connect ? "connected" : snapshot.state,
              connectedAt: args.request.connect
                ? new Date().toISOString()
                : snapshot.connectedAt,
              revision: snapshot.revision + 1,
            };
            listener(structuredClone(snapshot));
            return structuredClone(snapshot);
          }
          if (command === "disconnect") {
            snapshot = {
              ...snapshot,
              state: "idle",
              connectedAt: null,
              revision: snapshot.revision + 1,
            };
            listener(structuredClone(snapshot));
            return;
          }
          throw new Error(`Unsupported test command: ${command}`);
        },
      };
    },
    { connected, defaults: defaultConfig() },
  );
}

test("application settings persist independently and preserve connection edits", async ({ page }) => {
  await bridge(page, true);
  await page.setViewportSize({ width: 860, height: 620 });
  await page.goto("/#/settings");
  await page.getByLabel("服务器地址", { exact: true }).fill("unsaved.example.test");
  page.once("dialog", dialog => dialog.dismiss());
  await page.getByRole("link", { name: "应用设置", exact: true }).click();
  await expect(page.getByLabel("服务器地址", { exact: true })).toHaveValue("unsaved.example.test");
  page.once("dialog", dialog => dialog.accept());
  await page.getByRole("link", { name: "应用设置", exact: true }).click();
  const autoStart = page.getByRole("switch", { name: "开机自启", exact: true });
  const autoConnect = page.getByRole("switch", { name: "启动后自动连接", exact: true });
  await expect(autoStart).not.toBeChecked();
  await expect(autoConnect).not.toBeChecked();
  await autoConnect.click();
  await expect(autoConnect).toBeChecked();
  await expect(autoConnect.locator("span")).toHaveCSS("transform", "matrix(1, 0, 0, 1, 16, 0)");
  await page.screenshot({ path: "test-results/application-settings.png" });
  await autoStart.click();
  await expect(autoStart).toBeChecked();
  await page.reload();
  await expect(autoStart).toBeChecked();
  await expect(autoConnect).toBeChecked();
  await page.evaluate(() => { window.__settingsFailure = true; });
  await autoStart.click();
  await expect(page.getByRole("alert")).toContainText("无法更新系统开机自启设置");
  await expect(autoStart).toBeChecked();
  await page.getByRole("link", { name: "连接配置", exact: true }).click();
  await expect(page.getByLabel("服务器地址", { exact: true })).toHaveValue("edge.example.com");
});

test("first run validates configuration and navigates after saving", async ({
  page,
}) => {
  await bridge(page);
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "尚未连接" })).toBeVisible();
  await page.getByRole("button", { name: "填写连接信息" }).click();
  await expect(page.getByRole("switch", { name: "启用 SSL" })).not.toBeChecked();
  await expect(page.getByText("信任证书", { exact: true })).toBeHidden();
  await page.getByRole("button", { name: "保存并连接" }).click();
  await expect(
    page.getByText("请填写服务器地址", { exact: true }),
  ).toBeVisible();
  await page.getByLabel("服务器地址", { exact: true }).fill("edge.example.com");
  await page.getByLabel("License", { exact: true }).fill("test-license");
  await page.screenshot({
    path: "test-results/connection-setup.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "保存并连接" }).click();
  await expect(
    page.getByRole("heading", { name: "已连接", exact: true }),
  ).toBeVisible();
  expect(await page.evaluate(() => window.__lastSaved.config.ssl)).toBe(false);
});

test("protocol import replaces confirmed dirty edits and survives the next save", async ({ page }) => {
  await bridge(page, true);
  await page.setViewportSize({ width: 860, height: 620 });
  await page.goto("/#/settings");
  await page.getByLabel("服务器地址", { exact: true }).fill("unsaved.example.test");
  await page.evaluate(() => {
    window.__importFixture = {
      id: "protocol-import", canApply: true, notes: ["已读取同目录旧客户端 ID"],
      config: { server: "imported.example.test", clientId: "legacy-identity", waterMark: "32KB/1MB",
        allIdleSeconds: 60, maxFrameLength: 4194304, lengthFieldOffset: 2, lengthFieldLength: 2,
        lengthAdjustment: 0, initialBytesToStrip: 0 },
      importedFields: ["tunnel.server-ip", "tunnel.client-id", "protocol.water-mark", "protocol.all-idle-time-seconds",
        "protocol.max-frame-length", "protocol.length-field-offset", "protocol.length-field-length",
        "protocol.length-adjustment", "protocol.initial-bytes-to-strip"].map((key) => `neutrino.proxy.${key}`),
    };
  });
  page.once("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: "导入配置", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("32KB/1MB");
  await page.screenshot({ path: "test-results/protocol-import.png", fullPage: true });
  await page.getByRole("button", { name: "导入并保存" }).click();
  await expect(page.getByLabel("服务器地址", { exact: true })).toHaveValue("imported.example.test");
  await page.getByRole("button", { name: "仅保存，下次生效" }).click();
  const saved = await page.evaluate(() => window.__lastSaved.config);
  expect(saved).toMatchObject({ server: "imported.example.test", clientId: "legacy-identity",
    waterMark: "32KB/1MB", allIdleSeconds: 60, maxFrameLength: 4194304,
    lengthFieldOffset: 2, lengthFieldLength: 2, lengthAdjustment: 0, initialBytesToStrip: 0 });
});

test("tray navigation respects unsaved edits and opens logs when accepted", async ({ page }) => {
  await bridge(page, true);
  await page.goto("/#/settings");
  await page.getByLabel("服务器地址", { exact: true }).fill("unsaved.example.com");
  page.once("dialog", (dialog) => dialog.dismiss());
  await page.evaluate(() => window.__navigateFromTray("/logs"));
  await expect(page.getByLabel("服务器地址", { exact: true })).toHaveValue("unsaved.example.com");
  page.once("dialog", (dialog) => dialog.accept());
  await page.evaluate(() => window.__navigateFromTray("/logs"));
  await expect(page.getByRole("heading", { name: "日志", exact: true })).toBeVisible();
});

test("approved navigation stays horizontal and opens all three pages", async ({
  page,
}) => {
  await bridge(page, true);
  await page.setViewportSize({ width: 860, height: 620 });
  await page.goto("/");
  const nav = page.getByRole("navigation", { name: "主导航" });
  const positions = await Promise.all(
    ["连接", "日志", "设置"].map((name) =>
      nav.getByRole("link", { name, exact: true }).boundingBox(),
    ),
  );
  expect(
    Math.max(...positions.map((box) => box.y)) -
      Math.min(...positions.map((box) => box.y)),
  ).toBeLessThan(2);
  const status = await page
    .getByRole("heading", { name: "已连接", exact: true })
    .boundingBox();
  expect(status.y).toBeGreaterThan(positions[0].y + positions[0].height);
  await nav.getByRole("link", { name: "日志", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "日志", exact: true }),
  ).toBeVisible();
  await nav.getByRole("link", { name: "设置", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "保存并重连" }),
  ).toBeInViewport();
});

test("connected layout presents the endpoint, duration and connection controls", async ({
  page,
}) => {
  await bridge(page, true);
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "已连接", exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "断开连接" })).toBeVisible();
  await expect(page.locator(".hero-endpoint")).toHaveText(
    "edge.example.com:9002",
  );
  await expect(page.locator(".hero-duration strong")).toHaveText(
    /\d{2}:\d{2}:\d{2}/,
  );
  await expect(page.getByText("SSL", { exact: true })).toBeVisible();
  await expect(
    page.getByText("License 验证通过", { exact: true }),
  ).toBeVisible();
  await page.screenshot({ path: "test-results/connected.png", fullPage: true });
  await page.getByRole("button", { name: "全部日志" }).click();
  await expect(
    page.getByRole("heading", { name: "日志", exact: true }),
  ).toBeVisible();
  await page.screenshot({ path: "test-results/logs.png", fullPage: true });
  await page.getByLabel("搜索日志").fill("不存在");
  await expect(page.getByText("当前筛选没有日志")).toBeVisible();
});

test("minimum size and long content remain usable", async ({ page }) => {
  await bridge(page, true);
  await page.setViewportSize({ width: 860, height: 620 });
  await page.goto("/");
  await expect(page.getByRole("button", { name: "断开连接" })).toBeInViewport();
  expect(
    await page
      .locator(".main-content")
      .evaluate((element) => element.scrollWidth <= element.clientWidth),
  ).toBe(true);
  await page.screenshot({
    path: "test-results/connected-minimum.png",
    fullPage: true,
  });
  await page.goto("/#/settings");
  await expect(page.getByRole("button", { name: "保存并重连" })).toBeVisible();
  const primaryAction = await page
    .getByRole("button", { name: "保存并重连" })
    .boundingBox();
  expect(primaryAction.y + primaryAction.height).toBeLessThanOrEqual(620);
  await page.screenshot({ path: "test-results/settings-minimum-ssl.png", fullPage: true });
  expect(
    await page.getByRole("button", { name: "高级设置" }).evaluate((element) => {
      const box = element.getBoundingClientRect();
      const hit = document.elementFromPoint(
        box.x + box.width / 2,
        box.y + box.height / 2,
      );
      return element === hit || element.contains(hit);
    }),
  ).toBe(true);
  await page
    .getByLabel("服务器地址", { exact: true })
    .fill("very-long-server-address-for-overflow-check.example.com");
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: "test-results/minimum-size.png",
    fullPage: true,
  });
});

test("default configuration fits the window without unnecessary scrolling", async ({
  page,
}) => {
  await bridge(page);
  await page.goto("/#/settings");
  await expect(page.getByRole("heading", { name: "设置", exact: true })).toBeVisible();
  const size = await page.locator(".main-content").evaluate((element) => ({
    scroll: element.scrollHeight,
    visible: element.clientHeight,
  }));
  expect(size.scroll).toBeLessThanOrEqual(size.visible);
});

test("SSL and advanced controls stay reachable in a small window", async ({
  page,
}) => {
  await bridge(page, true);
  await page.goto("/#/settings");
  await expect(page.getByLabel("License", { exact: true })).toHaveAttribute(
    "placeholder",
    "已保存 · 留空不修改",
  );
  await page.screenshot({
    path: "test-results/settings-saved.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 860, height: 620 });
  await page.getByRole("switch", { name: "启用 SSL" }).click();
  await expect(page.getByText("信任证书", { exact: true })).toBeHidden();
  await page.screenshot({ path: "test-results/settings.png", fullPage: true });
  await page.getByRole("button", { name: "高级设置" }).click();
  await expect(page.getByLabel("客户端 ID", { exact: true })).toBeVisible();
  await page.getByLabel("UDP 端口范围", { exact: true }).fill("invalid");
  await page.getByRole("button", { name: "保存并重连" }).click();
  await expect(
    page.getByText("请输入有效范围，例如 10000-10500"),
  ).toBeVisible();
});

test("partial imports can be confirmed before credentials are complete and do not connect", async ({ page }) => {
  await bridge(page);
  await page.addInitScript(() => {
    const original = window.__NEUTRINO_TEST_BRIDGE__.invoke;
    window.__importCommands = [];
    window.__NEUTRINO_TEST_BRIDGE__.invoke = async (command, args) => {
      window.__importCommands.push(command);
      const snapshot = await original("get_snapshot");
      const config = { ...snapshot.config, server: "imported.example.com", readIdleSeconds: 75 };
      if (command === "import_config") return {
        id: "partial-import", config, hasLicense: false, canApply: true,
        importedFields: ["neutrino.proxy.tunnel.server-ip", "neutrino.proxy.protocol.read-idle-time"],
        notes: ["可导入 2 项配置，缺失项保留当前值"],
      };
      if (command === "apply_import") return { ...snapshot, config, revision: snapshot.revision + 1 };
      return original(command, args);
    };
  });
  await page.goto("/");
  await page.getByRole("button", { name: "导入配置", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "确认导入配置" });
  await expect(dialog.getByText("imported.example.com", { exact: true })).toBeVisible();
  await expect(dialog.getByText("75 秒", { exact: true })).toBeVisible();
  await expect(dialog.getByText(/License/)).toHaveCount(0);
  await expect(dialog.getByRole("button", { name: "导入并保存" })).toBeEnabled();
  await dialog.getByRole("button", { name: "导入并保存" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByLabel("服务器地址", { exact: true })).toHaveValue("imported.example.com");
  await expect(page.getByLabel("License", { exact: true })).toHaveValue("");
  await expect(page.getByRole("alert")).toHaveCount(0);
  expect(await page.evaluate(() => window.__importCommands)).toContain("apply_import");
  expect(await page.evaluate(() => window.__importCommands)).not.toContain("connect");
});

test("an unmatched file never presents saved connection values as imported data", async ({ page }) => {
  await bridge(page, true);
  await page.addInitScript(() => {
    const original = window.__NEUTRINO_TEST_BRIDGE__.invoke;
    window.__NEUTRINO_TEST_BRIDGE__.invoke = async (command, args) => {
      if (command !== "import_config") return original(command, args);
      const snapshot = await original("get_snapshot");
      return { id: "unmatched", config: snapshot.config, hasLicense: true, canApply: false,
        importedFields: [], notes: ["未发现可导入的配置"] };
    };
  });
  await page.goto("/#/settings");
  await page.getByRole("button", { name: "导入配置", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "确认导入配置" });
  await expect(dialog.getByText("未发现可导入的配置")).toBeVisible();
  await expect(dialog.getByRole("button", { name: "导入并保存" })).toBeDisabled();
  await expect(dialog.getByText(/edge\.example\.com/)).toHaveCount(0);
  await expect(dialog.getByText(/License/)).toHaveCount(0);
});

test("recognized legacy client fields preview correctly in a small window", async ({ page }) => {
  await bridge(page);
  await page.addInitScript(() => {
    const original = window.__NEUTRINO_TEST_BRIDGE__.invoke;
    window.__NEUTRINO_TEST_BRIDGE__.invoke = async (command, args) => {
      if (command !== "import_config") return original(command, args);
      const snapshot = await original("get_snapshot");
      return { id: "official-legacy-client", canApply: true, hasLicense: true,
        config: { ...snapshot.config, server: "official.example.com", port: 9000, ssl: false },
        importedFields: ["server-ip", "server-port", "ssl-enable", "license-key", "jks-path", "key-store-password"].map((key) => `neutrino.proxy.tunnel.${key}`),
        notes: ["可导入 6 项配置，缺失项保留当前值"] };
    };
  });
  await page.setViewportSize({ width: 860, height: 620 });
  await page.goto("/#/settings");
  await page.getByRole("button", { name: "导入配置", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "确认导入配置" });
  await expect(dialog.getByText("official.example.com", { exact: true })).toBeVisible();
  await expect(dialog.getByText("9000", { exact: true })).toBeVisible();
  await expect(dialog.getByText("未启用", { exact: true })).toBeVisible();
  await expect(dialog.getByText("License", { exact: true })).toBeVisible();
  await expect(dialog.getByText("已读取，隐藏明文", { exact: true })).toHaveCount(2);
  await expect(dialog.getByRole("button", { name: "导入并保存" })).toBeEnabled();
  await expect(dialog.getByRole("button", { name: "导入并保存" })).toBeInViewport();
  await page.screenshot({ path: "test-results/import-legacy-client.png", fullPage: true });
});
