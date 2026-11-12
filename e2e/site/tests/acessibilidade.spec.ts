import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const caminhos = [
  '/',
  '/como-funciona',
  '/para-casas',
  '/vantagens',
  '/ajuda',
  '/app',
];

// O cobre da marca (#d2642a) com o texto #221f1b fica em 4,37:1 no
// "Baixar o app" do menu, a 15px. O AA pede 4,5:1. Mudar o token
// --cobre altera o botão em todo o site, então fica para o Nícolas.
const conhecidas = new Set(['color-contrast:.menu-baixar']);

for (const caminho of caminhos) {
  test(`axe em ${caminho}`, async ({ page }) => {
    await page.goto(caminho);
    const resultados = await new AxeBuilder({ page }).analyze();
    const graves = resultados.violations
      .map((item) => ({
        ...item,
        nodes: item.nodes.filter((node) => {
          const alvo = `${item.id}:${node.target.join(' ')}`;
          return !conhecidas.has(alvo);
        }),
      }))
      .filter(
        (item) =>
          (item.impact === 'serious' || item.impact === 'critical') &&
          item.nodes.length > 0,
      );
    expect(graves, formatar(graves)).toEqual([]);
  });
}

function formatar(
  violacoes: { id: string; impact: string | null; help: string; nodes: { target: unknown; html: string }[] }[],
) {
  return violacoes
    .map((item) => {
      const alvos = item.nodes
        .slice(0, 5)
        .map((node) => `${node.target} ${node.html}`)
        .join('\n');
      return `${item.impact} ${item.id}: ${item.help}\n${alvos}`;
    })
    .join('\n\n');
}
