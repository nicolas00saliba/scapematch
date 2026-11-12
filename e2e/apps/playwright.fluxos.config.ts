import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testMatch: '**/fluxos.spec.ts',
  timeout: 60_000,
  reporter: [['line']],
  use: {
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
  },
});
