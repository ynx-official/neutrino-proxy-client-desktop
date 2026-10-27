import { createServer } from "vite";

// A private stdin pipe is a lifetime lease from the Rust parent. EOF also covers
// forced termination of the parent, where Rust destructors do not run.
let server;
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  const forceExit = setTimeout(() => process.exit(0), 2500);
  forceExit.unref();
  try { await server?.close(); }
  finally { process.exit(0); }
}
process.stdin.on("end", close);
process.stdin.resume();
process.on("SIGINT", close);
process.on("SIGTERM", close);

try {
  server = await createServer({
    clearScreen: false,
    server: { host: process.argv[2], port: Number(process.argv[3]), strictPort: true },
  });
  if (closing) await close();
  else {
    await server.listen();
    server.printUrls();
    console.log("NEUTRINO_DEV_READY");
  }
} catch (error) {
  console.error(error);
  await server?.close();
  process.exit(1);
}
