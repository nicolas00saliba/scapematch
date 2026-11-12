import { defineConfig } from 'astro/config';
import sentry from '@sentry/astro';
import sitemap from '@astrojs/sitemap';

const dsnSentry = process.env.PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN || '';
if (dsnSentry.startsWith('https://') && !process.env.PUBLIC_SENTRY_DSN) {
  process.env.PUBLIC_SENTRY_DSN = dsnSentry;
}
const releaseSentry =
  process.env.PUBLIC_SENTRY_RELEASE ||
  process.env.CF_PAGES_COMMIT_SHA ||
  process.env.GITHUB_SHA ||
  '';
if (releaseSentry && !process.env.PUBLIC_SENTRY_RELEASE) {
  process.env.PUBLIC_SENTRY_RELEASE = releaseSentry;
}
const sentryLigado = dsnSentry.startsWith('https://');

// Com build.format = 'file', /termos vira termos.html. No GitHub Pages,
// /termos.html e /index.html já são esses arquivos. O único endereço antigo
// que precisa de página própria é /termos-parceiro.html.
export default defineConfig({
  site: 'https://escapematch.com.br',
  trailingSlash: 'never',
  output: 'static',
  build: {
    format: 'file',
    inlineStylesheets: 'never',
  },
  integrations: [
    sentry({
      enabled: { client: sentryLigado, server: false },
      sourcemaps: { disable: true },
      telemetry: false,
      silent: true,
      bundleSizeOptimizations: {
        excludeReplayShadowDom: true,
        excludeReplayIframe: true,
        excludeReplayWorker: true,
      },
    }),
    sitemap({
      filter: (page) => {
        const path = new URL(page).pathname.replace(/\/$/, '') || '/';
        return path !== '/convite' && path !== '/404' && path !== '/contato' && path !== '/cidades/curitiba';
      },
      serialize(item) {
        item.lastmod = new Date('2026-11-11T00:00:00.000Z');
        return item;
      },
    }),
  ],
  redirects: {
    '/termos-parceiro.html': '/termos/parceiro',
  },
});
