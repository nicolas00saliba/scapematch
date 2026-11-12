import { expect, test } from '@playwright/test';

const LIMITE_MS = 2000;

test('Baixar o app abre a página do app', async ({ page }) => {
  await page.goto('/');
  const inicio = Date.now();
  await page.getByRole('link', { name: 'Baixar o app' }).first().click();
  await page.waitForURL(/\/app$/);
  expect(Date.now() - inicio).toBeLessThan(LIMITE_MS);
});

test('Como funciona abre a explicação', async ({ page }) => {
  await page.goto('/');
  const inicio = Date.now();
  await page.getByRole('link', { name: 'Como funciona' }).first().click();
  await page.waitForURL(/\/como-funciona$/);
  expect(Date.now() - inicio).toBeLessThan(LIMITE_MS);
});

test('Tenho uma casa e Seja parceiro abrem o cadastro', async ({ page }) => {
  await page.goto('/');
  const inicio = Date.now();
  await page.getByRole('tab', { name: 'Tenho uma casa' }).click();
  await page.getByRole('link', { name: 'Seja parceiro' }).last().click();
  await page.waitForURL(/\/para-casas\/cadastro$/);
  expect(Date.now() - inicio).toBeLessThan(LIMITE_MS);
});
