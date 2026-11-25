# Cadastro de conta PagBank da casa

Cada casa que recebe no split precisa de uma conta PagBank própria. O dinheiro cai nessa conta. O Pix para outro banco é manual, no app do PagBank. Não há saque automático pelo EscapeMatch.

Enquanto a API de Cadastro não está liberada para as nossas credenciais, o Parceiro fica no modo A: a casa cria a conta em [https://cadastro.pagbank.com.br/](https://cadastro.pagbank.com.br/) e depois autoriza o Connect que já existe. Os dados do formulário não são enviados ao PagBank e não ficam no banco. A tabela `venue_pagbank_signups` guarda só o tipo do documento (`cpf` ou `cnpj`), a categoria do negócio e o instante do aceite.

Quando a flag `pagbank_signup_settings.api_enabled` liga, o Parceiro passa sozinho para o modo B. A Edge Function `pagbank-signup` chama `POST /accounts` com `x-client-id`, `x-client-secret` e `Authorization: Bearer`. A resposta grava o id `ACCO_` e o status. CPF, CNPJ, endereço, nascimento, celular e e-mail não são coluna.

O titular ainda ativa a conta no aplicativo PagBank (documento, selfie e senha) e a casa autoriza o Connect.

## Páginas que a PagBank enviou

A [introdução das APIs](https://developer.pagbank.com.br/docs/apis-pagbank) separa três serviços que esta jornada usa em sequência. A [API de Cadastro](https://developer.pagbank.com.br/docs/cadastro-de-clientes) cria a conta de terceiro. O Connect liga essa conta à aplicação. A API de Pedido divide o pagamento. O modo A manda a casa para a página oficial porque a API de Cadastro ainda não está liberada. O modo B chama `POST /accounts` e, em seguida, pede o Connect. O PagVendas não entra nesse caminho.

[PagVendas](https://pagbank.com.br/para-seu-negocio/pagvendas/) é o aplicativo de frente de caixa, estoque e nota da própria casa. A pergunta “onde recebo os valores” responde que o dinheiro cai na conta digital PagBank e fica disponível para usar. É o mesmo destino do split depois da custódia: a conta da casa, com Pix manual no app PagBank. O EscapeMatch não abre o PagVendas nem pede cadastro lá.

A página [Configurando o Split](https://developer.pagbank.com.br/docs/config-split) instala o módulo Magento (`pagbank/split-magento`). Esse módulo não se aplica. O trecho que vale para o pedido é o objeto `splits`: `method` `FIXED`, `receivers` com `account.id` e `amount.value`, e a soma dos valores igual ao total pago. `fixedSplit` recusa a cobrança se a soma não fechar. Cada recebedor sai com `configurations.custody.apply = true`, então casa e EscapeMatch ficam HELD até o horário da sessão. Sem `release.scheduled`, a PagBank libera sozinha em 90 dias. O cron libera antes, quando a sessão já começou, pelo endpoint abaixo.

[Liberar divisão de pagamento com custódia](https://developer.pagbank.com.br/reference/liberar-divisao-de-pagamento-com-custodia) é `POST /splits/{id}/custody/release` em `https://api.pagseguro.com` (sandbox em `https://sandbox.api.pagseguro.com`). Não usa o host do Connect. O corpo manda `receivers[].account.id` da casa e da EscapeMatch. Só o dono da transação libera: a chamada usa o token da conta que criou o pedido. Resposta vazia com HTTP 200 é sucesso. O limite publicado é 500 liberações a cada 5 minutos. Depois disso o valor fica na conta PagBank de cada recebedor.

## Sonda

A cada 6 horas, no minuto 15 (`15 */6 * * *`), `private.invoke_pagbank_signup_probe()` chama `pagbank-signup-probe`. Sem os itens `pagbank_signup_probe_url` e `pagbank_signup_probe_secret` no Vault, a função não posta e grava o evento `config_ausente`. A URL só é aceita se for `https://<ref>.supabase.co/functions/v1/pagbank-signup-probe`.

A sonda manda `POST /accounts` com o corpo exatamente `{"type":"SELLER"}`. Não há e-mail, pessoa, empresa, categoria nem aceite, então esse corpo não cria conta.

Uma resposta só conta se todas estas condições forem verdadeiras:

- HTTP 400
- JSON com `error_messages` (ou `errors`) não vazio
- todo `code` é `40001` ou `40002`
- pelo menos um item tem `parameter_name` com nome de campo
- o corpo não contém `ACCO_`, `access_token` nem `refresh_token`
- o corpo não contém texto de permissão (`unauthorized`, `forbidden`, `permission`, `scope`, `escopo`)

A flag liga na segunda resposta seguida que passa nisso. A primeira grava o evento `probe_confirming` e não avisa. Qualquer resposta que não é inequívoca zera a contagem. 401, 403, 404, 2xx, 5xx, timeout, corpo vazio e 400 sem esses códigos deixam a flag como está. HTTP 201, ou um corpo com `ACCO_` ou token, não liga a flag, não grava id de conta e dispara o alerta Sentry `pagbank-signup-probe` / `probe_criou_conta`.

Na segunda resposta seguida, a função grava o evento `probe_enabled` e, na mesma chamada, escreve o log e dispara o alerta `api_liberada`, para avisar o Nícolas. Uma sonda seguinte, com a flag já ligada, não dispara de novo.

`held_off` impede a ligação mesmo com duas respostas inequívocas e zera a contagem. O admin com sessão `aal2` desliga em `admin_disable_pagbank_signup`. `admin_release_pagbank_signup_hold` religa o modo B na hora: `api_enabled` volta a verdadeiro e a trava sai. O evento é `admin_release` / `api_enabled`.

Se o `POST /accounts` responder `42001` sem id `ACCO_`, a função grava `account_status = exists` e não chama `POST /accounts` de novo. A casa vai ao Connect, que é quem traz o `account_id`.

## Publicar

Não aplicar daqui. O dono aprova.

1. Migration `20261124180000_pagbank_account_signup.sql`. Não apaga migration antiga. A flag de saque continua desligada.
2. Itens no Vault, com o mesmo valor do segredo da função: `pagbank_signup_probe_url` e `pagbank_signup_probe_secret`. A env da função, se existir, é `PAGBANK_SIGNUP_PROBE_SECRET`. Os outros segredos já usados são `PAGBANK_TOKEN`, `PAGBANK_ENV`, `PAGBANK_CONNECT_CLIENT_ID`, `PAGBANK_CONNECT_CLIENT_SECRET` e `PAGBANK_CONNECT_REDIRECT_URI`.
3. Funções: `pagbank-signup` e `pagbank-signup-probe`.

`venue-payouts` e `schedule-venue-withdrawals` continuam publicadas com o saque recusado no código.

## Chamado para o time de integração do PagBank

Assunto: Liberação da API de Cadastro (SELLER PF e PJ) para a EscapeMatch

A EscapeMatch é um marketplace de escape rooms. Cada casa que recebe no split precisa de uma conta PagBank própria. O Connect já está no ar: a aplicação tem client id e client secret, o redirect do Parceiro é `https://parceiro.escapematch.com.br/pagbank/retorno`, e os escopos pedidos hoje são `payments.read`, `payments.create`, `payments.refund` e `accounts.read`.

A gerente Priscila nos passou que o dinheiro cai na conta da casa e que o Pix para outro destino é manual. Não vamos mais sacar pela plataforma.

Precisamos da API de Cadastro liberada para essas credenciais, nos tipos SELLER pessoa física e SELLER pessoa jurídica, com `business_category` e `tos_acceptance` (`user_ip` e `date`). O servidor chamaria `POST /accounts` com `x-client-id`, `x-client-secret` e `Authorization: Bearer`.

Perguntas:

1. O que ainda falta para liberar a criação de contas SELLER PF e PJ no nosso client id?
2. Quais permissões ou escopos a aplicação precisa, além dos que o Connect já usa?
3. O Bearer do `POST /accounts` é o token da conta principal da EscapeMatch, outro token, ou só o par client id e client secret?
4. Depois que a conta nasce com id `ACCO_`, a autorização Connect pode ser automática, ou o titular precisa concluir documento, selfie e senha no app PagBank e ainda passar pelo OAuth?
5. Um `GET` de consulta numa conta inexistente, feito com as credenciais do parceiro e sem o access token do seller, responde 404 quando a API está liberada, ou esse GET só existe depois do Connect?
6. Um `POST /accounts` inválido, só com `{"type":"SELLER"}`, devolve 400 com `error_messages` `40001` ou `40002` quando a API está liberada, e 401 ou 403 enquanto não está?

Enquanto isso não estiver liberado, a casa cria a conta em `https://cadastro.pagbank.com.br/` e conecta pelo OAuth que já usamos. Quando liberar, queremos criar a conta pelo nosso servidor e, em seguida, pedir o Connect.
