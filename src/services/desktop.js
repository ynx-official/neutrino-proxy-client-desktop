import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { confirm } from "@tauri-apps/plugin-dialog";

// Test bridges are removed from the production build; a browser cannot report a real connection.
const testBridge = () =>
  import.meta.env.DEV ? window.__NEUTRINO_TEST_BRIDGE__ : null;
export const inDesktop = () => isTauri();
export async function call(command, args = {}) {
  if (testBridge()) return testBridge().invoke(command, args);
  if (!isTauri())
    throw new Error("请从桌面程序打开，浏览器预览不提供后台连接。");
  return invoke(command, args);
}
export async function subscribe(callback, eventName = "client-state") {
  if (testBridge()) return testBridge().subscribe(callback, eventName);
  if (!isTauri()) return () => {};
  return listen(eventName, (event) => callback(event.payload));
}
export async function subscribeNavigation(callback) {
  if (testBridge()) return testBridge().subscribeNavigation?.(callback) || (() => {});
  if (!isTauri()) return () => {};
  return listen("main-navigate", callback);
}
export async function confirmAction(message) {
  if (!isTauri()) return window.confirm(message);
  return confirm(message, {
    title: "Neutrino Proxy",
    kind: "warning",
    okLabel: "确定",
    cancelLabel: "取消",
  });
}
