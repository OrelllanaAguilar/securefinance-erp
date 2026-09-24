import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  testMatch: 'private-runtime.spec.js',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: 'list',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL: 'http://127.0.0.1:3000',
    channel: 'msedge',
    reducedMotion: 'reduce',
    screenshot: 'off',
    trace: 'off',
    video: 'off',
  },
  webServer: {
    command: 'pnpm --workspace-root build && pnpm --filter @securefinance/api start',
    url: 'http://127.0.0.1:3000/api/health',
    reuseExistingServer: true,
    timeout: 120_000,
  },
});
