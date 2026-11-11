import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

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
    sitemap({
      filter: (page) => {
        const path = new URL(page).pathname.replace(/\/$/, '') || '/';
        return path !== '/convite' && path !== '/404';
      },
    }),
  ],
  redirects: {
    '/termos-parceiro.html': '/termos/parceiro',
  },
});
