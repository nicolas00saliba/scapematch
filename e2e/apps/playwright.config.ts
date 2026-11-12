import { defineConfig, type ReporterDescription } from '@playwright/test';

const reporter: ReporterDescription[] = [['line']];
if (process.env.ARGOS_TOKEN) {
  reporter.push(['@argos-ci/playwright/reporter', { uploadToArgos: true }]);
}

export default defineConfig({
  testDir: './tests',
  testIgnore: '**/fluxos.spec.ts',
  timeout: 60_000,
  reporter,
  expect: {
    toHaveScreenshot: {
      animations: 'disabled',
      maxDiffPixelRatio: 0.02,
    },
  },
  use: {
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    colorScheme: 'light',
  },
  projects: [
    {
      name: 'desktop',
      use: { viewport: { width: 1440, height: 900 } },
    },
    {
      name: 'celular',
      use: { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true },
    },
  ],
  webServer: [
    {
      command: 'python3 ../../tool/servir_spa.py 4173 ../../build/web',
      url: 'http://127.0.0.1:4173',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'python3 ../../tool/servir_spa.py 4174 ../../apps/parceiro/build/web',
      url: 'http://127.0.0.1:4174',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'python3 ../../tool/servir_spa.py 4175 ../../apps/admin/build/web',
      url: 'http://127.0.0.1:4175',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
});
