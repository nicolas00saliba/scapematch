/// A conciliação com o provedor antigo saiu. Cobrança asaas fica só no livro.
export async function reconcilePayments(
  _admin: unknown,
): Promise<{ resolved: number; pending: number }> {
  return { resolved: 0, pending: 0 };
}
