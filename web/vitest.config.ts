import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
      "@snatchit/types": path.resolve(__dirname, "../packages/types/src/index.ts"),
      "@snatchit/core": path.resolve(__dirname, "../packages/core/src/index.ts"),
    },
  },
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
});
