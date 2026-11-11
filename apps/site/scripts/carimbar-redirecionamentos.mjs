import { readdir, readFile, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

// build.format = 'file' gera /termos-parceiro.html como termos-parceiro.html.html.
// Este passo grava o endereço antigo de verdade e carimba a CSP da landing.
const dist = path.resolve('dist');
const csp =
  "default-src 'self'; base-uri 'self'; object-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; worker-src 'none'; frame-src 'none'; manifest-src 'self'; form-action 'self'";
const carimbo = [
  '<meta name="referrer" content="strict-origin-when-cross-origin">',
  `<meta http-equiv="Content-Security-Policy" content="${csp}">`,
  '<script src="/frame-guard.js"></script>',
].join('');

async function htmls(dir) {
  const saida = [];
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) saida.push(...(await htmls(full)));
    else if (entry.name.endsWith('.html.html')) saida.push(full);
  }
  return saida;
}

for (const arquivo of await htmls(dist)) {
  let html = await readFile(arquivo, 'utf8');
  html = html.replaceAll('.html.html', '.html');
  if (!html.includes('Content-Security-Policy')) {
    html = html.includes('<!doctype html>')
      ? html.replace('<!doctype html>', `<!doctype html>${carimbo}`)
      : `${carimbo}${html}`;
  }
  const destino = arquivo.slice(0, -'.html'.length);
  await writeFile(destino, html);
  await unlink(arquivo);
}
