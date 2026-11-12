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

for (const caminho of caminhos) {
  test(`axe em ${caminho}`, async ({ page }) => {
    await page.goto(caminho);
    const resultados = await new AxeBuilder({ page }).analyze();
    const graves = resultados.violations.filter(
      (item) => item.impact === 'serious' || item.impact === 'critical',
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
