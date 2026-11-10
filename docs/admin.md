# EscapeMatch Admin

Painel exclusivo do Nícolas. Não há link a partir do app do jogador, do Parceiro, das demos nem da landing.

## Onde fica

- App: `apps/admin`
- Host proposto: `https://admin.escapematch.com.br/`
- Enquanto o repositório de Pages e o DNS não existem, o deploy também publica o mesmo build em `https://nicolas00saliba.github.io/scapematch/admin/`
- Este repositório não cria o host, não mexe em DNS e não publica sozinho

O build usa `--pwa-strategy=none`, como os outros apps. A identidade de instalação é `https://admin.escapematch.com.br/` na raiz e a URL do Pages antigo no subcaminho.

## O que o painel faz

1. Casas: lista, perfil, aprovar ou reprovar, suspender, editar dados e definir a comissão da casa. O percentual é digitado (22,5 vale), confirmado na tela e conferido no servidor entre 0% e 30%. A cobrança já feita guarda o percentual dela em `payment_charges.commission_bps`. Aprovar uma casa sem subconta chama a Edge Function `provision-venue-wallet`, o mesmo fluxo que já cria a subconta Asaas.
2. Jogadores: busca, perfil, reservas, saldo e extrato de Scape Points, indicações e nível. Suspende a conta. A fila `em_revisao` aprova ou rejeita a conta indicada.
3. Regras: grava as taxas de indicação, cashback, mínimo de resgate, teto de 30%, boas-vindas, níveis, horário vazio e travas antifraude. Cada gravação entra em `reward_settings_changes`. A distribuição de cashback só grava se todas as faixas couberem entre o mínimo e o máximo, com peso inteiro maior que zero e média até o teto. Se não couber, o banco devolve 22023 e o painel mostra a mensagem.
4. Ganhos: comissão bruta, recompensas e cashback, pontos em aberto, por período e por casa. Dívidas abertas do livro, inclusive o clawback tudo-ou-nada. A taxa do Asaas aparece só quando `payment_charges.asaas_fee_cents` existe.
5. Destaques: ordem das casas, das salas e do carrossel de novidades da home do jogador. Sem número, a home segue a ordem de sempre. Com número, o menor vem antes.

## Segurança

Toda leitura e escrita do painel passa por RPC `SECURITY DEFINER` com `search_path` vazio. Cada uma chama `private.admin_require()`, que exige admin e sessão `aal2`. `private.is_admin()` continua só conferindo a tabela `admins`, porque policies e funções de fora do console também a usam. O grant de execução é só para `authenticated`. `anon` e `service_role` não executam. O app não carrega a chave `service_role`.

Depois da senha, quem não tem TOTP cadastra o fator (`supabase.auth.mfa.enroll`) e quem já tem informa o código (`challenge` e `verify`). Sem o segundo fator o painel não abre.

`admin_audit_log` e `reward_settings_changes` não têm policy de leitura e o privilégio foi revogado. O painel lê a auditoria pela função `admin_audit`.

Casa suspensa sai da vitrine porque `private.venue_is_visible` exige `suspended_at` nulo. Sala e notícia não deixam o dono mudar a ordem do destaque. Conta suspensa não entra em grupo novo.

A migration nova é `supabase/migrations/20261109150000_admin_console.sql`. Ela não reaplica `20261105210000` e não foi aplicada no projeto remoto.

## Ordem para publicar

Aplicar a migration no Supabase antes de publicar o app do jogador. A home passa a pedir `featured_rank` e `carousel_rank`. Sem essas colunas, a vitrine quebra.
