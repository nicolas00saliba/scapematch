import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, envField } from 'astro/config';
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
    sitemap({
      filter: (page) => {
        const rota = new URL(page).pathname.replace(/\/$/, '') || '/';
        return rota !== '/convite' && rota !== '/404' && rota !== '/cidades/curitiba';
      },
      serialize(item) {
        item.lastmod = new Date('2026-11-12T00:00:00.000Z');
        return item;
      },
    }),
  ],
  redirects: {
    '/termos-parceiro.html': '/termos/parceiro',
  },
});
