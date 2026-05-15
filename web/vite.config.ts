import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwind from "@tailwindcss/vite";
import path from "node:path";

// @persistent-surface-wrapper
const DAEMON_HOST = process.env.CLAWIX_BRIDGE_HOST ?? "localhost";
const DAEMON_PORT = process.env.CLAWIX_BRIDGE_PORT ?? "24080";

export default defineConfig({
  plugins: [react(), tailwind()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
  server: {
    port: 5173,
    strictPort: false,
    proxy: {
      "/ws": {
        target: `ws://${DAEMON_HOST}:${DAEMON_PORT}`,
        ws: true,
        changeOrigin: true,
      },
      "/pairing": {
        target: `http://${DAEMON_HOST}:${DAEMON_PORT}`,
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
    target: "es2022",
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom"],
          crypto: ["hash-wasm"],
          framer: ["framer-motion"],
        },
      },
    },
  },
});
