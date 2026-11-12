import { expect, test } from '@playwright/test';

const paginas = [
  ['inicio', '/'],
  ['como-funciona', '/como-funciona'],
  ['para-casas', '/para-casas'],
  ['vantagens', '/vantagens'],
  ['ajuda', '/ajuda'],
  ['app', '/app'],
] as const;

for (const [nome, caminho] of paginas) {
  test(`página ${nome}`, async ({ page }) => {
    await page.goto(caminho);
    await page.evaluate(() => document.fonts.ready);
    await expect(page).toHaveScreenshot(`${nome}.png`, { fullPage: true });
  });
}
