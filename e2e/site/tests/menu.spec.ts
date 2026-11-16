import { expect, test } from '@playwright/test';

test.describe('menu suspenso no desktop', () => {
  test.skip(({ viewport }) => !viewport || viewport.width < 1080, 'o hover do mega menu é de desktop');

  test('Vantagens permanece aberto no caminho até o link e o painel é compacto', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);

    const nav = page.getByRole('navigation', { name: 'Seções' });
    const details = nav.locator('details').filter({ has: page.locator('summary', { hasText: 'Vantagens' }) });
    const summary = details.locator('summary');
    const painel = details.locator('.mega');
    const link = painel.getByRole('link', { name: 'Boas-vindas e pontos de volta' });

    const aba = await summary.boundingBox();
    expect(aba).not.toBeNull();
    const inicio = { x: aba!.x + aba!.width / 2, y: aba!.y + aba!.height / 2 };
    await page.mouse.move(inicio.x, inicio.y);
    await expect(painel).toBeVisible();

    const destino = await link.boundingBox();
    expect(destino).not.toBeNull();
    const fim = {
      x: destino!.x + Math.min(24, destino!.width / 2),
      y: destino!.y + destino!.height / 2,
    };
    const passos = 18;
    for (let i = 1; i <= passos; i += 1) {
      const x = inicio.x + ((fim.x - inicio.x) * i) / passos;
      const y = inicio.y + ((fim.y - inicio.y) * i) / passos;
      await page.mouse.move(x, y);
      if (i === 6) await page.waitForTimeout(320);
      await expect(painel, `painel fechou no passo ${i}`).toBeVisible();
    }

    await page.waitForTimeout(320);
    await expect(painel).toBeVisible();
    await expect(link).toBeVisible();

    const caixa = await painel.boundingBox();
    expect(caixa).not.toBeNull();
    const viewport = page.viewportSize();
    expect(viewport?.width).toBe(1440);
    expect(caixa!.width).toBeLessThan(1440 * 0.55);
    expect(caixa!.x + caixa!.width).toBeLessThanOrEqual(1440);

    await link.click();
    await page.waitForURL(/\/vantagens$/);
  });

  test('passar o mouse para outra aba troca o painel na hora', async ({ page }) => {
    await page.goto('/');
    const nav = page.getByRole('navigation', { name: 'Seções' });
    await nav.locator('summary', { hasText: 'Vantagens' }).hover();
    const vantagens = nav.getByRole('link', { name: 'Boas-vindas e pontos de volta' });
    await expect(vantagens).toBeVisible();
    await nav.locator('summary', { hasText: 'Empresa' }).hover();
    await expect(nav.getByRole('link', { name: 'Contato' })).toBeVisible();
    await expect(vantagens).toBeHidden();
  });

  test('teclado abre com Enter e fecha com Esc', async ({ page }) => {
    await page.goto('/');
    const summary = page.locator('summary', { hasText: 'Vantagens' });
    await summary.focus();
    await page.keyboard.press('Enter');
    const link = page.getByRole('link', { name: 'Boas-vindas e pontos de volta' });
    await expect(link).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(link).toBeHidden();
    await expect(summary).toBeFocused();
  });

  test('clique abre e fecha o painel', async ({ page }) => {
    await page.goto('/');
    const details = page.locator('#menu details').filter({ has: page.locator('summary', { hasText: 'Empresa' }) });
    const summary = details.locator('summary');
    await summary.click();
    await expect(details).toHaveAttribute('open', '');
    await expect(details.getByRole('link', { name: 'Contato' })).toBeVisible();
    await summary.click();
    await expect(details).not.toHaveAttribute('open', '');
  });
});

test('toque no menu mobile abre Vantagens', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'celular', 'só o projeto celular');
  await page.goto('/');
  await page.getByRole('button', { name: 'Menu' }).click();
  const nav = page.getByRole('navigation', { name: 'Seções' });
  await nav.locator('summary', { hasText: 'Vantagens' }).click();
  await expect(nav.getByRole('link', { name: 'Boas-vindas e pontos de volta' })).toBeVisible();
});
