import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [vue()],
  clearScreen: false,
  server: {
    host: "127.0.0.1", port: 1420, strictPort: true,
    headers: { "X-Neutrino-Dev-Server": "1" },
  },
  build: {
    target: ["es2021", "chrome105", "safari14"],
    rolldownOptions: { input: { main: fileURLToPath(new URL("./index.html", import.meta.url)) } },
  },
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.js"],
    restoreMocks: true,
  },
});
