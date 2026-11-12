import { expect, test } from '@playwright/test';

// A home da demonstração pinta a data de hoje nas salas. Um print de pixel
// ficaria vermelho todo dia. As telas públicas estáveis são os logins.
const telas = [
  {
    nome: 'jogador-login',
    url: 'http://127.0.0.1:4173/login',
    texto: 'Fazer cadastro',
  },
  {
    nome: 'parceiro-login',
    url: 'http://127.0.0.1:4174/',
    texto: 'Entrar como casa',
  },
  { nome: 'admin-login', url: 'http://127.0.0.1:4175/' },
];

for (const tela of telas) {
  test(`${tela.nome} em página inteira`, async ({ page }) => {
    await page.goto(tela.url, { waitUntil: 'domcontentloaded' });
    await page.locator('canvas, flutter-view').first().waitFor({ timeout: 30_000 });
    if (tela.texto) {
      await page.getByText(tela.texto).first().waitFor({ timeout: 30_000 });
    } else {
      await page.locator('#admin-splash').waitFor({ state: 'detached', timeout: 30_000 });
    }
    await page.waitForTimeout(500);
    await expect(page).toHaveScreenshot(`${tela.nome}.png`, { fullPage: true });
  });
}
