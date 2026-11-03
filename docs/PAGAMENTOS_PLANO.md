# Plano de saldo e pagamentos

O que a Conta já tem, o que a fase 2 colocou no pacote de domínio, e o que ainda não existe. Nada disto cobra de verdade, guarda número de cartão ou altera o saldo de exemplo da carteira.

## Fase 2, no pacote `dominio`

O pacote `packages/dominio` guarda a conta, sem tela e sem Supabase. O app na raiz depende dele. O site continua saindo da raiz.

- A taxa mora em `PlatformSettings`. A primeira linha é 1000 basis points, 10%. A fórmula `commissionCents` recebe a taxa por argumento.
- `setPlatformCommission` e `setHouseCommission` só rodam para `platformAdmin` e gravam `AuditEntry`. O override por casa já tem lugar; ninguém é obrigado a usá-lo.
- `createReservation` reparte o total entre os jogadores, calcula a comissão uma vez sobre o total e grava taxa, comissão e líquido em cada parte. Essa foto não muda se a configuração mudar depois.
- O meio centavo de comissão sobe. As primeiras partes levam o centavo do resto. Comissão de cada parte + líquido = valor da parte. A soma das comissões fecha com a comissão do total.
- `PaymentProvider` é a porta. `SimulatedPaymentProvider` confirma na hora e respeita a chave de idempotência.
- `PaymentBook.payShare` cobra a parte inteira do jogador. O líquido vira crédito da casa e a comissão vira crédito da plataforma.
- `refundShare` acrescenta débitos novos (`houseRefund` e `commissionRefund`). As linhas do pagamento ficam como estavam.
- A carteira de R$ 40 da Conta é outra conta. Ela não lê este livro.

A tela em que a equipe muda a taxa entra no app de manutenção, chamando `setPlatformCommission`. Ainda não há essa tela.

## Já está no código da Conta

- `Money` guarda centavos.
- `WalletTransaction` é uma linha de crédito ou débito, sem dado de cartão.
- `WalletRepository` lê o saldo, lê os lançamentos e tem `addBalance` com uma chave de idempotência. A implementação fictícia recusa a recarga e não muda o saldo. O saldo de exemplo é R$ 40,00, igual à soma do livro.
- `PaymentMethod` guarda id, bandeira, quatro últimos dígitos e apelido. Número completo, validade e CVV não existem no modelo.
- `PaymentMethodsRepository.list` devolve a lista. A fictícia devolve vazia.
- A Conta lê esses dois repositórios pelos providers. Trocar a fonte é trocar o provider.

## Fase 3, na tela do grupo

Entrar deixa a parte pendente. O botão “Pagar minha parte” abre Pix ou cartão simulado e grava no `PaymentBook`. O jogador vê o preço por pessoa e quem já pagou. A comissão fica no livro, fora da tela. Quem não paga até o prazo de fechar perde a vaga. Tudo continua na memória do aparelho.

## Próxima fase

O ScapeMatch Parceiro é um app à parte, em `apps/parceiro`, publicado em `/scapematch/parceiro/`. Login simulado da casa, saldo, extrato com bruto, comissão e líquido, reservas, grupos, salas, horários, preços e falta. O `PartnerRepository` lê o `PaymentBook` do banco que recebe. Cada app sobe o próprio livro de exemplo. O Supabase real fica para depois dessa demo e é o que vai unir jogador e casa.

## O que falta

Isto ainda vale para a carteira da Conta e para o provedor real. O livro da reserva, no pacote, já reparte, retém a comissão e estorna com linha nova, em memória.

1. **Gateway.** Um provedor cobra o Pix ou o cartão. O app não fala com a bandeira direto.
2. **PCI por tokenização.** O número do cartão é digitado no componente do provedor, ou nem chega ao nosso servidor. O app só guarda o token e os metadados seguros. Não há campo de número nesta versão de propósito.
3. **Livro-razão no Supabase.** O saldo não é uma coluna que o cliente soma. Cada recarga, estorno e uso vira uma linha. O saldo é a soma, calculada no banco. RLS deixa a pessoa ver só as próprias linhas. O cliente não faz `update` solto no saldo.
4. **Idempotência.** `addBalance` manda a mesma chave se a pessoa tocar de novo ou se a rede repetir. O banco e o gateway aceitam a chave uma vez.
5. **Estornos.** Cancelar um grupo ou sair dentro da regra devolve o valor como uma linha de crédito, não como edição da linha antiga. A regra de reembolso dos grupos continua a que já está em `docs/DECISOES.md`; aqui só entra o lançamento.
6. **Login.** Sem conta de verdade não há de quem é o saldo. O `currentUserProvider` entra antes do gateway.

A tela de Adicionar saldo e a de Cartões cadastrados ficam como estão até esses pontos existirem. O botão Confirmar e o cadastro de cartão só passam a chamar o repositório quando o gateway e o livro-razão estiverem no lugar.
