import { expect, test } from '@playwright/test';

const paginas = [
  ['inicio', '/'],
  ['como-funciona', '/como-funciona'],
  ['para-casas', '/para-casas'],
  ['vantagens', '/vantagens'],
  ['ajuda', '/ajuda'],
  ['app', '/app'],
  ['guia-sozinho-curitiba', '/guia/escape-room-sozinho-curitiba'],
] as const;

for (const [nome, caminho] of paginas) {
  test(`página ${nome}`, async ({ page }, testInfo) => {
    await page.goto(caminho);
    await page.evaluate(() => document.fonts.ready);
    if (nome === 'guia-sozinho-curitiba' && testInfo.project.name === 'desktop') {
      const h1 = await page.locator('header.pagina-topo h1').boundingBox();
      const h2 = await page.locator('article.leitura h2').first().boundingBox();
      expect(h1).not.toBeNull();
      expect(h2).not.toBeNull();
      expect(Math.abs(h1!.x - h2!.x)).toBeLessThanOrEqual(2);
    }
    await expect(page).toHaveScreenshot(`${nome}.png`, { fullPage: true });
  });
}
