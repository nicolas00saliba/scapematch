# Parceiro: um login com várias unidades

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
