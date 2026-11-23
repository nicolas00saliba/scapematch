import { expect, test, type Locator, type Page } from '@playwright/test';

// Ambiente de teste ou demonstração. Nunca a produção com pagamento real.
// O sandbox do Asaas fica nas Edge Functions. Este teste para na tela de
// pagamento e não confirma a cobrança.
//
// Secrets, todos opcionais. Sem eles o teste fica pendente:
//   E2E_BASE_URL          https de demo ou staging do jogador
//   E2E_JOGADOR_EMAIL     usuário sintético
//   E2E_JOGADOR_SENHA
//   E2E_BUSCA             texto da busca, por exemplo o nome de uma sala
//   E2E_SALA_URL          URL da sala ou do grupo no mesmo host, para chegar
//                         no Pix. Na demo: /groups/grp-cwb-cofre-almost
//   E2E_CADASTRO          "1" para executar o cadastro
//   E2E_CADASTRO_EMAIL    e-mail descartável do cadastro
//   E2E_CADASTRO_SENHA
//   E2E_PARCEIRO_URL      https de demo ou staging do parceiro
//   E2E_PARCEIRO_EMAIL
//   E2E_PARCEIRO_SENHA
//   E2E_SAQUES            "1" só se venue_payouts_settings.enabled estiver
//                         ligado nesse ambiente. O teste olha o saque e não
//                         confirma a transferência.
//
// O teste não clica em "Simular pagamento" nem em "Sacar".

const base = process.env.E2E_BASE_URL ?? '';
const email = process.env.E2E_JOGADOR_EMAIL ?? '';
const senha = process.env.E2E_JOGADOR_SENHA ?? '';
const faltaJogador = !base || !email || !senha;

const hostsProducao = new Set([
  'escapematch.com.br',
  'www.escapematch.com.br',
  'app.escapematch.com.br',
  'parceiro.escapematch.com.br',
  'admin.escapematch.com.br',
]);

export function hostDe(valor: string): string | null {
  const texto = valor.trim();
  if (!texto) return null;
  const comEsquema = /^https?:\/\//i.test(texto) ? texto : `https://${texto}`;
  try {
    return new URL(comEsquema).hostname.toLowerCase().replace(/\.$/, '');
  } catch {
    return null;
  }
}

export function urlsDeProducao(valores: string[]): string[] {
  return valores.filter((valor) => {
    const host = hostDe(valor);
    return host != null && hostsProducao.has(host);
  });
}

function recusarProducao(): void {
  const alvos = [
    process.env.E2E_BASE_URL,
    process.env.E2E_SALA_URL,
    process.env.E2E_PARCEIRO_URL,
  ].filter((valor): valor is string => Boolean(valor));
  const ruins = urlsDeProducao(alvos);
  if (ruins.length === 0) return;
  throw new Error(
    `E2E abortado: ${ruins.join(', ')} aponta para produção. ` +
      'A reserva não roda contra escapematch.com.br, app., parceiro. nem admin. ' +
      'Use demo ou staging (demo.escapematch.com.br e parceiro-demo.escapematch.com.br).',
  );
}

test.beforeEach(() => {
  recusarProducao();
});

test('rejeita host de produção e aceita a demo', () => {
  expect(urlsDeProducao(['https://app.escapematch.com.br/login'])).toEqual([
    'https://app.escapematch.com.br/login',
  ]);
  expect(urlsDeProducao(['https://escapematch.com.br/'])).toHaveLength(1);
  expect(urlsDeProducao(['parceiro.escapematch.com.br'])).toHaveLength(1);
  expect(urlsDeProducao(['https://admin.escapematch.com.br/painel'])).toHaveLength(1);
  expect(urlsDeProducao(['https://www.escapematch.com.br'])).toHaveLength(1);
  expect(urlsDeProducao(['https://demo.escapematch.com.br/'])).toEqual([]);
  expect(urlsDeProducao(['https://parceiro-demo.escapematch.com.br/'])).toEqual([]);
});

// O campo do Flutter web às vezes perde o fill quando o foco ainda está
// trocando. Clicar e digitar de verdade é estável.
async function preencher(campo: Locator, valor: string) {
  await campo.click();
  await campo.page().waitForTimeout(200);
  await campo.page().keyboard.press('ControlOrMeta+A');
  await campo.page().keyboard.type(valor, { delay: 15 });
}

async function entrar(page: Page) {
  await page.goto(`${base}/login`);
  await preencher(page.getByLabel('E-mail'), email);
  await preencher(page.getByLabel('Senha'), senha);
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
  await preencher(page.getByLabel('E-mail'), process.env.E2E_CADASTRO_EMAIL!);
  await preencher(page.getByLabel('Senha'), process.env.E2E_CADASTRO_SENHA ?? 'sintetica-e2e');
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
  // No Flutter web a dica vira aria-label, não placeholder.
  await preencher(page.getByRole('textbox', { name: 'Buscar sala ou casa' }), busca);
  // O cartão do grupo é um botão cujo nome começa pela sala.
  await expect(
    page.getByText(busca).or(page.getByRole('button', { name: busca })).first(),
  ).toBeVisible({ timeout: 20_000 });
});

test('reserva até a tela de pagamento', async ({ page }) => {
  const sala = process.env.E2E_SALA_URL ?? '';
  test.fixme(
    faltaJogador || !sala,
    'Falta E2E_SALA_URL no ambiente de teste. O teste para no Pix e não confirma o pagamento.',
  );
  await entrar(page);
  await page.goto(sala);
  // Na sala, Achar grupo. No grupo, Entrar no grupo abre Pagar minha parte.
  // Na demo tudo fica na memória do navegador: não cobra nem reserva.
  const passo = page.getByRole('button', { name: /^(Achar grupo|Entrar no grupo)$/ }).first();
  const pagar = page.getByText(/Pix|Pagar minha parte/).first();
  await expect(passo.or(pagar).first()).toBeVisible({ timeout: 20_000 });
  if (!(await pagar.isVisible())) {
    // O Flutter redesenha o botão logo depois do toque. Um clique basta.
    await passo.click({ timeout: 10_000 }).catch(() => {});
  }
  await expect(pagar).toBeVisible({ timeout: 20_000 });
  await expect(page.getByRole('button', { name: 'Simular pagamento' })).toHaveCount(0);
});

test('painel do parceiro e saldo da casa', async ({ page }) => {
  const url = process.env.E2E_PARCEIRO_URL ?? '';
  const parceiroEmail = process.env.E2E_PARCEIRO_EMAIL ?? '';
  const parceiroSenha = process.env.E2E_PARCEIRO_SENHA ?? '';
  test.fixme(
    !url || !parceiroEmail || !parceiroSenha,
    'Falta E2E_PARCEIRO_URL e o usuário sintético da casa.',
  );
  await page.goto(url);
  await preencher(page.getByLabel('E-mail'), parceiroEmail);
  await preencher(page.getByLabel('Senha'), parceiroSenha);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page.getByText('Saldo da casa')).toBeVisible({ timeout: 20_000 });
  if (process.env.E2E_SAQUES === '1') {
    await expect(page.getByRole('button', { name: /sacar|saque/i }).first()).toBeVisible();
  }
});
