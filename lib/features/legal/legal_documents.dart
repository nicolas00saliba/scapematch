/// Rascunhos. O aviso no topo deixa claro que um advogado ainda não revisou.
abstract final class LegalDocuments {
  static const reviewBanner =
      'A revisar juridicamente. Este texto é um rascunho de exemplo, não um contrato.';

  static const termsTitle = 'Termos de uso';
  static const privacyTitle = 'Política de privacidade';
  static const refundTitle = 'Política de reembolso';

  static const termsBody = '''
O ScapeMatch ajuda a achar gente para completar um grupo de escape room. Nesta versão os dados são fictícios e nada é cobrado.

Ao criar uma conta de exemplo você confirma que leu este rascunho, a política de privacidade e a política de reembolso. A conta fica só neste aparelho.

Menores de 18 anos não criam conta. Menores só jogam acompanhados de um responsável, em regra provisória.
''';

  static const privacyBody = '''
Este rascunho descreve o que a versão de exemplo guarda: nome, e-mail, data de nascimento, cidade, tipo de jogo e se a introdução já foi vista. A senha não sai da memória do exemplo e não vai para o disco.

Não há servidor. Não vendemos dados. Não há cookie de rastreamento além do que o navegador usa para lembrar a cidade, o jogo e a introdução.

Você pode pedir a exclusão da conta na aba Conta. Nesta versão o pedido fica registrado e a conta de exemplo não é apagada de verdade.
''';

  static const refundBody = '''
Nada é cobrado. O reembolso é simulado.

Cada casa define a antecedência mínima para devolver o valor. Cancelar dentro dessa janela registra o reembolso. Cancelar depois não devolve.

Se o grupo não atingir o mínimo até o prazo, ele é cancelado e todo mundo que estava na cadeira recebe reembolso integral simulado.

Não confirmar presença não conta como falta. A falta sem aviso vai ser marcada pela casa no futuro; esta versão não marca sozinha. Se a casa marcar três faltas em 60 dias, novas entradas pausam por 30 dias. Esta conta é provisória.
''';

  static const under18 =
      'Menores de 18 anos não criam conta. Nesta versão, menores só jogam acompanhados de um responsável.';

  static const termsRequired =
      'Aceite os termos, a privacidade e a política de reembolso para criar a conta.';
}
