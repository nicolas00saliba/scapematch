const chavesSensiveis = new Set([
  'email',
  'ip_address',
  'ipAddress',
  'phone',
  'telefone',
  'cpf',
  'cookies',
]);

export function redigirTexto(texto: string): string {
  return texto
    .replace(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/gi, '[email]')
    .replace(
      /([?&](?:email|e-mail|cpf|telefone|phone|celular)=)[^&#\s]+/gi,
      '$1[redigido]',
    )
    .replace(/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/g, '[cpf]')
    .replace(/(?:\+?55\s*)?\(?\d{2}\)?\s*9?\d{4}[-\s]\d{4}\b/g, '[telefone]')
    .replace(/\b\d{11}\b/g, (digitos) =>
      digitos[2] === '9' ? '[telefone]' : '[cpf]',
    );
}

export function redigirValor<T>(valor: T): T {
  if (typeof valor === 'string') {
    return redigirTexto(valor) as T;
  }
  if (Array.isArray(valor)) {
    return valor.map((item) => redigirValor(item)) as T;
  }
  if (valor && typeof valor === 'object') {
    const saida: Record<string, unknown> = {};
    for (const [chave, item] of Object.entries(valor)) {
      if (chavesSensiveis.has(chave)) {
        continue;
      }
      saida[chave] = redigirValor(item);
    }
    return saida as T;
  }
  return valor;
}

export function redigirEvento<T>(evento: T): T {
  return redigirValor(evento);
}

export function redigirBreadcrumb<T>(breadcrumb: T): T {
  return redigirValor(breadcrumb);
}
