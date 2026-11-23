/// Percentual do valor que o Asaas manda para o walletId da casa.
///
/// 2500 basis points são 25%. A casa recebe 75 e a EscapeMatch fica com o
/// restante, na conta que criou a cobrança. A mesma conta está em
/// `supabase/functions/_shared/asaas_provider.ts`.
double houseSplitPercent(int commissionBps) {
  if (commissionBps < 0 || commissionBps > 10000) {
    throw ArgumentError('Comissão fora de 0 a 10000 basis points.');
  }
  return (10000 - commissionBps) / 100;
}
