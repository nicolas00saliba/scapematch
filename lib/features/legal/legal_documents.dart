/// Rascunhos. O aviso no topo deixa claro que um advogado ainda não revisou.
abstract final class LegalDocuments {
  static const reviewBanner =
      'A revisar juridicamente. Rascunho para revisão de advogado. Este texto ainda não é um contrato.';

  static const termsTitle = 'Termos de uso';
  static const privacyTitle = 'Política de privacidade';
  static const refundTitle = 'Política de cancelamento e reembolso';

  static const termsBody = '''
O EscapeMatch ajuda você a achar pessoas para completar um grupo e dividir a reserva de uma sessão presencial, começando por escape room. A casa é quem realiza a sessão. O EscapeMatch intermedia a formação do grupo e a cobrança da sua parte.

Ao criar a conta você confirma que leu este rascunho, a política de privacidade e a política de cancelamento e reembolso. O aceite fica registrado com a versão do texto e a data.

Menores de 18 anos não criam conta. Menores só jogam acompanhados de um responsável, em regra provisória.

Você paga só a sua parte. A cobrança é confirmada quando o grupo atinge o mínimo. Enquanto o grupo não confirma, o Pix ainda não é liquidado como receita da sessão e o cartão fica só autorizado. Se o grupo não confirmar, o Pix pago é estornado e a autorização do cartão não é capturada. Quem entra depois paga a própria parte na hora, sem reajuste de quem já pagou.

A nota fiscal do serviço, quando a casa emite, é da casa para você. A comissão da intermediação é uma nota à parte, da EscapeMatch para a casa, e não aparece como nota sua.

Scape Points. 100 pontos valem R\$ 1. Não há saque. Dá para pagar a sua parte em dinheiro, em pontos ou nos dois. Não há mínimo de pontos nem teto de 30%. O servidor calcula quanto do saldo cabe na reserva. Se os pontos cobrem o valor inteiro e a reserva de pontos cobre a parte da casa, não há cobrança no PagBank. Se não cobrem, o restante sai em dinheiro. Pontos de boas-vindas e de promoção não têm lastro na reserva: eles abatem até a comissão. Pontos de indicação e de cashback podem cobrir a vaga quando a reserva tem saldo.

Boas-vindas. Quando o cadastro fica com um CPF válido, a conta recebe 100 pontos uma única vez. Esses pontos entram no saldo e podem abater uma reserva até o limite da comissão.

Cashback. Em cada reserva paga, o servidor sorteia uma taxa entre 0,5% e 5% do valor que você pagou. A distribuição é configurada para que a média não passe de 1% (o padrão esperado é 0,9%). A taxa sorteada e a semente da auditoria ficam gravadas. O resultado aparece no extrato depois que o pagamento confirma. A tela, antes de pagar, mostra a faixa de 0,5% a 5%. O cashback nasce da comissão da EscapeMatch, fica pendente por 30 dias e é estornado se o pagamento for cancelado. Horário vazio não dobra esse valor.

Indicação de pessoas. A taxa é absoluta e só muda com o número de indicados ativos: 1% desde o primeiro, 2,5% a partir de 5 e 5% a partir de 8. Sem indicado ativo, a taxa é zero. Ativo é o indicado com atribuição ativa e reserva paga nos últimos 90 dias. O nível é recalculado quando a recompensa é lançada. Jogador que indica casa ganha 5%, sem níveis. Casa que indica jogador ganha 5% em crédito, sem níveis, e só sobre gasto em outra casa. Casa que indica casa continua em 5%. A primeira sessão de quem entrou com código de indicação tem 20% de desconto. Quem se cadastrou sem código tem 10%.

Nesta versão de demonstração os dados de exemplo continuam no aparelho até a conta real entrar no ar. As regras acima são o combinado que a versão ligada ao servidor vai aplicar.
''';

  static const privacyBody = '''
Esta política descreve, em rascunho, o tratamento de dados pessoais pelo EscapeMatch, nos termos da Lei 13.709/2018 (LGPD).

Dados coletados. Do jogador: nome, e-mail, senha (guardada pelo provedor de conta, não em texto puro no app), data de nascimento, cidade, participação em grupos e o estado do pagamento da parte (sem número completo de cartão, validade ou código de segurança). Da casa: nome, documento (CPF ou CNPJ), telefone, endereço, renda informada para a subconta de pagamento e, quando houver, inscrição municipal, código de serviço e alíquota de ISS. Também ficam o aceite dos termos (versão e data) e os identificadores das notas fiscais emitidas.

Finalidade. Criar e manter a conta, formar o grupo, cobrar só a parte de cada pessoa quando o grupo confirma, estornar o que a política de cancelamento manda devolver, emitir ou registrar a nota fiscal, avisar sobre a sessão e cumprir obrigação legal.

Base. Execução do contrato de intermediação, obrigação legal (incluindo documento fiscal, quando couber) e, para avisos opcionais, o consentimento que você pode retirar.

Compartilhamento. A casa da sessão vê o necessário para receber o grupo. O provedor de pagamento processa a cobrança. A nota do serviço, quando existe, é emitida pela casa. Não vendemos dados.

Direitos. Você pode pedir confirmação do tratamento, acesso, correção, anonimização, portabilidade, informação sobre compartilhamento e eliminação dos dados desnecessários, além de revogar um consentimento. O pedido de exclusão da conta fica na aba Conta. Há casos em que a lei manda guardar o dado por um prazo, como o documento fiscal.

Encarregado. O contato do encarregado pelo tratamento de dados é um placeholder: encarregado@exemplo.invalid. Troque este endereço antes de divulgar o produto.

Nesta demonstração, parte dos dados ainda fica só no aparelho. Quando a conta real estiver ligada, vale o que estiver gravado no servidor, com as mesmas finalidades.
''';

  static const refundBody = '''
O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.

Pix. Se o grupo não atingir o mínimo até o prazo, ou se for cancelado antes de confirmar, o Pix que já tiver sido pago é estornado. A tela avisa que o valor foi liberado.

Cartão. A autorização não é capturada enquanto o grupo não confirma. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado. Se o grupo confirmar, a captura acontece e a parte entra no extrato da casa, já com a comissão da intermediação separada.

Cancelamento pelo jogador. Cada casa define a antecedência mínima. Sair dentro dessa janela, antes do início, devolve o que já tiver sido capturado. Sair depois da janela não devolve. O organizador pode excluir o grupo até 2 horas antes do início. No instante exato das 2 horas ainda pode. A exclusão libera a reserva ou reembolsa o que já foi capturado.

Arrependimento. Nas compras feitas fora do estabelecimento, o Código de Defesa do Consumidor (art. 49) prevê o direito de arrependimento em 7 dias a contar da contratação, enquanto o serviço não tiver sido usufruído. Como a sessão tem data marcada, a aplicação desse prazo a um horário já reservado precisa da revisão do advogado. Até lá, a janela prática desta versão é a da casa e a regra de o grupo não confirmar.

Não confirmar presença não conta como falta. A falta sem aviso é marcada pela casa. A primeira falta avisa. A terceira pode bloquear novas entradas por um tempo. Os dois números são configuração, não estão escritos neste texto.

Nada nesta tela autoriza a casa a ficar com um valor que a regra manda devolver.
''';

  static const under18 =
      'Menores de 18 anos não criam conta. Nesta versão, menores só jogam acompanhados de um responsável.';

  static const termsRequired =
      'Aceite os termos, a privacidade e a política de cancelamento e reembolso para criar a conta.';
}
