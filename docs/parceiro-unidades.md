# Parceiro: uma casa em várias cidades (unidades)

Pedido real: a Minos Escape Room tem duas unidades (Curitiba e Cascavel), com
CNPJs diferentes, e quer administrar tudo no mesmo login.

## Como fica

- O banco já aceitava mais de uma casa por `owner_id`. O Parceiro é que só
  lia a mais nova (`venues.first`). Com uma segunda unidade em análise, o
  painel da unidade aprovada ficava trancado na tela "aguardando".
- `loadPartnerAccount` lê todas as unidades do login e abre uma, por
  `pickPartnerVenue`: a escolhida antes (salva no aparelho em
  `parceiro.unidade_aberta.<user>`), senão a mais nova aprovada, senão a mais
  nova em análise, senão a mais nova.
- O botão **Unidades** (ícone de loja) no topo do painel lista as unidades,
  marca a aberta, mostra "(em análise)" ou "(recusada)" e tem **Cadastrar
  outra unidade**. A tela de espera lista as outras unidades para abrir.
- Cada unidade continua com o próprio cadastro, documento, salas, agenda,
  avaliações, código de indicação e conta de recebimento. Trocar de unidade
  refaz o painel (`ValueKey` com o id), sem estado de uma na outra.
- O código de indicação passa a ser o da unidade aberta:
  `my_venue_referral_code(p_venue_id)` (migration
  `20261127170000_venue_referral_code_por_unidade.sql`) confere o dono. Sem a
  migration no banco, o app cai no RPC antigo (unidade mais nova).
- Depois de enviar o cadastro de uma unidade por uma tela empilhada (outra
  unidade ou "Enviar outra casa"), a tela fecha e a unidade nova abre.

## O que não muda

- **Conta PagBank: continua uma por casa, e a mesma conta não liga a duas
  casas reais** (`docs/pagbank-conta-unica.md`, índice
  `venues_pagbank_account_real_uidx`). Usar a mesma conta PagBank para as duas
  unidades da Minos é decisão do Nícolas, ainda não tomada no código.
- Comissão, reembolso e as demais regras ficam iguais.

## Cidades como abas (pedido do Nícolas, 27/11)

- No cadastro, **Outras cidades desta casa** aceita várias cidades. Depois de
  enviar a primeira, o app abre o cadastro de cada cidade já preenchido com os
  dados da casa (nome, telefone, documento, categoria). Falta só o endereço
  daquela cidade.
- No painel, uma **aba por cidade** (`PartnerCityTabs`) abre a unidade daquela
  cidade, com salas, agenda, reservas e saldo dela. **+ Cidade** cadastra
  outra. **Gerenciar cidades** lista e remove.
- Cidade nova passa pela mesma análise do Admin.
- No app do jogador nada muda no código: cada unidade é uma casa com
  `city_id` próprio, então a cidade mostra as salas daquela unidade com o
  nome da casa.

## Remover cidade (desativar)

`deactivate_my_unit(p_venue_id)` (migration
`20261127180000_unidades_desativar.sql`): nada é apagado. A unidade fica com
`suspended_at` (o mesmo corte que já tira casa suspensa do jogador, das
cidades, do ranking e das reservas) e `deactivated_at`. Recusa unidade de
outro dono, a última cidade ativa, cidade com grupo futuro e cidade com saque
pendente ou cobrança a caminho (`private.venue_pagbank_in_flight`, a mesma
regra da troca de conta PagBank). O app pede confirmação. Trazer de volta é
pelo Admin (tirar a suspensão também limpa `deactivated_at`).

## Por que uma casa por cidade (e não casa única + tabela de cidades)

Uma `venue` por cidade reaproveita tudo o que já existe por casa: salas,
sessões, criação de grupo (que grava `groups.city_id` a partir da casa),
avaliações e ranking por cidade, mapa (coordenadas da casa), vitrine,
`cities_with_active_venues`, aprovação do Admin, saldo, saques e notas. Nada
disso muda. Casa única com tabela de cidades exigiria mudar a cidade de sala,
grupo, avaliação, mapa e as funções de criação de grupo e de cobrança, que
mexem com dinheiro.

O custo deste modelo são duas regras que já existem e não foram mudadas:

- **Documento**: o banco não aceita o mesmo CPF/CNPJ em duas casas ativas
  (`venues_document_digits_active_uidx`). Cada cidade precisa do documento da
  unidade daquela cidade (é o caso da Minos: CNPJs diferentes). Aceitar o
  mesmo CNPJ em várias cidades é decisão do Nícolas.
- **Conta PagBank**: uma por casa, e a mesma conta não liga a duas casas
  reais. Cada cidade conecta a dela. Centralizar o recebimento de várias
  cidades numa conta é decisão do Nícolas.
