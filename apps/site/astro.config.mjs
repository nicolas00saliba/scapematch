import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, envField } from 'astro/config';
import sentry from '@sentry/astro';
import sitemap from '@astrojs/sitemap';
import {
  arquivoGoogle,
  linhaArquivoGoogle,
  tokenBuscador,
  xmlBing,
} from './scripts/verificacao-buscadores.mjs';

// Meta e arquivo de verificação saem só com variável de build válida.
// Sem valor, o HTML publicado não ganha token inventado.
function verificacaoBuscadores() {
  return {
    name: 'verificacao-buscadores',
    hooks: {
      'astro:build:done': async ({ dir }) => {
        const { loadEnv } = await import('vite');
        const raiz = fileURLToPath(new URL('.', import.meta.url));
        const doArquivo = loadEnv('production', raiz, '');
        const env = { ...doArquivo, ...process.env };
        const nome = arquivoGoogle(env.GOOGLE_SITE_VERIFICATION_FILE);
        const bing = tokenBuscador(env.BING_SITE_VERIFICATION);
        const destino = fileURLToPath(dir);
        if (nome) {
          await writeFile(path.join(destino, nome), linhaArquivoGoogle(nome));
        }
        if (bing) {
          await writeFile(path.join(destino, 'BingSiteAuth.xml'), xmlBing(bing));
        }
      },
    },
  };
}

const dsnSentry = process.env.PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN || '';
if (dsnSentry.startsWith('https://') && !process.env.PUBLIC_SENTRY_DSN) {
  process.env.PUBLIC_SENTRY_DSN = dsnSentry;
}
// O HTML publicado nasce no tool/sync-site.sh. CF_PAGES_COMMIT_SHA só
// entra se essa variável ainda estiver no ambiente.
const releaseSentry =
  process.env.PUBLIC_SENTRY_RELEASE ||
  process.env.GITHUB_SHA ||
  process.env.CF_PAGES_COMMIT_SHA ||
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
  env: {
    schema: {
      GOOGLE_SITE_VERIFICATION: envField.string({
        context: 'server',
        access: 'public',
        default: '',
      }),
      BING_SITE_VERIFICATION: envField.string({
        context: 'server',
        access: 'public',
        default: '',
      }),
      GOOGLE_SITE_VERIFICATION_FILE: envField.string({
        context: 'server',
        access: 'public',
        default: '',
      }),
    },
  },
  build: {
    format: 'file',
    inlineStylesheets: 'never',
  },
  integrations: [
    verificacaoBuscadores(),
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
        const rota = new URL(page).pathname.replace(/\/$/, '') || '/';
        return rota !== '/convite' && rota !== '/404' && rota !== '/cidades/curitiba';
      },
      serialize(item) {
        item.lastmod = new Date('2026-11-13T00:00:00.000Z');
        return item;
      },
    }),
  ],
  redirects: {
    '/termos-parceiro.html': '/termos/parceiro',
  },
});
