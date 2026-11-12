import { expect, test } from '@playwright/test';

// Ambiente de teste ou demonstração. Nunca a produção com pagamento real.
// O sandbox do Asaas fica nas Edge Functions. Este teste para na tela de
// pagamento e não confirma a cobrança.
//
// Secrets, todos opcionais. Sem eles o teste fica pendente:
//   E2E_BASE_URL          https de demo ou staging do jogador
//   E2E_JOGADOR_EMAIL     usuário sintético
//   E2E_JOGADOR_SENHA
//   E2E_BUSCA             texto da busca, por exemplo o nome de uma sala
//   E2E_SALA_URL          URL da sala no mesmo host, para chegar no Pix
//   E2E_CADASTRO          "1" para executar o cadastro
//   E2E_CADASTRO_EMAIL    e-mail descartável do cadastro
//   E2E_CADASTRO_SENHA
//   E2E_PARCEIRO_URL      https de demo ou staging do parceiro
//   E2E_PARCEIRO_EMAIL
//   E2E_PARCEIRO_SENHA
//
// Não existe botão de saque. O painel mostra "Saldo da casa" e "Subcontas".
// O teste não clica em "Simular pagamento".

const base = process.env.E2E_BASE_URL ?? '';
const email = process.env.E2E_JOGADOR_EMAIL ?? '';
const senha = process.env.E2E_JOGADOR_SENHA ?? '';
const faltaJogador = !base || !email || !senha;

async function entrar(page: import('@playwright/test').Page) {
  await page.goto(`${base}/login`);
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(senha);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page.getByLabel('E-mail')).toBeHidden({ timeout: 20_000 });
}

test('cadastro com usuário sintético', async ({ page }) => {
  test.fixme(
    !base || process.env.E2E_CADASTRO !== '1' || !process.env.E2E_CADASTRO_EMAIL,
    'Falta o ambiente de teste e E2E_CADASTRO=1 com um e-mail descartável.',
  );
  await page.goto(`${base}/cadastro`);
  await page.getByLabel('Nome').fill('Conta sintética');
  await page.getByLabel('E-mail').fill(process.env.E2E_CADASTRO_EMAIL!);
  await page.getByLabel('Senha').fill(process.env.E2E_CADASTRO_SENHA ?? 'sintetica-e2e');
  await page.getByRole('button', { name: 'Criar conta' }).click();
  await expect(page.getByText('Criar conta')).toBeHidden({ timeout: 20_000 });
});

test('login com usuário sintético', async ({ page }) => {
  test.fixme(faltaJogador, 'Falta E2E_BASE_URL e o usuário sintético do jogador.');
  await entrar(page);
});

test('busca de sala', async ({ page }) => {
  const busca = process.env.E2E_BUSCA ?? '';
  test.fixme(faltaJogador || !busca, 'Falta E2E_BUSCA com o nome de uma sala do ambiente de teste.');
  await entrar(page);
  await page.getByPlaceholder('Buscar sala ou casa').fill(busca);
  await expect(page.getByText(busca).first()).toBeVisible();
});

test('reserva até a tela de pagamento', async ({ page }) => {
  const sala = process.env.E2E_SALA_URL ?? '';
  test.fixme(
    faltaJogador || !sala,
    'Falta E2E_SALA_URL no ambiente de teste. O teste para no Pix e não confirma o pagamento.',
  );
  await entrar(page);
  await page.goto(sala);
  const achar = page.getByRole('button', { name: 'Achar grupo' }).first();
  if (await achar.isVisible()) {
    await achar.click();
  }
  await expect(page.getByText(/Pix|Pagar minha parte/).first()).toBeVisible();
  await expect(page.getByRole('button', { name: 'Simular pagamento' })).toHaveCount(0);
});

test('painel do parceiro, saldo e ausência de saque', async ({ page }) => {
  const url = process.env.E2E_PARCEIRO_URL ?? '';
  const parceiroEmail = process.env.E2E_PARCEIRO_EMAIL ?? '';
  const parceiroSenha = process.env.E2E_PARCEIRO_SENHA ?? '';
  test.fixme(
    !url || !parceiroEmail || !parceiroSenha,
    'Falta E2E_PARCEIRO_URL e o usuário sintético da casa. Não há botão de saque no app.',
  );
  await page.goto(url);
  await page.getByLabel('E-mail').fill(parceiroEmail);
  await page.getByLabel('Senha').fill(parceiroSenha);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page.getByText('Saldo da casa')).toBeVisible({ timeout: 20_000 });
  await expect(page.getByRole('button', { name: /sacar|saque/i })).toHaveCount(0);
});
