import { appendFileSync } from 'node:fs';

import { expect, test } from '@playwright/test';

const LIMITE_MS = 2000;
const ARQUIVO = 'tempos-clique.tsv';

async function cronometrar(nome: string, acao: () => Promise<void>) {
  const inicio = Date.now();
  await acao();
  const ms = Date.now() - inicio;
  const projeto = test.info().project.name;
  const texto = `${projeto} ${nome}: ${ms} ms`;
  test.info().annotations.push({ type: 'tempo-clique', description: texto });
  appendFileSync(ARQUIVO, `${projeto}\t${nome}\t${ms}\n`);
  expect(ms, texto).toBeLessThan(LIMITE_MS);
}

test('Baixar o app abre a página do app', async ({ page }) => {
  await page.goto('/');
  await cronometrar('Baixar o app', async () => {
    await page.getByRole('link', { name: 'Baixar o app' }).first().click();
    await page.waitForURL(/\/app$/);
  });
});

test('Como funciona abre a explicação', async ({ page }) => {
  await page.goto('/');
  await cronometrar('Como funciona', async () => {
    await page.getByRole('link', { name: 'Como funciona' }).first().click();
    await page.waitForURL(/\/como-funciona$/);
  });
});

test('Tenho uma casa e Seja parceiro abrem o cadastro', async ({ page }) => {
  await page.goto('/');
  await cronometrar('Seja parceiro', async () => {
    await page.getByRole('tab', { name: 'Tenho uma casa' }).click();
    await page.getByRole('link', { name: 'Seja parceiro' }).last().click();
    await page.waitForURL(/\/para-casas\/cadastro$/);
  });
});
