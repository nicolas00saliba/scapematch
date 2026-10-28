# Plano de saldo e pagamentos

O que a Conta já tem, e o que ainda não existe. Nada disto cobra, guarda número de cartão ou altera o saldo de exemplo.

## Já está no código

- `Money` guarda centavos.
- `WalletTransaction` é uma linha de crédito ou débito, sem dado de cartão.
- `WalletRepository` lê o saldo, lê os lançamentos e tem `addBalance` com uma chave de idempotência. A implementação fictícia recusa a recarga e não muda o saldo. O saldo de exemplo é R$ 40,00, igual à soma do livro.
- `PaymentMethod` guarda id, bandeira, quatro últimos dígitos e apelido. Número completo, validade e CVV não existem no modelo.
- `PaymentMethodsRepository.list` devolve a lista. A fictícia devolve vazia.
- A Conta lê esses dois repositórios pelos providers. Trocar a fonte é trocar o provider.

## O que falta

1. **Gateway.** Um provedor cobra o Pix ou o cartão. O app não fala com a bandeira direto.
2. **PCI por tokenização.** O número do cartão é digitado no componente do provedor, ou nem chega ao nosso servidor. O app só guarda o token e os metadados seguros. Não há campo de número nesta versão de propósito.
3. **Livro-razão no Supabase.** O saldo não é uma coluna que o cliente soma. Cada recarga, estorno e uso vira uma linha. O saldo é a soma, calculada no banco. RLS deixa a pessoa ver só as próprias linhas. O cliente não faz `update` solto no saldo.
4. **Idempotência.** `addBalance` manda a mesma chave se a pessoa tocar de novo ou se a rede repetir. O banco e o gateway aceitam a chave uma vez.
5. **Estornos.** Cancelar um grupo ou sair dentro da regra devolve o valor como uma linha de crédito, não como edição da linha antiga. A regra de reembolso dos grupos continua a que já está em `docs/DECISOES.md`; aqui só entra o lançamento.
6. **Login.** Sem conta de verdade não há de quem é o saldo. O `currentUserProvider` entra antes do gateway.

A tela de Adicionar saldo e a de Cartões cadastrados ficam como estão até esses pontos existirem. O botão Confirmar e o cadastro de cartão só passam a chamar o repositório quando o gateway e o livro-razão estiverem no lugar.
